#!/usr/bin/env bash
#
# gh-bootstrap.sh — configure a target GitHub repository for remcc adoption.
#
# Usage:
#   bash gh-bootstrap.sh                  install / reconcile (idempotent)
#   bash gh-bootstrap.sh --uninstall      revert remcc-managed configuration
#   bash gh-bootstrap.sh --help
#
# What this script touches on the GitHub side:
#   - Branch protection on `main` (PR required, no force push, no deletions).
#   - A branch ruleset blocking non-admin updates to refs that do not match
#     `refs/heads/change/**`. The workflow's GITHUB_TOKEN is therefore confined
#     to `change/**` branches; the operator (admin) bypasses.
#   - A push ruleset blocking modifications to paths under `.github/**`. The
#     bot is therefore unable to rewrite CI; the operator (admin) bypasses.
#   - Secret scanning + secret push protection on the repository.
#   - The repository secret ANTHROPIC_API_KEY (prompted or read from env).
#
# Prerequisites:
#   - `gh` (GitHub CLI) authenticated as an account with admin on the target.
#   - `jq` for JSON parsing.
#   - Run from inside a clone of the target repository.
#
# Re-running this script is a no-op: an idempotency smoke test at the end
# re-applies every change and diffs the resulting state.

set -euo pipefail

readonly RULESET_BRANCH_NAME="remcc: restrict bot to change branches"
readonly RULESET_PUSH_NAME="remcc: block bot edits under .github"
readonly ROLE_ID_ADMIN=5

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

err() { printf 'error: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }
sub() { printf '    %s\n' "$*"; }

ensure_prereqs() {
  command -v gh >/dev/null 2>&1 || err "gh CLI not found on PATH (https://cli.github.com)"
  command -v jq >/dev/null 2>&1 || err "jq not found on PATH"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || err "must be run from inside a git repository"
  gh auth status >/dev/null 2>&1 \
    || err "gh is not authenticated; run 'gh auth login' first"
}

resolve_repo() {
  gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null \
    || err "could not resolve a GitHub repo from the current git context"
}

# ----------------------------------------------------------------------------
# Branch protection on main
# ----------------------------------------------------------------------------

want_branch_protection_json() {
  cat <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
}

configure_main_protection() {
  local repo="$1"
  log "Branch protection on main (${repo})"
  want_branch_protection_json \
    | gh api --method PUT "repos/${repo}/branches/main/protection" --input - >/dev/null
  sub "applied"
}

remove_main_protection() {
  local repo="$1"
  log "Removing branch protection on main (${repo})"
  if gh api "repos/${repo}/branches/main/protection" --silent >/dev/null 2>&1; then
    gh api --method DELETE "repos/${repo}/branches/main/protection" >/dev/null
    sub "removed"
  else
    sub "already absent"
  fi
}

# ----------------------------------------------------------------------------
# Rulesets
# ----------------------------------------------------------------------------

want_branch_ruleset_json() {
  cat <<JSON
{
  "name": "${RULESET_BRANCH_NAME}",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~ALL"],
      "exclude": ["refs/heads/change/**"]
    }
  },
  "rules": [
    { "type": "creation" },
    { "type": "update" },
    { "type": "deletion" },
    { "type": "non_fast_forward" }
  ],
  "bypass_actors": [
    { "actor_id": ${ROLE_ID_ADMIN}, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ]
}
JSON
}

want_push_ruleset_json() {
  cat <<JSON
{
  "name": "${RULESET_PUSH_NAME}",
  "target": "push",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~ALL"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "file_path_restriction",
      "parameters": { "restricted_file_paths": [".github/**"] }
    }
  ],
  "bypass_actors": [
    { "actor_id": ${ROLE_ID_ADMIN}, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ]
}
JSON
}

find_ruleset_id() {
  local repo="$1" name="$2"
  gh api "repos/${repo}/rulesets" --jq ".[] | select(.name==\"${name}\") | .id" 2>/dev/null \
    | head -n1
}

reconcile_ruleset() {
  local repo="$1" name="$2" body="$3" id
  id="$(find_ruleset_id "${repo}" "${name}" || true)"
  if [ -n "${id:-}" ]; then
    sub "ruleset '${name}' exists (id=${id}); reconciling"
    printf '%s' "${body}" \
      | gh api --method PUT "repos/${repo}/rulesets/${id}" --input - >/dev/null
  else
    sub "ruleset '${name}' missing; creating"
    printf '%s' "${body}" \
      | gh api --method POST "repos/${repo}/rulesets" --input - >/dev/null
  fi
}

configure_branch_ruleset() {
  local repo="$1"
  log "Branch ruleset (bot confined to refs/heads/change/**)"
  reconcile_ruleset "${repo}" "${RULESET_BRANCH_NAME}" "$(want_branch_ruleset_json)"
}

configure_push_ruleset() {
  local repo="$1"
  log "Push ruleset (bot blocked from editing .github/**)"
  reconcile_ruleset "${repo}" "${RULESET_PUSH_NAME}" "$(want_push_ruleset_json)"
}

remove_ruleset_by_name() {
  local repo="$1" name="$2" id
  id="$(find_ruleset_id "${repo}" "${name}" || true)"
  if [ -n "${id:-}" ]; then
    gh api --method DELETE "repos/${repo}/rulesets/${id}" >/dev/null
    sub "ruleset '${name}' removed"
  else
    sub "ruleset '${name}' already absent"
  fi
}

# ----------------------------------------------------------------------------
# Secret scanning + push protection
# ----------------------------------------------------------------------------

