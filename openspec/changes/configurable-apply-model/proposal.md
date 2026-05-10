## Why

Today the apply workflow hardcodes whatever model and effort Claude
Code defaults to. Different changes warrant different cost/quality
trade-offs: a routine refactor should not pay Opus prices, and a
gnarly architectural change should not be capped at Haiku. The
operator needs a default they pick once per repo *and* a per-run
override they can apply without editing the workflow file, both
from a manual dispatch and from a normal push-triggered run.

## What Changes

- Read `model` and `effort` for the apply step from GitHub
  repository variables (`vars.OPSX_APPLY_MODEL`,
  `vars.OPSX_APPLY_EFFORT`), with a hardcoded fallback of
  `sonnet` + `high` if the variables are unset.
- Add `model` and `effort` inputs to `workflow_dispatch` that, when
  non-empty, override the variable-sourced defaults for that run.
- On push triggers, parse the head commit message for
  `Opsx-Model:` and `Opsx-Effort:` trailers; either trailer, if
  present, overrides the corresponding default for that run.
- Translate the resolved `effort` value (`low` / `medium` / `high`)
  into the appropriate Claude Code thinking-budget CLI flag; pass
  the resolved `model` via `--model`.
- Extend `gh-bootstrap.sh` so the operator is prompted (or accepts
  via env var) for `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` and the
  script writes them as repository variables idempotently.
- Document the configuration surface and override precedence in
  `docs/SETUP.md` and `docs/COSTS.md`. Record the resolved model
  and effort in the PR body alongside the existing exit codes.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `apply-workflow`: adds requirements for default resolution from
  repository variables, override precedence (dispatch input >
  commit trailer > vars > baked-in default), per-run reporting,
  and translation of `effort` into Claude Code's thinking-budget
  flag. The existing "Run /opsx:apply for the resolved change"
  requirement is amended to pass `--model` and the effort flag.
- `repo-adoption`: adds requirements for `gh-bootstrap.sh` to
  install `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` as repository
  variables and for `docs/SETUP.md` / `docs/COSTS.md` to document
  the knobs and override precedence.

## Impact

- `templates/workflows/opsx-apply.yml`: new resolution step, new
  dispatch inputs, change to the apply invocation, PR body update.
- `templates/gh-bootstrap.sh`: new step that writes repo variables.
- `docs/SETUP.md`: new section on model/effort defaults and
  overrides; bootstrap output reflects the new prompts.
- `docs/COSTS.md`: model/effort selection guidance and the per-run
  override surfaces.
- No code changes in adopter repos beyond re-copying the workflow.
- Operators currently relying on the implicit default will see
  `sonnet` + `high` applied explicitly — a behavior change only if
  Claude Code's silent default differed.
