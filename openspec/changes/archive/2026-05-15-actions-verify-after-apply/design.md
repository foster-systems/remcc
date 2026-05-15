## Context

The cloud apply pipeline today runs `claude -p "/opsx:apply <name>"`
then `openspec validate <name>`, captures both exit codes, commits any
agent output, pushes the branch, and opens or comments on a PR. The
workflow lives in `templates/workflows/opsx-apply.yml`; its normative
contract lives in `openspec/specs/apply-workflow/spec.md`. Adopters
receive the template via `install.sh upgrade` (R2.2).

R4 asks the pipeline to also surface a semantic verification of what
just got applied — incomplete tasks, requirements lacking
implementation evidence, design drift — without auto-fixing. The
`/opsx:verify` skill already exists locally
(`.claude/commands/opsx/verify.md`); it produces a markdown report
with a scorecard table and CRITICAL/WARNING/SUGGESTION groups. This
change is purely workflow plumbing: invoke the existing skill in CI
and route its report to the PR.

## Goals / Non-Goals

**Goals:**

- Run `/opsx:verify <change>` in the same job as apply, reusing apply's
  resolved model and effort.
- Capture the verify report (final assistant markdown) to `verify.md`
  and the raw NDJSON stream to `verify.jsonl`, mirroring the
  apply.log / apply.jsonl pattern.
- Post `verify.md` to the change PR as a dedicated comment authored
  by the GitHub App's bot identity.
- Surface a `verify exit code` line in the existing run-summary PR
  body/comment for symmetry with apply and validate.
- Include `verify.md` and `verify.jsonl` in the `agent-logs-<change>`
  artifact.
- Keep verify informational: never flip the PR to draft based on
  verify alone.
- Close R4 in `openspec/ROADMAP.md`.

**Non-Goals:**

- No auto-fix loop. A human reads the verify comment and decides
  whether to push another `@change-apply` trigger commit.
- No new repository variables, no new commit trailers. Verify reuses
  apply's resolved model + effort.
- No change to the `/opsx:verify` skill itself.
- No change to the `@change-apply` trigger surface, the App
  installation token mint flow, the bot identity, or the concurrency
  partitioning.
- No change to `install.sh`. Adopters upgrade via the existing path.

## Decisions

### Decision: Invoke verify with the same model + effort as apply

The `Run /opsx:verify` step reads the resolved `model` and `effort`
from the existing `config` step outputs (`steps.config.outputs.model`,
`steps.config.outputs.effort`) and passes them to claude, matching
the existing apply step's invocation shape.

**Rationale:** zero new config surface. The trailer →
`OPSX_APPLY_*` var → baked-in default precedence already covers
"this run should use opus/high"; verify naturally inherits. If
verify ever wants a cheaper model than apply, a follow-up change can
add `OPSX_VERIFY_*` parallels — until that justification exists,
adding them is premature.

**Alternatives considered:**
- Bake in `sonnet` + `medium` for verify. Rejected: surprises
  operators who set `OPSX_APPLY_MODEL=opus` expecting both passes to
  use it, and would require explanation in the spec.
- Add `OPSX_VERIFY_*` repo vars and `Opsx-Verify-*` trailers up
  front. Rejected: doubles the config surface for a hypothetical
  future need.

### Decision: Capture the verify report via stream-json + jq, write the final assistant text to verify.md

Verify is invoked with `--output-format stream-json --verbose`,
piped through `tee verify.jsonl | jq … | tee verify.log`, mirroring
the apply step's pipeline. From `verify.jsonl` we then extract the
last `assistant`-type message's text content into `verify.md`. That
final assistant message is the markdown report the skill emits
(scorecard table + CRITICAL/WARNING/SUGGESTION groups + final
assessment).

**Rationale:** the apply step already proves this pipeline works
under `--dangerously-skip-permissions` and we get the same live
console trace for debugging. `verify.md` is a clean, comment-ready
markdown blob; `verify.jsonl` is the raw audit trail.

**Alternatives considered:**
- `--output-format text`. Simpler to write to `verify.md` directly,
  but loses the per-tool-use trace we get in the Actions console.
- Run verify with `--output-format text` *and* parse `verify.jsonl`
  separately. Rejected: two invocations, two API spends.

### Decision: Post the report as a dedicated PR comment, not inside the run-summary

The existing "Open or update PR" step writes the run-summary body
(on first open) or posts a run-summary comment (on rerun). After
that step, a new `Post verify report` step calls
`gh pr comment <pr-number> --body-file verify.md`, conditional on a
PR existing for the branch. Authored by the App installation token
so the comment author is `<slug>[bot]`.

