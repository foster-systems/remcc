#!/usr/bin/env bash
#
# Smoke-test `install.sh upgrade` end-to-end against a throwaway target repo.
# Covers tasks 6.1–6.5 of openspec/changes/install-sh-upgrade.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... WORKFLOW_PAT=github_pat_... \
#     scripts/smoke-upgrade.sh \
#     [--target OWNER/NAME] [--ref REF] [--old-ref REF] [--workdir DIR] \
#     [--skip-setup] [--cleanup]
#
# Defaults: --target premeq/remcc-smoke-upgrade --ref main --old-ref v0.1.1
#           --workdir /tmp/remcc-smoke-upgrade
#
# The init step still requires ANTHROPIC_API_KEY and WORKFLOW_PAT (consumed by
# gh-bootstrap.sh during init). The upgrade step itself does not — it does
# not re-run gh-bootstrap.sh — but the harness reuses init to seed the
# target, so both env vars are mandatory.

set -euo pipefail

TARGET="premeq/remcc-smoke-upgrade"
NEW_REF="main"
OLD_REF="v0.1.1"
WORKDIR="/tmp/remcc-smoke-upgrade"
SKIP_SETUP=0
CLEANUP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)      TARGET="$2"; shift 2 ;;
    --ref)         NEW_REF="$2"; shift 2 ;;
    --old-ref)     OLD_REF="$2"; shift 2 ;;
    --workdir)     WORKDIR="$2"; shift 2 ;;
    --skip-setup)  SKIP_SETUP=1; shift ;;
    --cleanup)     CLEANUP=1; shift ;;
    -h|--help)
      sed -n '3,17p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${ANTHROPIC_API_KEY:?must be set — init step passes it through to gh-bootstrap.sh}"
: "${WORKFLOW_PAT:?must be set — init step passes it through to gh-bootstrap.sh (Contents:write + Workflows:write on the target repo)}"
for t in gh jq pnpm git curl; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

OLD_INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${OLD_REF}/install.sh"
NEW_INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${NEW_REF}/install.sh"

FAILED=0

step() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=1; }

snapshot() {
  local out="$1"
  mkdir -p "$out"
  gh api "repos/$TARGET/branches/main/protection" 2>/dev/null > "$out/protection.json" || echo '{}' > "$out/protection.json"
  gh api "repos/$TARGET/rulesets" > "$out/rulesets.json"
  gh api "repos/$TARGET/actions/permissions/workflow" > "$out/actions-perms.json"
}

normalize() {
  jq -S 'walk(if type=="object" then del(.id,.node_id,.created_at,.updated_at) else . end)' "$1"
}

# ----------------------------------------------------------------------------
# Setup: create target, seed prereqs. No init yet — we need an un-adopted
# state for the failure-mode assertion below.
# ----------------------------------------------------------------------------
if [ "$SKIP_SETUP" = 0 ]; then
  step "Setup: create $TARGET, seed prereqs in $WORKDIR"
  rm -rf "$WORKDIR"  # wipe stale clone from a prior failed run
  gh repo create "$TARGET" --private --add-readme
  gh repo clone "$TARGET" "$WORKDIR"
  cd "$WORKDIR"
  cat > package.json <<'JSON'
{
  "name": "remcc-smoke-upgrade",
  "private": true,
  "packageManager": "pnpm@9.12.3"
}
JSON
  pnpm install --silent >/dev/null 2>&1 \
    || { echo "pnpm install (seed lockfile) failed" >&2; exit 1; }
  mkdir -p openspec .claude
  touch openspec/.gitkeep .claude/.gitkeep
  git add .
  git -c user.email=smoke@example.com -c user.name=smoke commit -m "Seed prereqs"
  git push origin main
fi

cd "$WORKDIR"

# ----------------------------------------------------------------------------
# Step 1 — curl-piped --help on the NEW install.sh (verify upgrade listed)
# ----------------------------------------------------------------------------
step "Step 1: curl-piped --help (verify 'upgrade' listed)"
HELP_OUT="$(bash <(curl -fsSL "$NEW_INSTALL_URL") --help)"
if grep -qE '^\s*upgrade\b' <<<"$HELP_OUT"; then
  pass "help lists 'upgrade' subcommand"
else
  fail "help does not list 'upgrade' subcommand"
  printf '%s\n' "$HELP_OUT" >&2
fi
UPG_HELP="$(bash <(curl -fsSL "$NEW_INSTALL_URL") upgrade --help)"
grep -q -- '--ref' <<<"$UPG_HELP" && pass "upgrade --help documents --ref" || fail "upgrade --help missing --ref"
grep -qi 'origin/main' <<<"$UPG_HELP" && pass "upgrade --help mentions origin/main marker" || fail "upgrade --help omits origin/main note"

