#!/usr/bin/env bash
#
# install.sh — adopt remcc in a target GitHub repository.
#
# Usage (one-liner):
#   bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) init
#
# Usage (inspect first):
#   curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh -o install.sh
#   less install.sh
#   bash install.sh init
#
# Subcommands:
#   init          adopt remcc in the current working directory's repo
#   --help        show this message
#
# Options (init):
#   --ref <ref>   remcc tag or commit to fetch templates from. Defaults to
#                 the latest release tag on premeq/remcc, falling back to
#                 'main' with a warning if no releases exist.

set -euo pipefail

readonly REMCC_REPO="premeq/remcc"
readonly REMCC_CLONE_URL="https://github.com/${REMCC_REPO}.git"
readonly INIT_BRANCH="remcc-init"
readonly INIT_COMMIT_SUBJECT="Adopt remcc via install.sh init"

# Tempdir for the remcc source clone. Cleaned up on exit.
REMCC_SRC_DIR=""

cleanup() {
  if [ -n "${REMCC_SRC_DIR}" ] && [ -d "${REMCC_SRC_DIR}" ]; then
    rm -rf "${REMCC_SRC_DIR}"
  fi
}
trap cleanup EXIT

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
log()  { printf '==> %s\n' "$*"; }
sub()  { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Read a line from /dev/tty so the script works under `curl | bash -s --`
# (where stdin is the curl pipe rather than the terminal).
read_tty() {
  local prompt="$1" __varname="$2" __val=""
  if [ -r /dev/tty ]; then
    printf '%s' "${prompt}" >/dev/tty
    IFS= read -r __val </dev/tty
  else
    printf '%s' "${prompt}" >&2
    IFS= read -r __val
  fi
  printf -v "${__varname}" '%s' "${__val}"
}

# ----------------------------------------------------------------------------
# Usage / help
# ----------------------------------------------------------------------------

usage_root() {
  cat <<'USAGE'
install.sh — adopt remcc (remote Claude Code) in a GitHub repo.

Usage:
  install.sh <subcommand> [options]
  install.sh --help

Subcommands:
  init     Adopt remcc in the current repository (prereq check, GitHub-side
           bootstrap, template-file install, pull request).

Run `install.sh <subcommand> --help` for subcommand-specific help.
USAGE
}

usage_init() {
  cat <<'USAGE'
install.sh init — adopt remcc in the current repository.

Usage:
  install.sh init [--ref <tag-or-sha>] [--help]

Options:
  --ref <ref>   remcc tag or commit to fetch templates from. Defaults to
                the latest release tag on premeq/remcc, falling back to
                'main' with a warning if no releases exist.

Behavior:
  1. Verifies prerequisites (admin on target, OpenSpec initialised,
     pnpm-lock.yaml present, local tools installed).
  2. Resolves a remcc ref and shallow-clones premeq/remcc at that ref
     into a tempdir (cleaned up on exit).
  3. Runs the cloned gh-bootstrap.sh against the target repo (branch
     protection, rulesets, ANTHROPIC_API_KEY + WORKFLOW_PAT secrets, apply
     configuration variables). Idempotent on re-run.
  4. Writes template-managed files (overwrites any existing copies):
       .github/workflows/opsx-apply.yml
       .claude/settings.json
       openspec/config.yaml
       .remcc/version
  5. Creates branch `remcc-init`, commits the template diff, pushes,
     and opens a pull request against `main`. PR body flags any
     pre-existing template-managed paths so the operator can verify
     the diff hasn't clobbered local customizations.

If the template diff is empty (re-install with no upstream changes),
init prints "already up to date" and exits zero without creating a
branch or PR.

Environment passthrough (consumed by gh-bootstrap.sh):
  ANTHROPIC_API_KEY     Anthropic API key (prompted if unset).
  WORKFLOW_PAT          Fine-grained PAT with Contents:write + Workflows:write
                        on the target repo. Required by opsx-apply.yml because
                        GITHUB_TOKEN cannot push under .github/workflows/.
                        Create at https://github.com/settings/personal-access-tokens/new.
                        Prompted if unset.
  OPSX_APPLY_MODEL      Per-repo default Claude model alias.
  OPSX_APPLY_EFFORT     Per-repo default thinking-budget level.
USAGE
}

# ----------------------------------------------------------------------------
# Prerequisite verification — runs BEFORE any GitHub mutation or file write.
# ----------------------------------------------------------------------------

require_local_tool() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 \
    || err "required local tool not found on PATH: ${name}"
}

