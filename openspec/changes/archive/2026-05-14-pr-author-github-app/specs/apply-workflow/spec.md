## ADDED Requirements

### Requirement: GitHub App installation token minted before any git or PR operation

The workflow SHALL mint a short-lived GitHub App installation token as the first job step after the preflight gates (secret presence, trigger subject case-sensitivity, change-name resolution). The token SHALL be obtained by exchanging the App ID and PEM-encoded private key for an installation token via the canonical `actions/create-github-app-token` action (or an equivalent action that produces a single-installation token bound to the running repository). The App ID SHALL be read from `secrets.REMCC_APP_ID` and the private key from `secrets.REMCC_APP_PRIVATE_KEY`. The minted token's value SHALL be redacted from workflow logs.

All subsequent steps that interact with the git remote or the GitHub API on behalf of remcc — `actions/checkout`, `git push`, and `gh pr create` / `gh pr comment` — SHALL use the minted installation token, not `secrets.GITHUB_TOKEN` and not any operator personal access token.

#### Scenario: Missing App ID secret fails fast

- **WHEN** `REMCC_APP_ID` is not set in repository secrets
- **THEN** the workflow exits non-zero before minting a token or invoking Claude Code, with a message identifying the missing secret and pointing the operator at `install.sh reconfigure`

#### Scenario: Missing App private key secret fails fast

- **WHEN** `REMCC_APP_PRIVATE_KEY` is not set in repository secrets
- **THEN** the workflow exits non-zero before minting a token or invoking Claude Code, with a message identifying the missing secret and pointing the operator at `install.sh reconfigure`

#### Scenario: App not installed on the target repo surfaces clear error

- **WHEN** the App credentials are present but the App has not been installed on the running repository
- **THEN** the token-mint step fails with a non-zero exit, the workflow surfaces a `::error::` annotation that names the App slug and links to the App's settings page, and no Claude Code invocation has been made

#### Scenario: Minted token is used for checkout

- **WHEN** the token-mint step completes successfully
- **THEN** the `actions/checkout` step that follows uses the minted token (passed via the action's `token:` input) so the remote URL is persisted with the App's credentials for subsequent `git push`

#### Scenario: Minted token is used for PR creation

- **WHEN** the workflow reaches the PR-open-or-update step
- **THEN** `gh pr create` and `gh pr comment` run with `GH_TOKEN` set to the minted installation token, not `secrets.GITHUB_TOKEN`

### Requirement: Bot git identity matches the GitHub App

The workflow SHALL configure `git user.name` and `git user.email` so that commits the workflow creates are attributed to the GitHub App's bot identity. `user.name` SHALL be `<slug>[bot]` where `<slug>` is the App's GitHub slug, read from the repository variable `REMCC_APP_SLUG`. `user.email` SHALL be `<numeric-id>+<slug>[bot]@users.noreply.github.com`, where `<numeric-id>` is the numeric ID of the bot user backing the App. The workflow SHALL look up the numeric ID at runtime by querying the GitHub API (`GET /users/<slug>[bot]`) using the minted installation token; the value SHALL NOT be hardcoded in the workflow template.

#### Scenario: Commits land with the App's identity

- **WHEN** the workflow creates a commit on a `change/**` branch
- **THEN** the commit's author and committer fields show `<slug>[bot] <numeric-id>+<slug>[bot]@users.noreply.github.com`

#### Scenario: Missing slug variable fails fast

- **WHEN** the repository variable `REMCC_APP_SLUG` is unset or empty
- **THEN** the workflow exits non-zero before invoking Claude Code, with a message identifying the missing variable and pointing the operator at `install.sh reconfigure`

### Requirement: PR author is the GitHub App identity

Any pull request the workflow creates SHALL be authored by the GitHub App's bot identity (`<slug>[bot]`), not by `github-actions[bot]` and not by the operator. This is a direct consequence of using the minted installation token for `gh pr create`, but it is called out as a normative requirement so that future workflow refactors do not silently regress to `secrets.GITHUB_TOKEN`-backed PR creation.

#### Scenario: First successful run opens a PR as the App

- **WHEN** the workflow opens a new PR for the change branch
- **THEN** the PR's "author" field as returned by `gh pr view --json author --jq .author.login` is `<slug>[bot]`

#### Scenario: PR comments on subsequent runs come from the App

- **WHEN** the workflow comments on an existing PR for the change branch
- **THEN** the comment's "author" field is `<slug>[bot]`

## MODIFIED Requirements

### Requirement: Commit any uncommitted agent output

The workflow SHALL stage all working-tree changes and create a single commit if any uncommitted changes exist after the apply step. If the working tree is clean after apply, the workflow SHALL NOT create an empty commit. Commits created by this step SHALL be authored by the GitHub App's bot identity (see "Bot git identity matches the GitHub App").

#### Scenario: Agent left changes unstaged

- **WHEN** apply completes with modified files in the working tree
- **AND** the changes are not yet committed
- **THEN** the workflow creates a commit containing those changes
  with author `<slug>[bot]` (the GitHub App identity)

#### Scenario: Agent already committed everything

- **WHEN** apply completes with a clean working tree
- **THEN** the workflow does not create an additional commit

### Requirement: Push the change branch

The workflow SHALL push commits to the change branch using the GitHub App installation token (see "GitHub App installation token minted before any git or PR operation") whenever the local branch is ahead of `origin`. The workflow SHALL NOT push when no commits are ahead of `origin`. The workflow SHALL NOT use `secrets.GITHUB_TOKEN` or any operator PAT for this push.

#### Scenario: New commits are pushed to the branch

- **WHEN** the local branch is ahead of its remote tracking branch
- **THEN** the workflow pushes the new commits to `origin` using the App installation token persisted by the `actions/checkout` step

#### Scenario: Push attempts under `.github/workflows/` succeed for the App

- **WHEN** the agent's apply step modifies a file under `.github/workflows/`
- **AND** the workflow attempts to push that change
- **THEN** the push succeeds (the App's installation token has `Workflows: write`, which `secrets.GITHUB_TOKEN` lacks)
