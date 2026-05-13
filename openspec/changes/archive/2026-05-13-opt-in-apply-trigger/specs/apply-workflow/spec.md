## ADDED Requirements

### Requirement: Apply runs only on opt-in trigger commits

The workflow SHALL run the apply job only when the head commit of
the pushed `change/**` ref has a subject (the first line of its
commit message) that starts with the byte sequence `@change-apply`
(case-sensitive, byte-exact, including the leading `@`). The
character that follows the magic word — colon, parenthesis,
space, exclamation mark, newline, or end-of-string — SHALL NOT be
validated; any continuation is treated as the author's free-form
description.

Pushes whose head commit does not match this convention SHALL be
a complete no-op: the job SHALL NOT start, SHALL NOT charge
runner time, SHALL NOT post any PR comment, SHALL NOT upload any
log artifact, and SHALL NOT call any Anthropic or GitHub API
beyond what GitHub Actions itself performs to evaluate the
trigger filter.

The match SHALL be implemented as a job-level `if:` expression
(e.g. `if: startsWith(github.event.head_commit.message,
'@change-apply')`) so that GitHub Actions skips the job before
any runner is provisioned.

The text after the magic word SHALL NOT be parsed by the workflow;
it is human context only.

#### Scenario: Trigger commit with colon-separator runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `@change-apply: first pass`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Trigger commit with parens runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `@change-apply(retry with opus)`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Trigger commit with space-separator runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `@change-apply retry after task 3`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Bare trigger commit runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  exactly `@change-apply`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Non-trigger commit subject is a no-op

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `tweak proposal wording`
- **THEN** the workflow job is skipped before any runner is
  provisioned, no PR comment is posted, no log artifact is
  uploaded, and no Anthropic API call is made

#### Scenario: Trigger token in body but not subject is a no-op

- **WHEN** a commit is pushed to `change/foo` whose subject is
  `wip refactor` and whose body contains the line
  `@change-apply: retry`
- **THEN** the workflow job is skipped (the trigger token only
  counts at the start of the subject line)

#### Scenario: Similar-looking subjects do not trigger an apply

- **WHEN** a commit is pushed to `change/foo` with any of the
  subjects `change-apply: retry` (no `@`),
  `@change_apply: retry` (underscore),
  ` @change-apply: retry` (leading space), or
  `[@change-apply] retry`
- **THEN** the job-level `if:` evaluates false and the workflow
  job is skipped (no runner provisioned, no Anthropic spend)

#### Scenario: Case-variant subjects are blocked at the guard step

- **WHEN** a commit is pushed to `change/foo` with a subject like
  `@Change-Apply: retry` or `@CHANGE-APPLY: retry`
- **THEN** the job-level `if:` lets the run start (GitHub Actions'
  `startsWith()` is case-insensitive), the case-sensitive shell
  guard step fails the run, and all subsequent steps including
  `Run /opsx:apply` are skipped — no Anthropic spend, no PR
  comment, no log artifact written by the agent

#### Scenario: Bot's own commit subject does not trigger

- **WHEN** the workflow's "Stage and commit agent output" step
  creates a commit whose subject is `/opsx:apply foo`
- **AND** that commit is pushed to `change/foo`
- **THEN** the workflow job is skipped (the bot's subject does
  not start with `@change-apply`), implicitly preventing
  self-loops

#### Scenario: Trigger commit on a non-change branch is a no-op

- **WHEN** a commit with subject `@change-apply: retry` is
  pushed to branch `main`
- **THEN** the workflow does not run (the push trigger's
  `change/**` branch filter still applies)

### Requirement: Concurrency group is partitioned by trigger-vs-noop

The workflow's concurrency group key SHALL include a partition
suffix that is `apply` when the head commit subject opts into the
apply trigger and `noop` otherwise, so that `cancel-in-progress:
true` only cancels runs within the `apply` slot. Non-trigger
pushes (the bot's own output push, WIP commits, near-miss
subjects) SHALL NOT cancel an in-flight apply run.

#### Scenario: Bot's output push does not cancel the parent apply

