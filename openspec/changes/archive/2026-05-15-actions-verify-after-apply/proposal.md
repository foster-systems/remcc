## Why

R4 on the roadmap asks the cloud apply pipeline to also run `opsx:verify`
so that semantic gaps (incomplete tasks, requirements with no
implementation evidence, design drift) surface alongside the structural
`openspec validate` gate. Today the workflow stops at `validate`, which
only checks artifact structure — a change can apply cleanly, validate
green, and still leave unchecked task boxes or unimplemented
requirements that reviewers have to spot by hand. Adding verify closes
that loop with a heuristic semantic check whose output becomes a PR
comment a human reads before merging.

## What Changes

- The `templates/workflows/opsx-apply.yml` workflow gains a new
  `Run /opsx:verify` step right after `Run openspec validate`. It
  invokes `claude -p "/opsx:verify <change>"` with the same model and
  effort that apply resolved, runs `continue-on-error`, and captures
  the markdown verification report to `verify.md` plus the raw NDJSON
  stream to `verify.jsonl`.
- A new `Post verify report` step posts `verify.md` as a dedicated
  PR comment using the GitHub App installation token (so the comment
  author matches the PR author). It runs only when a PR exists for
  the branch; if the branch is not ahead of `main`, no comment is
  posted.
- The existing run-summary PR body/comment gains one line — the
  `verify exit code` — for symmetry with `apply` and `validate`.
  The verification report itself is **not** embedded in the run
  summary; it lives only in its own dedicated comment.
- The `agent-logs-<change>` artifact upload is extended to include
  `verify.md` and `verify.jsonl` (14-day retention, unchanged).
- Verify is **informational only**: its exit code and any CRITICAL
  findings do NOT flip the PR to draft. Apply or validate non-zero
  remain the only draft triggers. This is called out as a normative
  carve-out so future refactors do not silently regress.
- `openspec/ROADMAP.md` line 10 is updated to check off R4 with a
  reference to this change's slug, matching the format of other
  closed roadmap items.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `apply-workflow`: adds the verify step contract (invocation, report
  capture, dedicated PR comment, informational-only carve-out) and
  extends two existing requirements (log artifact contents, run-summary
  PR body) to cover verify alongside apply and validate.

## Impact

- **Workflow template** (`templates/workflows/opsx-apply.yml`):
  one new claude invocation step, one new gh-pr-comment step, and
  small edits to the existing stage/commit, PR open/update, and log
  upload steps.
- **Spec** (`openspec/specs/apply-workflow/spec.md`): four new
  requirements and two modified requirements, applied via the delta
  in this change.
- **Roadmap** (`openspec/ROADMAP.md`): R4 line flipped to checked
  with this change's slug.
- **Adopters**: pick up the new workflow via the existing
  `install.sh upgrade` path (R2.2 already shipped). No new install
  step, no new secret, no new repository variable.
- **API spend**: one additional Claude invocation per trigger commit,
  at the same model/effort as apply. Verify is bounded by the
  existing job `timeout-minutes: 180`.
- **No change** to: the verify skill itself
  (`.claude/commands/opsx/verify.md`, `.claude/skills/openspec-verify-change/`),
  the `@change-apply` trigger surface, the bot identity, the minted
  installation token flow, or the concurrency partitioning.

## Non-goals

- No auto-fix loop. The roadmap-line phrase "another go" stays a
  human action; this change deliberately does not re-trigger apply
  from a verify finding.
- No separate `OPSX_VERIFY_MODEL` / `OPSX_VERIFY_EFFORT` repository
  variables and no separate `Opsx-Verify-*` commit trailers. Verify
  reuses apply's resolved values. Splitting them is a follow-up if
  cost or latency ever justifies it.
- No new install.sh work. Adopters get the updated workflow via the
  existing upgrade command.
