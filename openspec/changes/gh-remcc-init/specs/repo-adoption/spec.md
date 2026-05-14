## ADDED Requirements

### Requirement: Automated install path is provided

The repo SHALL provide an automated install path via the
curl-piped `install.sh init` invocation (defined in `remcc-cli`).
`docs/SETUP.md` SHALL present this as the primary adoption flow and
SHALL preserve the existing manual checklist as a fallback for
operators who cannot or will not pipe a remote script to bash. The
automated path SHALL replace the manual steps for prerequisite
verification, template-file copying, bootstrap-script invocation,
and PR opening.

#### Scenario: Operator adopts via the automated path

- **WHEN** the operator runs the documented `install.sh init`
  one-liner in a target repository that satisfies the prerequisites
- **THEN** the adoption completes by opening a single pull request
  for the operator to review, and the operator was not required to
  copy any template files by hand

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
