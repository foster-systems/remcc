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
cloned alongside:

```sh
# Adjust REMCC if your remcc clone is elsewhere.
REMCC=../remcc

mkdir -p .github/workflows
cp "${REMCC}/templates/workflows/opsx-apply.yml" .github/workflows/opsx-apply.yml
```

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

Commit and push these changes on a regular feature branch (not a
`change/**` branch — that branch namespace will be restricted to the
bot in step 3).

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
3. Creates two rulesets, with admin bypass:
   - A **branch ruleset** that blocks any non-admin actor from
     creating, updating, deleting, or non-fast-forwarding refs that
     do not match `refs/heads/change/**`. The workflow's
     `GITHUB_TOKEN` is therefore confined to `change/**`.
   - A **push ruleset** that blocks non-admin pushes from modifying
     paths under `.github/**`. The workflow cannot rewrite CI; you
     can, because you bypass.
4. Enables GitHub secret scanning and secret push protection.
5. Prompts for `ANTHROPIC_API_KEY` (input hidden) and uploads it as
   the repository secret `ANTHROPIC_API_KEY`. If the variable is
   already set in your shell, the script picks it up and does not
   prompt.
6. Runs an idempotency smoke test: re-applies every change and
   diffs the resulting state. A diff is a bug — please report it.

Re-running the script later is a no-op.

### If a step fails

- **"gh is not authenticated"**: run `gh auth login` and retry.
- **403 errors from `gh api`**: you are not admin on the target repo.
  Ask the owner to grant admin or run the script themselves.
- **secret_scanning enable fails**: secret scanning requires either
  a public repo or GitHub Advanced Security on the plan. Address
  the underlying issue rather than skipping this step — secret push
  protection is the backstop against `ANTHROPIC_API_KEY` accidentally
  landing in a commit.

## Step 4 — smoke test

Push a trivial change branch to verify the full path runs end to end.

1. Create an OpenSpec change under `openspec/changes/test-apply/`
   with whatever scaffolding `openspec` produces by default. Any
   minimal change with a `tasks.md` is fine. Commit it on `main`
   locally.
2. Create and push the change branch:
   ```sh
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
   This deletes the two rulesets, removes branch protection on
   `main`, disables secret scanning + push protection, and deletes
   the `ANTHROPIC_API_KEY` repository secret. It does not touch
   any files in your repository.
2. **Workflow file** — delete it from the repository:
   ```sh
   git rm .github/workflows/opsx-apply.yml
   ```
3. **Claude settings template** — if you copied
   `templates/claude/settings.json`, leave it; it is harmless and
   contains no remcc-specific configuration. If you did not have
   one before, you can delete it: `git rm .claude/settings.json`.
4. Commit and push the workflow removal on a regular feature
   branch and merge via PR.

After these steps, no remcc-specific configuration remains on the
target repository.