configure_secret_scanning() {
  local repo="$1"
  log "Secret scanning + push protection (${repo})"
  gh api --method PATCH "repos/${repo}" --input - >/dev/null <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
JSON
  sub "enabled"
}

disable_secret_scanning() {
  local repo="$1"
  log "Disabling secret scanning + push protection (${repo})"
  gh api --method PATCH "repos/${repo}" --input - >/dev/null <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "disabled" },
    "secret_scanning_push_protection": { "status": "disabled" }
  }
}
JSON
  sub "disabled"
}

# ----------------------------------------------------------------------------
# ANTHROPIC_API_KEY repository secret
# ----------------------------------------------------------------------------

read_anthropic_key_into_env() {
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    return 0
  fi
  printf 'Enter ANTHROPIC_API_KEY (input hidden): ' >&2
  local key=""
  if [ -t 0 ]; then
    stty -echo
    IFS= read -r key
    stty echo
    printf '\n' >&2
  else
    IFS= read -r key
  fi
  [ -n "${key}" ] || err "ANTHROPIC_API_KEY was empty"
  export ANTHROPIC_API_KEY="${key}"
}

configure_anthropic_secret() {
  local repo="$1"
  log "Repository secret ANTHROPIC_API_KEY (${repo})"
  read_anthropic_key_into_env
  printf '%s' "${ANTHROPIC_API_KEY}" \
    | gh secret set ANTHROPIC_API_KEY --repo "${repo}" >/dev/null
  sub "uploaded"
}

remove_anthropic_secret() {
  local repo="$1"
  log "Removing repository secret ANTHROPIC_API_KEY (${repo})"
  if gh secret list --repo "${repo}" --json name --jq '.[].name' \
       | grep -qx ANTHROPIC_API_KEY; then
    gh secret delete ANTHROPIC_API_KEY --repo "${repo}" >/dev/null
    sub "removed"
  else
    sub "already absent"
  fi
}

# ----------------------------------------------------------------------------
# Idempotency smoke test
# ----------------------------------------------------------------------------

snapshot_state() {
  local repo="$1" bid pid
  echo "# branch protection on main"
  gh api "repos/${repo}/branches/main/protection" 2>/dev/null \
    | jq 'del(.url, .self_link, .urls)' || true
  echo "# branch ruleset"
  bid="$(find_ruleset_id "${repo}" "${RULESET_BRANCH_NAME}" || true)"
  if [ -n "${bid:-}" ]; then
    gh api "repos/${repo}/rulesets/${bid}" \
      | jq 'del(.id, .updated_at, .created_at, ._links, .links, .source_type, .source, .node_id)' || true
  fi
  echo "# push ruleset"
  pid="$(find_ruleset_id "${repo}" "${RULESET_PUSH_NAME}" || true)"
  if [ -n "${pid:-}" ]; then
    gh api "repos/${repo}/rulesets/${pid}" \
      | jq 'del(.id, .updated_at, .created_at, ._links, .links, .source_type, .source, .node_id)' || true
  fi
  echo "# security_and_analysis"
  gh api "repos/${repo}" --jq '.security_and_analysis' 2>/dev/null || true
}

run_idempotency_smoke_test() {
  local repo="$1" before after
  log "Idempotency smoke test"
  before="$(snapshot_state "${repo}")"
  configure_main_protection "${repo}"
  configure_branch_ruleset "${repo}"
  configure_push_ruleset "${repo}"
  configure_secret_scanning "${repo}"
  after="$(snapshot_state "${repo}")"
  if [ "${before}" = "${after}" ]; then
    sub "confirmed: configuration unchanged on re-apply"
  else
    {
      echo "::: state diff :::"
      diff <(printf '%s' "${before}") <(printf '%s' "${after}") || true
    } >&2
    err "idempotency check failed; state drifted on re-apply"
  fi
}

# ----------------------------------------------------------------------------
# Entry points
# ----------------------------------------------------------------------------

usage() {
  cat <<'USAGE'
Usage:
  bash gh-bootstrap.sh                install / reconcile (idempotent)
  bash gh-bootstrap.sh --uninstall    revert remcc-managed configuration
  bash gh-bootstrap.sh --help         show this message

The install path will prompt for ANTHROPIC_API_KEY unless it is already set in
the environment. The uninstall path does not delete repository content; it
only reverses the GitHub-side configuration this script applies.
USAGE
}

install_remcc() {
  ensure_prereqs
  local repo
  repo="$(resolve_repo)"
  log "Target repository: ${repo}"

  configure_main_protection "${repo}"
  configure_branch_ruleset "${repo}"
  configure_push_ruleset "${repo}"
  configure_secret_scanning "${repo}"
  configure_anthropic_secret "${repo}"
  run_idempotency_smoke_test "${repo}"

  log "Bootstrap complete for ${repo}"
}

uninstall_remcc() {
  ensure_prereqs
  local repo
  repo="$(resolve_repo)"
  log "Target repository: ${repo}"

  remove_ruleset_by_name "${repo}" "${RULESET_BRANCH_NAME}"
  remove_ruleset_by_name "${repo}" "${RULESET_PUSH_NAME}"
  remove_main_protection "${repo}"
  disable_secret_scanning "${repo}"
  remove_anthropic_secret "${repo}"

  log "Uninstall complete for ${repo}"
}

case "${1:-}" in
  ''|install) install_remcc ;;
  --uninstall|uninstall) uninstall_remcc ;;
  -h|--help) usage ;;
  *) usage; exit 1 ;;
esac