verify_node_version() {
  local raw major minor
  raw="$(node -v 2>/dev/null | sed 's/^v//')" \
    || err "node not found on PATH (need >= 20.19)"
  major="${raw%%.*}"
  minor="${raw#*.}"; minor="${minor%%.*}"
  if [ "${major}" -lt 20 ] || { [ "${major}" -eq 20 ] && [ "${minor}" -lt 19 ]; }; then
    err "node version ${raw} is below the required 20.19"
  fi
}

verify_target_is_admin() {
  local repo="$1" perm
  perm="$(gh repo view "${repo}" --json viewerPermission --jq .viewerPermission 2>/dev/null)" \
    || err "could not query viewer permission on ${repo} (is gh authenticated?)"
  if [ "${perm}" != "ADMIN" ]; then
    err "you are not admin on ${repo} (viewer permission: ${perm:-unknown})"
  fi
}

verify_main_branch_exists() {
  local repo="$1"
  gh api "repos/${repo}/branches/main" --silent >/dev/null 2>&1 \
    || err "remote branch 'main' does not exist on ${repo}"
}

verify_prereqs() {
  local repo="$1"
  log "Verifying prerequisites"

  require_local_tool gh
  require_local_tool jq
  require_local_tool git
  require_local_tool pnpm
  verify_node_version
  sub "local tools: gh, jq, git, node, pnpm ok"

  gh auth status >/dev/null 2>&1 \
    || err "gh is not authenticated; run 'gh auth login' first"

  verify_target_is_admin "${repo}"
  sub "admin on ${repo}"

  verify_main_branch_exists "${repo}"
  sub "remote branch 'main' present"

  [ -d openspec ] || err "openspec/ not found at repo root (initialise OpenSpec first)"
  sub "openspec/ present"

  [ -d .claude ] || err ".claude/ not found at repo root (commit Claude Code skills/commands first)"
  sub ".claude/ present"

  [ -f pnpm-lock.yaml ] || err "pnpm-lock.yaml not found at repo root (remcc v1 supports pnpm-managed repos only)"
  sub "pnpm-lock.yaml present"

  verify_package_manager_field
  sub "package.json packageManager: pnpm@<version> present"
}

# The opsx-apply workflow uses pnpm/action-setup@v4 with no `version:` input,
# which means it resolves the pnpm version from package.json#packageManager.
# Without that field the workflow fails at "Setup pnpm".
verify_package_manager_field() {
  [ -f package.json ] \
    || err "package.json not found at repo root (remcc v1 supports pnpm-managed repos only)"
  local pm
  pm="$(jq -r '.packageManager // empty' < package.json 2>/dev/null)" \
    || err "could not parse package.json as JSON"
  [ -n "${pm}" ] \
    || err "package.json is missing the 'packageManager' field (set it to e.g. 'pnpm@9.12.3' — required by the workflow's pnpm/action-setup step)"
  case "${pm}" in
    pnpm@*) ;;
    *) err "package.json#packageManager is '${pm}'; remcc v1 requires 'pnpm@<version>'" ;;
  esac
}

# ----------------------------------------------------------------------------
# Pre-mutation guards: target must be a git repo, on main, clean.
# ----------------------------------------------------------------------------

resolve_target_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || err "not inside a git repository"
  gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null \
    || err "could not resolve a GitHub repo from the current git context (no 'origin' remote?)"
}

verify_clean_main() {
  local branch
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
  [ "${branch}" = "main" ] \
    || err "must be on branch 'main' to run init (currently on '${branch:-DETACHED}')"
  if [ -n "$(git status --porcelain)" ]; then
    err "working tree is dirty; commit or stash changes before running init"
  fi
}

