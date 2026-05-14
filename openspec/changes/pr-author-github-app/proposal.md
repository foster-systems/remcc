## Why

Today the `opsx-apply` workflow authenticates as the operator: `gh-bootstrap.sh` installs the operator's fine-grained PAT as `WORKFLOW_PAT`, the workflow checks out and pushes via that PAT, and GitHub attributes the resulting PR to the PAT owner. The operator therefore cannot meaningfully code-review or approve the bot's PR without bypassing branch protection (you can't approve your own PR), which defeats roadmap goal R3: *the merge request opened by the bot, after verify, should be authored by the bot — not by me — so I can do a proper code review and merge without overriding branch protection rules*.

A dedicated bot identity also tightens the security story: credentials scope to a single GitHub App rather than a long-lived personal token tied to the operator's whole account.

## What Changes

- Introduce a **remcc GitHub App** as the authenticated identity for the `opsx-apply` workflow. The App installs on each adopter repository; the workflow exchanges its App credentials for a short-lived installation access token at the start of every run, and uses that token for checkout, push, and PR creation.
- **BREAKING for adopters**: replace the `WORKFLOW_PAT` repository secret with two new repository secrets: `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY`. The workflow no longer reads `WORKFLOW_PAT`, and `gh-bootstrap.sh` no longer installs it.
- Workflow uses an action (e.g. `actions/create-github-app-token@v1` or equivalent) early in the job to mint an installation token, then uses that token instead of `WORKFLOW_PAT` for `actions/checkout`, `git push`, and `gh pr create`. The auto-provisioned `GITHUB_TOKEN` is no longer used for PR creation.
- Workflow sets `git config user.name` / `user.email` to the App's bot identity (`<app-slug>[bot]` / `<numeric-id>+<app-slug>[bot]@users.noreply.github.com`) instead of `github-actions[bot]`, so commits and PR authorship line up.
- `gh-bootstrap.sh` learns two new install steps: prompt for / accept `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY` from env, write them as repository secrets, and remove `WORKFLOW_PAT` if it exists (so re-running bootstrap on an upgraded adopter is clean). The `--uninstall` path removes the two new secrets.
- `install.sh init` flows the new env vars through to the fetched `gh-bootstrap.sh` the same way it currently flows `ANTHROPIC_API_KEY` and `WORKFLOW_PAT`. `install.sh upgrade` remains template-only (no bootstrap re-run, unchanged).
- New subcommand `install.sh reconfigure` re-runs only the fetched `gh-bootstrap.sh` against an already-adopted repo, without touching the working tree or opening a PR. This is the migration entry point for existing adopters: after merging the upgrade PR, the operator runs `install.sh reconfigure` to install the new App secrets and let bootstrap delete the legacy `WORKFLOW_PAT`.
- Docs: `docs/SETUP.md` documents how to create the remcc GitHub App (one-time, by the adopter), the required App permissions (`Contents: write`, `Pull requests: write`, `Workflows: write`), and how to install it on the target repo. `docs/SECURITY.md` documents the App-based identity model and what an attacker compromising the App credentials could do.
- Branch protection / rulesets in `gh-bootstrap.sh` keep their current shape: the branch ruleset still excludes `refs/heads/change/**` from the bot's reach, and the push ruleset (when supported) still blocks `.github/**` edits to non-admin actors. The App's installation token is still a non-admin actor, so the existing safety bounds carry over.
- Onboarding: an adopter who already used `WORKFLOW_PAT` upgrades via `install.sh upgrade`, supplies the new App credentials when prompted, and the bootstrap idempotency check confirms `WORKFLOW_PAT` has been removed.

Out of scope (deferred): hosting / distributing the remcc App itself (creating it on `github.com/settings/apps/new` is a one-time operator step; we do not ship Terraform or App-manifest tooling in this change), and removing the `Allow GitHub Actions to create pull requests` repository setting (the App, not `GITHUB_TOKEN`, will create PRs, but the setting is harmless when left as is — flipping it back to `read` is a follow-up).

## Capabilities

### New Capabilities

(none — every change lands in existing capabilities)

### Modified Capabilities

- `apply-workflow`: replace the `WORKFLOW_PAT`-based auth requirement with a GitHub App installation token requirement; update PR-creation and push-attribution requirements so PR author and commit author are the App's bot identity.
- `repo-adoption`: replace the `WORKFLOW_PAT` secret install requirement with two new secret install requirements (`REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`) and a removal-on-upgrade requirement for the legacy `WORKFLOW_PAT` secret; update docs requirements to cover App setup.
- `remcc-cli`: add a new `install.sh reconfigure` subcommand that runs only the GitHub-side bootstrap step against an already-adopted target; update `install.sh init`'s documented env-var pass-through from `{ANTHROPIC_API_KEY, WORKFLOW_PAT, ...}` to `{ANTHROPIC_API_KEY, REMCC_APP_ID, REMCC_APP_PRIVATE_KEY, REMCC_APP_SLUG, ...}`.

## Impact

- `templates/workflows/opsx-apply.yml`: add a `Mint App installation token` step; swap `secrets.WORKFLOW_PAT` for the minted token across `actions/checkout`, the push step, and `gh pr create`; update the bot's git identity; remove the WORKFLOW_PAT preflight.
- `templates/gh-bootstrap.sh`: add `configure_remcc_app_secrets` (read/install `REMCC_APP_ID` + `REMCC_APP_PRIVATE_KEY`), add `remove_workflow_pat_secret_legacy` to the install path so upgrades drop the old secret, extend the idempotency snapshot to include the new secrets' presence, extend `--uninstall` to delete the new secrets.
- `install.sh`: update `init`'s `--help` env-var pass-through documentation; add a new `reconfigure` subcommand that only runs the fetched bootstrap script against an already-adopted repo (verifies `.remcc/version` on `origin/main`, refuses on un-adopted targets); root `--help` and no-arg invocations list the new subcommand.
- `docs/SETUP.md`: add a "Create and install the remcc GitHub App" section before the bootstrap step; update the secrets section.
- `docs/SECURITY.md`: replace the WORKFLOW_PAT threat-model section with an App-credentials section.
- `scripts/smoke-init.sh`, `scripts/smoke-postmerge.sh`, `scripts/smoke-upgrade.sh`: pass the new env vars through; assert the new secrets exist and the legacy one is gone after upgrade.
- No changes to `apply-workflow`'s trigger surface, opt-in trigger gate, concurrency partitioning, log-artifact upload, or model/effort resolution. Branch protection and ruleset shapes are unchanged.
