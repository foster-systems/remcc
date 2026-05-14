#!/usr/bin/env bash
#
# Smoke-test `install.sh init` end-to-end against a throwaway target repo.
# Covers task 7.1 of openspec/changes/gh-remcc-init (plus task 3.4 — the
# second-run idempotency check).
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... scripts/smoke-init.sh \
#     [--target OWNER/NAME] [--ref REF] [--workdir DIR] \
#     [--skip-setup] [--cleanup]
#
# Defaults: --target premeq/remcc-smoke, --ref main, --workdir /tmp/remcc-smoke

set -euo pipefail

TARGET="premeq/remcc-smoke"
REF="main"
WORKDIR="/tmp/remcc-smoke"
SKIP_SETUP=0
CLEANUP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)      TARGET="$2"; shift 2 ;;
    --ref)         REF="$2"; shift 2 ;;
    --workdir)     WORKDIR="$2"; shift 2 ;;
    --skip-setup)  SKIP_SETUP=1; shift ;;
    --cleanup)     CLEANUP=1; shift ;;
    -h|--help)
      sed -n '3,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${ANTHROPIC_API_KEY:?must be set — install.sh passes it through to gh-bootstrap.sh}"
for t in gh jq pnpm git curl; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${REF}/install.sh"
FAILED=0

step() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=1; }

snapshot() {
  # snapshot <out-dir>
  local out="$1"
  mkdir -p "$out"
  gh api "repos/$TARGET/branches/main/protection" 2>/dev/null > "$out/protection.json" || echo '{}' > "$out/protection.json"
  gh api "repos/$TARGET/rulesets" > "$out/rulesets.json"
  gh api "repos/$TARGET/actions/permissions/workflow" > "$out/actions-perms.json"
}

normalize() {
  # normalize <file> — strip volatile fields before diffing
  jq -S 'walk(if type=="object" then del(.id,.node_id,.created_at,.updated_at) else . end)' "$1"
}

# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
if [ "$SKIP_SETUP" = 0 ]; then
  step "Setup: create $TARGET, seed prereqs in $WORKDIR"
  gh repo create "$TARGET" --private --add-readme
  gh repo clone "$TARGET" "$WORKDIR"
  cd "$WORKDIR"
  cat > package.json <<'JSON'
{ "name": "remcc-smoke", "private": true }
JSON
  touch pnpm-lock.yaml
  mkdir -p openspec .claude
  echo '{}' > .claude/settings.json
  touch openspec/.gitkeep
  git add .
  git -c user.email=smoke@example.com -c user.name=smoke commit -m "Seed prereqs"
  git push origin main
fi

cd "$WORKDIR"

# ----------------------------------------------------------------------------
# Step 1 — curl-piped --help (scenario: process substitution)
# ----------------------------------------------------------------------------
step "Step 1: curl-piped --help"
HELP_OUT="$(bash <(curl -fsSL "$INSTALL_URL") --help)"
if grep -qE '^\s*init\b' <<<"$HELP_OUT"; then
  pass "help lists 'init' subcommand"
else
  fail "help does not list 'init' subcommand"
  printf '%s\n' "$HELP_OUT" >&2
fi

# ----------------------------------------------------------------------------
# Step 2 — first init
# ----------------------------------------------------------------------------
step "Step 2: first init"
git checkout main
bash <(curl -fsSL "$INSTALL_URL") init --ref "$REF"
pass "first init exited 0"

# Snapshot after run #1 (this is the reference state for idempotency)
S1="$(mktemp -d)"; snapshot "$S1"

# ----------------------------------------------------------------------------
# Step 3 — verify written artifacts on remcc-init branch
# ----------------------------------------------------------------------------
step "Step 3: verify written artifacts"
git fetch origin remcc-init
git checkout remcc-init

for f in .github/workflows/opsx-apply.yml .claude/settings.json openspec/config.yaml .remcc/version; do
  [ -f "$f" ] && pass "exists: $f" || fail "missing: $f"
