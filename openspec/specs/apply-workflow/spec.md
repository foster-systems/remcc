# apply-workflow Specification

## Purpose

Defines the behaviour of the GitHub Actions workflow that runs
`/opsx:apply` unattended on an ephemeral runner, on push to a
`change/**` branch or via `workflow_dispatch`. The contract covers:
the trigger surface, the runner-side sandbox (permissive inside, scoped
GITHUB_TOKEN outside), the runtime preparation steps, the apply +
validate sequence, the commit/push semantics, the PR open/update flow
including draft-on-failure, concurrency, log-artifact upload, run
timeout, and ANTHROPIC_API_KEY plumbing. It does not cover the
GitHub-side configuration that bounds the bot — see `repo-adoption`.

## Requirements

### Requirement: Trigger on change branch push

The workflow SHALL be triggered automatically by a push event on any
branch matching the pattern `change/**`.

#### Scenario: Push to a change branch starts the workflow

- **WHEN** a commit is pushed to a branch named `change/<name>`
- **THEN** the workflow runs with the change name resolved to `<name>`

#### Scenario: Push to a non-change branch does not start the workflow

- **WHEN** a commit is pushed to a branch not matching `change/**`
- **THEN** the workflow does not run

### Requirement: Manual dispatch with explicit change name

The workflow SHALL support `workflow_dispatch` invocation with a
required `change_name` input identifying the change to apply.

#### Scenario: Operator triggers a manual run

- **WHEN** the operator invokes `workflow_dispatch` with
  `change_name=foo`
- **THEN** the workflow runs against the change named `foo`,
  irrespective of the branch the dispatch was issued from

### Requirement: Change name resolution

The workflow SHALL resolve the change name from the
`workflow_dispatch` input when present, otherwise from the branch ref
by stripping the `change/` prefix. The workflow SHALL fail early if
the resolved change name does not correspond to an existing directory
under `openspec/changes/`.

#### Scenario: Resolution from branch ref

- **WHEN** the workflow is triggered by a push to `change/foo`
- **AND** no `workflow_dispatch` input is present
- **THEN** the resolved change name is `foo`

#### Scenario: Resolution from dispatch input takes precedence

- **WHEN** the workflow is triggered by `workflow_dispatch` with
  `change_name=bar` while running on branch `change/foo`
- **THEN** the resolved change name is `bar`

#### Scenario: Missing change directory fails the workflow early

- **WHEN** the resolved change name does not correspond to a
  directory at `openspec/changes/<name>/`
- **THEN** the workflow exits non-zero before invoking Claude Code

### Requirement: Minimal token scope

The workflow's `permissions:` block SHALL grant only `contents: write`
and `pull-requests: write` to the auto-provisioned `GITHUB_TOKEN`. No
other scopes (in particular: `actions`, `secrets`, `packages`,
`deployments`, `workflows`, admin) SHALL be granted.

#### Scenario: GITHUB_TOKEN cannot modify Actions secrets

- **WHEN** the agent attempts to call the GitHub API to read or
  modify repository secrets using the workflow's `GITHUB_TOKEN`
- **THEN** the call fails due to missing permissions

### Requirement: Permissive sandbox inside the runner

The workflow SHALL invoke Claude Code with
`--dangerously-skip-permissions`, granting it full shell access
inside the runner. The workflow SHALL NOT attempt to apply tool
restrictions inside the runner.

#### Scenario: Agent runs without confirmation prompts

- **WHEN** the workflow invokes `/opsx:apply`
- **THEN** Claude Code does not pause for any tool-use confirmation
  during the run

### Requirement: Workflow prepares runtime before apply

The workflow SHALL prepare the runner before invoking the apply step
by (a) installing a Node.js version that satisfies the OpenSpec
CLI's minimum requirement (`>= 20.19` at the time of this change),
(b) installing the Claude Code CLI and the OpenSpec CLI globally so
that both `claude` and `openspec` are resolvable on `PATH`, and
(c) installing the target repository's workspace dependencies so
that scripts the agent may execute during apply can resolve their
imports.

#### Scenario: Apply step finds the agent and OpenSpec CLIs on PATH

- **WHEN** the apply step starts
- **THEN** invoking `claude --version` and `openspec --version`
  both succeed with non-zero output

#### Scenario: Workspace dependencies are installed before apply

- **WHEN** the apply step starts
- **THEN** the target repository's workspace dependencies are
  installed (e.g. `node_modules` populated from a deterministic
  install command), so scripts the agent runs during apply can
  resolve their dependencies

