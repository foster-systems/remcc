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
#   - The repository variables OPSX_APPLY_MODEL and OPSX_APPLY_EFFORT, which
#     set per-repo defaults for the /opsx:apply step. Each is prompted or
#     read from an env var of the same name; empty input leaves the variable
#     unset, in which case the workflow's baked-in defaults (sonnet/high)
#     apply.
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

owner_type() {
  local repo="$1"
  gh api "repos/${repo}" --jq .owner.type 2>/dev/null
}

push_rulesets_supported() {
  local repo="$1"
  [ "$(owner_type "${repo}")" = "Organization" ]
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
  if ! push_rulesets_supported "${repo}"; then
    sub "WARNING: GitHub push rulesets are only available on organization-owned"
    sub "repositories. ${repo} is user-owned, so the .github/** push restriction"
    sub "cannot be enforced via rulesets. The branch ruleset still confines the"
    sub "bot to change/** branches; .github/** edits within agent PRs must be"
    sub "caught by your PR review. See docs/SECURITY.md for the full picture."
    return 0
  fi
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

secret_scanning_available() {
  local repo="$1" body
  body="$(gh api "repos/${repo}" 2>/dev/null)" || return 1
  # If the repo is public, secret scanning is always available.
  if [ "$(printf '%s' "${body}" | jq -r '.private')" = "false" ]; then
    return 0
  fi
  # Private repos: only available with GitHub Advanced Security
  # (security_and_analysis surfaces as a non-null object in that case).
  [ "$(printf '%s' "${body}" | jq -r '.security_and_analysis')" != "null" ]
}

configure_secret_scanning() {
  local repo="$1"
  log "Secret scanning + push protection (${repo})"
  if ! secret_scanning_available "${repo}"; then
    sub "WARNING: secret scanning is not available on this repository. GitHub"
    sub "ships secret scanning for free on public repos and as part of GitHub"
    sub "Advanced Security on private repos. ${repo} is private without GHAS,"
    sub "so the secret-scanning backstop is not active. ANTHROPIC_API_KEY is"
    sub "still redacted from workflow logs by GitHub Actions. Treat any commit"
    sub "with secret-shaped content as needing manual review. See docs/SECURITY.md."
    return 0
  fi
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
# Allow GitHub Actions to create pull requests
# ----------------------------------------------------------------------------
#
# By default, the auto-provisioned GITHUB_TOKEN cannot open or approve PRs.
# The workflow's "Open or update PR" step needs this enabled. The setting maps
# to the "Allow GitHub Actions to create and approve pull requests" toggle in
# Settings → Actions → General. Note: this also allows Actions to *approve*
# PRs, but the workflow's permissions block does not exercise that capability.

configure_actions_pr_creation() {
  local repo="$1"
  log "Allow GitHub Actions to create pull requests (${repo})"
  gh api --method PUT "repos/${repo}/actions/permissions/workflow" --input - >/dev/null <<'JSON'
{
  "default_workflow_permissions": "write",
  "can_approve_pull_request_reviews": true
}
JSON
  sub "enabled"
}

disable_actions_pr_creation() {
  local repo="$1"
  log "Disabling GitHub Actions PR creation (${repo})"
  gh api --method PUT "repos/${repo}/actions/permissions/workflow" --input - >/dev/null <<'JSON'
{
  "default_workflow_permissions": "read",
  "can_approve_pull_request_reviews": false
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
# Apply configuration variables: OPSX_APPLY_MODEL / OPSX_APPLY_EFFORT
# ----------------------------------------------------------------------------

read_apply_config_into_env() {
  if [ -z "${OPSX_APPLY_MODEL+x}" ]; then
    if [ -t 0 ]; then
      printf 'OPSX_APPLY_MODEL (Claude model for /opsx:apply, e.g. opus, sonnet, haiku; empty to skip): ' >&2
      IFS= read -r OPSX_APPLY_MODEL || OPSX_APPLY_MODEL=""
    else
      OPSX_APPLY_MODEL=""
    fi
    export OPSX_APPLY_MODEL
  fi

  if [ -z "${OPSX_APPLY_EFFORT+x}" ]; then
    if [ -t 0 ]; then
      printf 'OPSX_APPLY_EFFORT (low|medium|high; empty to skip): ' >&2
      IFS= read -r OPSX_APPLY_EFFORT || OPSX_APPLY_EFFORT=""
    else
      OPSX_APPLY_EFFORT=""
    fi
    export OPSX_APPLY_EFFORT
  fi

  if [ -n "${OPSX_APPLY_EFFORT:-}" ]; then
    case "${OPSX_APPLY_EFFORT}" in
      low|medium|high) ;;
      *) err "OPSX_APPLY_EFFORT must be one of: low, medium, high (got '${OPSX_APPLY_EFFORT}')" ;;
    esac
  fi
}

get_repo_variable_value() {
  local repo="$1" name="$2"
  gh api "repos/${repo}/actions/variables/${name}" --jq '.value' 2>/dev/null || true
}

set_repo_variable() {
  local repo="$1" name="$2" value="$3" current
  current="$(get_repo_variable_value "${repo}" "${name}")"
  if [ "${current}" = "${value}" ]; then
    sub "${name} unchanged (= ${value})"
    return 0
  fi
  gh variable set "${name}" --repo "${repo}" --body "${value}" >/dev/null
  sub "${name} set to ${value}"
}

configure_apply_config_variables() {
  local repo="$1"
  log "Apply configuration variables (${repo})"
  read_apply_config_into_env
  if [ -n "${OPSX_APPLY_MODEL:-}" ]; then
    set_repo_variable "${repo}" OPSX_APPLY_MODEL "${OPSX_APPLY_MODEL}"
  else
    sub "OPSX_APPLY_MODEL not provided; workflow will use its baked-in default (sonnet)"
  fi
  if [ -n "${OPSX_APPLY_EFFORT:-}" ]; then
    set_repo_variable "${repo}" OPSX_APPLY_EFFORT "${OPSX_APPLY_EFFORT}"
  else
    sub "OPSX_APPLY_EFFORT not provided; workflow will use its baked-in default (high)"
  fi
}

remove_apply_config_variables() {
  local repo="$1" name
  log "Removing apply configuration variables (${repo})"
  for name in OPSX_APPLY_MODEL OPSX_APPLY_EFFORT; do
    if gh api "repos/${repo}/actions/variables/${name}" --silent >/dev/null 2>&1; then
      gh variable delete "${name}" --repo "${repo}" >/dev/null
      sub "${name} removed"
    else
      sub "${name} already absent"
    fi
  done
}

# ----------------------------------------------------------------------------
# Idempotency smoke test
# ----------------------------------------------------------------------------

snapshot_state() {
  local repo="$1" bid pid name
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
  echo "# actions workflow permissions"
  gh api "repos/${repo}/actions/permissions/workflow" 2>/dev/null || true
  echo "# apply configuration variables"
  for name in OPSX_APPLY_MODEL OPSX_APPLY_EFFORT; do
    if gh api "repos/${repo}/actions/variables/${name}" --silent >/dev/null 2>&1; then
      gh api "repos/${repo}/actions/variables/${name}" \
        | jq '{name, value}' || true
    else
      echo "{\"name\":\"${name}\",\"value\":null}"
    fi
  done
}

run_idempotency_smoke_test() {
  local repo="$1" before after
  log "Idempotency smoke test"
  before="$(snapshot_state "${repo}")"
  configure_main_protection "${repo}"
  configure_branch_ruleset "${repo}"
  configure_push_ruleset "${repo}"
  configure_secret_scanning "${repo}"
  configure_actions_pr_creation "${repo}"
  configure_apply_config_variables "${repo}"
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
  configure_actions_pr_creation "${repo}"
  configure_anthropic_secret "${repo}"
  configure_apply_config_variables "${repo}"
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
  disable_actions_pr_creation "${repo}"
  remove_anthropic_secret "${repo}"
  remove_apply_config_variables "${repo}"

  log "Uninstall complete for ${repo}"
}

case "${1:-}" in
  ''|install) install_remcc ;;
  --uninstall|uninstall) uninstall_remcc ;;
  -h|--help) usage ;;
  *) usage; exit 1 ;;
esac