# ----------------------------------------------------------------------------
# Step 2 — failure mode: upgrade on un-adopted target (task 6.2)
# `.remcc/version` does not exist on origin/main yet.
# ----------------------------------------------------------------------------
step "Step 2: upgrade refuses un-adopted target"
S_BEFORE="$(mktemp -d)"; snapshot "$S_BEFORE"
UPG_ERR_LOG="$(mktemp)"
if bash <(curl -fsSL "$NEW_INSTALL_URL") upgrade --ref "$NEW_REF" 2>"$UPG_ERR_LOG"; then
  fail "upgrade exited 0 on un-adopted target (expected non-zero)"
else
  pass "upgrade exited non-zero on un-adopted target"
fi
grep -q '.remcc/version' "$UPG_ERR_LOG" && pass "error names .remcc/version" || fail "error did not mention .remcc/version"
grep -qi 'install.sh init' "$UPG_ERR_LOG" && pass "error points at install.sh init" || fail "error did not point at install.sh init"
S_AFTER="$(mktemp -d)"; snapshot "$S_AFTER"
for n in protection rulesets actions-perms; do
  if diff -q <(normalize "$S_BEFORE/$n.json") <(normalize "$S_AFTER/$n.json") >/dev/null; then
    pass "no GitHub mutation: $n"
  else
    fail "drift detected after failure-mode run: $n"
  fi
done
rm -f "$UPG_ERR_LOG"

# ----------------------------------------------------------------------------
# Step 3 — seed target with init at OLD_REF, merge PR to land marker on main
# ----------------------------------------------------------------------------
step "Step 3: install.sh init --ref $OLD_REF, merge PR"
bash <(curl -fsSL "$OLD_INSTALL_URL") init --ref "$OLD_REF"
pass "init at $OLD_REF exited 0"
gh pr merge --repo "$TARGET" remcc-init --merge --delete-branch >/dev/null
git checkout main
git pull --ff-only >/dev/null
INIT_INST_AT="$(jq -r .installed_at < .remcc/version)"
INIT_SRC_REF="$(jq -r .source_ref < .remcc/version)"
pass "post-merge installed_at: $INIT_INST_AT, source_ref: $INIT_SRC_REF"
[ "$INIT_SRC_REF" = "$OLD_REF" ] && pass "main records source_ref=$OLD_REF" || fail "main source_ref=$INIT_SRC_REF (expected $OLD_REF)"

# ----------------------------------------------------------------------------
# Step 4 — first upgrade at NEW_REF; assert PR shape and marker preservation
# (task 6.1 a–d)
# ----------------------------------------------------------------------------
step "Step 4: install.sh upgrade --ref $NEW_REF (first run)"
bash <(curl -fsSL "$NEW_INSTALL_URL") upgrade --ref "$NEW_REF"
pass "first upgrade exited 0"

PR_NUM="$(gh pr list --repo "$TARGET" --head remcc-upgrade --state open --json number --jq '.[0].number // empty')"
[ -n "$PR_NUM" ] && pass "remcc-upgrade PR opened (#$PR_NUM)" || fail "no remcc-upgrade PR found"

PR_TITLE="$(gh pr view "$PR_NUM" --repo "$TARGET" --json title --jq .title)"
grep -qi "upgrade remcc to $NEW_REF" <<<"$PR_TITLE" \
  && pass "PR title names new ref: $PR_TITLE" \
  || fail "PR title unexpected: $PR_TITLE"

PR_BODY="$(gh pr view "$PR_NUM" --repo "$TARGET" --json body --jq .body)"
grep -q "Upgrading remcc" <<<"$PR_BODY" && pass "PR body has 'Upgrading remcc' source line" || fail "PR body missing source line"
grep -q "$OLD_REF" <<<"$PR_BODY" && pass "PR body names previous ref $OLD_REF" || fail "PR body missing previous ref"
grep -q "$NEW_REF" <<<"$PR_BODY" && pass "PR body names new ref $NEW_REF" || fail "PR body missing new ref"
for f in opsx-apply.yml .claude/settings.json openspec/config.yaml .remcc/version; do
  grep -q "$f" <<<"$PR_BODY" && pass "PR body lists $f" || fail "PR body missing $f"
done
grep -qi 'next apply run' <<<"$PR_BODY" \
  && pass "PR body has next-apply-run pointer" \
  || fail "PR body missing next-apply-run pointer"
grep -q '### Smoke test' <<<"$PR_BODY" \
  && fail "PR body unexpectedly contains an init-style smoke-test section" \
  || pass "PR body has no smoke-test one-liner (correct)"

