## Context

The `opsx-apply` workflow today checks out, pushes, and opens PRs using `secrets.WORKFLOW_PAT` — a fine-grained personal access token belonging to the operator (see `templates/workflows/opsx-apply.yml` lines 40–47, 74–79, 297–315, and 317–369; the secret is installed by `templates/gh-bootstrap.sh` `configure_workflow_pat_secret`, lines 379–386). The auto-provisioned `GITHUB_TOKEN` cannot push under `.github/workflows/`, which is why a PAT was introduced in the first place.

Consequence: GitHub attributes every workflow PR to the PAT owner (the operator). Required-approving-reviews branch protection forbids the PR author from approving their own PR, and even with the current `required_approving_review_count: 0`, the optics make "code review by a human distinct from the author" impossible — defeating R3 (operator cannot meaningfully review-and-merge the bot's PRs without bypassing protection).

A GitHub App fixes the attribution issue and tightens the credential blast radius: a leaked App private key compromises the App's installation scope (write on enrolled repos), not the operator's entire GitHub account.

## Goals / Non-Goals

**Goals:**
- PR author shown in the GitHub UI for opsx-apply PRs is the App's bot identity (`<slug>[bot]`), not the operator.
- Commits authored on `change/**` branches are attributed to the App's bot identity.
- Workflow can still push under `.github/workflows/` (the original reason WORKFLOW_PAT existed).
- Adopter onboarding (`install.sh init`) and upgrade (`install.sh upgrade`) flow the new App credentials through to the bootstrap script without manual file editing.
- Bootstrap remains idempotent: re-running after the migration is a no-op; running on a legacy adopter cleanly removes `WORKFLOW_PAT` after writing the new secrets.
- Existing safety controls (branch ruleset confining bot to `change/**`, push ruleset blocking `.github/**` on org repos) carry over unchanged — the App's installation token is still a non-admin actor.

**Non-Goals:**
- Shipping the remcc GitHub App itself, an App manifest, or any "click to install" automation. Each operator creates their own App once (the `github.com/settings/apps/new` flow) and installs it on every repo they adopt. We document the App's required permissions and the steps; we do not host or distribute the App.
- Removing the `Allow GitHub Actions to create pull requests` repository setting that `configure_actions_pr_creation` toggles. It becomes redundant (the App, not `GITHUB_TOKEN`, opens PRs), but flipping it back to `read` is a separate, low-priority cleanup change.
- Multi-App support, App-per-operator-vs-org policy, or App-credential rotation tooling. The operator rotates the private key manually via App settings and re-runs `install.sh upgrade` with the new value.
- Backwards compatibility with the old WORKFLOW_PAT-shaped workflow. After this change, an adopter on the new template MUST have App credentials installed; the old shape is removed entirely.

## Decisions

### Decision: Use a GitHub App, not a separate machine-user PAT

**Choice:** GitHub App with installation tokens minted at workflow start.

**Why:** The App identity is a first-class GitHub actor (`<slug>[bot]`). Branch protection treats it as distinct from any human user, so an operator who is admin on the repo can approve and merge the App's PRs without configuring bypass exceptions. A separate machine-user PAT would also create a distinct identity, but it costs a GitHub seat, requires a separate login to maintain, exposes a long-lived high-scope credential, and (on private orgs) counts toward seat limits. App installation tokens are short-lived (1 hour), scoped to specific permissions, and rotatable by regenerating a private key.

**Alternatives considered:**
- *Machine-user PAT*: rejected as above.
- *GITHUB_TOKEN only*: rejected because GITHUB_TOKEN cannot push under `.github/workflows/`, which the agent must do during apply runs that touch the workflow file itself.

### Decision: Mint the installation token via `actions/create-github-app-token@v1`

**Choice:** Use the GitHub-authored `actions/create-github-app-token` action as the first step inside the apply job. Provide `app-id` and `private-key` as inputs (sourced from `secrets.REMCC_APP_ID` / `secrets.REMCC_APP_PRIVATE_KEY`). The action outputs `token` and `installation-id`.

**Why:** It's the canonical action, maintained by GitHub, handles JWT signing and token exchange, redacts the resulting token from logs, and returns the installation token as a step output for downstream `with:` and `env:` plumbing. Vendored action means no extra `npm install` or shell JWT-generation code in the workflow.

**Alternatives considered:**
- *Inline JWT generation in bash/Python*: rejected. Reinvents an audited path and pushes a private key through shell variables.
- *`tibdex/github-app-token`*: a popular third-party alternative, but it's a third-party action and would need pinning to a SHA, adding supply-chain surface. The first-party action is preferable.

### Decision: Use the installation token for checkout, push, AND PR creation

**Choice:** A single installation token is passed as:
- `actions/checkout@v4` `token:` input (so the remote is configured with this token for subsequent `git push`).
- `GH_TOKEN` env on the PR step (so `gh pr create` runs as the App).
- The default token for `git push` (inherited from the checkout-step remote URL).

`secrets.GITHUB_TOKEN` is no longer used for PR creation. The job-level `permissions:` block can stay at `contents: write` + `pull-requests: write` for the (now-unused) auto-provisioned token, since GitHub Actions still provisions it; we leave it as-is rather than reducing to `permissions: {}` because shrinking it is not load-bearing for R3.

**Why:** Every git/GitHub-side action attributed via the App requires its token. Mixing tokens (App for some operations, GITHUB_TOKEN for others) would split attribution — e.g., commits attributed to App but PR opened by `github-actions[bot]` — defeating the goal.

### Decision: Compute the bot's git identity from the App's slug and installation ID at workflow runtime

**Choice:** After minting the installation token, query the `users/<app-slug>[bot]` endpoint with the installation token to fetch the bot user's numeric ID, then set:
- `git config user.name "<app-slug>[bot]"`
- `git config user.email "<numeric-id>+<app-slug>[bot]@users.noreply.github.com"`

The App slug is supplied as a third workflow-level input (`vars.REMCC_APP_SLUG`, a repository variable installed by bootstrap), since GitHub's installation-token endpoint does not return the slug directly.

**Why:** Commits MUST be attributed to the App identity to keep PR author and commit author aligned (otherwise `git log` would still show "github-actions[bot]" on the bot's commits even though the PR shows the App). The `noreply` email shape with the numeric ID is the canonical pattern GitHub itself uses for bot accounts.

**Alternatives considered:**
- *Hardcode the slug in the workflow template*: rejected — the slug differs per operator (each operator creates their own App with their own name).
- *Skip the numeric-ID lookup and use just `<slug>[bot]@users.noreply.github.com`*: rejected — GitHub silently rejects commit-author emails for bots that don't match the `<id>+<slug>[bot]@users.noreply.github.com` shape (commits appear as the wrong identity).

### Decision: Three new repository config items, replacing one

**Choice:**
- `secrets.REMCC_APP_ID` (numeric App ID; not actually a secret on GitHub's classification, but treating as such is harmless and avoids leaking it via the public variables list).
- `secrets.REMCC_APP_PRIVATE_KEY` (PEM, multiline).
- `vars.REMCC_APP_SLUG` (App slug, used to construct the git identity).

`secrets.WORKFLOW_PAT` is deleted by `gh-bootstrap.sh` when the three new items are present.

**Why:** The App ID is technically public information (visible to anyone with App-page access), but storing it as a secret means bootstrap can use a single uniform `gh secret set` path for both fields, and the slug-as-variable separation reflects that the slug also appears in PR-body summaries (we want it visible). The three-item split mirrors what `actions/create-github-app-token` expects.

### Decision: Bootstrap removes WORKFLOW_PAT only after the new secrets are confirmed installed

**Choice:** `configure_remcc_app_secrets` runs *before* `remove_workflow_pat_legacy_secret`. The removal step is unconditional after both new secrets are in place; if `read_remcc_app_private_key_into_env` errors (empty input), bootstrap exits before deleting `WORKFLOW_PAT`, leaving the adopter on a working (legacy) configuration.

**Why:** Avoids bricking an adopter mid-migration. The new workflow template requires App secrets; the old required WORKFLOW_PAT. If we deleted WORKFLOW_PAT before confirming App secrets, a failed bootstrap run would leave the workflow unable to push, requiring manual recovery.

### Decision: install.sh flows new env vars through unchanged for `init`; new `reconfigure` subcommand handles migration

**Choice:** `install.sh init` passes `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, and `REMCC_APP_SLUG` from its environment to the spawned `gh-bootstrap.sh` exactly the way it already passes `ANTHROPIC_API_KEY` and the (now-obsolete) `WORKFLOW_PAT`. The CLI does not prompt for these itself — `gh-bootstrap.sh` owns the interactive prompts.

`install.sh upgrade` remains template-only (no bootstrap run; unchanged from today). For existing adopters whose bootstrap-managed config needs reconfiguring after a template upgrade, a new subcommand `install.sh reconfigure` is added: it verifies `.remcc/version` exists on `origin/main`, fetches the chosen ref, runs only the cloned `gh-bootstrap.sh`, and exits — without touching the working tree, creating a branch, or opening a PR.

**Why:** Keeps `upgrade`'s existing contract intact (template-only, no surprise GitHub-side mutation). A dedicated `reconfigure` command is the explicit, opt-in entry point for re-bootstrap, which is needed whenever bootstrap-managed config changes (this change is the first instance; future changes that alter what bootstrap installs will reuse the same path).

**Alternatives considered:**
- *Auto-running bootstrap from `upgrade`*: rejected — silently mutates GitHub config during a "template refresh" command, breaking the existing separation.
- *Re-using `init` for re-bootstrap*: rejected — `init` is documented as first-time adoption, opens a (likely-empty) PR each time, and conflates "I want to re-run bootstrap" with "I want to install templates".
- *Telling adopters to run `bash <(curl …/templates/gh-bootstrap.sh)` manually*: rejected — adds a second curl entry point with no version-marker check; easy to footgun against an un-adopted repo.

### Decision: One App per operator, installed per adopter repo

**Choice:** Documentation says: "create one GitHub App under your personal account (or org) once, install it on each adopter repository, and reuse the same `REMCC_APP_ID` / `REMCC_APP_PRIVATE_KEY` across them. `REMCC_APP_SLUG` is the same too." The App permissions are `Contents: write`, `Pull requests: write`, `Workflows: write`, `Metadata: read`.

**Why:** Minimal operator overhead (one App created, one private key managed). The App's per-installation token is automatically scoped to the installed repo only — no cross-repo blast radius despite a shared App.

## Risks / Trade-offs

- **[Risk] Operator forgets to install the App on the adopter repo** → workflow fails when `actions/create-github-app-token` tries to mint a token for an uninstalled App, with GitHub's "installation not found" error. **Mitigation:** the action's error is clear; SETUP.md's checklist puts "install the App on this repo" as a numbered step before "run `install.sh init`", and a preflight step in the workflow surfaces a one-line `::error::` with the App's settings URL if the mint step exits non-zero.

- **[Risk] Operator pastes the private-key PEM with mangled newlines** → `actions/create-github-app-token` rejects it. **Mitigation:** `gh secret set` accepts multiline values via stdin; `gh-bootstrap.sh` reads the PEM from `/dev/tty` (or env) and pipes it directly to `gh secret set ... < /dev/stdin`. Smoke test asserts a successful token mint.

- **[Risk] Bypass: an attacker who exfiltrates the App private key can push to any installed adopter repo** → larger than a per-repo PAT in raw count, but the credential is rotatable in seconds (regenerate key in App settings) and the App's permissions are narrower than a fine-grained PAT (no profile, no settings, no orgs). **Mitigation:** SECURITY.md documents the new credential, rotation procedure, and the recommendation to install the App on a curated set of repos only.

- **[Risk] App slug name collisions** → two operators happening to create Apps with the same slug would produce identical commit identities. **Mitigation:** GitHub already enforces App slug uniqueness across the platform, so this cannot happen.

- **[Trade-off] Workflow gains one extra step (token mint) and one extra repo-config item (the slug variable)** → ~3 seconds added per run, plus a tiny extra preflight surface. Acceptable given the R3 unlock.

- **[Trade-off] Adopters on the old template MUST upgrade to keep working once they update their workflow file** → unavoidable given the BREAKING nature. `install.sh upgrade` makes this a one-command operation; SETUP.md upgrade section calls out the new prerequisite.

## Migration Plan

1. Land this change. Adopters on the old workflow continue to work (no change to their `.github/workflows/opsx-apply.yml`).
2. Each adopter, when ready:
   - Creates a remcc GitHub App per `docs/SETUP.md` and installs it on the target repo.
   - Runs `install.sh upgrade --ref <new>` to refresh templates. Merges the resulting PR. (At this point the new workflow file is on `main` but its App-secret references are dangling.)
   - Runs `install.sh reconfigure` (new subcommand), providing `REMCC_APP_ID` / `REMCC_APP_PRIVATE_KEY` / `REMCC_APP_SLUG` via env vars or prompts. Bootstrap installs the App secrets and removes the legacy `WORKFLOW_PAT` secret.
   - Next `@change-apply` push triggers the workflow with App identity end-to-end.
3. Smoke tests (`scripts/smoke-init.sh`, `scripts/smoke-postmerge.sh`, `scripts/smoke-upgrade.sh`) are updated to require the new env vars and to assert post-run PR authorship matches the App slug. A new smoke test (or extension to `smoke-upgrade.sh`) exercises the full `upgrade` → `reconfigure` migration on a legacy-WORKFLOW_PAT fixture.

Rollback: revert this commit; adopters on the new template revert their adopter repo to the prior template via `install.sh upgrade --ref <previous-tag>` and then `install.sh reconfigure --ref <previous-tag>`. The older bootstrap re-installs `WORKFLOW_PAT` and removes the new App secrets (the older bootstrap's idempotency path treats them as foreign).
