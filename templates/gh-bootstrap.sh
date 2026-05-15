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
#   - A branch ruleset on the repository's default branch (only) that requires
#     a pull request and at least one approval to merge and blocks force-push.
#     The operator (admin) bypasses for emergency merges. Deletion of the
#     default branch is intentionally NOT blocked by this ruleset.
#
#     This script does NOT touch any pre-existing branch protection or any
#     prior-version remcc-managed rulesets. Adopters upgrading from prior
#     versions keep whatever legacy controls they already have until they
#     remove them themselves in the GitHub UI (Settings -> Branches,
#     Settings -> Rules -> Rulesets). See docs/SETUP.md for the exact opt-in
#     recipe.
#   - Secret scanning + secret push protection on the repository.
#   - The repository secret ANTHROPIC_API_KEY (prompted or read from env).
#   - The repository secrets REMCC_APP_ID and REMCC_APP_PRIVATE_KEY (prompted
#     or read from env). The `opsx-apply` workflow exchanges these for a
#     short-lived GitHub App installation token at the start of every run,
#     and uses it for checkout, push, and PR creation — so the workflow's
#     PR author is the App's bot identity, not the operator. Create the App
#     under your account at https://github.com/settings/apps/new with
#     permissions `Contents: write`, `Pull requests: write`, `Workflows: write`,
#     `Metadata: read`, install it on the target repo, then download the
#     private-key PEM and pass it here.
#   - The repository variable REMCC_APP_SLUG (prompted or read from env).
#     The workflow constructs the bot's commit identity from this slug
#     (`<slug>[bot]`).
#   - Any pre-existing legacy `WORKFLOW_PAT` secret is removed once the App
#     secrets are installed (the workflow no longer reads it).
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

readonly RULESET_MAIN_NAME="remcc: require approval on main"
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
# Main-branch approval ruleset
#
# This script installs a single repository branch ruleset on the default
# branch (only) requiring a pull request and at least one approval to merge,
# and blocking force-push. Admin (RepositoryRole 5) bypasses. No other
# ref/path-level interdiction is installed — PR review on merge is the gate.
#
# This script does NOT touch any pre-existing branch protection (legacy
# /branches/<name>/protection endpoint) or any prior-version remcc-managed
# rulesets. Adopters upgrading from prior versions keep their legacy items
# in place; converging to the new model is a manual UI action.
# ----------------------------------------------------------------------------

