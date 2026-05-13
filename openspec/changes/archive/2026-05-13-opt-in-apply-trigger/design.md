## Context

`templates/workflows/opsx-apply.yml` triggers in two ways today:

1. `on: push: branches: [change/**]` — every push to a change branch.
2. `on: workflow_dispatch:` — manual run from the GitHub UI, with
   optional `change_name`, `model`, and `effort` inputs.

Once triggered, the workflow always runs the apply step (subject to
the existing bot-self-loop `if:` guard that skips runs whose head
commit was authored by `github-actions[bot]`). The author has no
fine-grained control over *when* the agent runs: any non-bot push
to a `change/**` ref is an implicit "go ahead, implement the
change."

In practice authors want the opposite default. A change branch is
where drafts live: the proposal evolves, tasks get refined,
co-authors push edits, and the author wants to see the proposal in
a PR-like view *before* spending tokens. The current model forces
authors to choose between (a) iterating locally and pushing only
once (losing collaboration), or (b) accepting that every WIP push
burns an apply run.

The mechanism we want is the inverse: the workflow listens to every
push to `change/**`, but only runs apply when the author has
explicitly written a commit that asks for it. The convention is a
commit subject that begins with the magic word `@change-apply`. The
`@`-prefix pairs visually with the `change/` branch name (both
identify the change), is virtually never the start of a natural
commit subject, and has no shell-history footgun. What follows the
magic word is the author's choice — a colon and a human description
(`@change-apply: first pass`), parens (`@change-apply(retry)`), a
space and free text (`@change-apply retry after extending task 3`),
or nothing at all. Everything else is treated as draft work.

This also subsumes self-loop prevention (the bot's commit subject
is `/opsx:apply <name>`, which does not match), eliminates the
`workflow_dispatch` trigger surface (the trigger commit is the
opt-in signal — no separate UI button needed), and replaces the
ideas explored in the previous draft of this change (marker file,
skip trailers, force trailers) with one rule.

## Goals / Non-Goals

**Goals:**

- Apply runs only when the head commit's subject on the pushed
  ref starts with the magic word `@change-apply`.
- Authors can push any number of draft / WIP / collaboration
  commits to a `change/**` branch with no apply runs.
- The shape after the magic word is the author's choice — colon,
  parens, space, or nothing. remcc does not impose a separator.
- Re-applying after extending the proposal or tasks is one extra
  commit (`git commit --allow-empty -m "@change-apply: retry"`
  and push).
- Per-run model and effort overrides remain available via
  `Opsx-Model:` / `Opsx-Effort:` trailers on the apply-triggering
  commit.
- Self-loop prevention is a free consequence of the trigger
  convention — no explicit author-name check needed.
- A push whose head commit does not match the trigger convention
  is a clean no-op (no Anthropic spend, no log artifact, no PR
  comment, no failure surface).

**Non-Goals:**

- A `workflow_dispatch` escape hatch. The opt-in commit is the
  trigger surface; if the author wants to run apply, they write
  one commit. No GitHub-UI path.
- Branches other than `change/**`. The push trigger keeps the
  branch filter for cheap scoping; pushing a
  `@change-apply: retry` commit to `main` does nothing.
- Parsing the text after the magic word for meaning (e.g. extract
  a model name or effort hint from `@change-apply: retry with
  opus`). The text is human-readable context only; structured
  overrides go in trailers.
- A "re-apply on every commit until done" mode. Each apply run
  requires its own opt-in commit. This is explicitly the design
  goal: authors choose the moment.
- A way to skip the trigger on a commit that legitimately starts
  with `@change-apply` for an unrelated reason. With the
  `@`-prefixed magic word, the chance of an accidental collision
  with a natural commit subject is effectively zero, so no escape
  hatch is provided.

## Decisions

### D1. Trigger gate is a single head-commit subject prefix check

The workflow uses a job-level `if:` expression to gate the entire
job on the head commit subject:

```yaml
if: startsWith(github.event.head_commit.message, '@change-apply')
```

When the expression is false, GitHub Actions does not start the
job at all — no runner is spun up, no Actions minutes are charged,
nothing appears on the PR. The Actions run *does* show in the
workflow's history with status "skipped", which is the right
audit-trail signal.

Note that `head_commit.message` is the full message, but
`startsWith` evaluates against the start of that string, which is
the first line of the subject. This makes the check effectively
"subject line starts with `@change-apply`."

