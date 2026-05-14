## ADDED Requirements

### Requirement: install.sh exposes a reconfigure subcommand

The `install.sh` CLI SHALL expose a `reconfigure` subcommand in addition to `init` and `upgrade`. `install.sh --help` and the no-argument invocation SHALL list all three subcommands. `install.sh reconfigure --help` SHALL describe the subcommand's flow, the `--ref <tag-or-sha>` option, and the requirement that the target repository has previously been adopted (must contain `.remcc/version` on `origin/main`).

#### Scenario: Help lists reconfigure alongside init and upgrade

- **WHEN** the operator runs `bash <(curl -fsSL .../install.sh) --help`
- **THEN** the output lists `init`, `upgrade`, and `reconfigure` as available subcommands
- **AND** `bash <(curl -fsSL .../install.sh) reconfigure --help` prints reconfigure-specific behaviour and the `--ref` option

### Requirement: install.sh reconfigure refuses targets without a version marker

`install.sh reconfigure` SHALL verify that `.remcc/version` exists on the target repository's `origin/main` branch before mutating anything. If the marker is absent, the command SHALL exit non-zero with a message identifying the missing marker and pointing the operator at `install.sh init`, and SHALL NOT have issued any `gh api` mutation or filesystem write.

#### Scenario: Reconfigure refuses an un-adopted target

- **WHEN** the operator runs `install.sh reconfigure` in a repository that has never been adopted via `install.sh init` (no `.remcc/version` on `origin/main`)
- **THEN** the command exits non-zero, the error message names the missing marker file and directs the operator to `install.sh init`, and no GitHub-side configuration has been changed

### Requirement: install.sh reconfigure verifies prerequisites before mutating

`install.sh reconfigure` SHALL run the same prerequisite verifier as `init` and `upgrade` (admin on target, `main` exists, OpenSpec initialised, `.claude/` present, `pnpm-lock.yaml` at root, `package.json#packageManager: pnpm@<version>`, required local tools) before making any change to the target repository's filesystem or GitHub configuration. On verification failure, the command SHALL exit non-zero with a message identifying the unmet prerequisite and SHALL NOT have applied any partial change.

#### Scenario: Missing prerequisite is detected before mutation

- **WHEN** the operator runs `install.sh reconfigure` in an adopted repo whose `package.json` no longer contains a `packageManager` field
- **THEN** the command exits non-zero, the error names the unmet prerequisite, and no GitHub-side configuration has been changed

### Requirement: install.sh reconfigure runs only the fetched bootstrap script

`install.sh reconfigure` SHALL resolve a remcc ref (default: latest release tag on `premeq/remcc`; overridable via `--ref <tag-or-sha>`), shallow-clone the repo at that ref into a tempdir, and invoke the cloned `templates/gh-bootstrap.sh` against the resolved target repository. `reconfigure` SHALL NOT touch the working tree, SHALL NOT write `.remcc/version`, SHALL NOT create a branch, and SHALL NOT open a pull request. The tempdir SHALL be cleaned up on exit. Re-running `reconfigure` with the same inputs SHALL be idempotent (no diffs in any GitHub-side configuration the bootstrap manages).

#### Scenario: Reconfigure applies only bootstrap-managed config

- **WHEN** the operator runs `install.sh reconfigure --ref v0.3.0` against an adopted target
- **THEN** the cloned `gh-bootstrap.sh` runs to completion
- **AND** the working tree of the target repo is unchanged after the run
- **AND** no `remcc-init` or `remcc-upgrade` branch was created locally or pushed
- **AND** no pull request was opened

#### Scenario: Re-running reconfigure is a bootstrap no-op

- **WHEN** the operator runs `install.sh reconfigure` twice in succession with the same inputs in the same target repo
- **THEN** the second invocation produces no diffs in any GitHub-side configuration the bootstrap script manages, and exits zero

### Requirement: install.sh reconfigure does not trigger an apply run

`install.sh reconfigure` SHALL NOT push to a `change/**` branch, SHALL NOT push any commit with a subject starting `@change-apply`, and SHALL NOT cause an `opsx-apply` workflow run on the target repo as a consequence of its execution.

#### Scenario: No apply run is triggered during reconfigure

- **WHEN** `install.sh reconfigure` completes against an adopted target
- **THEN** no `opsx-apply` workflow run on the target repo has been triggered by the invocation

## MODIFIED Requirements

### Requirement: install.sh init runs the fetched bootstrap script

`install.sh init` SHALL resolve a remcc ref (default: latest release tag on `premeq/remcc`; overridable via `--ref <tag-or-sha>`), shallow-clone the repo at that ref into a tempdir, and invoke the `templates/gh-bootstrap.sh` from that clone against the resolved target repository. The invocation SHALL be idempotent: re-running `install.sh init` SHALL NOT produce diffs in branch protection, rulesets, secrets, or repository variables managed by the bootstrap script. The command SHALL pass `ANTHROPIC_API_KEY`, `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, `REMCC_APP_SLUG`, `OPSX_APPLY_MODEL`, and `OPSX_APPLY_EFFORT` from its environment to the bootstrap subprocess; `install.sh --help` (and `install.sh init --help`) SHALL document each as bootstrap-consumed environment passthrough.

#### Scenario: Re-running init is a bootstrap no-op

- **WHEN** the adopter runs `install.sh init` twice in succession
  in the same target repo
- **THEN** the second invocation produces no diffs in any
  GitHub-side configuration the bootstrap script manages, and exits
  zero

#### Scenario: install.sh init documents App credentials in --help

- **WHEN** the operator runs `install.sh init --help`
- **THEN** the output names `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, and `REMCC_APP_SLUG` as environment-variable passthroughs consumed by `gh-bootstrap.sh`
- **AND** the output does not name `WORKFLOW_PAT` (it is no longer used)