want_main_ruleset_json() {
  cat <<JSON
{
  "name": "${RULESET_MAIN_NAME}",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    { "type": "non_fast_forward" }
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

configure_main_ruleset() {
  local repo="$1"
  log "Main-branch approval ruleset (default branch only; PR + 1 approval; blocks force-push)"
  reconcile_ruleset "${repo}" "${RULESET_MAIN_NAME}" "$(want_main_ruleset_json)"
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
# remcc GitHub App credentials
#
# The opsx-apply workflow authenticates as a dedicated GitHub App per run
# rather than a per-operator PAT. The three config items together identify
# the App:
#   - REMCC_APP_ID            (secret)   numeric App ID
#   - REMCC_APP_PRIVATE_KEY   (secret)   multi-line PEM
#   - REMCC_APP_SLUG          (variable) lower-case slug from the App's URL
# An empty private key or slug is a hard error — the workflow needs both.
# ----------------------------------------------------------------------------

read_remcc_app_id_into_env() {
  if [ -n "${REMCC_APP_ID:-}" ]; then
    return 0
  fi
  printf 'Enter REMCC_APP_ID (numeric App ID from your GitHub App settings page; input hidden): ' >&2
  local app_id=""
  if [ -t 0 ]; then
    stty -echo
    IFS= read -r app_id
    stty echo
    printf '\n' >&2
  else
    IFS= read -r app_id
  fi
  [ -n "${app_id}" ] || err "REMCC_APP_ID was empty"
  export REMCC_APP_ID="${app_id}"
}

# Read a multi-line PEM into REMCC_APP_PRIVATE_KEY. Terminated by an empty
# line — safe because standard RSA/PKCS PEMs have no internal blank lines.
# Input echo is suppressed when stdin is a TTY.
read_remcc_app_private_key_into_env() {
  if [ -n "${REMCC_APP_PRIVATE_KEY:-}" ]; then
    return 0
  fi
  printf 'Enter REMCC_APP_PRIVATE_KEY (paste the PEM, then a blank line; input hidden):\n' >&2
  local line key=""
  if [ -t 0 ]; then
    stty -echo
  fi
  while IFS= read -r line; do
    [ -z "${line}" ] && break
    if [ -z "${key}" ]; then
      key="${line}"
    else
      key="${key}
${line}"
    fi
  done
  if [ -t 0 ]; then
    stty echo
    printf '\n' >&2
  fi
  [ -n "${key}" ] || err "REMCC_APP_PRIVATE_KEY was empty"
  export REMCC_APP_PRIVATE_KEY="${key}"
}

configure_remcc_app_secrets() {
  local repo="$1"
  log "Repository secrets REMCC_APP_ID + REMCC_APP_PRIVATE_KEY (${repo})"
  sub "remcc GitHub App permissions required: Contents:write, Pull requests:write, Workflows:write, Metadata:read"
  read_remcc_app_id_into_env
  read_remcc_app_private_key_into_env
  # Piping via stdin preserves the multi-line PEM byte-for-byte; `gh secret
  # set --body` would mangle newlines.
  printf '%s' "${REMCC_APP_ID}" \
    | gh secret set REMCC_APP_ID --repo "${repo}" >/dev/null
  printf '%s' "${REMCC_APP_PRIVATE_KEY}" \
    | gh secret set REMCC_APP_PRIVATE_KEY --repo "${repo}" >/dev/null
  sub "uploaded"
}

remove_remcc_app_secrets() {
  local repo="$1" name
  log "Removing repository secrets REMCC_APP_ID + REMCC_APP_PRIVATE_KEY (${repo})"
  for name in REMCC_APP_ID REMCC_APP_PRIVATE_KEY; do
    if gh secret list --repo "${repo}" --json name --jq '.[].name' \
         | grep -qx "${name}"; then
      gh secret delete "${name}" --repo "${repo}" >/dev/null
      sub "${name} removed"
    else
      sub "${name} already absent"
    fi
  done
}

read_remcc_app_slug_into_env() {
  if [ -n "${REMCC_APP_SLUG:-}" ]; then
    return 0
  fi
  if [ -t 0 ]; then
    printf 'Enter REMCC_APP_SLUG (the slug from the App URL github.com/apps/<slug>; visible): ' >&2
    IFS= read -r REMCC_APP_SLUG || REMCC_APP_SLUG=""
  else
    IFS= read -r REMCC_APP_SLUG || REMCC_APP_SLUG=""
  fi
  [ -n "${REMCC_APP_SLUG:-}" ] \
    || err "REMCC_APP_SLUG was empty (the workflow needs the slug to construct the bot's git identity)"
  export REMCC_APP_SLUG
}

configure_remcc_app_slug_variable() {
  local repo="$1"
  log "Repository variable REMCC_APP_SLUG (${repo})"
  read_remcc_app_slug_into_env
  set_repo_variable "${repo}" REMCC_APP_SLUG "${REMCC_APP_SLUG}"
}

remove_remcc_app_slug_variable() {
  local repo="$1"
  log "Removing repository variable REMCC_APP_SLUG (${repo})"
  if gh api "repos/${repo}/actions/variables/REMCC_APP_SLUG" --silent >/dev/null 2>&1; then
    gh variable delete REMCC_APP_SLUG --repo "${repo}" >/dev/null
    sub "removed"
  else
    sub "already absent"
  fi
}

# Remove the legacy WORKFLOW_PAT secret left over from pre-App adopters.
# Runs AFTER the new App secrets are confirmed installed (see install_remcc)
# so a failed migration leaves the legacy PAT in place and the old workflow
# keeps working.
remove_workflow_pat_legacy() {
  local repo="$1"
  log "Removing legacy WORKFLOW_PAT secret if present (${repo})"
  if gh secret list --repo "${repo}" --json name --jq '.[].name' \
       | grep -qx WORKFLOW_PAT; then
    gh secret delete WORKFLOW_PAT --repo "${repo}" >/dev/null
    sub "removed"
  else
    sub "already absent"
  fi
}

# ----------------------------------------------------------------------------
# Apply configuration variables: OPSX_APPLY_MODEL / OPSX_APPLY_EFFORT
# ----------------------------------------------------------------------------

read_apply_config_into_env() {
  local repo="$1" existing

  if [ -z "${OPSX_APPLY_MODEL+x}" ]; then
    existing="$(get_repo_variable_value "${repo}" OPSX_APPLY_MODEL)"
    if [ -n "${existing}" ]; then
      OPSX_APPLY_MODEL="${existing}"
    elif [ -t 0 ]; then
      printf 'OPSX_APPLY_MODEL (Claude model for /opsx:apply, e.g. opus, sonnet, haiku; empty to skip): ' >&2
      IFS= read -r OPSX_APPLY_MODEL || OPSX_APPLY_MODEL=""
    else
      OPSX_APPLY_MODEL=""
    fi
    export OPSX_APPLY_MODEL
  fi

  if [ -z "${OPSX_APPLY_EFFORT+x}" ]; then
    existing="$(get_repo_variable_value "${repo}" OPSX_APPLY_EFFORT)"
    if [ -n "${existing}" ]; then
      OPSX_APPLY_EFFORT="${existing}"
    elif [ -t 0 ]; then
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
  local repo="$1" name="$2" body
  # gh api with --jq still prints the raw error body to stdout on 404, which
  # leaked the JSON error blob into callers. Fetch the body, then extract
  # .value via jq only when it's a real success response.
  body="$(gh api "repos/${repo}/actions/variables/${name}" 2>/dev/null)" || true
  [ -n "${body}" ] || return 0
  printf '%s' "${body}" | jq -r 'if type=="object" and has("value") then .value else empty end'
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
  read_apply_config_into_env "${repo}"
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
  local repo="$1" mid name secret_names
  echo "# main ruleset"
  mid="$(find_ruleset_id "${repo}" "${RULESET_MAIN_NAME}" || true)"
  if [ -n "${mid:-}" ]; then
    gh api "repos/${repo}/rulesets/${mid}" \
      | jq 'del(.id, .updated_at, .created_at, ._links, .links, .source_type, .source, .node_id)' || true
  fi
  echo "# security_and_analysis"
  gh api "repos/${repo}" --jq '.security_and_analysis' 2>/dev/null || true
  echo "# actions workflow permissions"
  gh api "repos/${repo}/actions/permissions/workflow" 2>/dev/null || true
  echo "# remcc App secrets (presence only — values are never read back)"
  secret_names="$(gh secret list --repo "${repo}" --json name --jq '.[].name' 2>/dev/null || true)"
  for name in REMCC_APP_ID REMCC_APP_PRIVATE_KEY WORKFLOW_PAT; do
    if printf '%s\n' "${secret_names}" | grep -qx "${name}"; then
      echo "{\"name\":\"${name}\",\"present\":true}"
    else
      echo "{\"name\":\"${name}\",\"present\":false}"
    fi
  done
  echo "# remcc App slug variable"
  if gh api "repos/${repo}/actions/variables/REMCC_APP_SLUG" --silent >/dev/null 2>&1; then
    gh api "repos/${repo}/actions/variables/REMCC_APP_SLUG" \
      | jq '{name, value}' || true
  else
    echo "{\"name\":\"REMCC_APP_SLUG\",\"value\":null}"
  fi
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
  configure_main_ruleset "${repo}"
  configure_secret_scanning "${repo}"
  configure_actions_pr_creation "${repo}"
  configure_remcc_app_slug_variable "${repo}"
  remove_workflow_pat_legacy "${repo}"
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

The install path will prompt for ANTHROPIC_API_KEY, REMCC_APP_ID,
REMCC_APP_PRIVATE_KEY, and REMCC_APP_SLUG unless they are already set in the
environment. The three REMCC_APP_* values identify a GitHub App the operator
has created (one-time, per docs/SETUP.md) with permissions Contents:write,
Pull requests:write, Workflows:write, Metadata:read, installed on the target
repo. The workflow mints a short-lived installation token from these
credentials and uses it for checkout, push, and PR creation — so the bot's
PR author is the App, not the operator.

The uninstall path does not delete repository content; it only reverses the
GitHub-side configuration this script applies.
USAGE
}

install_remcc() {
  ensure_prereqs
  local repo
  repo="$(resolve_repo)"
  log "Target repository: ${repo}"

  configure_main_ruleset "${repo}"
  configure_secret_scanning "${repo}"
  configure_actions_pr_creation "${repo}"
  configure_anthropic_secret "${repo}"
  configure_remcc_app_secrets "${repo}"
  configure_remcc_app_slug_variable "${repo}"
  # Only after the App secrets and slug variable land successfully do we
  # remove the legacy WORKFLOW_PAT — a failed App install leaves the legacy
  # PAT in place so the old workflow keeps working.
  remove_workflow_pat_legacy "${repo}"
  configure_apply_config_variables "${repo}"
  run_idempotency_smoke_test "${repo}"

  log "Bootstrap complete for ${repo}"
}

uninstall_remcc() {
  ensure_prereqs
  local repo
  repo="$(resolve_repo)"
  log "Target repository: ${repo}"

  remove_ruleset_by_name "${repo}" "${RULESET_MAIN_NAME}"
  disable_secret_scanning "${repo}"
  disable_actions_pr_creation "${repo}"
  remove_anthropic_secret "${repo}"
  remove_remcc_app_secrets "${repo}"
  remove_remcc_app_slug_variable "${repo}"
  # Cover legacy adopters whose state still carries WORKFLOW_PAT (uninstall
  # on a repo that was never migrated should still be a clean wipe).
  remove_workflow_pat_legacy "${repo}"
  remove_apply_config_variables "${repo}"

  log "Uninstall complete for ${repo}"
}

case "${1:-}" in
  ''|install) install_remcc ;;
  --uninstall|uninstall) uninstall_remcc ;;
  -h|--help) usage ;;
  *) usage; exit 1 ;;
esac