Rationale: gating at the job-level `if:` is the cheapest possible
implementation. Skipped runs cost zero runner time and zero
Actions minutes for the bulk of pushes (any subject not starting
with the magic-word prefix, case-insensitively).

**Case-sensitivity gap.** GitHub Actions' `startsWith()` expression
function is [documented as
case-insensitive](https://docs.github.com/en/actions/learn-github-actions/expressions#startswith).
The job-level `if:` therefore lets through case-variant subjects
like `@Change-Apply: retry` and `@CHANGE-APPLY: retry`, which D2
explicitly rules out. To honor the byte-exact contract a step-level
guard is added immediately after the `Verify WORKFLOW_PAT` step:

```yaml
- name: Confirm trigger subject is case-sensitive match
  env:
    HEAD_MSG: ${{ github.event.head_commit.message }}
    GH_TOKEN: ${{ github.token }}
    RUN_ID: ${{ github.run_id }}
  run: |
    subject="$(printf '%s' "${HEAD_MSG}" | head -n1)"
    case "${subject}" in
      "@change-apply"*) ;;
      *)
        gh run cancel "${RUN_ID}" --repo "${GITHUB_REPOSITORY}"
        sleep 60
        exit 1
        ;;
    esac
```

The shell `case` glob is byte-exact and case-sensitive, so it
catches what `startsWith()` lets through. On mismatch the step
calls `gh run cancel` and waits — the run shows up as `cancelled`
in the Actions UI within a minute. The `exit 1` is a fallback in
case the cancel doesn't propagate before the sleep finishes (the
run then shows as `failed`); both outcomes communicate "didn't
run" clearly enough.

Cost of a case-typo push: ~15-30s of runner time for the verify
steps plus the cancel-propagation sleep. No Anthropic spend, no PR
comment, no log artifact. Strictly cheaper than a full apply, and
the typo gets a visible "cancelled" entry that confirms the gate
worked.

Alternatives considered:

- **Step-level guard that prints `skip_reason`.** Costs ~15s of
  runner time per push and adds a "skipped" comment to the run
  history twice (once for the run, once for the step). Rejected
  in favour of zero-cost job-level skip.
- **Filtering at the trigger level via
  `on: push: paths: [...]`.** GitHub Actions doesn't support
  filtering pushes by commit-message content at the trigger
  level. Rejected (impossible).
- **A separate `on: push: paths: [openspec/apply-trigger.txt]`
  marker file pushed by the author.** Adds an artifact the
  author has to remember to commit and remove. Rejected — the
  commit subject is already the right opt-in signal.
- **Strict-separator gate (e.g. require one of
  `opsx-apply:`, `opsx-apply(`, `opsx-apply `).** Encoded as an
  OR-chain of `startsWith` calls in the `if:` expression.
  Considered but rejected: the magic word *is* the contract; the
  separator after it is style. A future operator who wants to
  write `opsx-apply!retry` or `opsx-apply\n\nbody only` should
  not have to argue with the workflow. The cost of accepting
  oddly-shaped triggers is borne by the author who wrote them.

### D2. Trigger token shape: magic word `@change-apply` at subject start

The contract is just: the subject (first line of the commit
message) starts with the byte sequence `@change-apply`. Anything
that follows is the author's free-form context. All of these
trigger apply:

- `@change-apply: first pass`
- `@change-apply(retry with opus)`
- `@change-apply retry after task 3 update`
- `@change-apply` (alone)
- `@change-apply!` / `@change-apply...` /
  `@change-apply\n\nbody only`

The recommended-for-humans idiom in SETUP.md is
`@change-apply: <reason>` (conventional-commits "type: subject"
shape), but the workflow does not enforce a separator.

Rationale: the magic word *is* the opt-in. Forcing a specific
separator buys nothing — the workflow doesn't parse what comes
after — and creates a class of friendly-typo failures
(`@change-apply foo` vs `@change-apply: foo` vs
`@change-apply(foo)`) that the user explicitly wants to avoid.
The cheap `startsWith` check gives a deterministic gate without
parsing.

Why `@change-apply` and not a simpler word:

- **Visual pairing with the branch name.** Branches are
  `change/<name>`; the trigger is `@change-apply`. Both refer to
  "the change," so the language is internally consistent.
- **`@`-prefix avoids collisions.** A natural commit subject
  virtually never starts with `@` at position 0. (`@-mentions`
  inside commit messages are common, but they don't start at
  position 0 of the subject line.) This eliminates the
  loose-prefix concern that the bare-word form
  (`opsx-applying-fixes`) would have had.
