## 1. Workflow template — trigger surface

- [x] 1.1 Remove the entire `workflow_dispatch:` block from `templates/workflows/opsx-apply.yml`, including its `change_name`, `model`, and `effort` inputs
- [x] 1.2 Replace the existing job-level `if:` condition (the bot-self-loop guard) with `if: startsWith(github.event.head_commit.message, '@change-apply')` so that the job is skipped before any runner is provisioned whenever the head commit subject does not begin with the magic word
- [x] 1.3 In the "Resolve change name" step, remove the `INPUT_CHANGE_NAME` branch and the `workflow_dispatch` case; the step now reads only from `github.ref_name` (or the equivalent), strips the `change/` prefix, and exits non-zero if the resolved name does not correspond to an existing directory under `openspec/changes/`
- [x] 1.4 In the "Resolve apply config" step, remove the `INPUT_MODEL` and `INPUT_EFFORT` branches; the resolution precedence becomes commit trailer > repository variable > baked-in default (no dispatch input level)
- [x] 1.5 Verify the bot's commit-message template in the "Stage and commit agent output" step continues to produce a subject of the form `/opsx:apply <name>` (so it does not start with `@change-apply`); add a defensive `grep` at the end of that step that fails the run if the generated commit subject starts with `@change-apply`, preventing a future template change from re-introducing the self-loop
- [x] 1.6 Run `actionlint` (or equivalent YAML linter) on the updated workflow to confirm the `if:` expression is syntactically valid and the dispatch removal did not leave orphaned `${{ inputs.* }}` references elsewhere in the file
- [x] 1.7 Add a case-sensitive shell guard step right after `Verify WORKFLOW_PAT` that re-checks the head commit subject against `@change-apply` byte-exactly (GHA's `startsWith()` is case-insensitive, so `@Change-Apply: ...` would otherwise slip through the job-level `if:`); on mismatch, the step calls `gh run cancel` and exits
- [x] 1.8 Partition the `concurrency:` group key by trigger-vs-noop using a ternary on `startsWith(github.event.head_commit.message, '@change-apply')`, so the bot's own output push and WIP pushes land in a separate `noop` slot and don't cancel an in-flight apply via `cancel-in-progress: true`

## 2. Workflow template — sanity sweep

- [x] 2.1 Search the workflow for any remaining references to `inputs.change_name`, `inputs.model`, `inputs.effort`, `workflow_dispatch`, or the `INPUT_*` env vars that fed them; remove or rewrite each
- [x] 2.2 Confirm the `concurrency:` group still keys on `github.ref` and that the cancel-in-progress behaviour still works for the push-only trigger model
- [x] 2.3 Confirm the `permissions:`, `timeout-minutes:`, `Verify ANTHROPIC_API_KEY is set`, and `Verify WORKFLOW_PAT is set` steps are unchanged in behaviour (they should be; double-check)

## 3. Documentation (`docs/SETUP.md`)

- [x] 3.1 Rewrite the "How to trigger a run" section: the canonical trigger is now a commit whose subject starts with the magic word `@change-apply` pushed to a `change/**` branch; remove the manual-dispatch walkthrough
- [x] 3.2 Document the canonical idiom for a no-op trigger commit: `git commit --allow-empty -m "@change-apply: first pass"` followed by `git push`; show two or three acceptable subject shapes (`@change-apply: foo`, `@change-apply(foo)`, `@change-apply foo`, bare `@change-apply`) and clarify that the workflow doesn't parse what comes after the magic word
- [x] 3.3 Add an "Iterating on a change" subsection walking the full loop: push WIP commits → write trigger commit → review PR → push more WIP (free) → write another trigger commit (e.g. `@change-apply: retry with feedback`) → review again
- [x] 3.4 Document how to override `model` and `effort` for a single run via `Opsx-Model:` / `Opsx-Effort:` trailers on the trigger commit; include a copy-pasteable HEREDOC example
- [x] 3.5 Note that pushing a `@change-apply...` commit to a non-`change/**` branch is silently a no-op (the workflow's branch filter still applies) and that the GitHub web UI's file-edit flow can be used to author a trigger commit when terminal access is unavailable
- [x] 3.6 Note that the `@`-prefix makes accidental triggering effectively impossible (natural commit subjects don't start with `@` at position 0) and that the trigger word `@change-apply` pairs intentionally with the `change/<name>` branch convention
- [x] 3.7 Remove any references to `workflow_dispatch`, `gh workflow run opsx-apply.yml`, or "manual dispatch from the GitHub UI" from `docs/SETUP.md`

## 4. Documentation (`docs/COSTS.md`)

- [x] 4.1 Update the cost model section: drafts and WIP collaboration on a `change/**` branch no longer cost anything (the workflow is skipped at the job-level `if:`); only commits whose subject matches the trigger convention spin up a runner
- [x] 4.2 Replace the "retry with a different model" example: previously a `workflow_dispatch` with `model=opus` input, now an `@change-apply: retry with opus` commit with `Opsx-Model: opus` trailer

## 5. Dogfood on the first adopter

- [x] 5.1 Re-copy the updated workflow into the adopter's `.github/workflows/opsx-apply.yml` and merge to main
- [x] 5.2 Push a fresh `change/dogfood-opt-in` branch with a small proposal and three WIP commits (no trigger subject); confirm via the Actions UI that no apply runs have started
- [x] 5.3 Push a fourth commit with subject `@change-apply: first pass`; confirm the workflow runs, the agent commits its output (subject `/opsx:apply dogfood-opt-in`), and the bot's push does not re-trigger the workflow
- [x] 5.4 Push two more WIP commits extending tasks.md; confirm no apply runs start
- [x] 5.5 Push an empty trigger commit `git commit --allow-empty -m "@change-apply(retry after task extension)"` (parens shape this time); confirm the workflow runs again against the current branch state
- [x] 5.6 Push a trigger commit carrying both an `Opsx-Model: opus` and an `Opsx-Effort: low` trailer; confirm the PR comment reports `model=opus` and `effort=low` for that run
- [x] 5.7 Attempt near-miss subjects and confirm none trigger: `change-apply: retry` (missing `@`), `@change_apply: retry` (underscore), ` @change-apply: retry` (leading space), `@Change-Apply: retry` (capitalised) — the first three are skipped at the job-level `if:`; the capitalised one is caught by the case-sensitive guard step (run conclusion `failure`, but apply step skipped, no spend)
- [x] 5.8 Confirm bare `@change-apply` (no separator, no description) also triggers — push an empty commit with that exact subject and verify a run starts
- [x] 5.9 Confirm shell-quoting works with both single and double quotes: `git commit --allow-empty -m "@change-apply: foo"` and `git commit --allow-empty -m '@change-apply: foo'` should both succeed in bash and zsh without history-expansion errors
- [x] 5.10 Confirm that previously-working commands no longer apply: `gh workflow run opsx-apply.yml -f change_name=...` should fail with "no workflow_dispatch trigger" or equivalent
- [x] 5.11 Re-read `docs/SETUP.md` and `docs/COSTS.md` end to end after the dogfood walkthrough and tighten any wording that didn't survive contact with reality
