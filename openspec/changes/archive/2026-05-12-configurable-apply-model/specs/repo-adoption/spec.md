## ADDED Requirements

### Requirement: Bootstrap installs OPSX_APPLY_MODEL and OPSX_APPLY_EFFORT variables

`gh-bootstrap.sh` SHALL prompt the operator for `OPSX_APPLY_MODEL`
and `OPSX_APPLY_EFFORT` values (or accept them via environment
variables of the same name) and write them as repository variables
via `gh variable set`. The prompts SHALL accept empty input; an
empty value SHALL NOT write a variable, allowing the workflow's
baked-in default for that knob to take effect. Running the script
twice with the same inputs SHALL be a no-op on the resulting
repository configuration.

#### Scenario: Operator supplies values interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without the
  `OPSX_APPLY_MODEL` or `OPSX_APPLY_EFFORT` environment variables
  set
- **AND** answers the prompts with `opus` and `high`
- **THEN** the script sets `OPSX_APPLY_MODEL=opus` and
  `OPSX_APPLY_EFFORT=high` as repository variables

#### Scenario: Operator skips a knob by leaving the prompt empty

- **WHEN** the operator runs `gh-bootstrap.sh` and answers the
  `OPSX_APPLY_MODEL` prompt with empty input
- **THEN** the script does not write the `OPSX_APPLY_MODEL`
  repository variable, leaving the workflow's baked-in default
  in effect

#### Scenario: Re-running the script with the same answers is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` twice in succession
  with the same answers for the model/effort prompts
- **THEN** the second invocation produces no diffs in the
  repository's variables and exits zero

### Requirement: SETUP.md documents model and effort configuration

`docs/SETUP.md` SHALL document the `OPSX_APPLY_MODEL` and
`OPSX_APPLY_EFFORT` repository variables, the workflow's baked-in
defaults, and the override precedence (`workflow_dispatch` input >
commit trailer > repository variable > baked-in default). The
section SHALL include the exact commit-trailer syntax
(`Opsx-Model: <value>`, `Opsx-Effort: <value>`) and a worked
example of overriding from a manual dispatch.

#### Scenario: Adopter learns how to set defaults from SETUP.md

- **WHEN** an operator follows `docs/SETUP.md` end to end
- **THEN** they encounter a section explaining the two
  configuration variables, their baked-in defaults, and how to
  override per run via dispatch or commit trailer

### Requirement: COSTS.md covers model and effort cost guidance

`docs/COSTS.md` SHALL include guidance on choosing `model` and
`effort` for cost/quality trade-offs, and SHALL note that the
resolved values appear in the PR body so the operator can audit
run cost decisions after the fact.

#### Scenario: Adopter consults COSTS.md before raising defaults

- **WHEN** an operator opens `docs/COSTS.md` before changing
  `OPSX_APPLY_MODEL` to a more expensive model
- **THEN** they find guidance on the cost implications of model
  and effort choices, plus a pointer to the PR body as the source
  of truth for what each run actually used
