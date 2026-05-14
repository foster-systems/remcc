## MODIFIED Requirements

### Requirement: install.sh init writes a version marker

`install.sh init` SHALL write `.remcc/version` recording at minimum the
resolved remcc source ref (tag or commit SHA the templates were fetched
from). The file format SHALL be machine-parseable (JSON). The marker
SHALL include an `installed_at` field recording the timestamp at which
the adopter first installed remcc; on re-runs of `install.sh init`
against a target that already has `.remcc/version` committed on
`origin/main`, the `installed_at` value SHALL be preserved (read from
`origin/main:.remcc/version`, not from the working tree, since the
init branch is rebuilt from `main` before the marker is written). The
marker enables the `upgrade` subcommand to identify the installed
version and preserve adoption history.

#### Scenario: Marker records the source ref

- **WHEN** the adopter runs `install.sh init` against a `premeq/remcc`
  release tagged `v0.2.0` (the default ref resolution)
- **THEN** `.remcc/version` in the target repo contains a parseable
  JSON object whose `source_ref` field is `v0.2.0`

#### Scenario: Re-running init preserves installed_at from origin/main

- **WHEN** the adopter runs `install.sh init` twice against the same
  target repo and the first run's PR was merged to `main` between
  invocations
- **THEN** the second invocation's `.remcc/version` contains the same
  `installed_at` value as the first run's marker on `origin/main`

## ADDED Requirements

### Requirement: install.sh exposes an upgrade subcommand

The `install.sh` CLI SHALL expose an `upgrade` subcommand in addition
to `init`. `install.sh --help` and the no-argument invocation SHALL
list both subcommands. `install.sh upgrade --help` SHALL describe the
subcommand's flow, the `--ref <tag-or-sha>` option, and the requirement
that the target repository has previously been adopted (must contain
`.remcc/version` on `origin/main`).

#### Scenario: Help lists upgrade alongside init

- **WHEN** the operator runs `bash <(curl -fsSL .../install.sh) --help`
- **THEN** the output lists both `init` and `upgrade` as available
  subcommands
- **AND** `bash <(curl -fsSL .../install.sh) upgrade --help` prints
  upgrade-specific behaviour and the `--ref` option

### Requirement: install.sh upgrade refuses targets without a version marker

`install.sh upgrade` SHALL verify that `.remcc/version` exists on the
target repository's `origin/main` branch before mutating anything. If
the marker is absent, the command SHALL exit non-zero with a message
identifying the missing marker and pointing the operator at
`install.sh init`, and SHALL NOT have issued any `gh api` mutation or
filesystem write.

#### Scenario: Upgrade refuses an un-adopted target

- **WHEN** the operator runs `install.sh upgrade` in a repository that
  has never been adopted via `install.sh init` (no `.remcc/version` on
  `origin/main`)
- **THEN** the command exits non-zero, the error message names the
  missing marker file and directs the operator to `install.sh init`,
  and no GitHub-side configuration or working-tree file has been
  changed

### Requirement: install.sh upgrade verifies prerequisites before mutating

`install.sh upgrade` SHALL run the same prerequisite verifier as
`install.sh init` (admin on target, `main` exists, OpenSpec
initialised, `.claude/` present, `pnpm-lock.yaml` at root,
`package.json#packageManager: pnpm@<version>`, required local tools)
before making any change to the target repository's filesystem or
remote refs. On verification failure, the command SHALL exit non-zero
with a message identifying the unmet prerequisite and SHALL NOT have
applied any partial change.

#### Scenario: Missing prerequisite is detected before mutation

- **WHEN** the operator runs `install.sh upgrade` in an adopted repo
  whose `package.json` no longer contains a `packageManager` field
- **THEN** the command exits non-zero, the error names the unmet
  prerequisite, and no GitHub-side configuration or template file has
  been rewritten

### Requirement: install.sh upgrade does not re-run gh-bootstrap.sh

`install.sh upgrade` SHALL NOT invoke `templates/gh-bootstrap.sh`. The
subcommand SHALL NOT change branch protection, rulesets, secrets,
repository variables, or any other GitHub-side configuration. Upgrade
operates exclusively on template-managed files inside the target
repo's working tree.

#### Scenario: Upgrade leaves GitHub configuration untouched

- **WHEN** the operator runs `install.sh upgrade` against an adopted
  target
- **THEN** snapshots of branch protection, rulesets, repository secrets,
  and repository variables taken before and after the run are
  bit-identical

### Requirement: install.sh upgrade resolves a ref and refreshes template files

`install.sh upgrade` SHALL resolve a remcc ref (default: latest release
tag on `premeq/remcc`; overridable via `--ref <tag-or-sha>`),
shallow-clone the repo at that ref into a tempdir, and overwrite the
template-managed files (`.github/workflows/opsx-apply.yml`,
`.claude/settings.json`, `openspec/config.yaml`, `.remcc/version`) in
the target repo's working tree using the templates from that clone.
The tempdir SHALL be cleaned up on exit.

