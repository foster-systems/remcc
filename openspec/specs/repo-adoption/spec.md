# repo-adoption Specification

## Purpose

Defines the contract a target repository's adoption of remcc must
satisfy: the prerequisites the operator confirms, the templates this
repo ships (workflow, Claude settings, bootstrap script), the
GitHub-side configuration the bootstrap script applies (idempotently),
the documentation set, the smoke-test procedure, and the
reversibility guarantee. The companion capability `apply-workflow`
defines what the workflow itself does once installed.

## Requirements

### Requirement: Adoption prerequisites documented

The repo SHALL document the prerequisites a target repository MUST
satisfy before adopting remcc. Prerequisites SHALL include: an
initialised OpenSpec project, a `.claude/` directory committed to
the repo, an existing `main` branch, a GitHub remote to which the
operator has admin access, and (for v1) a pnpm-managed JavaScript
project with a committed `pnpm-lock.yaml` at the repo root AND a
`package.json` whose `packageManager` field is set to
`pnpm@<version>`. The `packageManager` field is required because the
workflow's `pnpm/action-setup@v4` step has no explicit `version:`
input and resolves the pnpm version from that field; without it the
action errors at runtime.

The pnpm prerequisite reflects a v1 scoping decision: the workflow
template installs workspace dependencies via `pnpm install
--frozen-lockfile`. Adopters using npm, yarn, or no package manager
at all are out of scope until a future change generalises the
template.

#### Scenario: Operator can verify prerequisites before starting

- **WHEN** the operator opens `docs/SETUP.md`
- **THEN** they find a checklist of prerequisites at the top of the
  document with a verification command for each item, including a
  check that `pnpm-lock.yaml` exists at the repo root and that
  `package.json` declares `packageManager: pnpm@<version>`

#### Scenario: Non-pnpm adopter is told remcc is not for them yet

- **WHEN** an operator without a `pnpm-lock.yaml` reads `docs/SETUP.md`
- **THEN** the prerequisites section explicitly states that v1 of
  remcc supports pnpm-managed repos only, and points the operator
  at an issue or future change for non-pnpm adoption

#### Scenario: Missing packageManager field is caught before mutation

- **WHEN** the operator runs `install.sh init` in a repo whose
  `package.json` lacks a `packageManager` field (or whose value does
  not start with `pnpm@`)
- **THEN** the command exits non-zero with a message identifying the
  missing/invalid field, and no GitHub-side configuration or file
  write has been issued

### Requirement: Workflow template provided

The repo SHALL ship a copy-pasteable GitHub Actions workflow file at
`templates/workflows/opsx-apply.yml` that satisfies the
`apply-workflow` capability with no edits required for a minimal
adoption.

#### Scenario: Adopter copies the workflow file unchanged

- **WHEN** the operator copies `templates/workflows/opsx-apply.yml`
  to the target repo's `.github/workflows/opsx-apply.yml`
- **THEN** no further edits to the workflow file are required for
  the apply flow to function

### Requirement: Claude settings template provided

The repo SHALL ship a `templates/claude/settings.json` file
containing minimal, runner-safe defaults intended to be merged into
the target repo's `.claude/settings.json`.

#### Scenario: Adopter merges settings into existing .claude/

- **WHEN** the operator merges `templates/claude/settings.json`
  into a pre-existing `.claude/settings.json` in the target repo
- **THEN** the merged file contains the union of both, with no
  conflicting permissive defaults overriding existing local
  restrictions

### Requirement: GitHub bootstrap script provided

The repo SHALL ship `templates/gh-bootstrap.sh`, an idempotent POSIX
shell script run from inside a target repository that uses `gh api`
to apply the GitHub-side configuration the safety contract requires.

#### Scenario: Bootstrap script run twice is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` twice in succession
  in the same target repo
- **THEN** the second invocation produces no diffs in repo
  configuration and exits zero

### Requirement: Bootstrap configures branch protection on main

`gh-bootstrap.sh` SHALL configure branch protection on the target
repo's `main` branch such that direct pushes are blocked, force
pushes are blocked, and a pull request is required for merging.

#### Scenario: Direct push to main is rejected after bootstrap

- **WHEN** the operator runs `gh-bootstrap.sh` on a fresh repo
- **AND** subsequently attempts `git push origin main` from a local
  checkout with new commits
- **THEN** GitHub rejects the push citing branch protection

