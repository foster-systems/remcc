## ADDED Requirements

### Requirement: Adoption prerequisites documented

The repo SHALL document the prerequisites a target repository MUST
satisfy before adopting remcc. Prerequisites SHALL include: an
initialised OpenSpec project, a `.claude/` directory committed to
the repo, an existing `main` branch, a GitHub remote to which the
operator has admin access, and (for v1) a pnpm-managed JavaScript
project with a committed `pnpm-lock.yaml` at the repo root.

The pnpm prerequisite reflects a v1 scoping decision: the workflow
template installs workspace dependencies via `pnpm install
--frozen-lockfile`. Adopters using npm, yarn, or no package manager
at all are out of scope until a future change generalises the
template.

#### Scenario: Operator can verify prerequisites before starting

- **WHEN** the operator opens `docs/SETUP.md`
- **THEN** they find a checklist of prerequisites at the top of the
  document with a verification command for each item, including a
  check that `pnpm-lock.yaml` exists at the repo root

#### Scenario: Non-pnpm adopter is told remcc is not for them yet

- **WHEN** an operator without a `pnpm-lock.yaml` reads `docs/SETUP.md`
- **THEN** the prerequisites section explicitly states that v1 of
  remcc supports pnpm-managed repos only, and points the operator
  at an issue or future change for non-pnpm adoption

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

### Requirement: Bootstrap configures push ruleset for change branches

`gh-bootstrap.sh` SHALL configure a repository push ruleset that
restricts pushes from `GITHUB_TOKEN` (the auto-provisioned bot
identity) to branches matching `change/**`, and SHALL block such
pushes from modifying any path under `.github/**`.

#### Scenario: Bot push to a non-change branch is rejected

- **WHEN** the workflow attempts to push commits to a branch not
  matching `change/**` using `GITHUB_TOKEN`
- **THEN** the push is rejected by the ruleset

#### Scenario: Bot push that touches .github/** is rejected

- **WHEN** the workflow attempts to push commits to a `change/**`
  branch where any file under `.github/**` has been modified
- **THEN** the push is rejected by the ruleset

### Requirement: Bootstrap enables secret scanning and push protection

`gh-bootstrap.sh` SHALL enable GitHub secret scanning and secret
push protection on the target repository.

#### Scenario: Commit containing a secret is blocked at push time

- **WHEN** a commit contains a token matching a known secret
  pattern (e.g., an Anthropic API key)
- **AND** the commit is pushed to any branch
- **THEN** the push is rejected by secret push protection

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
document the two-layer safety model and enumerate the controls
each layer relies on. COSTS.md SHALL document Anthropic admin
console budget configuration and GitHub Actions minute usage.

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
