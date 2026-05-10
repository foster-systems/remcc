## 1. Confirm Claude Code thinking-budget flag

- [x] 1.1 Determine the current Claude Code CLI flag that controls thinking budget by reading `claude --help` (or the latest Claude Code docs) for the version pinned by the workflow's `npm install -g @anthropic-ai/claude-code` step
- [x] 1.2 Record the flag name and the concrete numeric values (or named levels) chosen for `low`, `medium`, `high` in `design.md` under D3, replacing the open question; if no thinking-budget flag exists in the installed CLI, document the fallback (model-only override) and update `apply-workflow` spec accordingly before continuing

## 2. Workflow template (`templates/workflows/opsx-apply.yml`)

- [x] 2.1 Add `model` and `effort` inputs to the `workflow_dispatch` block (both optional, type `string`, with helpful descriptions)
- [x] 2.2 Add a "Resolve apply config" step before the apply step that computes `model` and `effort` independently using the precedence: non-empty `inputs.*` > head commit trailer (`Opsx-Model:` / `Opsx-Effort:`) > `vars.OPSX_APPLY_*` > baked-in defaults (`sonnet`, `high`)
- [x] 2.3 Parse commit trailers using `git interpret-trailers --parse` against the head commit message rather than ad-hoc grep/sed; extract values for `Opsx-Model` and `Opsx-Effort` case-insensitively per `git-interpret-trailers` defaults
- [x] 2.4 Emit `model` and `effort` as step outputs from the resolution step and reuse them in subsequent steps
- [x] 2.5 Validate the resolved `effort` against the enum `{low, medium, high}`; if invalid, log an error naming the value and the source (dispatch input / commit trailer / repository variable / baked default) and exit non-zero before invoking Claude Code
- [x] 2.6 Update the apply invocation in the "Run /opsx:apply" step to pass `--model "${MODEL}"` and the thinking-budget flag derived from `${EFFORT}` via a small `case` block mapping enum to flag arguments
- [x] 2.7 Echo the resolved `model` and `effort` (but never the API key) at the start of `apply.log` for log-based auditability
- [x] 2.8 Extend the PR body and PR-comment blocks in the "Open or update PR" step to include `model:` and `effort:` lines next to the existing exit-code lines

## 3. GitHub bootstrap script (`templates/gh-bootstrap.sh`)

- [x] 3.1 Add prompts (with environment-variable overrides `OPSX_APPLY_MODEL` and `OPSX_APPLY_EFFORT`) that accept empty input as "leave unset"
- [x] 3.2 For each non-empty value, call `gh variable set OPSX_APPLY_MODEL --body "<value>"` (and the equivalent for effort), idempotently — re-running with the same value produces no diff and exits zero
- [x] 3.3 For empty input, do not write the variable; print a one-line note that the workflow's baked-in default for that knob will apply
- [x] 3.4 Validate any non-empty `OPSX_APPLY_EFFORT` value against `{low, medium, high}` in the bootstrap script and refuse to write an out-of-enum value, mirroring the workflow's runtime validation
- [x] 3.5 Update the script's existing idempotency smoke test (or add a small one) so the second invocation confirms `gh variable list` output is unchanged for both variables

## 4. Documentation

- [x] 4.1 Add a "Configuring the apply model" section to `docs/SETUP.md` covering: the two repository variables, their baked-in defaults, the override precedence (`workflow_dispatch` input > commit trailer > variable > default), the exact trailer syntax with an example commit message, and a worked manual-dispatch example
- [x] 4.2 Update `docs/COSTS.md` with guidance on choosing model and effort for cost/quality trade-offs and note that the resolved values appear in the PR body for after-the-fact auditing
- [x] 4.3 Note in SETUP.md that repository variables are not exposed to forked-PR runs and that the trigger surface (push to `change/**` and `workflow_dispatch`) makes this a non-issue in practice

## 5. Dogfood on actr

- [x] 5.1 Re-copy the updated workflow into `~/ws/prv/actr/.github/workflows/opsx-apply.yml` and re-run `gh-bootstrap.sh` to install the new variables (try both setting and skipping each knob)
- [ ] 5.2 Trigger a push-based run with no overrides and verify the PR body reports `sonnet` / `high` (or whatever the resolved values are) and the run completes
- [ ] 5.3 Trigger a push-based run with `Opsx-Model: opus` in the commit trailer and verify the PR-comment reports the override; trigger another with `Opsx-Effort: low` and verify
- [ ] 5.4 Trigger a manual `workflow_dispatch` with explicit `model` and `effort` inputs and verify the dispatch values win over both the trailer and the variables
- [ ] 5.5 Submit an intentionally invalid `Opsx-Effort: extreme` and verify the workflow exits with a clear error before invoking Claude Code
- [ ] 5.6 Update `docs/SETUP.md` / `docs/COSTS.md` with anything learned during dogfood and re-read both before closing the change