git fetch --quiet origin remcc-upgrade
UPG_INST_AT="$(git show origin/remcc-upgrade:.remcc/version | jq -r .installed_at)"
UPG_SRC_REF="$(git show origin/remcc-upgrade:.remcc/version | jq -r .source_ref)"
[ "$UPG_INST_AT" = "$INIT_INST_AT" ] \
  && pass "installed_at preserved on remcc-upgrade: $UPG_INST_AT" \
  || fail "installed_at changed: $INIT_INST_AT → $UPG_INST_AT"
[ "$UPG_SRC_REF" = "$NEW_REF" ] \
  && pass "remcc-upgrade source_ref=$NEW_REF" \
  || fail "remcc-upgrade source_ref=$UPG_SRC_REF (expected $NEW_REF)"

# ----------------------------------------------------------------------------
# Step 5 — re-run upgrade on open PR with a DIFFERENT ref (task 6.3).
# Uses the resolved commit SHA of NEW_REF so the source_ref differs but the
# source_sha may match. Verifies installed_at-from-origin/remcc-upgrade path.
# ----------------------------------------------------------------------------
step "Step 5: re-run upgrade with different --ref (verify origin/remcc-upgrade read)"
NEW_REF_SHA="$(gh api "repos/premeq/remcc/commits/${NEW_REF}" --jq .sha)"
[ -n "$NEW_REF_SHA" ] && pass "resolved $NEW_REF → $NEW_REF_SHA" || fail "could not resolve $NEW_REF to a SHA"

# Step 4's upgrade left local HEAD on remcc-upgrade; upgrade requires main.
git checkout main >/dev/null 2>&1
bash <(curl -fsSL "$NEW_INSTALL_URL") upgrade --ref "$NEW_REF_SHA"
pass "second upgrade exited 0"

PR_COUNT="$(gh pr list --repo "$TARGET" --head remcc-upgrade --state open --json number --jq 'length')"
[ "$PR_COUNT" = "1" ] && pass "exactly one open PR for remcc-upgrade" || fail "expected 1 open PR, found $PR_COUNT"

git fetch --quiet origin remcc-upgrade
UPG_INST_AT_2="$(git show origin/remcc-upgrade:.remcc/version | jq -r .installed_at)"
UPG_SRC_REF_2="$(git show origin/remcc-upgrade:.remcc/version | jq -r .source_ref)"
[ "$UPG_INST_AT_2" = "$INIT_INST_AT" ] \
  && pass "installed_at stable across re-run: $UPG_INST_AT_2" \
  || fail "installed_at changed on re-run: $INIT_INST_AT → $UPG_INST_AT_2"
[ "$UPG_SRC_REF_2" = "$NEW_REF_SHA" ] \
  && pass "remcc-upgrade source_ref updated to $NEW_REF_SHA" \
  || fail "remcc-upgrade source_ref=$UPG_SRC_REF_2 (expected $NEW_REF_SHA)"

# ----------------------------------------------------------------------------
# Step 6 — merge upgrade PR; re-run; assert "already up to date" short-circuit
# (task 6.1 e)
# ----------------------------------------------------------------------------
step "Step 6: merge upgrade PR, re-run upgrade (expect 'already up to date')"
gh pr merge --repo "$TARGET" "$PR_NUM" --merge --delete-branch >/dev/null
git checkout main
git pull --ff-only >/dev/null

THIRD_OUT="$(bash <(curl -fsSL "$NEW_INSTALL_URL") upgrade --ref "$NEW_REF_SHA" 2>&1)"
echo "$THIRD_OUT" | tail -8
grep -qi 'already up to date' <<<"$THIRD_OUT" \
  && pass "third upgrade hit 'already up to date'" \
  || fail "third upgrade did not short-circuit"
PR_AFTER="$(gh pr list --repo "$TARGET" --head remcc-upgrade --state open --json number --jq 'length')"
[ "$PR_AFTER" = "0" ] && pass "no new remcc-upgrade PR opened" || fail "expected 0 open PRs, found $PR_AFTER"

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
if [ "$CLEANUP" = 1 ]; then
  step "Cleanup"
  gh repo delete "$TARGET" --yes
  rm -rf "$WORKDIR" "$S_BEFORE" "$S_AFTER"
  pass "deleted $TARGET and $WORKDIR"
else
  printf '\nArtifacts left in place:\n  repo:    %s\n  workdir: %s\n  snaps:   %s, %s\nRe-run with --cleanup to delete.\n' \
    "$TARGET" "$WORKDIR" "$S_BEFORE" "$S_AFTER"
fi

echo
if [ "$FAILED" = 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
