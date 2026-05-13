# remcc costs

remcc has two cost surfaces: Anthropic API usage and GitHub Actions
runner minutes. Neither is metered by remcc itself — both are
controlled by the operator on the relevant provider's side.

## Anthropic API costs

Each `/opsx:apply` run consumes Anthropic API tokens proportional to
the size of the change being applied: input tokens for the artifacts
(proposal, design, specs, tasks, plus context files the agent reads)
and output tokens for the agent's reasoning, edits, and command
output it processes.

The trigger surface is opt-in: the workflow runs apply only when the
head commit on a `change/**` push has a subject starting with the
magic word `@change-apply`. Draft commits, WIP edits, and co-author
collaboration pushes that don't carry the trigger subject are skipped
at the job-level `if:` — no runner is provisioned, no Anthropic
tokens are spent, and no runner minutes are charged. Apply spend
correlates with the number of trigger commits the author writes, not
with the number of pushes.

Capitalised case-typos (`@Change-Apply: ...`) are an edge case: the
job-level `if:` lets them through (GitHub Actions' `startsWith()` is
case-insensitive), and a case-sensitive shell guard step then aborts
the run before the apply step. Cost: ~20 seconds of runner time per
case-typo push, no Anthropic spend.

There is no per-run kill switch in v1. Cost is bounded by:

- **Anthropic admin-console budget cap.** This is the primary
  control. Set it deliberately in the Anthropic admin console under
  organisation billing settings; once exceeded, API requests fail
  for the rest of the billing period. A hard cap rather than a
  soft alert.
- **Workflow `timeout-minutes: 180`.** A runaway agent is bounded
  by wall-clock time, not just tokens. After three hours the runner
  is killed regardless of token spend — although three hours of
  continuous Claude Code activity can still cost meaningfully.

### Recommended setup

1. Choose a monthly budget you would be comfortable losing if
   something went wrong (a misbehaving agent, a stuck loop, an
   unexpectedly large change).
2. In the Anthropic admin console, set this as a **hard cap** on
   the organisation. Soft alerts alone do not stop the runner —
   the hard cap does.
3. Optionally set a lower soft alert at, say, 50% of the cap so you
   get a warning before the cap actually trips.
4. Revisit the cap after each month of real usage. The first few
   months are the noisy ones; once a steady baseline emerges you
   can size the cap closer to it.

### Reading the artifact logs to reason about cost

Each workflow run uploads `apply.log` and `validate.log` as the
artifact `agent-logs-<change>` with 14 days of retention. The apply
log contains the full Claude Code session output. To estimate
tokens for a specific run:

- Look for the session-summary lines Claude Code emits at exit
  (input/output token counts for the run).
- Cross-reference against the change's `tasks.md` to see how many
  tasks were applied; large heterogeneous changes cost more per
  task than narrow, repetitive ones.
- If a single change burns a meaningful fraction of your monthly
  cap, consider splitting the change into smaller proposals.

A per-run hard kill switch is intentionally not part of v1. Add one
only if real usage shows that the budget cap and 180-minute timeout
together are insufficient.

### Choosing model and effort

Each `/opsx:apply` run passes an explicit `--model` and an
`--effort` (Claude Code's thinking-budget level) to the agent.
Both are knobs you can turn for cost vs. quality.

- **Model.** `haiku` is the cheapest, `sonnet` is the workflow's
  default, `opus` is the most expensive. As a rule of thumb,
  prefer `sonnet` for routine changes and reach for `opus` only
  on large, architectural, or otherwise gnarly work where the
  cost is justified by the quality lift.
- **Effort.** `low` < `medium` < `high` thinking budget. Higher
  effort lets the agent reason more before acting, which usually
  improves quality on hard changes but also costs more tokens.
  `high` is the default and is usually right for non-trivial
  OpenSpec changes; drop to `medium` or `low` for small,
  well-specified work where extra reasoning is dead weight.

The two knobs compose: `sonnet` + `low` is the cheapest reasonable
configuration; `opus` + `high` is the most expensive. Most repos
land on `sonnet` + `high` as the default and override per change
only when the change is small enough to warrant `low`, or hard
enough to warrant `opus`.

The resolved `model` and `effort` (and the source each came from)
appear in the body of every PR the workflow opens, and in the
comment it leaves on re-runs of an existing PR. Use those values
to audit cost decisions after the fact rather than guessing from
the change name. See `docs/SETUP.md` for the override mechanics
(repository variables and commit trailers).

#### Retry with a different model

If a `sonnet` run produces a result you want to redo with `opus`,
push a fresh trigger commit on the change branch carrying the
override trailer:

```sh
git commit --allow-empty -m "$(cat <<'EOF'
@change-apply: retry with opus

Opsx-Model: opus
EOF
)"
git push
```

The single commit is both the "go again" signal and the model
override — no GitHub UI step, no context-switch out of the
terminal. The PR comment for the new run reports `model=opus`
and the source as `commit trailer Opsx-Model`.

## GitHub Actions runner minutes

Each `/opsx:apply` run consumes GitHub-hosted Ubuntu runner minutes
for the duration of the job (capped at 180 minutes).

- **Public repositories** get free Ubuntu minutes within GitHub's
  generous public-repo allowance.
- **Private repositories** consume from your account's or
  organisation's monthly minute budget. Ubuntu minutes are billed
  at 1× — the lowest multiplier.
- A typical apply run completes in well under an hour for narrow
  changes. The 180-minute cap is a safety ceiling, not a target.

### Reading run duration

Each workflow run shows wall-clock duration in the Actions tab.
Sustained increases in average run duration usually mean either:

- Changes are getting larger (consider splitting them), or
- The agent is spending time on side quests (read the apply log to
  see what it actually did, and whether the proposal/specs needed
  to be tighter).

There is no per-run runner-minute alert in v1. If runner minutes
become a binding constraint, GitHub's Actions billing alerts and
the per-repo Actions usage page are the right place to look first.