#### Scenario: Upgrade refreshes all template-managed files at the new ref

- **WHEN** an adopted repo currently records `source_ref: v0.1.1` in
  its `.remcc/version`
- **AND** the operator runs `install.sh upgrade --ref v0.2.0`
- **THEN** every template-managed file in the working tree matches the
  contents of `templates/...` at `v0.2.0`
- **AND** `.remcc/version` records `source_ref: v0.2.0` and the
  corresponding `source_sha`

### Requirement: install.sh upgrade preserves installed_at across upgrades

`install.sh upgrade` SHALL preserve the `installed_at` value from the
previously committed `.remcc/version` when writing the upgraded marker.
The previous marker SHALL be read from
`origin/remcc-upgrade:.remcc/version` if that branch exists on the
remote, falling back to `origin/main:.remcc/version`. The previous
marker SHALL NOT be read from the working tree, because the upgrade
branch is rebuilt from `main` before the marker is written. If the
previous marker is malformed JSON or lacks an `installed_at` field,
the upgraded marker's `installed_at` SHALL default to the current UTC
timestamp.

#### Scenario: installed_at is preserved on upgrade

- **WHEN** an adopted repo's `origin/main:.remcc/version` records
  `installed_at: 2026-04-01T10:00:00Z`
- **AND** the operator runs `install.sh upgrade --ref v0.2.0` and
  merges the resulting PR
- **THEN** the merged `.remcc/version` on `main` still records
  `installed_at: 2026-04-01T10:00:00Z`

#### Scenario: Re-running upgrade keeps installed_at stable

- **WHEN** the operator runs `install.sh upgrade --ref v0.2.0` twice
  in succession against the same adopted target, the first
  invocation having opened a PR that is still open on the
  `remcc-upgrade` branch
- **THEN** the second invocation's marker has the same `installed_at`
  value as the first invocation's marker (read back from
  `origin/remcc-upgrade:.remcc/version`)

### Requirement: install.sh upgrade opens a single reused branch pull request

`install.sh upgrade` SHALL commit the refreshed template-managed files
to a single reused branch (default: `remcc-upgrade`) and SHALL open a
pull request against `main` after the templates are written. If a
pull request from `remcc-upgrade` to `main` is already open on the
target repository, the command SHALL update the branch tip via
force-with-lease push and SHALL NOT open a duplicate pull request.

The PR title SHALL identify the upgrade as a remcc upgrade and name
the new ref. The PR body SHALL include: a source line stating both
the previous ref/sha and the new ref/sha; the list of files written;
a per-path flag for any path whose pre-upgrade working-tree content
differed from the new template (potential customization collision);
and a pointer that the upgraded workflow takes effect on the next
apply run after merge. The PR body SHALL NOT include a smoke-test
one-liner (the operator already ran one at `init`).

#### Scenario: PR is opened against main from remcc-upgrade

- **WHEN** the operator runs `install.sh upgrade --ref v0.2.0` against
  an adopted target whose previous source ref was `v0.1.1`
- **THEN** a pull request exists from `remcc-upgrade` to `main` on the
  target repo, the title identifies the upgrade, and the body's
  source line reads `v0.1.1 (<old_sha>) → v0.2.0 (<new_sha>)`
- **AND** the body lists each of the four template-managed files
- **AND** the body does not include a smoke-test one-liner

#### Scenario: Re-running upgrade does not open a duplicate PR

- **WHEN** the operator runs `install.sh upgrade` while a PR from
  `remcc-upgrade` to `main` is already open on the target
- **THEN** no second pull request is opened
- **AND** the existing PR's head branch is updated to the new tip
  via force-with-lease push, if the new templates differ from the
  branch's previous tip

### Requirement: install.sh upgrade short-circuits when no diff exists

`install.sh upgrade` SHALL skip branch creation, commit, push, and PR
opening when the refreshed template-managed files match what is
already committed on `origin/main`. In that case the command SHALL
print an `already up to date` message and exit zero. No GitHub-side
state SHALL be mutated.

#### Scenario: Upgrade at the same ref is a no-op

- **WHEN** the operator runs `install.sh upgrade --ref v0.1.1` against
  an adopted target whose `origin/main:.remcc/version` already records
  `source_ref: v0.1.1`
- **THEN** the command prints `already up to date` and exits zero
- **AND** no commit, push, or pull request creation has occurred

### Requirement: install.sh upgrade does not trigger an apply run

`install.sh upgrade` SHALL NOT push to a `change/**` branch, SHALL
NOT push any commit with a subject starting `@change-apply`, and
SHALL NOT cause an `opsx-apply` workflow run on the target repo as
a consequence of its execution.

#### Scenario: No apply run is triggered during upgrade

- **WHEN** `install.sh upgrade` completes against an adopted target
- **THEN** no `opsx-apply` workflow run on the target repo has been
  triggered by the upgrade invocation
