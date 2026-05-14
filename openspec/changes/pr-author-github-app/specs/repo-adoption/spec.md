## ADDED Requirements

### Requirement: Bootstrap installs REMCC_APP_ID and REMCC_APP_PRIVATE_KEY secrets

`gh-bootstrap.sh` SHALL prompt the operator for (or read from environment variables of the same name) the GitHub App ID and PEM-encoded private key associated with the operator's remcc GitHub App, and install them as the repository secrets `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY`. The PEM is multi-line; the script SHALL accept it via `/dev/tty` or env without mangling newlines, and SHALL upload it to GitHub via `gh secret set` with the body piped on stdin (so multi-line content is preserved). The script SHALL NOT echo either value to stdout and SHALL NOT commit them to disk. The `--uninstall` path SHALL delete both secrets (it does not delete the App or revoke its credentials on GitHub).

#### Scenario: Operator provides App credentials interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without `REMCC_APP_ID` or `REMCC_APP_PRIVATE_KEY` in the environment
- **THEN** the script prompts for each value with input hidden, uploads both as repository secrets, and the prompts name the required GitHub App permissions (`Contents: write`, `Pull requests: write`, `Workflows: write`, `Metadata: read`)

#### Scenario: Multi-line PEM is preserved on upload

- **WHEN** the operator supplies a multi-line PEM via the `REMCC_APP_PRIVATE_KEY` environment variable
- **AND** runs `gh-bootstrap.sh`
- **THEN** the resulting repository secret's value matches the supplied PEM byte-for-byte (including all newlines), as verifiable by minting an installation token in a subsequent workflow run

#### Scenario: Uninstall removes both secrets

- **WHEN** the operator runs `gh-bootstrap.sh --uninstall` on a target where the App secrets have been installed
- **THEN** the repository secrets `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY` are deleted and the script exits zero

### Requirement: Bootstrap installs REMCC_APP_SLUG repository variable

`gh-bootstrap.sh` SHALL prompt the operator for (or read from the environment variable of the same name) the GitHub App's slug (the lower-cased, hyphen-separated identifier visible in the App's URL on GitHub), and write it as the repository variable `REMCC_APP_SLUG` via `gh variable set`. An empty value SHALL be a hard error (the workflow needs the slug to construct the bot's git identity). The `--uninstall` path SHALL delete the variable.

#### Scenario: Operator supplies slug interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without `REMCC_APP_SLUG` in the environment
- **THEN** the script prompts for the value (input visible — the slug is not secret), writes it as the repository variable, and exits zero

#### Scenario: Empty slug is rejected

- **WHEN** the operator runs `gh-bootstrap.sh` and responds to the slug prompt with empty input (or supplies an empty `REMCC_APP_SLUG` environment variable)
- **THEN** the script exits non-zero with a message identifying the empty slug, and no other bootstrap step that has not already run is executed

#### Scenario: Uninstall removes the variable

- **WHEN** the operator runs `gh-bootstrap.sh --uninstall` on a target where `REMCC_APP_SLUG` has been installed
- **THEN** the repository variable is deleted and the script exits zero

### Requirement: Bootstrap removes legacy WORKFLOW_PAT secret when the App secrets are installed

`gh-bootstrap.sh` SHALL delete any pre-existing `WORKFLOW_PAT` repository secret AFTER it has successfully written both `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY`. If either App secret fails to install, the legacy `WORKFLOW_PAT` SHALL NOT be deleted (so a failed migration leaves the legacy workflow in a working state). The removal step SHALL be idempotent: re-running bootstrap when `WORKFLOW_PAT` has already been removed SHALL be a no-op.

#### Scenario: Legacy PAT is removed during migration

- **WHEN** the operator runs `gh-bootstrap.sh` on a target that has the legacy `WORKFLOW_PAT` installed
- **AND** the operator supplies valid `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, and `REMCC_APP_SLUG` values
- **THEN** the App secrets and slug variable are installed first
- **AND** the legacy `WORKFLOW_PAT` secret is then deleted from the repository
- **AND** the script exits zero

#### Scenario: App secret installation failure preserves legacy PAT

- **WHEN** the operator runs `gh-bootstrap.sh` on a target with legacy `WORKFLOW_PAT` installed
- **AND** the App private key supplied is empty or invalid (so secret install fails)
- **THEN** the script exits non-zero
- **AND** the legacy `WORKFLOW_PAT` secret is still present on the target

#### Scenario: Re-run when WORKFLOW_PAT already gone is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` on a target where `WORKFLOW_PAT` is already absent
- **THEN** the WORKFLOW_PAT-removal step prints a clear "already absent" message and exits zero, with no API calls that mutate state

## REMOVED Requirements

### Requirement: Bootstrap installs WORKFLOW_PAT secret

**Reason**: The opsx-apply workflow no longer authenticates via a per-operator fine-grained PAT. It now mints a short-lived installation token from a GitHub App per run (see `apply-workflow` capability, "GitHub App installation token minted before any git or PR operation"). The PAT was the root cause of PR authorship being attributed to the operator (R3 in the roadmap), so it is removed entirely.

**Migration**: Existing adopters carrying `WORKFLOW_PAT` upgrade via `install.sh upgrade --ref <new>` (refreshes the workflow file and bootstrap script) followed by `install.sh reconfigure` (runs the new bootstrap, which installs the App secrets and deletes the legacy PAT). See `docs/SETUP.md` for the step-by-step. The operator separately revokes the underlying PAT on GitHub once the migration is confirmed working.

## MODIFIED Requirements

### Requirement: Documentation set is sufficient for unaided adoption

The repo SHALL include `docs/SETUP.md`, `docs/SECURITY.md`, and `docs/COSTS.md`. SETUP.md SHALL contain a complete adoption checklist runnable without external context, including a "Create and install the remcc GitHub App" section that documents the App's required permissions (`Contents: write`, `Pull requests: write`, `Workflows: write`, `Metadata: read`), where to create the App, how to generate and download the private-key PEM, and how to install the App on the target repository. SECURITY.md SHALL document the two-layer safety model, enumerate the controls each layer relies on, explicitly call out which controls are unavailable on user-owned and on private-without-GHAS targets, document the GitHub App as the bot's identity (including credential-rotation procedure for the private key and the resulting blast-radius implications), together with the substitutions that take their place. COSTS.md SHALL document Anthropic admin console budget configuration and GitHub Actions minute usage.

#### Scenario: A second adopter completes setup using docs alone

- **WHEN** an operator who has not previously interacted with remcc
  follows `docs/SETUP.md` end to end on a fresh repository
- **THEN** the adoption completes successfully and the smoke test
  passes without questions back to the remcc maintainer

#### Scenario: SETUP.md walks through GitHub App creation

- **WHEN** an operator who has never created a GitHub App opens `docs/SETUP.md`
- **THEN** they find a step-by-step section that names every form field they need to fill in (App name, homepage URL, webhook off, the four required permissions), how to generate a private-key PEM, and how to install the App on a single repository

#### Scenario: SECURITY.md documents App credential rotation

- **WHEN** an operator opens `docs/SECURITY.md` looking for how to rotate the App private key
- **THEN** they find a procedure (regenerate key in App settings → re-run `install.sh reconfigure` → revoke old key) and a paragraph describing the blast radius if the key is exfiltrated