### Requirement: Bootstrap restricts bot to change/** branches

`gh-bootstrap.sh` SHALL configure a repository branch ruleset that
prevents non-admin actors from creating, updating, deleting, or
non-fast-forwarding any ref except those matching
`refs/heads/change/**`. Branch rulesets are available on both
user-owned and organization-owned repositories.

#### Scenario: Bot push to a non-change branch is rejected

- **WHEN** the workflow attempts to push commits to a branch not
  matching `change/**` using `GITHUB_TOKEN`
- **THEN** the push is rejected by the ruleset and branch protection

### Requirement: Bootstrap configures .github/** push ruleset when supported

`gh-bootstrap.sh` SHALL configure a repository push ruleset blocking
non-admin pushes that modify any path under `.github/**`, **when the
target repository is organization-owned**. GitHub does not support
push rulesets on user-owned repositories; on user-owned targets the
script SHALL emit a clear warning identifying the limitation,
SHALL NOT fail, and SHALL continue with the remaining bootstrap
steps. SETUP.md and SECURITY.md document the resulting reliance on
PR review.

#### Scenario: Org-owned target gets the push ruleset

- **WHEN** the operator runs `gh-bootstrap.sh` against an
  organization-owned repository
- **THEN** the script creates the push ruleset and the workflow
  attempting to push commits modifying `.github/**` from a
  `change/**` branch is rejected

#### Scenario: User-owned target produces a documented warning

- **WHEN** the operator runs `gh-bootstrap.sh` against a user-owned
  repository
- **THEN** the script prints a warning that push rulesets are
  unavailable and that `.github/**` enforcement falls to PR review,
  and continues with subsequent steps

### Requirement: Bootstrap enables secret scanning and push protection when supported

`gh-bootstrap.sh` SHALL enable GitHub secret scanning and secret
push protection on the target repository **when the feature is
available** for that repository's visibility and plan. Public
repositories receive the feature for free; private repositories
require GitHub Advanced Security (organization-level paid feature).
On private repositories without GHAS, the script SHALL emit a clear
warning identifying the limitation, SHALL NOT fail, and SHALL
continue with the remaining bootstrap steps. SECURITY.md documents
the resulting reliance on Actions log redaction as the only
secret-leak protection in that configuration.

#### Scenario: Public or GHAS-enabled target gets secret scanning

- **WHEN** the operator runs `gh-bootstrap.sh` against a repository
  where secret scanning is available
- **AND** a subsequent commit contains a token matching a known
  secret pattern
- **THEN** the push is rejected by secret push protection

#### Scenario: Private user-owned target produces a documented warning

- **WHEN** the operator runs `gh-bootstrap.sh` against a private
  repository where secret scanning is unavailable
- **THEN** the script prints a warning that secret scanning is
  unavailable and that the only remaining secret-leak protection is
  Actions log redaction, and continues with subsequent steps

### Requirement: Bootstrap enables Actions to create pull requests

`gh-bootstrap.sh` SHALL enable the GitHub Actions setting that allows
the auto-provisioned `GITHUB_TOKEN` to open pull requests, by setting
both `default_workflow_permissions` to `write` and
`can_approve_pull_request_reviews` to `true` on the
`/repos/{owner}/{repo}/actions/permissions/workflow` endpoint. The
workflow does not exercise the approve capability; the toggle is
required because GitHub couples create-PR and approve-PR under one
flag.

#### Scenario: Workflow's PR-creation step succeeds after bootstrap

- **WHEN** the workflow runs `gh pr create` from inside a runner
  using `GITHUB_TOKEN` after bootstrap has been applied
- **THEN** the PR is created without a permissions error

### Requirement: Bootstrap installs ANTHROPIC_API_KEY secret

`gh-bootstrap.sh` SHALL prompt the operator for an Anthropic API
key (or accept it via environment variable) and install it as the
repository secret `ANTHROPIC_API_KEY`. The script SHALL NOT echo
the key value to stdout or commit it to disk.

#### Scenario: Operator provides key interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without
  `ANTHROPIC_API_KEY` in the environment
- **THEN** the script prompts for the key with input hidden, and
  uploads it as the repository secret

### Requirement: Documentation set is sufficient for unaided adoption

