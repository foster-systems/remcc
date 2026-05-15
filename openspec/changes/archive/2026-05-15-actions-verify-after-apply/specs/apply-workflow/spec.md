## ADDED Requirements

### Requirement: Run /opsx:verify after validate

The workflow SHALL invoke `claude -p "/opsx:verify <name>"` for the
resolved change name in non-interactive mode immediately after the
validate step. The invocation SHALL pass `--model` with the same
resolved model value used by the apply step and the Claude Code
thinking-budget flag corresponding to the same resolved effort value
used by the apply step (i.e. verify reuses apply's already-resolved
values from the existing trailer → repository-variable →
baked-in-default precedence; no separate verify config surface is
introduced). The invocation SHALL pass `--dangerously-skip-permissions`,
matching the apply step's sandbox posture.

The verify step SHALL run regardless of the apply or validate exit
codes. The exit code of the Claude invocation SHALL be captured into a
step output named `exit_code` but SHALL NOT cause the workflow to fail
immediately (`continue-on-error: true`).

#### Scenario: Verify runs after a successful apply and validate

- **WHEN** apply has exited zero and validate has exited zero
- **THEN** the workflow invokes `claude -p "/opsx:verify <name>"` next
- **AND** the verify step's exit code is captured into its step output

#### Scenario: Verify runs even when apply exited non-zero

- **WHEN** apply has exited non-zero
- **THEN** validate runs (per existing contract) and verify runs after
  it
- **AND** verify's exit code is captured into its step output

#### Scenario: Verify runs even when validate exited non-zero

- **WHEN** apply exited zero but validate exited non-zero
- **THEN** verify runs after validate
- **AND** verify's exit code is captured into its step output

#### Scenario: Verify reuses apply's resolved model and effort

- **WHEN** the workflow's `config` step resolved `model=opus` and
  `effort=medium` for this run
- **THEN** the verify step's `claude` invocation is passed
  `--model opus` and the thinking-budget flag corresponding to
  `medium`, with no other source of model or effort consulted

#### Scenario: Verify non-zero does not fail the workflow step that follows

- **WHEN** Claude Code exits non-zero from the verify invocation
- **THEN** the workflow continues to subsequent steps (stage, push,
  PR open/update, post verify report) and records the verify exit code
  for later use

#### Scenario: Verify completes before any PR-side communication

- **WHEN** the workflow runs end-to-end for a single trigger commit
- **THEN** the verify step finishes before any of: the
  `open or update the change PR` step, the run-summary rerun comment,
  or the dedicated verify comment are produced
- **AND** the run-summary body or rerun comment posted by this run
  reflects the verify exit code captured in this run, not a prior one

#### Scenario: Every trigger commit on the same branch gets its own verify

- **WHEN** apply has already been run once on `change/foo` (PR exists)
- **AND** the author pushes a second `@change-apply` trigger commit
  to `change/foo`
- **THEN** the second workflow job runs apply, then validate, then
  verify in order