done

SRC_REF="$(jq -r .source_ref < .remcc/version)"
SRC_SHA="$(jq -r .source_sha < .remcc/version)"
INST_AT="$(jq -r .installed_at < .remcc/version)"
[ "$SRC_REF" = "$REF" ] && pass "source_ref=$SRC_REF" || fail "source_ref=$SRC_REF (expected $REF)"
[[ "$SRC_SHA" =~ ^[0-9a-f]{40}$ ]] && pass "source_sha is 40-char SHA" || fail "source_sha=$SRC_SHA"
[[ "$INST_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] && pass "installed_at ISO 8601: $INST_AT" || fail "installed_at=$INST_AT"

# ----------------------------------------------------------------------------
# Step 4 — PR body
# ----------------------------------------------------------------------------
step "Step 4: PR body"
PR_BODY="$(gh pr view remcc-init --repo "$TARGET" --json body --jq .body)"
for f in opsx-apply.yml .claude/settings.json openspec/config.yaml .remcc/version; do
  grep -q "$f" <<<"$PR_BODY" && pass "PR body mentions $f" || fail "PR body missing $f"
done
grep -qiE 'pre-existing|customization|collision|verify the diff' <<<"$PR_BODY" \
  && pass "PR body flags pre-existing paths" \
  || fail "PR body does not flag pre-existing paths"
grep -qi 'smoke' <<<"$PR_BODY" \
  && pass "PR body has smoke-test one-liner" \
  || fail "PR body lacks smoke-test one-liner"

# ----------------------------------------------------------------------------
# Step 5 — no apply run triggered
# ----------------------------------------------------------------------------
step "Step 5: no opsx-apply run"
RUNS="$(gh run list --repo "$TARGET" --workflow opsx-apply.yml --json databaseId --jq 'length' 2>/dev/null || echo 0)"
[ "$RUNS" = "0" ] && pass "no opsx-apply runs" || fail "$RUNS opsx-apply run(s) triggered"

# ----------------------------------------------------------------------------
# Step 6 — second init for bootstrap idempotency
# Spec scenario: "Re-running init is a bootstrap no-op" — exits zero, no
# GitHub-side config drift, and reuses the existing PR rather than opening
# another. (Task 5.6's "already up to date" path requires post-merge state
# and is exercised by task 7.3, not here.)
# ----------------------------------------------------------------------------
step "Step 6: second init (idempotency)"
git checkout main
bash <(curl -fsSL "$INSTALL_URL") init --ref "$REF"
pass "second init exited 0"

PR_COUNT="$(gh pr list --repo "$TARGET" --head remcc-init --state open --json number --jq 'length')"
[ "$PR_COUNT" = "1" ] \
  && pass "exactly one open PR for remcc-init (no duplicate opened)" \
  || fail "expected 1 open PR for remcc-init, found $PR_COUNT"

S2="$(mktemp -d)"; snapshot "$S2"
for n in protection rulesets actions-perms; do
  if diff -q <(normalize "$S1/$n.json") <(normalize "$S2/$n.json") >/dev/null; then
    pass "idempotent: $n"
  else
    fail "drift detected: $n"
    diff <(normalize "$S1/$n.json") <(normalize "$S2/$n.json") | head -20 >&2
  fi
done

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
if [ "$CLEANUP" = 1 ]; then
  step "Cleanup"
  gh repo delete "$TARGET" --yes
  rm -rf "$WORKDIR" "$S1" "$S2"
  pass "deleted $TARGET and $WORKDIR"
else
  printf '\nArtifacts left in place:\n  repo:    %s\n  workdir: %s\n  snaps:   %s, %s\nRe-run with --cleanup to delete.\n' \
    "$TARGET" "$WORKDIR" "$S1" "$S2"
fi

echo
if [ "$FAILED" = 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
