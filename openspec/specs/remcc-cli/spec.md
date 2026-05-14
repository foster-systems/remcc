# remcc-cli Specification

## Purpose

Defines the contract for `install.sh`, the curl-invocable entry point
that automates remcc adoption in a target repository. The CLI verifies
prerequisites, fetches templates at a pinned ref, runs the
`gh-bootstrap.sh` script, writes template-managed files, records a
version marker, and opens a pull request — all without triggering an
apply-workflow run. Companion capabilities `repo-adoption` and
`apply-workflow` define what is adopted and what the workflow does
once installed.

## Requirements

### Requirement: Installer is invokable over curl in a single command

The repo SHALL ship `install.sh` at its root such that
`bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/<ref>/install.sh) <subcommand>`
executes the named subcommand against the current working directory's
target repository. The script SHALL also work under the `curl … |
bash -s -- <subcommand>` shape; interactive prompts inside the
script SHALL read from `/dev/tty` so the piped form does not hang.

#### Scenario: Adopter invokes install.sh init via process substitution

- **WHEN** the adopter runs
  `bash <(curl -fsSL .../install.sh) init` from a clone of a target
  repository that satisfies the prerequisites
- **THEN** the script exits zero after completing its steps
- **AND** `bash <(curl -fsSL .../install.sh) --help` lists `init`
  as an available subcommand

### Requirement: install.sh init verifies prerequisites before mutating

`install.sh init` SHALL verify the prerequisites enumerated in
`repo-adoption` (admin on target, `main` exists, OpenSpec
initialised, `.claude/` present, `pnpm-lock.yaml` at root, required
local tools) before making any change to the target repository's
GitHub configuration, filesystem, or remote refs. On verification
failure, the command SHALL exit non-zero with a message identifying
the unmet prerequisite and SHALL NOT have applied any partial
change.

#### Scenario: Missing pnpm-lock.yaml is detected before mutation

- **WHEN** the adopter runs `install.sh init` in a repo that lacks
  `pnpm-lock.yaml` at the root
- **THEN** the command exits non-zero, prints which prerequisite
  failed, and `gh api` calls that would mutate GitHub configuration
  have not been issued

### Requirement: install.sh init runs the fetched bootstrap script

`install.sh init` SHALL resolve a remcc ref (default: latest release
tag on `premeq/remcc`; overridable via `--ref <tag-or-sha>`),
shallow-clone the repo at that ref into a tempdir, and invoke the
`templates/gh-bootstrap.sh` from that clone against the resolved
target repository. The invocation SHALL be idempotent: re-running
`install.sh init` SHALL NOT produce diffs in branch protection,
rulesets, secrets, or repository variables managed by the bootstrap
script.

#### Scenario: Re-running init is a bootstrap no-op

- **WHEN** the adopter runs `install.sh init` twice in succession
  in the same target repo
- **THEN** the second invocation produces no diffs in any
  GitHub-side configuration the bootstrap script manages, and exits
  zero

### Requirement: install.sh init writes template-managed files

`install.sh init` SHALL write the following files in the target
repo's working tree: `.github/workflows/opsx-apply.yml`,
`.claude/settings.json`, `openspec/config.yaml`, and
`.remcc/version`. If any of these paths already exist, the script
SHALL overwrite them without prompting. The expectation is that the
operator reviews the resulting diff in the pull request and
re-applies any local customizations there.

#### Scenario: Pre-existing file is overwritten and surfaces in the PR diff

- **WHEN** the adopter runs `install.sh init` in a repo whose
  `.claude/settings.json` already contains operator-authored
  configuration
- **THEN** the file is overwritten with the template's contents,
  the change is visible in the resulting pull request's diff, and
  no interactive prompt is presented during the run

### Requirement: install.sh init writes a version marker

`install.sh init` SHALL write `.remcc/version` recording at minimum
the resolved remcc source ref (tag or commit SHA the templates were
fetched from). The file format SHALL be machine-parseable (JSON).
The marker enables a future `upgrade` subcommand to identify the
installed version; that subcommand is out of scope here.

#### Scenario: Marker records the source ref

- **WHEN** the adopter runs `install.sh init` against a `premeq/remcc`
  release tagged `v0.2.0` (the default ref resolution)
- **THEN** `.remcc/version` in the target repo contains a parseable
  JSON object whose `source_ref` field is `v0.2.0`

### Requirement: install.sh init opens a pull request

`install.sh init` SHALL commit the written template files to a
branch (default: `remcc-init`) and SHALL open a pull request against
`main` after the template-write and bootstrap steps complete. The
PR body SHALL list every file written and SHALL explicitly flag any
path that existed in the target repo before the run, identifying it
as a potential customization collision the operator should verify
in the diff.

#### Scenario: PR is opened and identifies pre-existing files

- **WHEN** `install.sh init` runs successfully in a repo that had a
  pre-existing `.claude/settings.json`
- **THEN** a pull request exists from `remcc-init` to `main` on the
  target repo, with a body listing every file written and flagging
  `.claude/settings.json` as a pre-existing file requiring diff
  review

### Requirement: install.sh init does not trigger an apply run

`install.sh init` SHALL NOT push to a `change/**` branch, SHALL NOT
push any commit with a subject starting `@change-apply`, and SHALL
NOT cause an `opsx-apply` workflow run on the target repo. The
operator runs a smoke test manually after merging the PR; the PR
body SHALL include a copy-pasteable smoke-test one-liner.

#### Scenario: No apply run is triggered during init

- **WHEN** `install.sh init` completes against a freshly configured
  target repo
- **THEN** no `opsx-apply` workflow run exists on the target repo
  as a consequence of the invocation, and the PR body includes a
  smoke-test command the operator can run after merging