- **No shell-history footgun.** `@` is not a special character
  in bash, zsh, or fish quoting; `git commit -m "@change-apply:
  foo"` and `git commit -m '@change-apply: foo'` both work
  identically. By contrast a `!`-prefix (also considered) would
  trigger bash/zsh history substitution in double-quoted
  strings.
- **Decoupled from implementation namespace.** The internal
  command is still `/opsx:apply` and the workflow file is still
  `opsx-apply.yml`; the trigger word is the human-facing
  contract and can be different from the implementation name
  without confusion.

Alternatives considered:

- **`opsx-apply` (bare word, no prefix).** Earlier draft of
  this design. Rejected: loose prefix match also fires on
  subjects like `opsx-applying-fixes`, which is an avoidable
  edge case.
- **`!opsx-apply` (leading `!` for emphasis).** Same
  distinctiveness as `@`, but `!` in bash/zsh double-quoted
  strings triggers history substitution; authors would have to
  remember to use single quotes. Rejected for the ergonomic
  cost.
- **`[opsx-apply]` (bracket-wrapped, like `[skip ci]`).** No
  shell issues, familiar shape. Rejected because the bracket
  form fixes one specific spelling and loses the "freeform
  separator" property the user asked for.
- **`^opsx-apply\(.*\)` (strict parens).** Rejected per the
  user's "anything I like" framing.
- **`opsx-apply:` only (conventional-commits style).** Single
  separator, easy to grep, but rejects `opsx-apply(retry)` and
  `opsx-apply retry`. Rejected.
- **OR-chain of common separators (`opsx-apply:`,
  `opsx-apply(`, `opsx-apply `, `opsx-apply\n`).** Bloats the
  `if:` expression and still misses edge cases like
  `opsx-apply!`. Rejected.
- **`/opsx:apply` (matches the slash-command syntax the agent
  itself uses).** Rejected — the bot's own commit subject is
  exactly this, so the self-loop guard would have to come back.
- **A trailer (`Opsx-Apply: true`).** Hides the trigger in the
  commit body; less visible in `git log`. Rejected.

### D3. `workflow_dispatch` removed entirely

