## 1. Repo skeleton

- [x] 1.1 Create top-level directory layout: `docs/`, `templates/workflows/`, `templates/claude/`
- [x] 1.2 Write top-level `README.md` describing remcc in one paragraph and pointing readers at `docs/SETUP.md`

## 2. Workflow template (`templates/workflows/opsx-apply.yml`)

- [x] 2.1 Set triggers: push to `change/**` and `workflow_dispatch` with required `change_name` input
- [x] 2.2 Declare concurrency group keyed on `github.ref` with `cancel-in-progress: true`
- [x] 2.3 Set workflow `permissions:` to `contents: write` and `pull-requests: write` only
- [x] 2.4 Set the `apply` job `timeout-minutes: 180`
- [x] 2.5 Add a fail-fast step that checks `ANTHROPIC_API_KEY` is non-empty and exits with a clear message if missing
- [x] 2.6 Implement change-name resolution: prefer `inputs.change_name`, otherwise strip the `change/` prefix from `github.ref_name`; fail early if `openspec/changes/<name>/` does not exist
- [x] 2.7 Add `actions/setup-node@v4` pinned to Node 20.x (must satisfy OpenSpec's `>= 20.19` floor; e.g. `node-version: '20'` resolves to the current 20.x LTS, which already meets the floor)
- [x] 2.8 Add `pnpm/action-setup@v4` to make `pnpm` available on the runner (target repo is a pnpm workspace; see D11)
- [x] 2.9 Install Claude Code and the OpenSpec CLI globally: `npm install -g @anthropic-ai/claude-code @fission-ai/openspec@latest`
- [x] 2.10 Run `pnpm install --frozen-lockfile` in the checkout so workspace deps are available to any task the agent executes (apply skill does not run install itself)
- [x] 2.11 Configure git identity as `github-actions[bot]` for any commit the workflow itself creates
- [x] 2.12 Invoke `claude --dangerously-skip-permissions -p "/opsx:apply <name>"` with `continue-on-error: true`, capturing stdout/stderr to `apply.log` and the exit code to a step output
- [x] 2.13 Invoke `openspec validate <name>` with `continue-on-error: true`, capturing stdout/stderr to `validate.log` and the exit code to a step output
- [x] 2.14 Stage all working-tree changes (apply skill leaves them unstaged — the workflow's commit is load-bearing); create a commit only if `git diff --cached --quiet` reports diffs; do not create empty commits
- [x] 2.15 Push the branch when local is ahead of `origin` (skip otherwise)
- [x] 2.16 If a PR for the branch does not exist, create one; otherwise add a comment to the existing PR; pass `--draft` to creation when either captured exit code is non-zero
- [x] 2.17 Upload `apply.log` and `validate.log` as artifact `agent-logs-<change>` with `retention-days: 14` and `if: always()`

## 3. Claude settings template (`templates/claude/settings.json`)

- [x] 3.1 Author a minimal `settings.json` with runner-safe defaults (no permissive allowlists that would persist into a developer's local environment)
- [x] 3.2 Document the merge expectation in `docs/SETUP.md` — what to do when the target repo already has a `.claude/settings.json`

## 4. GitHub bootstrap script (`templates/gh-bootstrap.sh`)

- [x] 4.1 Verify `gh auth status` and resolve the target repo from the current git context; print a clear error and exit non-zero if run outside a git repo or without `gh` auth
- [x] 4.2 Configure branch protection on `main` (PR required, no direct push, no force push) via `gh api`, idempotently
- [x] 4.3 Configure a repository push ruleset restricting `GITHUB_TOKEN`-actor pushes to `change/**` branches and blocking path edits under `.github/**`, idempotently
- [x] 4.4 Enable secret scanning and secret push protection on the repository via `gh api`, idempotently
- [x] 4.5 Prompt for `ANTHROPIC_API_KEY` with input hidden (or read from the environment) and upload it as repo secret `ANTHROPIC_API_KEY` without echoing the value
- [x] 4.6 Add an idempotency smoke test inside the script: run the same `gh api` calls a second time at the end and assert no diff in the resulting configuration
- [x] 4.7 Document a removal counterpart (script section or separate `gh-uninstall.sh`) that reverts the configuration changes

## 5. Documentation

- [x] 5.1 Write `docs/SETUP.md`: prerequisites checklist with verification commands (including a pnpm-lock.yaml check and an explicit "v1 supports pnpm-managed repos only" note), copy-paste adoption steps, bootstrap script invocation, ANTHROPIC_API_KEY handling, and the smoke-test procedure
- [x] 5.2 Write `docs/SECURITY.md`: enumerate the two-layer safety model, list each control with what it stops, and document the load-bearing nature of the `.github/**` push restriction
- [x] 5.3 Write `docs/COSTS.md`: how to set Anthropic admin console budget caps, what to expect from GitHub Actions runner minutes, and how to read the artifact logs to reason about cost
- [x] 5.4 Add a "Removing remcc" section to `docs/SETUP.md` covering workflow file deletion, ruleset removal, and secret deletion

## 6. Dogfood on actr

- [x] 6.1 Adopt remcc into `~/ws/prv/actr` by following `docs/SETUP.md` verbatim; record every deviation or missing step encountered, and fix the docs before continuing
- [x] 6.2 Run `gh-bootstrap.sh` against actr's GitHub repo; verify branch protection, push ruleset, secret scanning, and `ANTHROPIC_API_KEY` are all in place
- [x] 6.3 Push a trivial `change/test-apply` branch on actr and observe: workflow trigger, Claude Code run to completion, `openspec validate` pass, PR creation — without manual intervention
- [x] 6.4 Exercise the negative paths on actr: attempt `git push origin main` from local, observe rejection; modify the workflow to attempt a write under `.github/**` from a `change/**` branch, observe ruleset rejection; revert the test workflow afterward
- [x] 6.5 Resolve the remaining open question from `design.md` based on dogfood findings (whether GitHub push rulesets can pin path restrictions to a specific actor) and capture any newly surfaced unknowns; update `design.md` and the specs in this change accordingly
- [x] 6.6 Update `docs/SETUP.md`, `docs/SECURITY.md`, and `docs/COSTS.md` to reflect anything learned during dogfood; close the change only after a fresh read-through of SETUP.md still describes a workable adoption path
