# Setting up remcc on a target repository

remcc adds an unattended `/opsx:apply` GitHub Actions workflow to a
repository that already uses OpenSpec. Adoption is a small number of
file copies plus a one-time GitHub configuration script. This document
is the complete checklist; if you find yourself reaching for context
that isn't here, that is a documentation bug — please record what you
needed and update this file before continuing.

## Prerequisites

remcc v1 is intentionally narrow. Confirm every box below before
proceeding.

| # | Requirement | Verification command |
|---|---|---|
| 1 | An existing GitHub repository you have admin on | `gh repo view --json viewerPermission --jq .viewerPermission` should print `ADMIN` |
| 2 | A `main` branch on the remote | `git ls-remote --heads origin main \| grep main` |
| 3 | OpenSpec initialised in the repo | `test -d openspec && echo ok` |
| 4 | `.claude/` directory committed (skills/commands available to the runner) | `test -d .claude && echo ok` |
| 5 | **pnpm-managed JavaScript project with a committed `pnpm-lock.yaml` at the repo root** | `test -f pnpm-lock.yaml && echo ok` |
| 6 | Local tools installed: `gh`, `jq`, `git`, Node.js ≥ 20.19, `pnpm` | `gh --version && jq --version && node -v && pnpm -v` |
| 7 | An Anthropic API key with budget configured | (key is uploaded as a repo secret in step 3 below) |

> **v1 supports pnpm-managed repos only.** The workflow runs
> `pnpm install --frozen-lockfile`. If your repository uses npm, yarn,
> or no JavaScript at all, remcc v1 will fail. Generalising to other
> package managers is deferred to a future change; until then, please
> open an issue on the remcc repository describing your setup rather
> than working around the constraint locally.

## Step 1 — copy the template files

From a clone of the target repository, with this remcc repo also
cloned alongside, on a fresh feature branch:

```sh
# Adjust REMCC if your remcc clone is elsewhere.
REMCC=../remcc

git checkout main
git pull --ff-only
git checkout -b setup-remcc

mkdir -p .github/workflows
cp "${REMCC}/templates/workflows/opsx-apply.yml" .github/workflows/opsx-apply.yml
```

The `setup-remcc` branch is a regular feature branch — *not* a
`change/**` branch. After step 3, the `change/**` namespace is
restricted to the workflow's bot identity, and the bootstrap
configuration would block your local pushes to such a branch.

### `.claude/settings.json` — merge, don't overwrite

The template at `templates/claude/settings.json` is intentionally
minimal: it carries no permissive `permissions.allow` entries. The
runner ignores `.claude/settings.json` because Claude Code is invoked
with `--dangerously-skip-permissions`; the file's only effect is on
local development.

- **No existing `.claude/settings.json` in the target repo:** copy
  the template directly:
  ```sh
  cp "${REMCC}/templates/claude/settings.json" .claude/settings.json
  ```
- **Existing `.claude/settings.json`:** keep your existing file. The
  remcc template adds no fields that your file does not already
  cover (an empty `permissions.allow`). If you want a record that
  remcc ran, leave the file untouched.

### `openspec/config.yaml` — runner-aware drafting hints (optional)

The template at `templates/openspec/config.yaml` carries a
commented-out "remcc baseline" block: a `context:` paragraph and a
`rules.tasks:` list that tell the OpenSpec drafting agents
(proposal / design / tasks) that the change will likely be applied
unattended on a GitHub Actions runner. The intent is to catch
runner-incompatible task shapes (manual browser checks, lingering
background processes, undeclared tool dependencies) at *drafting*
time rather than discovering them mid-apply on the runner.

This is opt-in. Adopters who sometimes apply changes locally may
want to prune individual rules; adopters who always apply via the
runner will likely want the whole block.

- **No existing `openspec/config.yaml` (you need to initialise
  OpenSpec anyway):** copy the template directly:
  ```sh
  cp "${REMCC}/templates/openspec/config.yaml" openspec/config.yaml
  ```
  Then open the file and uncomment the `context:` and `rules:`
  blocks under "remcc baseline".