The `on: workflow_dispatch:` block, including its `change_name`,
`model`, and `effort` inputs, is removed from the workflow YAML.
The corresponding spec requirements ("Manual dispatch with
explicit change name," "Manual dispatch inputs override defaults")
are removed. The "Change name resolution" requirement loses its
dispatch-input clause. The "Override precedence" requirement
loses its top level (dispatch input); the new top level is the
commit trailer.

Rationale: the opt-in commit is itself a manual action. An author
who wants a different model writes
`opsx-apply(retry with opus)` and adds an `Opsx-Model: opus`
trailer on the same commit. No GitHub UI required, no
context-switch out of the terminal. Keeping dispatch as a
parallel path would mean two trigger surfaces, two skip rules,
two test paths — not worth the complexity for the small
"trigger from the UI" convenience.

Alternatives considered:

- **Keep `workflow_dispatch` for emergency reruns.** The opt-in
  commit covers reruns more cleanly. Rejected.
- **Keep `workflow_dispatch` but drop the inputs.** Same
  duplication, fewer benefits. Rejected.

### D4. Self-loop prevention is implicit

The bot's commit subject after a successful apply run is
`/opsx:apply <name>` (set by the existing "Stage and commit agent
output" step). That subject does not start with `@change-apply`, so
the job-level `if:` evaluates to false and the bot's push does
not re-trigger the workflow. The existing
`head_commit.author.name != 'github-actions[bot]'` clause becomes
redundant and is removed.

If a future change ever shapes the bot's commit subject as
`@change-apply...`, the implicit guard breaks. To prevent that,
the workflow's commit-message template is fixed (`/opsx:apply
<name>`), and any future change to that template MUST be
accompanied by a corresponding change to the trigger gate or the
self-loop guard's reintroduction. This is captured as a tasks-md
gate.

Rationale: one rule that doubles as self-loop prevention is
strictly better than two rules. The implicit guarantee is
trivially observable in the YAML.

### D5. Empty trigger commits are the canonical re-apply idiom

To re-apply after extending tasks or fixing verify findings, the
canonical idiom is:

```
git commit --allow-empty -m "@change-apply: retry with feedback"
git push
```

The empty commit carries no working-tree changes; the *previous*
non-trigger commits (which carried the task extensions / fixes)
are what the agent will see. This is the "I'm done editing — go
again" signal, decoupled from any specific edit.

Rationale: separating the "I edited" commits from the "go apply"
commit lets authors collaborate freely on the edits and own the
trigger themselves. Empty commits are a well-established git
idiom; `git commit --allow-empty` requires no special tooling.

Alternatives considered:

- **Require the trigger commit to carry at least one file
  change.** Forces authors to bundle a meaningless edit with the
  trigger, adding noise. Rejected.
- **Provide a `remcc trigger` helper script.** Yet another tool
  to install. Rejected; `git commit --allow-empty` is already in
  every operator's shell.

### D6. The change name still comes from the branch

The branch `change/<name>` continues to be the source of the
change name. The "Resolve change name" step simplifies to just
the branch-ref derivation (no `INPUT_CHANGE_NAME` fallback). The
text after `@change-apply` in the trigger commit is not parsed
for a change name — the branch is the contract. The shared word
"change" between `change/<name>` and `@change-apply` is
intentional pairing, not a parse target.

Rationale: a single source of truth for which change is being
applied. If the author wanted to apply a different change, they'd
check out that change's branch.

### D7. Concurrency group is partitioned by trigger-vs-noop

Discovered during the dogfood: the original concurrency block
(`group: opsx-apply-${{ github.ref }}` with `cancel-in-progress:
true`) caused the bot's own output push to cancel the parent run
on its way out. GitHub Actions evaluates concurrency at the
listener level, *before* the job-level `if:`, so even a push that
will be skipped by the gate participates in the group and triggers
the cancel. The parent run completed all its steps successfully,
but its overall conclusion was stamped `cancelled` — confusing in
the Actions UI.

The fix: partition the group by whether the head commit subject
opts into apply.

```yaml
concurrency:
  group: opsx-apply-${{ github.ref }}-${{ startsWith(github.event.head_commit.message, '@change-apply') && 'apply' || 'noop' }}
  cancel-in-progress: true
```

Effect:

- **Trigger push** (`@change-apply...`) → group `...-apply`.
- **Bot's output push** (`/opsx:apply <name>`) → group `...-noop`,
  separate from any in-flight apply, no cancellation.
- **WIP push** (anything else) → group `...-noop`, also separate
  from any in-flight apply, no cancellation. This also fixes a
  pre-existing bug where pushing a draft commit while an apply
  was running cancelled it.
- **Fresh `@change-apply: retry`** during in-flight apply → both
  in `...-apply` group, `cancel-in-progress: true` cancels the
  stale run as intended.

Rationale: keeps `cancel-in-progress: true` for the legitimate
"author replaces stale apply with fresh trigger" case, while
isolating non-trigger pushes from the cancellation mechanism. One
extra YAML expression, no behavioural regression for any case
that was working before.

Edge case: a case-typo (`@Change-Apply: ...`) lands in the
`...-apply` group too — `startsWith()` is case-insensitive — so
a typo arriving mid-flight cancels a legit in-flight apply. The
typo's own apply step is then skipped by the case-sensitive guard
(see D1's case-sensitivity gap). Net result is one cancelled
legit run; the author re-pushes a properly-cased trigger to
recover. Documented but not specially mitigated, since case-typos
are rare and the cost is one cancelled run rather than wasted
spend.

Alternatives considered:

- **Drop `cancel-in-progress`.** Bot push and WIP push no longer
  cancel anything; they queue and skip. But a fresh `@change-apply:
  retry` mid-flight then waits for the stale apply to complete,
  paying full token cost on stale state. Rejected — the
  retry-mid-flight optimisation is the reason
  `cancel-in-progress: true` exists in the first place.
- **`[skip ci]` in the bot's commit subject.** GitHub honors the
  magic string and the bot's push wouldn't fire the listener at
  all. Tiny change. Rejected because it doesn't fix the broader
  WIP-push-during-apply case, and it depends on documented-but-
  not-contractual GitHub behaviour.
- **SHA-based group key (`group: ...-${{ github.sha }}`).** Every
  push gets its own group; `cancel-in-progress` becomes a no-op.
  Rejected — same reason as dropping cancel-in-progress.
- **Step-level "did the branch move past me?" abort.** Apply step
  starts with `git fetch && [ HEAD = origin/branch ] || exit 0`.
  Lets `cancel-in-progress: false` ship while still aborting stale
  work. Rejected — adds runtime complexity and the abort happens
  *after* runner provisioning, so it's strictly more expensive
  than `cancel-in-progress: true` for the retry-mid-flight case.

### D8. Documentation surface

`docs/SETUP.md`:

- Rewrites the existing "How to trigger a run" section around the
  opt-in magic-word convention.
- Removes the manual-dispatch walkthrough.
- Adds the `git commit --allow-empty -m "@change-apply: <reason>"`
  idiom as the canonical trigger; notes that
  `@change-apply(<reason>)`, `@change-apply <reason>`, or bare
  `@change-apply` all work — the magic word at the start is the
  only contract.
- Adds a short "Iterating on a change" subsection that walks the
  loop: WIP commits → trigger commit → review PR → more WIP →
  another trigger commit.
- Notes that pushing a `@change-apply...` commit to a non-
  `change/**` branch does nothing (the push trigger's branch
  filter still applies).
- Notes the loose prefix match (subjects like
  `@change-applying-fixes` would also trigger) and that this is
  effectively unreachable in practice because natural commit
  subjects don't start with `@`.

`docs/COSTS.md`:

- Notes that the new trigger model removes the floor cost of
  "every push to a change branch costs an apply run." Drafts and
  collaboration are free.
- The "retry with a different model" path becomes one commit
  (`@change-apply: retry with opus` + `Opsx-Model: opus` trailer)
  rather than a dispatch.

## Risks / Trade-offs

- **Authors forget to push the trigger commit** → The branch sits
  unapplied indefinitely. Mitigated by the new SETUP.md walkthrough
  making the trigger commit the explicit "go" step, and by the PR
  UI showing the branch as having no apply runs (which is the
  desired behaviour for drafts, but may confuse new adopters).
- **Authors push the trigger commit prematurely** → The agent
  runs against a half-finished proposal. Mitigated by the trigger
  being a deliberate action (an explicit commit) — same cost as
  today's accidental push trigger, but now under direct author
  control. The author can also force-push to amend the trigger
  commit to a non-trigger subject before the workflow starts; in
  practice the GitHub Actions queue is fast enough that this is a
  ~10-second window.
- **Trigger subject typos silently no-op** →
  `@change_apply: retry` or `change-apply: retry` (missing `@`)
  does not trigger. Mitigated by the canonical idiom being
  copy-paste from SETUP.md, and by the "no run started" feedback
  being itself a signal that something is off.

- **Loose prefix matches edge-case subjects** →
  `@change-applying-changes` or `@change-apply2bar` would also
  trigger (they start with the magic byte sequence). The
  `@`-prefix makes such subjects functionally unreachable in
  natural use, so this is documented but not specially
  mitigated.
- **No GitHub-UI trigger path** → An operator who's locked out of
  their terminal can't trigger a run. Mitigated by the operator
  being able to write the trigger commit via the GitHub web UI's
  edit-file flow (commit a tiny edit with the right subject); the
  workflow doesn't care how the commit was authored. Out of scope
  to optimise further.
- **Implicit self-loop guard depends on the bot's commit subject
  template** → If a future change makes the bot commit with a
  subject starting `@change-apply`, every apply run re-triggers
  forever. Mitigated by adding a tasks-md gate that the bot's
  commit template MUST NOT match the trigger prefix, plus a
  workflow-side unit-style check (a `grep` in the
  "Stage and commit agent output" step that fails the run if the
  generated subject would match the trigger).
- **`change/**` is a hard-coded branch filter** → Operators
  using a different branch convention won't trigger at all. Same
  constraint as today; not introduced by this change. Documented
  in SETUP.md.

## Migration Plan

remcc itself does not run `/opsx:apply` (per the existing v1
non-recursion decision). The migration is adopter-facing only:

1. Adopters re-copy `templates/workflows/opsx-apply.yml`. Existing
   change branches stop re-triggering on every push immediately;
   no harm, just quieter.
2. To trigger an apply run on an existing in-flight change
   branch, the operator pushes a new commit whose subject starts
   with `@change-apply`. The canonical idiom is `git commit
   --allow-empty -m "@change-apply: first pass"`.
3. To roll back, the adopter restores the previous workflow file.
   The trigger commits left behind in branch history are
   harmless — they just look like normal commits.

## Open Questions

(none — the user clarified the trigger shape, the trailer
behaviour, and the rename)