- **WHEN** an apply run on `change/foo` completes its `Push branch`
  step (pushing the bot's `/opsx:apply foo` commit)
- **AND** the resulting push fires a new workflow listener
- **THEN** the new listener's run is placed in the `noop` partition
  of the concurrency group, separate from the parent run's
  `apply` partition
- **AND** the parent run finishes with overall conclusion `success`
  (not `cancelled`)

#### Scenario: WIP push during in-flight apply does not cancel it

- **WHEN** an apply run on `change/foo` is in flight
- **AND** an author pushes a draft commit (subject not starting
  with `@change-apply`) to the same branch
- **THEN** the WIP push's run is placed in the `noop` partition
- **AND** the in-flight apply continues to completion uninterrupted

#### Scenario: Fresh trigger push during in-flight apply cancels it

- **WHEN** an apply run on `change/foo` is in flight
- **AND** an author pushes another commit whose subject starts
  with `@change-apply` to the same branch
- **THEN** both runs share the `apply` partition of the
  concurrency group
- **AND** `cancel-in-progress: true` cancels the in-flight run so
  the new trigger commit applies against the latest branch state

## MODIFIED Requirements

### Requirement: Trigger on change branch push

The workflow SHALL be triggered by a push event on any branch
matching the pattern `change/**`. Whether the job actually runs
apply depends on the head commit subject (see "Apply runs only on
opt-in trigger commits") — the workflow's listener fires on every
push to a `change/**` ref, but the job is gated so that only
opt-in trigger commits cause work.

#### Scenario: Push to a change branch starts the workflow listener

- **WHEN** a commit is pushed to a branch named `change/<name>`
- **THEN** the workflow's listener fires; whether the job runs
  depends on the head commit subject convention

#### Scenario: Push to a non-change branch does not start the workflow

- **WHEN** a commit is pushed to a branch not matching `change/**`
- **THEN** the workflow does not run, regardless of the commit
  subject

### Requirement: Change name resolution

The workflow SHALL resolve the change name from the pushed branch
ref by stripping the `change/` prefix. The workflow SHALL fail
early if the resolved change name does not correspond to an
existing directory under `openspec/changes/`.

#### Scenario: Resolution from branch ref

- **WHEN** the workflow runs on a push to `change/foo`
- **THEN** the resolved change name is `foo`

#### Scenario: Missing change directory fails the workflow early

- **WHEN** the resolved change name does not correspond to a
  directory at `openspec/changes/<name>/`
- **THEN** the workflow exits non-zero before invoking Claude Code

### Requirement: Override precedence

The workflow SHALL resolve each of `model` and `effort`
independently using this precedence, highest to lowest: commit
trailer on the head commit, repository variable, baked-in default.

#### Scenario: Commit trailer beats repository variable

- **WHEN** the head commit message contains `Opsx-Model: opus`
- **AND** `vars.OPSX_APPLY_MODEL=haiku` is set
- **THEN** the resolved model is `opus`

#### Scenario: Repository variable beats baked-in default

- **WHEN** no commit trailer overrides `model`
- **AND** `vars.OPSX_APPLY_MODEL=opus` is set
- **THEN** the resolved model is `opus`

#### Scenario: Baked-in default applies when nothing else does

- **WHEN** no commit trailer overrides `model` or `effort`
- **AND** neither `vars.OPSX_APPLY_MODEL` nor
  `vars.OPSX_APPLY_EFFORT` is set
- **THEN** the resolved model is `sonnet` and the resolved
  effort is `high`

## REMOVED Requirements

### Requirement: Manual dispatch with explicit change name

**Reason**: `workflow_dispatch` is replaced by the opt-in
trigger commit convention. Authors trigger a run by pushing a
commit whose subject starts with `@change-apply` rather than by
invoking the workflow manually from the GitHub UI. Keeping
dispatch as a parallel trigger would duplicate the per-run
override surface (`model`, `effort` inputs vs. commit trailers)
and split the test/spec surface in two.

**Migration**: To trigger a one-off apply run on a branch, push a
commit whose subject starts with `@change-apply`. The canonical
idiom is `git commit --allow-empty -m "@change-apply: <reason>"`
followed by `git push`. To trigger from outside the terminal, an
operator can author the same commit via the GitHub web UI's
file-edit flow (the workflow does not care how the commit is
authored, only what its subject says).

### Requirement: Manual dispatch inputs override defaults

**Reason**: With `workflow_dispatch` removed, there are no
dispatch inputs. The corresponding override capability moves to
the commit trailers on the opt-in trigger commit, which already
supported `Opsx-Model:` and `Opsx-Effort:` and are now the top
priority in the override chain.

**Migration**: To override `model` or `effort` for a specific
run, add the corresponding trailer to the apply-triggering
commit. Example: `git commit --allow-empty -m
"@change-apply: retry with opus\n\nOpsx-Model: opus\nOpsx-Effort:
low"`. The trailer values take precedence over repository
variables and baked-in defaults.