# ----------------------------------------------------------------------------
# Resolve the remcc ref, then shallow-clone into a tempdir.
# ----------------------------------------------------------------------------

resolve_ref() {
  local explicit="$1"
  if [ -n "${explicit}" ]; then
    printf '%s' "${explicit}"
    return
  fi
  local tag
  tag="$(gh api "repos/${REMCC_REPO}/releases/latest" --jq .tag_name 2>/dev/null || true)"
  if [ -n "${tag}" ] && [ "${tag}" != "null" ]; then
    printf '%s' "${tag}"
    return
  fi
  warn "no releases on ${REMCC_REPO}; falling back to 'main' (unstable)"
  printf 'main'
}

clone_remcc_at() {
  local ref="$1"
  REMCC_SRC_DIR="$(mktemp -d -t remcc-src-XXXXXX)"
  log "Fetching remcc@${ref} into ${REMCC_SRC_DIR}"
  git clone --quiet --depth 1 --branch "${ref}" "${REMCC_CLONE_URL}" "${REMCC_SRC_DIR}" \
    || err "git clone of ${REMCC_REPO}@${ref} failed"
  sub "ok"
}

# ----------------------------------------------------------------------------
# Template-managed paths.
# ----------------------------------------------------------------------------

readonly TEMPLATE_PATHS=(
  ".github/workflows/opsx-apply.yml"
  ".claude/settings.json"
  "openspec/config.yaml"
  ".remcc/version"
)

template_source_for() {
  case "$1" in
    ".github/workflows/opsx-apply.yml") printf '%s' "${REMCC_SRC_DIR}/templates/workflows/opsx-apply.yml" ;;
    ".claude/settings.json")            printf '%s' "${REMCC_SRC_DIR}/templates/claude/settings.json" ;;
    "openspec/config.yaml")             printf '%s' "${REMCC_SRC_DIR}/templates/openspec/config.yaml" ;;
    ".remcc/version")                   printf '' ;;   # generated, not copied
    *) err "internal: no source mapping for template path: $1" ;;
  esac
}

# ----------------------------------------------------------------------------
# .remcc/version marker.
# ----------------------------------------------------------------------------

resolved_source_sha() {
  git -C "${REMCC_SRC_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown"
}

write_version_marker() {
  local target="$1" ref="$2" sha now
  sha="$(resolved_source_sha)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Preserve installed_at when re-installing the same source ref+sha, so that
  # back-to-back runs produce bit-identical version markers (and therefore
  # identical commit trees on the remcc-init branch).
  if [ -f "${target}" ]; then
    local prev_ref prev_sha prev_at
    prev_ref="$(jq -r '.source_ref // empty' < "${target}" 2>/dev/null || true)"
    prev_sha="$(jq -r '.source_sha // empty' < "${target}" 2>/dev/null || true)"
    if [ "${prev_ref}" = "${ref}" ] && [ "${prev_sha}" = "${sha}" ]; then
      prev_at="$(jq -r '.installed_at // empty' < "${target}" 2>/dev/null || true)"
      [ -n "${prev_at}" ] && now="${prev_at}"
    fi
  fi

  mkdir -p "$(dirname -- "${target}")"
  cat >"${target}" <<JSON
{
  "source_ref": "${ref}",
  "source_sha": "${sha}",
  "installed_at": "${now}"
}
JSON
}

# ----------------------------------------------------------------------------
# Snapshot pre-existing template paths (for PR-body collision flagging).
# ----------------------------------------------------------------------------

snapshot_preexisting() {
  local path
  for path in "${TEMPLATE_PATHS[@]}"; do
    if [ -e "${path}" ]; then
      printf '%s\n' "${path}"
    fi
  done
}

# ----------------------------------------------------------------------------
# Write templates unconditionally; generate the version marker.
# ----------------------------------------------------------------------------

