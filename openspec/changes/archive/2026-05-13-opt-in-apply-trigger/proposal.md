## Why

The apply workflow today runs on every push to `change/**` and on
`workflow_dispatch`. Both triggers are too eager:

- A change branch is a working surface, not a "ready to apply"
  signal. Authors want to push WIP scaffolding, iterate on the
  proposal, collaborate with co-authors, and queue commits — none
  of which should burn an apply run.
- Re-applying after seeing the agent's first pass is a normal part
  of the loop (extend tasks, push, let the agent implement the
  delta). Today the only way to do that is push *any* commit and
  hope it's the one that triggers, then deal with the bot-self-loop
  and the noise from every intermediate push.
- `workflow_dispatch` is a parallel trigger surface that duplicates
  per-run override knobs (model, effort) already available via
  commit trailers, and forces operators to context-switch from git
  to the GitHub UI.

The cleaner mental model is: apply runs when the author **asks it
to**, by writing one commit whose subject says so. Everything else
on the branch is "draft work" and is ignored by the workflow.

## What Changes

- **Trigger surface narrows to one rule.** The workflow runs the
  apply step if and only if the head commit on the pushed
  `change/**` ref has a subject line that starts with the magic
  word `@change-apply`. The `@`-prefixed token pairs visually
  with the `change/` branch name (both refer to the change being
  worked on), is highly unlikely to occur at the start of any
  natural commit subject, and has no shell-history footgun
  (unlike a leading `!`). Whatever follows the magic word —
  `: foo bar`, `(foo bar)`, ` foo bar`, or nothing — is the
  author's free-form description. The workflow does not parse it.
- **`workflow_dispatch` is removed entirely**, along with its
  `change_name`, `model`, and `effort` inputs. The "Manual
  dispatch with explicit change name" and "Manual dispatch inputs
  override defaults" requirements in the `apply-workflow` spec are
  removed. The "Override precedence" requirement is simplified to
  two levels: commit trailer > repository variable > baked default.
- **The push trigger keeps the `change/**` filter** for cheap
  branch scoping, but pushes whose head commit doesn't carry the
  trigger token are a clean no-op — the job either doesn't start
  (via job-level `if:`) or starts and exits immediately after the
  trigger check.
- **The change name still comes from the branch ref** (`change/foo`
  → `foo`). The parenthesised description is for humans only and
  is not used to resolve the change name.
- **Self-loop prevention is automatic.** The bot's apply-output
  commit message starts with `/opsx:apply <name>`, not
  `@change-apply`, so it never re-triggers. The existing
  `head_commit.author.name != 'github-actions[bot]'` guard becomes
  redundant and is removed.
- **Per-run model/effort overrides remain via commit trailers** on
  the apply-triggering commit. `Opsx-Model:` and `Opsx-Effort:`
  trailers are unchanged in syntax and precedence (now top of the
  override chain since dispatch is gone).
- **Documentation walks the new loop**: write the change proposal,
  push WIP commits as much as needed, then write the apply commit
  (`git commit --allow-empty -m "@change-apply: first pass"` is
  the canonical idiom; `@change-apply(first pass)` or any other
  shape starting with `@change-apply` works too) when ready. To
  re-apply after extending tasks or fixing verify findings, push
  another commit whose subject starts with `@change-apply` (empty
  or not) — the agent picks up the current state of the branch.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `apply-workflow`: trigger model changes from "push to `change/**`
  always runs apply" to "push to `change/**` runs apply only when
  the head commit subject starts with `@change-apply`"; the
  manual dispatch trigger and its inputs are removed; change-name
  resolution drops the dispatch fallback; override precedence
  drops the dispatch level. All other behaviours (validate,
  commit, push, PR open/comment, draft on failure, log artifact,
  concurrency, timeout, secret plumbing) stay as is.

## Impact

- `templates/workflows/opsx-apply.yml`: the `workflow_dispatch:`
  block is removed; the existing bot-author `if:` condition is
  replaced with
  `if: startsWith(github.event.head_commit.message, '@change-apply')`;
  the "Resolve change name" step drops its `INPUT_CHANGE_NAME`
  branch; the "Resolve apply config" step drops its `INPUT_MODEL`
  and `INPUT_EFFORT` branches. The workflow filename and the
  internal `/opsx:apply` command name are unchanged — `@change-apply`
  is only the commit-subject trigger word.
- `templates/gh-bootstrap.sh`: no behavioural change. The script
  still installs `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT`
  repository variables; those remain meaningful as the per-repo
  default.
- `docs/SETUP.md`: rewrites the "How to trigger a run" section
  around the opt-in convention; removes the manual-dispatch
  walkthrough; adds the `git commit --allow-empty` idiom for
  triggering re-apply runs; explains that draft/WIP commits in
  between are free.
- `docs/COSTS.md`: tightens the cost story — operators no longer
  pay for accidental apply runs on every WIP push, and the
  "retry with a different model" path is one commit, not one
  GitHub UI dispatch.
- Operator workflow: the canonical loop becomes (a) push WIP
  commits freely, (b) when ready, `git commit --allow-empty -m
  "@change-apply: first pass"` and push, (c) review the PR, (d)
  if re-applying, push more WIP if needed, then another commit
  starting with `@change-apply` (e.g. `@change-apply: retry with
  feedback`). There is no marker file, no skip token, no force
  trailer — the trigger *is* the opt-in signal.
- No change for adopters beyond re-copying the workflow file.
  Existing change branches will simply stop re-triggering on
  every push, which is the desired behaviour.