- **Existing `openspec/config.yaml`:** open both files side-by-side
  and merge the `context:` paragraph and the `rules.tasks:` entries
  from the template's "remcc baseline" block into your existing
  keys (do not introduce duplicate top-level keys). If you already
  have project-specific entries under `rules.tasks:`, append the
  remcc rules below them.

The "Runner profile" section near the bottom of this document
enumerates the tooling the rules assume is preinstalled.

Commit and push the `setup-remcc` branch, then open a PR and merge
it to `main`:

```sh
git add .github/workflows/opsx-apply.yml .claude/settings.json openspec/config.yaml
git commit -m "Adopt remcc: workflow + Claude settings + drafting hints"
git push -u origin setup-remcc
gh pr create --base main --head setup-remcc --fill
gh pr merge --merge --delete-branch
```

The merge must happen *before* the smoke test, because the workflow
file needs to be on `main` for `change/**` branches forked from `main`
to inherit it.

## Step 2 — verify the workflow file at a glance

Open `.github/workflows/opsx-apply.yml` and confirm:

- It triggers on `push` to `change/**` and `workflow_dispatch`.
- `permissions:` block contains only `contents: write` and
  `pull-requests: write`.
- `timeout-minutes: 180`.
- `claude --dangerously-skip-permissions` is invoked.

You should not need to edit anything for a default adoption.

## Step 3 — configure GitHub-side controls

Run the bootstrap script from the root of the target repository:

```sh
bash "${REMCC}/templates/gh-bootstrap.sh"
```

The script:

1. Verifies `gh` is authenticated and you are inside a git repo.
2. Configures branch protection on `main` (PR required, no force
   push, no deletions).
3. Creates a **branch ruleset** that blocks any non-admin actor from
   creating, updating, deleting, or non-fast-forwarding refs that
   do not match `refs/heads/change/**`. The workflow's
   `GITHUB_TOKEN` is therefore confined to `change/**`. Admin
   bypasses, so you keep direct access.
4. Creates a **push ruleset** blocking non-admin pushes that modify
   paths under `.github/**`, **if the target is an
   organization-owned repo**. On user-owned repos, push rulesets
   are unavailable — the script prints a warning and continues.
   On user-owned repos, `.github/**` modifications must be caught
   during your PR review.
5. Enables **secret scanning + secret push protection**, **if the
   feature is available** for the target repo. Public repos get it
   for free; private repos require GitHub Advanced Security. On
   private repos without GHAS, the script prints a warning and
   continues. The remaining secret-leak protection is GitHub
   Actions log redaction (built into Actions, no setup required).
6. Enables the GitHub Actions setting that allows `GITHUB_TOKEN`
   to open pull requests. This setting defaults to off; without it,
   the workflow's PR-creation step always fails.
7. Prompts for `ANTHROPIC_API_KEY` (input hidden) and uploads it as
   the repository secret. If the variable is already set in your
   shell, the script picks it up and does not prompt.
8. Prompts for `OPSX_APPLY_MODEL` and `OPSX_APPLY_EFFORT` — the
   per-repo defaults for the `/opsx:apply` step. Empty input
   leaves the variable unset, in which case the workflow's
   baked-in defaults (`sonnet` / `high`) apply. The script reads
   `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` from the environment
   if set, so the prompts can be skipped in scripted runs. See
   "Configuring the apply model" below for what these knobs do.
9. Runs an idempotency smoke test: re-applies every change and
   diffs the resulting state. A diff is a bug — please report it.

Re-running the script later is a no-op.

> **What this means for user-owned private repos.** The model loses
> two outside-the-runner controls on user-owned private targets
> (push ruleset and secret scanning). The bot is still confined to
> `change/**` and cannot push to `main`. The substitutions —
> `.github/**` is gated by your PR review; secret-shaped commits
> are not blocked at push time, only redacted from logs — are
> documented in `SECURITY.md`. If you need the full model, host
> the target repo under a GitHub organization with GHAS.

### If a step fails

- **"gh is not authenticated"**: run `gh auth login` and retry.
- **403 errors from `gh api`**: you are not admin on the target repo.
  Ask the owner to grant admin or run the script themselves.
