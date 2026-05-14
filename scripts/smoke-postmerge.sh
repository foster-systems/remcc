#!/usr/bin/env bash
#
# Smoke-test the post-merge phase of remcc adoption.
# Covers tasks 7.3 and 7.4 of openspec/changes/gh-remcc-init.
#
# Prereq: scripts/smoke-init.sh has been run without --cleanup, leaving:
#   - premeq/remcc-smoke on GitHub with the remcc-init PR open
#   - /tmp/remcc-smoke locally on main with the seed commit
#
# Steps:
#   1. Merge the remcc-init PR (gh pr merge --squash --delete-branch).
#   2. Re-run install.sh init → assert "already up to date" path
#      (task 5.6 / 7.3).
#   3. Push a @change-apply smoke-test commit → triggers opsx-apply
#      workflow (task 7.4 — costs ~$0.50–$5 Anthropic).
#   4. Poll the workflow until it concludes; assert success.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... WORKFLOW_PAT=github_pat_... \
#     scripts/smoke-postmerge.sh \
#     [--target OWNER/NAME] [--workdir DIR] [--ref REF|auto] [--cleanup]

set -euo pipefail

TARGET="premeq/remcc-smoke"
WORKDIR="/tmp/remcc-smoke"
REF="auto"
CLEANUP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)   TARGET="$2"; shift 2 ;;
    --workdir)  WORKDIR="$2"; shift 2 ;;
    --ref)      REF="$2"; shift 2 ;;
    --cleanup)  CLEANUP=1; shift ;;
    -h|--help)  sed -n '3,22p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${ANTHROPIC_API_KEY:?must be set — smoke-test apply consumes Anthropic tokens}"
# Not re-uploaded here (smoke-init seeded it on the target), but checked
# so a forgotten env fails fast rather than partway through Step 4.
: "${WORKFLOW_PAT:?must be set — same PAT smoke-init seeded as the target repo secret}"
for t in gh jq git curl; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

[ -d "$WORKDIR" ] || { echo "$WORKDIR not present — run scripts/smoke-init.sh first (without --cleanup)" >&2; exit 1; }

if [ "$REF" = "auto" ]; then
  RESOLVED_REF="$(gh api repos/premeq/remcc/releases/latest --jq .tag_name 2>/dev/null || true)"
  [ -n "$RESOLVED_REF" ] || { echo "no release tag found on premeq/remcc" >&2; exit 1; }
  INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${RESOLVED_REF}/install.sh"
  INIT_REF_ARGS=()
  echo "ref=auto resolved to ${RESOLVED_REF}"
else
  INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${REF}/install.sh"
  INIT_REF_ARGS=(--ref "$REF")
fi

FAILED=0
step() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=1; }

# ----------------------------------------------------------------------------
# Step 1 — merge the open remcc-init PR
# ----------------------------------------------------------------------------
step "Step 1: merge remcc-init PR"
cd "$WORKDIR"

PR_NUM="$(gh pr list --repo "$TARGET" --head remcc-init --state open --json number --jq '.[0].number // empty')"
[ -n "$PR_NUM" ] || { echo "no open remcc-init PR on $TARGET — run scripts/smoke-init.sh first" >&2; exit 1; }

# --admin: the ruleset install.sh seeds restricts updates on all branches
# except change/**; admins bypass via RepositoryRole. The smoke seed user
# owns the target repo, so this matches the real operator-merging-own-PR
# path.
gh pr merge "$PR_NUM" --repo "$TARGET" --squash --delete-branch --admin >/dev/null
pass "merged PR #$PR_NUM (squash + delete branch, admin bypass)"

git checkout main >/dev/null 2>&1
git pull --ff-only origin main >/dev/null
[ -f .github/workflows/opsx-apply.yml ] && pass "opsx-apply.yml landed on main" || fail "opsx-apply.yml not on main"
[ -f .remcc/version ]                   && pass ".remcc/version landed on main" || fail ".remcc/version not on main"

# ----------------------------------------------------------------------------
# Step 2 — re-run install.sh init; expect "already up to date" (task 7.3)
# ----------------------------------------------------------------------------
step "Step 2: re-run install.sh init (post-merge — expect 'already up to date')"
SECOND_OUT="$(bash <(curl -fsSL "$INSTALL_URL") init ${INIT_REF_ARGS[@]+"${INIT_REF_ARGS[@]}"} 2>&1)"
echo "$SECOND_OUT"

grep -qi 'already up to date' <<<"$SECOND_OUT" \
  && pass "hit 'already up to date' path (task 5.6 / 7.3)" \
  || fail "did NOT hit 'already up to date' path"

PR_AFTER="$(gh pr list --repo "$TARGET" --head remcc-init --state open --json number --jq 'length')"
[ "$PR_AFTER" = "0" ] && pass "no new remcc-init PR opened" || fail "$PR_AFTER new PR(s) opened"

# ----------------------------------------------------------------------------
# Step 3 — push the smoke-test @change-apply commit (task 7.4)
# ----------------------------------------------------------------------------
step "Step 3: push @change-apply smoke-test (Anthropic spend)"
git checkout main >/dev/null
git pull --ff-only origin main >/dev/null
git checkout -b change/test-apply >/dev/null

mkdir -p openspec/changes/test-apply
cat > openspec/changes/test-apply/proposal.md <<'EOF'
## Why

Smoke-test the remcc apply path end-to-end.

## What Changes

Create a single empty file `smoke.txt`.
EOF
cat > openspec/changes/test-apply/tasks.md <<'EOF'
## 1. Smoke

- [ ] 1.1 Create empty file `smoke.txt` at repo root.
EOF
git add openspec/changes/test-apply >/dev/null
git -c user.email=smoke@example.com -c user.name=smoke commit -m "Add smoke test change" >/dev/null
git push -u origin change/test-apply >/dev/null 2>&1
git -c user.email=smoke@example.com -c user.name=smoke commit --allow-empty -m "@change-apply: smoke test" >/dev/null
git push >/dev/null 2>&1
pass "pushed @change-apply trigger commit"

# ----------------------------------------------------------------------------
# Step 4 — poll opsx-apply workflow run
# ----------------------------------------------------------------------------
step "Step 4: poll opsx-apply workflow run"
echo "Waiting up to 60s for the workflow run to appear..."
DEADLINE=$(( $(date +%s) + 60 ))
RUN_ID=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  RUN_ID="$(gh run list --repo "$TARGET" --workflow opsx-apply.yml --branch change/test-apply --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [ -n "$RUN_ID" ] && break
  sleep 5
done

[ -n "$RUN_ID" ] || { fail "no opsx-apply run appeared within 60s"; exit 1; }
pass "opsx-apply run id=$RUN_ID started"

echo "Watching run $RUN_ID (apply burns Anthropic tokens — typical: minutes)..."
gh run watch "$RUN_ID" --repo "$TARGET" --exit-status || true
CONCLUSION="$(gh run view "$RUN_ID" --repo "$TARGET" --json conclusion --jq .conclusion)"
[ "$CONCLUSION" = "success" ] \
  && pass "opsx-apply concluded: success (task 7.4)" \
  || fail "opsx-apply concluded: $CONCLUSION"

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
if [ "$CLEANUP" = 1 ]; then
  step "Cleanup"
  gh repo delete "$TARGET" --yes
  rm -rf "$WORKDIR"
  pass "deleted $TARGET and $WORKDIR"
else
  printf '\nLeaving %s and %s in place. Re-run with --cleanup to delete.\n' "$TARGET" "$WORKDIR"
fi

echo
if [ "$FAILED" = 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