The repo SHALL include `docs/SETUP.md`, `docs/SECURITY.md`, and
`docs/COSTS.md`. SETUP.md SHALL contain a complete adoption
checklist runnable without external context. SECURITY.md SHALL
document the two-layer safety model, enumerate the controls each
layer relies on, **and explicitly call out which controls are
unavailable on user-owned and on private-without-GHAS targets**,
together with the substitutions that take their place. COSTS.md
SHALL document Anthropic admin console budget configuration and
GitHub Actions minute usage.

#### Scenario: A second adopter completes setup using docs alone

- **WHEN** an operator who has not previously interacted with remcc
  follows `docs/SETUP.md` end to end on a fresh repository
- **THEN** the adoption completes successfully and the smoke test
  passes without questions back to the remcc maintainer

### Requirement: Smoke test procedure documented

`docs/SETUP.md` SHALL include a smoke-test procedure that verifies
adoption succeeded. The procedure SHALL involve pushing a trivial
`change/<test-name>` branch and observing the workflow run, the
PR creation, and the agent's behaviour on a no-op change.

#### Scenario: Smoke test exercises the full path

- **WHEN** the operator follows the smoke-test procedure after
  adoption
- **THEN** they observe (a) workflow trigger, (b) Claude Code run
  to completion, (c) `openspec validate` pass, (d) PR creation, in
  that order, all without manual intervention

### Requirement: Bootstrap installs OPSX_APPLY_MODEL and OPSX_APPLY_EFFORT variables

`gh-bootstrap.sh` SHALL prompt the operator for `OPSX_APPLY_MODEL`
and `OPSX_APPLY_EFFORT` values (or accept them via environment
variables of the same name) and write them as repository variables
via `gh variable set`. The prompts SHALL accept empty input; an
empty value SHALL NOT write a variable, allowing the workflow's
baked-in default for that knob to take effect. Running the script
twice with the same inputs SHALL be a no-op on the resulting
repository configuration.

#### Scenario: Operator supplies values interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without the
  `OPSX_APPLY_MODEL` or `OPSX_APPLY_EFFORT` environment variables
  set
- **AND** answers the prompts with `opus` and `high`
- **THEN** the script sets `OPSX_APPLY_MODEL=opus` and
  `OPSX_APPLY_EFFORT=high` as repository variables

#### Scenario: Operator skips a knob by leaving the prompt empty

- **WHEN** the operator runs `gh-bootstrap.sh` and answers the
  `OPSX_APPLY_MODEL` prompt with empty input
- **THEN** the script does not write the `OPSX_APPLY_MODEL`
  repository variable, leaving the workflow's baked-in default
  in effect

#### Scenario: Re-running the script with the same answers is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` twice in succession
  with the same answers for the model/effort prompts
- **THEN** the second invocation produces no diffs in the
  repository's variables and exits zero

### Requirement: SETUP.md documents model and effort configuration

`docs/SETUP.md` SHALL document the `OPSX_APPLY_MODEL` and
`OPSX_APPLY_EFFORT` repository variables, the workflow's baked-in
defaults, and the override precedence (`workflow_dispatch` input >
commit trailer > repository variable > baked-in default). The
section SHALL include the exact commit-trailer syntax
(`Opsx-Model: <value>`, `Opsx-Effort: <value>`) and a worked
example of overriding from a manual dispatch.

#### Scenario: Adopter learns how to set defaults from SETUP.md

- **WHEN** an operator follows `docs/SETUP.md` end to end
- **THEN** they encounter a section explaining the two
  configuration variables, their baked-in defaults, and how to
  override per run via dispatch or commit trailer

### Requirement: COSTS.md covers model and effort cost guidance

`docs/COSTS.md` SHALL include guidance on choosing `model` and
`effort` for cost/quality trade-offs, and SHALL note that the
resolved values appear in the PR body so the operator can audit
run cost decisions after the fact.

#### Scenario: Adopter consults COSTS.md before raising defaults

- **WHEN** an operator opens `docs/COSTS.md` before changing
  `OPSX_APPLY_MODEL` to a more expensive model
- **THEN** they find guidance on the cost implications of model
  and effort choices, plus a pointer to the PR body as the source
  of truth for what each run actually used

### Requirement: Adoption is reversible

The repo SHALL document how to remove remcc from a target
repository, covering removal of the workflow file, removal of the
ruleset and secret via `gh api`, and any other adoption-time
configuration.

#### Scenario: Operator removes adoption cleanly