- **422 errors not handled by the script's warnings**: GitHub
  occasionally adds new constraints. Capture the full error and
  open an issue on the remcc repo before working around it locally.

## Configuring the apply model

The `/opsx:apply` step is invoked with an explicit `--model` and
`--effort` (Claude Code's thinking-budget level). Both are
configurable per repo and per run.

### Repository-variable defaults

| Variable | Purpose | Accepted values | Default if unset |
|---|---|---|---|
| `OPSX_APPLY_MODEL` | Claude model alias passed to `claude --model` | `opus`, `sonnet`, `haiku`, or any full model id the CLI accepts | `sonnet` |
| `OPSX_APPLY_EFFORT` | Claude Code thinking-budget level | `low`, `medium`, `high` | `high` |

`gh-bootstrap.sh` prompts for these during install. To change them
later without re-running the script:

```sh
gh variable set OPSX_APPLY_MODEL --body opus
gh variable set OPSX_APPLY_EFFORT --body medium
```

To revert to the baked-in default, delete the variable:

```sh
gh variable delete OPSX_APPLY_MODEL
```

The two variables resolve independently — leaving `OPSX_APPLY_EFFORT`
unset while setting `OPSX_APPLY_MODEL` is fine.

### Per-run override precedence

The workflow resolves `model` and `effort` independently for every
run with this precedence (highest first):

1. `workflow_dispatch` input (when non-empty)
2. Commit trailer on the head commit (`Opsx-Model:` / `Opsx-Effort:`)
3. Repository variable (`OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT`)
4. Baked-in default (`sonnet` for model, `high` for effort)

#### Commit-trailer override

For a push-triggered run, add a trailer to the head commit on the
change branch:

```text
Refactor auth middleware

Opsx-Model: opus
Opsx-Effort: medium
```

Trailer parsing uses `git interpret-trailers`, so standard Git
trailer rules apply: a blank line before the trailer block,
`Token: value` per line, token matching is case-insensitive.

#### Manual-dispatch override

Trigger the workflow manually with `gh workflow run` (or from the
Actions tab) and supply the inputs explicitly:

```sh
gh workflow run opsx-apply.yml \
  --ref change/refactor-auth \
  -f change_name=refactor-auth \
  -f model=opus \
  -f effort=low
```

Empty input means "no override" — leave a field blank to fall
through to the trailer / repo variable / baked default.

### Resolved values are reported in the PR

The workflow records the resolved `model` and `effort` (and the
source each came from) in the body of any PR it opens and in any
comment it posts on a re-run. That PR body is the source of truth
for "what did this run actually use?" — there is no need to dig
through the Actions logs.

### Forked PRs

Repository variables are not exposed to workflow runs originating
from forked PRs. The `opsx-apply` workflow only triggers on `push`
to `change/**` and on `workflow_dispatch`, both of which are
privileged events on the main repo, so the fork-PR exposure path
does not apply to remcc in practice.

## Runner profile

The `opsx-apply` workflow runs on GitHub-hosted `ubuntu-latest`.
The drafting hints in `templates/openspec/config.yaml` tell the
OpenSpec agents to assume the tooling listed here is available
without further setup; anything else must be installed by the
task itself.

### Provided by the workflow

| Tool | Source | Notes |
|---|---|---|
| Node.js 20 | `actions/setup-node@v4` | Pinned by the workflow; do not assume the ubuntu-latest default Node version |
| pnpm | `pnpm/action-setup@v4` | Resolves the version from your repo's `package.json#packageManager` if set, otherwise the action's latest |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` | Invoked with `--dangerously-skip-permissions` |
| OpenSpec CLI | `npm install -g @fission-ai/openspec@latest` | Used for the post-apply validate step |
| `ANTHROPIC_API_KEY` | Repo secret, exposed as env | Set by `gh-bootstrap.sh`; redacted from logs by GitHub |

### Provided by the `ubuntu-latest` image

The drafting hints assume the standard tools that GitHub bundles
into `ubuntu-latest`. The ones most likely to come up in tasks:

| Tool | Notes |
|---|---|
| Docker Engine + Compose v2 | `docker`, `docker compose` (no separate `docker-compose` v1) |
| `git`, `gh` | `gh` is pre-authenticated to the run's `GITHUB_TOKEN` for the same repo |
| `curl`, `wget`, `jq` | Use these for headless verification |
| `bash`, `sh` | Default shell for `run:` steps is `bash -e` |
| Postgres / MySQL clients | `psql`, `mysql` are present; the *servers* are not running by default |
| Python 3, build tools (`gcc`, `make`) | Useful for one-off scripts and native deps |

The full image manifest changes over time; the canonical reference
is GitHub's
[`runner-images`](https://github.com/actions/runner-images)
repository (`images/ubuntu/Ubuntu2404-Readme.md` for `ubuntu-latest`).
If you find yourself relying on something not listed in either
table above, install it explicitly in the relevant task — do not
assume future-you (or future-runner) will have it.

### What the runner does *not* provide

Worth calling out because tasks frequently assume them:

- No GUI / browser. Verification must use HTTP, exec, or log inspection.
- No long-lived state across runs. Every apply starts from a fresh checkout
  with cold Docker / pnpm caches unless the workflow opts into caching.
- No cloud credentials beyond what you've explicitly added as repo secrets.
- No interactive TTY. Commands that read from stdin or block on a prompt
  will hang the run until the 180-minute job timeout.

## Step 4 — smoke test

Push a trivial change branch to verify the full path runs end to end.

1. Create an OpenSpec change directory at `openspec/changes/test-apply/`
   with at minimum: `proposal.md`, `tasks.md`, and any specs/design
   that `openspec validate test-apply` requires for your project's
   schema. The trivial-task pattern works well — one task that
   creates a single small file is enough to exercise the path. Land
   this on `main` via the same feature-branch + PR flow you used in
   step 1, or as admin via direct push (you will see a
   `remote: Bypassed rule violations for refs/heads/main` message
   in the output — that is GitHub recording your admin bypass and
   is expected).
2. Create and push the change branch:
   ```sh
   git checkout main
   git pull --ff-only
   git checkout -b change/test-apply
   git push -u origin change/test-apply
   ```
3. Within a few seconds, the `opsx-apply` workflow run should appear
   under the repo's Actions tab. Watch the run and confirm:
   - The workflow trigger fires.
   - Claude Code runs to completion (apply step exits, exit code is
     captured to a step output).
   - `openspec validate test-apply` runs and passes.
   - A pull request to `main` is opened from `change/test-apply`.
   - Workflow logs are uploaded as artifact `agent-logs-test-apply`.
4. Close the PR without merging and delete the `change/test-apply`
   branch. The smoke test is over.

If any step is observed to require manual intervention, that is a
documentation bug. Capture what you had to do and patch SETUP.md.

## Removing remcc

remcc is reversible. To remove it from a target repository:

1. **GitHub-side configuration** — run the bootstrap script with
   `--uninstall`:
   ```sh
   bash "${REMCC}/templates/gh-bootstrap.sh" --uninstall
   ```
   This deletes any rulesets the script created, removes branch
   protection on `main`, disables secret scanning + push protection
   (where applicable), reverts the Allow-Actions-create-PRs toggle,
   and deletes the `ANTHROPIC_API_KEY` repository secret. It does
   not touch any files in your repository.
2. **Workflow file** — delete it from the repository:
   ```sh
   git rm .github/workflows/opsx-apply.yml
   ```
3. **Claude settings template** — if you copied
   `templates/claude/settings.json`, leave it; it is harmless and
   contains no remcc-specific configuration. If you did not have
   one before, you can delete it: `git rm .claude/settings.json`.
4. **OpenSpec drafting hints** — if you merged the "remcc baseline"
   block into `openspec/config.yaml`, delete those lines (the
   `context:` paragraph and `rules.tasks:` entries that reference
   the GitHub Actions runner). The rest of the file is your own
   project configuration; leave it alone.
5. Commit and push the workflow removal on a regular feature
   branch and merge via PR.

After these steps, no remcc-specific configuration remains on the
target repository.