install_templates() {
  local ref="$1" path src
  log "Installing template-managed files"
  for path in "${TEMPLATE_PATHS[@]}"; do
    if [ "${path}" = ".remcc/version" ]; then
      write_version_marker "${path}" "${ref}"
      sub "wrote ${path} (generated)"
      continue
    fi
    src="$(template_source_for "${path}")"
    [ -f "${src}" ] || err "fetched template missing: ${src}"
    mkdir -p "$(dirname -- "${path}")"
    cp "${src}" "${path}"
    sub "wrote ${path}"
  done
}

# ----------------------------------------------------------------------------
# Invoke the cloned bootstrap script (GitHub-side configuration).
# ----------------------------------------------------------------------------

run_bootstrap() {
  local bootstrap="${REMCC_SRC_DIR}/templates/gh-bootstrap.sh"
  log "Running gh-bootstrap.sh (GitHub-side configuration)"
  [ -f "${bootstrap}" ] || err "fetched bootstrap script missing: ${bootstrap}"
  bash "${bootstrap}"
}

# ----------------------------------------------------------------------------
# Branch / commit / push / PR.
# ----------------------------------------------------------------------------

create_init_branch() {
  # Re-runs leave the branch behind. Drop it so we always rebuild from main
  # with the current templates.
  if git rev-parse --verify --quiet "${INIT_BRANCH}" >/dev/null; then
    git branch -D "${INIT_BRANCH}" >/dev/null
  fi
  git checkout -b "${INIT_BRANCH}" main >/dev/null
}

stage_and_commit() {
  local ref="$1" sha
  sha="$(resolved_source_sha)"
  git add -- "${TEMPLATE_PATHS[@]}"
  if git diff --cached --quiet; then
    return 1   # nothing to commit
  fi
  git commit -m "$(cat <<EOF
${INIT_COMMIT_SUBJECT}

Source: remcc ${ref} (${sha})

Files written by install.sh init:
  .github/workflows/opsx-apply.yml
  .claude/settings.json
  openspec/config.yaml
  .remcc/version
EOF
)" >/dev/null
  return 0
}

build_pr_body() {
  local repo="$1" preexisting="$2" ref="$3" sha
  sha="$(resolved_source_sha)"

  printf '## remcc adoption\n\n'
  printf 'This PR was opened by `install.sh init`. It installs the\n'
  printf 'template-managed files remcc needs and records the source ref.\n\n'
  printf '**Source:** remcc `%s` (`%s`)\n\n' "${ref}" "${sha}"

  printf '### Files written\n\n'
  local p
  for p in "${TEMPLATE_PATHS[@]}"; do
    printf -- '- `%s`\n' "${p}"
  done
  printf '\n'

  if [ -n "${preexisting}" ]; then
    printf '### Pre-existing files (verify the diff)\n\n'
    printf 'These paths existed in your repo before `init` ran. The\n'
    printf 'installer overwrote them with the template contents; if you\n'
    printf 'had local customizations, re-apply them before merging.\n\n'
    while IFS= read -r p; do
      [ -z "${p}" ] && continue
      printf -- '- `%s`\n' "${p}"
    done <<<"${preexisting}"
    printf '\n'
  else
    printf '### Pre-existing files\n\nNone — every template-managed path was new.\n\n'
  fi

  printf '### Smoke test (after merging)\n\n'
  printf 'Run this from a clone of `%s` once this PR is on `main`:\n\n' "${repo}"
  printf '```sh\n'
  printf 'git checkout main && git pull --ff-only\n'
  printf 'git checkout -b change/test-apply\n'
  printf 'mkdir -p openspec/changes/test-apply\n'
  printf "cat > openspec/changes/test-apply/proposal.md <<'EOF'\n"
  printf '## Why\n\nSmoke-test the remcc apply path end-to-end.\n\n'
  printf '## What Changes\n\nCreate a single empty file `smoke.txt`.\n'
  printf 'EOF\n'
  printf "cat > openspec/changes/test-apply/tasks.md <<'EOF'\n"
  printf '## 1. Smoke\n\n- [ ] 1.1 Create empty file `smoke.txt` at repo root.\n'
  printf 'EOF\n'
  printf 'git add openspec/changes/test-apply\n'
  printf "git commit -m 'Add smoke test change'\n"
  printf 'git push -u origin change/test-apply\n'
  printf "git commit --allow-empty -m '@change-apply: smoke test'\n"
  printf 'git push\n'
  printf '```\n\n'
  printf 'Watch the Actions tab for the `opsx-apply` run.\n'
}