**Rationale:** the report can be long (per-requirement findings,
per-scenario coverage) and folding it into the run summary muddles
two signals — a short exit-code summary readable at a glance vs. a
long semantic review readable on demand. Two separate comments stay
independent: a reviewer can link directly to the verify comment, and
each rerun produces a fresh report comment without rewriting the
run-summary.

**Alternatives considered:**
- Embed verify.md inside the run-summary body/comment as a
  collapsible `<details>` block. Rejected: less linkable, harder to
  scan a PR timeline.
- Replace the previous verify comment in place (single sticky
  comment). Rejected: timeline history of verify reports across
  reruns is valuable; the report changes meaningfully when apply
  reruns with different model/effort or trailer overrides.

### Decision: Verify is informational — apply or validate non-zero remain the only draft triggers

The existing draft logic is `if APPLY_EXIT != 0 OR VALIDATE_EXIT != 0
then --draft`. This change keeps that condition unchanged. The new
`verify exit code` line in the run-summary is purely descriptive.

**Rationale:** verify is heuristic — keyword search and reasoning
about coverage produce false positives. Making a heuristic gate the
ready-for-review signal would either over-block (wasting human
review cycles dismissing false CRITICALs) or under-block (the gate
gets ignored). Surfacing the report and letting the human decide
matches the "highlight in PR → human review → another go" framing
from the roadmap.

**Alternatives considered:**
- CRITICAL findings flip the PR to draft. Rejected per above.
- Verify exit code (non-zero from the skill itself) flips the PR to
  draft. Rejected: same false-positive concern; the skill returning
  non-zero conflates a crashed verify with a found-CRITICAL verify.

### Decision: One verify step per trigger commit, no separate trigger

Verify runs in the same job as apply. There is no opt-in commit
subject for verify alone; it runs on every `@change-apply` trigger.

**Rationale:** the verify report is a function of "the state of the
change after this apply". Decoupling its trigger would require a
separate way to mark "the branch is ready to verify even though no
apply happened", which solves no problem we have.

### Decision: Drop verify.md and verify.jsonl from the commit

Like apply.log / apply.jsonl / validate.log, the new verify outputs
are git-reset before commit. They live only in the workflow artifact
and the dedicated PR comment.

**Rationale:** they are runner-local and ephemeral; committing them
would clutter the change branch and re-trigger downstream consumers.

## Risks / Trade-offs

- **[Long verify reports may hit GitHub's PR comment size cap (65 536 chars)]**
  → Mitigation: if verify.md exceeds the cap, the post step
  truncates with a "report truncated — see agent-logs artifact"
  footer pointing at the artifact. We expect this to be rare in
  practice but spec it as a scenario.

- **[Verify's API spend doubles per-run cost in the worst case]**
  → Mitigation: documented, accepted. If cost ever bites, a
  follow-up can split `OPSX_VERIFY_*` vars and default verify to a
  cheaper model. The existing `OPSX_APPLY_EFFORT=low` already lets
  operators dial down both passes today.

- **[Verify may report false-positive CRITICALs that confuse reviewers]**
  → Mitigation: the skill itself biases toward SUGGESTION over
  WARNING and WARNING over CRITICAL when uncertain. The
  informational-only carve-out means false positives cost reviewer
  attention, not blocked merges.

- **[Verify crashes mid-run and verify.md never gets written]**
  → Mitigation: `continue-on-error: true` plus a guard in the post
  step — if `verify.md` is missing or empty, post a fallback comment
  ("Verify did not produce a report; see agent-logs artifact and the
  recorded exit code") instead of skipping the post entirely.

- **[Verify comment author drifts off the App identity]**
  → Mitigation: the post step uses `GH_TOKEN=${{ steps.app-token.outputs.token }}`,
  the same token the existing PR open/update step uses. The spec
  carries a normative scenario asserting the comment author is
  `<slug>[bot]`.

## Migration Plan

1. Update `templates/workflows/opsx-apply.yml` with the new verify
   step, the new post step, the extended log upload, and the
   extended run-summary body.
2. Update the `apply-workflow` spec via the delta in this change.
3. Update `openspec/ROADMAP.md` line 10 to mark R4 complete with
   this change's slug.
4. Self-test: push a `@change-apply` trigger commit on a sandbox
   change in this repo, confirm verify runs, posts a dedicated
   comment, and does not flip the PR to draft on a clean apply.
5. Adopters pick up the new workflow on their next `install.sh
   upgrade` run. No new secrets, no new vars.

Rollback: revert the workflow template and the spec delta. The new
step has no persistent side effects (no schema changes, no new
secrets, no new branch protection rules).

## Open Questions

- None at this time. Scope is locked by the prior decisions.
