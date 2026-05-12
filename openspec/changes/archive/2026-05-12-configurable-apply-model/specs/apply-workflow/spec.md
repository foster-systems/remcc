## ADDED Requirements

### Requirement: Default model and effort sourced from repository variables

The workflow SHALL read its default Claude model from the repository
variable `OPSX_APPLY_MODEL` and its default effort from the
repository variable `OPSX_APPLY_EFFORT`. When either variable is
unset or empty, the workflow SHALL fall back to baked-in defaults
of `sonnet` for model and `high` for effort.

#### Scenario: Both variables set

- **WHEN** the workflow runs with `vars.OPSX_APPLY_MODEL=opus` and
  `vars.OPSX_APPLY_EFFORT=medium`
- **AND** no overrides are present (no non-empty dispatch input,
  no commit trailer)
- **THEN** the resolved model is `opus` and the resolved effort
  is `medium`

#### Scenario: Both variables unset

- **WHEN** neither `vars.OPSX_APPLY_MODEL` nor `vars.OPSX_APPLY_EFFORT`
  is set on the repository
- **AND** no overrides are present
- **THEN** the resolved model is `sonnet` and the resolved effort
  is `high`

#### Scenario: One variable set, the other unset

- **WHEN** `vars.OPSX_APPLY_MODEL=opus` and `vars.OPSX_APPLY_EFFORT`
  is unset
- **AND** no overrides are present
- **THEN** the resolved model is `opus` and the resolved effort
  is the baked-in default `high`

### Requirement: Manual dispatch inputs override defaults

The workflow's `workflow_dispatch` SHALL accept optional `model`
and `effort` inputs. When the workflow is triggered by
`workflow_dispatch` and the corresponding input value is non-empty,
that value SHALL override the variable-sourced or baked-in default
for that knob, independently of the other knob.

#### Scenario: Dispatch overrides only the model

- **WHEN** the operator dispatches with `model=opus` and `effort`
  left empty
- **AND** the repo variables are unset
- **THEN** the resolved model is `opus` and the resolved effort is
  the baked-in default `high`

#### Scenario: Dispatch overrides both knobs

- **WHEN** the operator dispatches with `model=opus` and
  `effort=low`
- **THEN** the resolved model is `opus` and the resolved effort
  is `low`, regardless of any repo-variable values

#### Scenario: Empty dispatch input is not an override

- **WHEN** the operator dispatches with both inputs left empty
- **AND** `vars.OPSX_APPLY_MODEL=opus` is set
- **THEN** the resolved model is `opus` (the variable wins; the
  empty input is not treated as an explicit override)

### Requirement: Commit trailer overrides defaults on push

The workflow SHALL parse the head commit message for trailers
`Opsx-Model:` and `Opsx-Effort:`. When a trailer is present, its
value SHALL override the variable-sourced or baked-in default for
that knob. Trailers SHALL be parsed by a strict trailer parser
(such as `git interpret-trailers`) rather than ad-hoc regex.

#### Scenario: Trailer overrides only the model

- **WHEN** the head commit message contains a trailer
  `Opsx-Model: opus`
- **AND** the workflow was triggered by push
- **AND** the repo variables are unset
- **THEN** the resolved model is `opus` and the resolved effort
  is the baked-in default `high`

#### Scenario: Trailer overrides both knobs

- **WHEN** the head commit message contains both
  `Opsx-Model: opus` and `Opsx-Effort: low` trailers
- **THEN** the resolved model is `opus` and the resolved effort
  is `low`

#### Scenario: No trailer means no override

- **WHEN** the head commit message contains no `Opsx-Model:` or
  `Opsx-Effort:` trailer
- **AND** the repo variables are set
- **THEN** the resolved values come from the repo variables

### Requirement: Override precedence

When multiple override sources are present, the workflow SHALL
resolve each knob (`model`, `effort`) independently using this
precedence, highest to lowest: non-empty `workflow_dispatch` input,
commit trailer on the head commit, repository variable, baked-in
default.

#### Scenario: Dispatch input beats commit trailer

- **WHEN** the workflow is dispatched with `model=opus`
- **AND** the head commit message contains `Opsx-Model: haiku`
- **THEN** the resolved model is `opus`

#### Scenario: Commit trailer beats repository variable

- **WHEN** the workflow is triggered by push and no
  `workflow_dispatch` is in flight
- **AND** the head commit message contains `Opsx-Model: opus`
- **AND** `vars.OPSX_APPLY_MODEL=haiku` is set
- **THEN** the resolved model is `opus`

#### Scenario: Repository variable beats baked-in default

- **WHEN** no dispatch input or commit trailer overrides `model`
- **AND** `vars.OPSX_APPLY_MODEL=opus` is set
- **THEN** the resolved model is `opus`

### Requirement: Effort enum validation

The workflow SHALL accept only `low`, `medium`, or `high` as
resolved `effort` values. If the resolved value (from any source)
is anything else, the workflow SHALL exit non-zero before invoking
Claude Code with a message identifying the invalid value and its
source.

#### Scenario: Unknown effort fails fast

- **WHEN** the resolved effort value is `extreme`
- **THEN** the workflow exits non-zero before invoking Claude
  Code, with a message naming the invalid value and the source it
  came from (dispatch input, commit trailer, repository variable,
  or baked-in default)

#### Scenario: Valid effort proceeds

- **WHEN** the resolved effort value is `low`, `medium`, or `high`
- **THEN** the workflow proceeds to invoke Claude Code

### Requirement: Effort maps to Claude Code thinking budget

The workflow SHALL translate the resolved effort enum value into
the Claude Code CLI flag that controls thinking budget, passing
the result to the `claude` invocation. `low` SHALL correspond to a
smaller thinking budget than `medium`, which SHALL correspond to a
smaller budget than `high`. The exact flag name and budget values
SHALL be those supported by the installed Claude Code CLI version.

#### Scenario: High effort produces a larger budget than low effort

- **WHEN** two runs are compared, identical except that one
  resolves to `effort=high` and the other to `effort=low`
- **THEN** the high-effort run is invoked with a thinking-budget
  value strictly greater than the low-effort run

### Requirement: Resolved values reported in PR

The workflow SHALL include the resolved `model` and `effort`
values in the body of any PR it creates and in any comment it
adds to an existing PR for the change branch.

#### Scenario: First successful run reports resolved values

- **WHEN** the workflow opens a new PR for the change branch
- **THEN** the PR body contains the resolved `model` and the
  resolved `effort` values for that run

#### Scenario: Rerun comment reports resolved values

- **WHEN** the workflow comments on an existing PR for the change
  branch
- **THEN** the comment contains the resolved `model` and `effort`
  values for that run

## MODIFIED Requirements

### Requirement: Run /opsx:apply for the resolved change

The workflow SHALL invoke `claude -p "/opsx:apply <name>"` for the
resolved change name in non-interactive mode, passing `--model`
with the resolved model value and the Claude Code thinking-budget
flag corresponding to the resolved effort value. The exit code of
the Claude invocation SHALL be captured but SHALL NOT cause the
workflow to fail immediately.

#### Scenario: Apply step continues despite non-zero exit

- **WHEN** Claude Code exits non-zero from the apply invocation
- **THEN** the workflow continues to subsequent steps and records
  the exit code for later use in the PR body

#### Scenario: Apply invocation carries resolved model and effort

- **WHEN** the resolved model is `opus` and the resolved effort
  is `medium`
- **THEN** the `claude` invocation includes `--model opus` and the
  thinking-budget flag corresponding to `medium`