push_and_open_pr() {
  local repo="$1" preexisting="$2" ref="$3" body existing_pr

  # If the remote branch exists and its tree matches ours, skip the push
  # (the previous run's tip is already correct).
  git fetch origin "${INIT_BRANCH}" >/dev/null 2>&1 || true
  if git rev-parse --verify --quiet "refs/remotes/origin/${INIT_BRANCH}" >/dev/null \
     && [ "$(git rev-parse 'HEAD^{tree}')" = "$(git rev-parse "origin/${INIT_BRANCH}^{tree}")" ]; then
    log "Branch ${INIT_BRANCH} already in sync with origin; skipping push"
  else
    log "Pushing branch ${INIT_BRANCH} to origin"
    git push --force-with-lease -u origin "${INIT_BRANCH}" >/dev/null 2>&1 \
      || err "failed to push ${INIT_BRANCH} to origin"
  fi

  # If a PR is already open for this branch, leave it alone.
  existing_pr="$(gh pr list --repo "${repo}" --head "${INIT_BRANCH}" --state open \
                   --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "${existing_pr}" ]; then
    log "Pull request #${existing_pr} already open for ${INIT_BRANCH}; not opening another"
    return 0
  fi

  body="$(build_pr_body "${repo}" "${preexisting}" "${ref}")"
  log "Opening pull request"
  gh pr create \
    --base main \
    --head "${INIT_BRANCH}" \
    --title "${INIT_COMMIT_SUBJECT}" \
    --body "${body}" \
    || err "failed to open pull request"
}

# ----------------------------------------------------------------------------
# `init` orchestration.
# ----------------------------------------------------------------------------

cmd_init() {
  local explicit_ref=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage_init; exit 0 ;;
      --ref) shift; [ $# -gt 0 ] || err "--ref requires a value"; explicit_ref="$1"; shift ;;
      --ref=*) explicit_ref="${1#--ref=}"; shift ;;
      *) err "unknown option to init: $1" ;;
    esac
  done

  local repo ref preexisting
  repo="$(resolve_target_repo)"
  log "Target repository: ${repo}"

  verify_prereqs "${repo}"
  verify_clean_main

  ref="$(resolve_ref "${explicit_ref}")"
  log "Using remcc ref: ${ref}"
  clone_remcc_at "${ref}"

  # Snapshot pre-existing paths BEFORE we overwrite anything, so the PR body
  # can flag potential customization collisions.
  preexisting="$(snapshot_preexisting)"

  # Run the GitHub-side bootstrap first; failures here leave the working
  # tree untouched (templates haven't been written yet).
  run_bootstrap

  install_templates "${ref}"

  if [ -z "$(git status --porcelain -- "${TEMPLATE_PATHS[@]}")" ]; then
    log "already up to date"
    sub "no template diff vs. ${repo}@main; nothing to commit"
    exit 0
  fi

  create_init_branch
  if ! stage_and_commit "${ref}"; then
    log "already up to date"
    sub "templates matched the staged tree; no commit created"
    git checkout main >/dev/null 2>&1 || true
    git branch -D "${INIT_BRANCH}" >/dev/null 2>&1 || true
    exit 0
  fi

  push_and_open_pr "${repo}" "${preexisting}" "${ref}"
  log "Done. Review the pull request and run the smoke test from its body after merging."
}

# ----------------------------------------------------------------------------
# Dispatch.
# ----------------------------------------------------------------------------

main() {
  case "${1:-}" in
    ''|-h|--help|help) usage_root; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    *) printf 'unknown subcommand: %s\n\n' "$1" >&2; usage_root >&2; exit 1 ;;
  esac
}

main "$@"