#### Scenario: Workflow does not gate on type-check or test

- **WHEN** the workflow runs end to end
- **THEN** no step invokes a project-level type-check, lint, or
  test runner as a gate; only `openspec validate` is run as a
  structural gate (see "Validate change after apply")

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

### Requirement: Validate change after apply

The workflow SHALL run `openspec validate <change>` after the apply
step. The exit code of the validate step SHALL be captured.

#### Scenario: Validate runs regardless of apply outcome

- **WHEN** the apply step has completed (with any exit code)
- **THEN** the validate step runs and its exit code is recorded

### Requirement: Commit any uncommitted agent output

The workflow SHALL stage all working-tree changes and create a single
commit if any uncommitted changes exist after the apply step. If the
working tree is clean after apply, the workflow SHALL NOT create an
empty commit.

#### Scenario: Agent left changes unstaged

- **WHEN** apply completes with modified files in the working tree
- **AND** the changes are not yet committed
- **THEN** the workflow creates a commit containing those changes
  with author `github-actions[bot]`

#### Scenario: Agent already committed everything

- **WHEN** apply completes with a clean working tree
- **THEN** the workflow does not create an additional commit

### Requirement: Push the change branch

The workflow SHALL push commits to the change branch using
`GITHUB_TOKEN` whenever the local branch is ahead of `origin`. The
workflow SHALL NOT push when no commits are ahead of `origin`.

#### Scenario: New commits are pushed to the branch

- **WHEN** the local branch is ahead of its remote tracking branch
- **THEN** the workflow pushes the new commits to `origin`

### Requirement: Open or update the change PR

If the change branch has commits ahead of `main`, the workflow SHALL
ensure a PR exists from the change branch to `main`. If no PR exists,
the workflow SHALL create one. If a PR already exists, the workflow
SHALL post a comment summarising the run.

#### Scenario: First successful run opens a PR

- **WHEN** the workflow completes successfully and no PR exists
  for the change branch
- **THEN** the workflow creates a PR with the change name in the
  title and the apply/validate exit codes in the body

#### Scenario: Subsequent run on existing PR adds a comment

- **WHEN** the workflow completes and a PR already exists for the
  change branch
- **THEN** the workflow adds a comment to the PR with the latest
  apply/validate exit codes

### Requirement: Surface failures as draft PR

Any PR the workflow creates SHALL be opened as a draft whenever
either the apply or validate step exited non-zero. The workflow
SHALL NOT silently switch existing PRs between draft and ready.

#### Scenario: Apply failure produces a draft PR

- **WHEN** apply exited non-zero and no PR exists yet
- **THEN** the workflow creates the PR with `--draft`

#### Scenario: Validate failure produces a draft PR

- **WHEN** apply exited zero but validate exited non-zero, and no
  PR exists yet
- **THEN** the workflow creates the PR with `--draft`

### Requirement: Concurrency cancels in-flight runs

The workflow SHALL declare a concurrency group keyed on the branch
ref with `cancel-in-progress: true`, so that pushing a new commit
to a change branch cancels any in-flight run for the same branch.

#### Scenario: New push cancels prior run

- **WHEN** a workflow run is in progress for branch `change/foo`
- **AND** a new commit is pushed to `change/foo`
- **THEN** the prior run is cancelled and a new run begins

### Requirement: Upload apply and validate logs

The workflow SHALL upload `apply.log` and `validate.log` as a
workflow artifact named `agent-logs-<change>` with a retention of
14 days, regardless of whether earlier steps succeeded or failed.

#### Scenario: Logs are retrievable after a failed run

- **WHEN** the workflow run has completed (success or failure)
- **THEN** an artifact `agent-logs-<change>` is available for
  download from the run summary

### Requirement: Bounded run duration

The workflow's `apply` job SHALL declare `timeout-minutes: 180` as
a hard ceiling on wall-clock duration.

#### Scenario: Runaway apply is killed by timeout

- **WHEN** the apply job has been running for 180 minutes
- **THEN** the runner cancels the job

### Requirement: ANTHROPIC_API_KEY supplied via secret

The workflow SHALL read `ANTHROPIC_API_KEY` from
`secrets.ANTHROPIC_API_KEY` and expose it to the apply step via
environment variable. The workflow SHALL NOT echo or log the key.

#### Scenario: Missing secret fails fast

- **WHEN** `ANTHROPIC_API_KEY` is not set in repository secrets
- **THEN** the workflow exits non-zero before invoking Claude Code,
  with a message identifying the missing secret