- **AND** the second job posts both a fresh run-summary rerun comment
  (with the second run's verify exit code) and a fresh dedicated
  verify comment (with the second run's `verify.md`)

### Requirement: Verify report captured as markdown

The workflow SHALL capture the markdown verification report produced
by the `/opsx:verify` skill — the final assistant text message of the
Claude invocation — into a file named `verify.md` at the runner's
working directory. The workflow SHALL capture the raw NDJSON stream
of the verify invocation into a file named `verify.jsonl` in the same
directory.

#### Scenario: Successful verify writes a non-empty verify.md

- **WHEN** the verify invocation completes and the skill emitted its
  markdown report as its final assistant message
- **THEN** the workflow has written that markdown report to
  `verify.md`
- **AND** `verify.jsonl` contains the raw NDJSON stream of the
  invocation

#### Scenario: Verify crash produces an empty or missing verify.md

- **WHEN** the verify invocation exits non-zero before emitting a
  final assistant text message
- **THEN** `verify.md` may be empty or absent at the runner's working
  directory
- **AND** `verify.jsonl` still contains whatever partial NDJSON the
  stream captured before the crash

### Requirement: Verify report posted as dedicated PR comment

The workflow SHALL post the contents of `verify.md` as a dedicated
pull-request comment on the change PR using `gh pr comment`
authenticated with the GitHub App installation token (see "GitHub App
installation token minted before any git or PR operation"). The post
step SHALL run after the existing "open or update the change PR" step
and only when a pull request exists for the change branch (i.e. the
branch is ahead of `main`).

The verify comment SHALL be distinct from the run-summary body or
run-summary rerun comment created by the "open or update the change
PR" step. The workflow SHALL NOT replace, edit, or fold previous
verify comments; each run SHALL produce a fresh dedicated verify
comment on the PR.

If no pull request exists for the change branch (e.g. the branch has
no commits ahead of `main`), the workflow SHALL NOT post a verify
comment.

If `verify.md` is missing or empty, the workflow SHALL post a
fallback comment naming the captured verify exit code and pointing
the reader at the `agent-logs-<change>` artifact, rather than skip
posting entirely.

If `verify.md` exceeds GitHub's PR-comment body size limit, the
workflow SHALL post a truncated body that retains the top of the
report and ends with a footer indicating the report was truncated
and naming the `agent-logs-<change>` artifact as the source of the
full report.

#### Scenario: First successful run posts a dedicated verify comment

- **WHEN** the workflow has opened a new PR for the change branch
- **AND** `verify.md` is non-empty
- **THEN** the workflow posts a second PR comment whose body is the
  contents of `verify.md`, distinct from the PR body itself

#### Scenario: Rerun on existing PR posts another dedicated verify comment

- **WHEN** the workflow completes and a PR already exists for the
  change branch
- **AND** `verify.md` is non-empty
- **THEN** the workflow posts a fresh dedicated verify comment whose
  body is the contents of `verify.md`, separate from the run-summary
  rerun comment

#### Scenario: Verify comment author is the GitHub App identity

- **WHEN** the workflow posts a dedicated verify comment
- **THEN** the comment's author field as returned by the GitHub API
  is `<slug>[bot]` (the GitHub App's bot identity), matching the PR
  author

#### Scenario: No PR means no verify comment

- **WHEN** the change branch has no commits ahead of `main` and no
  PR is opened
- **THEN** the workflow does not post a verify comment

#### Scenario: Missing or empty verify.md produces a fallback comment

- **WHEN** the verify step crashed and `verify.md` is missing or
  empty
- **AND** a PR exists for the change branch
- **THEN** the workflow posts a fallback comment naming the captured
  verify exit code and the `agent-logs-<change>` artifact, rather
  than skipping the post step

#### Scenario: Oversized verify.md is posted truncated with a pointer

- **WHEN** `verify.md` exceeds GitHub's PR-comment body size cap
- **AND** a PR exists for the change branch
- **THEN** the workflow posts a truncated body that retains the head
  of the report and ends with a footer pointing at the
  `agent-logs-<change>` artifact

### Requirement: Verify is informational and does not gate draft status

The workflow's draft-on-failure logic SHALL consider only the apply
and validate exit codes when deciding whether to open a new PR with
`--draft` (see "Surface failures as draft PR"). The verify exit
code, the contents of `verify.md`, and the presence of CRITICAL,
WARNING, or SUGGESTION findings in the verify report SHALL NOT
affect the `--draft` flag on PR open. The workflow SHALL NOT toggle
an existing PR between draft and ready based on verify outcome.

#### Scenario: Apply clean and validate clean but verify reports CRITICAL — PR opens ready

- **WHEN** apply exited zero, validate exited zero, no PR exists
  yet, and `verify.md` contains CRITICAL findings
- **THEN** the workflow creates the PR without `--draft` (ready for
  review)

#### Scenario: Apply clean and validate clean and verify exited non-zero — PR opens ready

- **WHEN** apply exited zero, validate exited zero, no PR exists
  yet, and the verify step exited non-zero (e.g. skill crashed)
- **THEN** the workflow creates the PR without `--draft`

#### Scenario: Validate non-zero still drafts the PR regardless of verify

- **WHEN** apply exited zero, validate exited non-zero, and verify
  reports no CRITICAL findings
- **AND** no PR exists yet
- **THEN** the workflow creates the PR with `--draft` (validate
  failure remains the trigger)

#### Scenario: Apply non-zero still drafts the PR regardless of verify

- **WHEN** apply exited non-zero, validate exited zero, and verify
  reports no CRITICAL findings
- **AND** no PR exists yet
- **THEN** the workflow creates the PR with `--draft` (apply failure
  remains the trigger)

## MODIFIED Requirements

### Requirement: Upload apply and validate logs

The workflow SHALL upload `apply.log`, `apply.jsonl`, `validate.log`,
`verify.md`, and `verify.jsonl` as a single workflow artifact named
`agent-logs-<change>` with a retention of 14 days, regardless of
whether earlier steps succeeded or failed. Missing files SHALL be
ignored by the upload step (so a crashed verify that produced no
`verify.md` does not fail the upload).

#### Scenario: Logs are retrievable after a failed run

- **WHEN** the workflow run has completed (success or failure)
- **THEN** an artifact `agent-logs-<change>` is available for
  download from the run summary

#### Scenario: Artifact contains verify outputs alongside apply and validate

- **WHEN** the workflow run has completed and the verify step
  produced a `verify.md` and `verify.jsonl`
- **THEN** the `agent-logs-<change>` artifact includes
  `verify.md` and `verify.jsonl` alongside `apply.log`,
  `apply.jsonl`, and `validate.log`

#### Scenario: Missing verify outputs do not fail the artifact upload

- **WHEN** the verify step crashed before writing `verify.md`
- **THEN** the upload step still completes and the artifact contains
  whichever of the expected files exist on disk

### Requirement: Open or update the change PR

If the change branch has commits ahead of `main`, the workflow SHALL
ensure a PR exists from the change branch to `main`. If no PR
exists, the workflow SHALL create one with the title format
`Change: <change-name>` (the literal string `Change: ` followed by
the resolved change name as the entire title). If a PR already
exists, the workflow SHALL post a comment summarising the run and
SHALL NOT modify the existing PR's title.

The run-summary PR body (on PR creation) and the run-summary rerun
comment (on subsequent runs) SHALL include separate lines for the
`apply`, `validate`, and `verify` exit codes. The verification
report itself SHALL NOT be embedded in the run-summary body or
comment — it lives only in the dedicated verify comment (see
"Verify report posted as dedicated PR comment").

#### Scenario: First successful run opens a PR

- **WHEN** the workflow completes successfully and no PR exists
  for the change branch `change/foo`
- **THEN** the workflow creates a PR with the title `Change: foo`
  and the apply, validate, and verify exit codes each on their own
  line in the body

#### Scenario: Subsequent run on existing PR adds a comment

- **WHEN** the workflow completes and a PR already exists for the
  change branch
- **THEN** the workflow adds a run-summary comment to the PR with
  the latest apply, validate, and verify exit codes
- **AND** the existing PR's title is not changed

#### Scenario: Run-summary does not embed the verify report

- **WHEN** the workflow opens a new PR or posts a run-summary
  comment
- **THEN** the body/comment contains the verify exit code but does
  not contain the scorecard table or CRITICAL/WARNING/SUGGESTION
  sections from `verify.md`