- **WHEN** the operator follows the documented removal procedure
- **THEN** no remcc-specific configuration remains on the target
  repository (no workflow file, no push ruleset, no secret),
  while the repo's own files outside `.github/` are untouched

### Requirement: Automated install path is provided

The repo SHALL provide an automated install path via the curl-piped
`install.sh init` invocation (defined in `remcc-cli`) and an automated
update path via `install.sh upgrade`. `docs/SETUP.md` SHALL present
`install.sh init` as the primary adoption flow and SHALL preserve the
existing manual checklist as a fallback for operators who cannot or
will not pipe a remote script to bash. `docs/SETUP.md` SHALL also
document `install.sh upgrade` as the primary update flow once a repo
has been adopted, including the curl one-liner and the `--ref`
override. The automated paths SHALL replace the manual steps for
prerequisite verification, template-file copying, bootstrap-script
invocation (init only), and PR opening.

#### Scenario: Operator adopts via the automated path

- **WHEN** the operator runs the documented `install.sh init`
  one-liner in a target repository that satisfies the prerequisites
- **THEN** the adoption completes by opening a single pull request
  for the operator to review, and the operator was not required to
  copy any template files by hand

#### Scenario: Operator upgrades via the automated path

- **WHEN** the operator runs the documented `install.sh upgrade`
  one-liner in a target repository that was previously adopted via
  `install.sh init`
- **THEN** the upgrade completes by opening a single pull request
  refreshing every template-managed file at the new remcc ref, and
  the operator was not required to copy any template files by hand

#### Scenario: Manual fallback remains documented

- **WHEN** an operator who will not pipe a remote script to bash
  reads `docs/SETUP.md`
- **THEN** the document contains the manual step-by-step checklist
  (template copies, bootstrap invocation, smoke test) as an
  explicit fallback path

### Requirement: Adopted repos contain a remcc version marker

Repositories adopted via `install.sh init` SHALL contain a
`.remcc/version` file recording the remcc ref the templates were
sourced from. The marker SHALL be committed to the repository as
part of the adoption pull request and SHALL persist on `main` after
merge. Its presence enables future update-delivery commands (out of
scope here) to identify the installed version.

#### Scenario: Marker is present after adoption

- **WHEN** the operator completes `install.sh init` and merges the
  resulting pull request
- **THEN** the target repository's `main` branch contains
  `.remcc/version`

### Requirement: Version marker preserves installed_at across upgrades

The `.remcc/version` marker in an adopted repository SHALL retain its
`installed_at` value across `install.sh upgrade` invocations. The
`installed_at` field records the date the operator first adopted
remcc; it SHALL NOT be re-stamped to the upgrade date on subsequent
upgrades. The mechanism by which the value is preserved is specified
in `remcc-cli`.

#### Scenario: installed_at survives an upgrade-and-merge cycle

- **WHEN** an adopted repo's `main` branch records
  `installed_at: 2026-04-01T10:00:00Z` in `.remcc/version`
- **AND** the operator runs `install.sh upgrade` and merges the
  resulting pull request
- **THEN** `main` still records `installed_at: 2026-04-01T10:00:00Z`
  in `.remcc/version` after the merge

### Requirement: Bootstrap installs WORKFLOW_PAT secret

`gh-bootstrap.sh` SHALL prompt the operator for a fine-grained GitHub
personal access token (or accept it via the `WORKFLOW_PAT` environment
variable) and install it as the repository secret `WORKFLOW_PAT`. The
PAT is required by `opsx-apply.yml`: the workflow checks out the
change branch using this token because the default `GITHUB_TOKEN`
cannot push changes under `.github/workflows/`, so any agent task
that creates or edits a workflow file would otherwise fail at the
push step. The script SHALL NOT echo the value to stdout or commit
it to disk. The `--uninstall` path SHALL delete this secret (it does
not revoke the PAT itself; the operator does that on GitHub).

#### Scenario: Operator provides PAT interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without `WORKFLOW_PAT`
  in the environment
- **THEN** the script prompts for the PAT with input hidden, uploads
  it as the repository secret, and the prompt names the required
  scopes (`Contents: write`, `Workflows: write`)

#### Scenario: Uninstall removes the secret

- **WHEN** the operator runs `gh-bootstrap.sh --uninstall` on a target
  where `WORKFLOW_PAT` has been installed
- **THEN** the repository secret `WORKFLOW_PAT` is deleted and the
  script exits zero
