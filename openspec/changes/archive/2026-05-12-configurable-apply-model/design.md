## Context

The apply workflow today invokes `claude
--dangerously-skip-permissions -p "/opsx:apply <name>"` with no
`--model` and no thinking-budget control. Whatever defaults Claude
Code applies are what every change pays for, and the only way to
change them is to edit the workflow file in the adopter repo.

Two things motivate explicit control:

1. **Cost / quality trade-off per change.** A typo-fix change in
   docs and a multi-file architectural refactor have very different
   right answers for model and depth-of-thinking, and the operator
   is the only one who knows in advance which is which.

2. **Two trigger modes need parity.** Push to `change/**` is the
   primary trigger, but `workflow_dispatch` is the manual rerun
   path. Both need to accept overrides; otherwise the operator
   pushes a no-op commit just to change the model.

The distribution model is unchanged: copy-paste template,
idempotent `gh-bootstrap.sh`. New defaults belong in a place the
operator can change without re-copying the workflow, which points
at GitHub repository variables (not env hardcoded in the YAML).

## Goals / Non-Goals

**Goals:**

- A repo-level default for `model` and `effort` that the operator
  sets once and rarely revisits.
- A per-run override path for both manual dispatch and ordinary
  push triggers, with a clear precedence rule.
- Defaults baked into the workflow so a freshly copied template
  works on a repo whose `gh-bootstrap.sh` step set no variables.
- PR body records the resolved values, so a reader of the PR can
  tell what was used without digging into the run logs.

**Non-Goals:**

- A model picker per task within a single change. The apply step
  is one invocation; one model, one effort per run.
- An auto-tuner that picks a model based on change size. The
  operator decides; remcc just plumbs the choice.
- A separate "verify model" or "review model" — out of scope until
  remcc grows a CI-side verify step (and `/opsx:verify` is
  explicitly not a workflow gate per the existing `apply-workflow`
  spec).
- A per-change config file (`openspec/changes/<name>/.opsx-apply.yml`
  or similar). Considered and rejected in D3.
- Validating the supplied model name against an allowlist of
  Claude models. Claude Code itself will error if the name is
  bogus; an allowlist in remcc would lag every model release.

## Decisions

### D1. Defaults sourced from GitHub repository variables

The workflow reads `vars.OPSX_APPLY_MODEL` and
`vars.OPSX_APPLY_EFFORT` for its defaults. If a variable is empty or
unset, the workflow falls back to `sonnet` / `high` baked into the
YAML.

Rationale: repo variables are change-able without touching the
workflow file (`gh variable set OPSX_APPLY_MODEL --body opus`), are
visible in the GitHub UI under Settings → Variables, and are not
secrets — exactly the right primitive for non-secret, repo-level
configuration. Hardcoded fallbacks mean a freshly copied template
works on day zero, before the operator has run bootstrap.

Alternatives considered:

- **Env block in the workflow YAML.** Requires editing the workflow
  file to change the default, which conflicts with the copy-paste
  distribution model. Rejected.
- **`.opsx-apply.yml` checked into the repo root.** Same friction
  as editing the workflow plus introduces a new config file format
  remcc owns. Rejected.
- **Both vars and YAML env, with vars winning.** Considered, kept
  in spirit: the YAML carries a hardcoded fallback for the
  unset-variable case but is not the primary surface.

### D2. Override precedence: dispatch input > commit trailer > vars > baked default

The workflow resolves `model` and `effort` independently, top to
bottom:

1. If `workflow_dispatch` was used and the corresponding input
   (`model`, `effort`) is non-empty, use it.
2. Else, if the head commit message contains a trailer
   (`Opsx-Model: <value>` or `Opsx-Effort: <value>`), use the
   trailer value.
3. Else, if the corresponding repo variable is non-empty, use it.
4. Else, use the baked-in default (`sonnet` for model, `high` for
   effort).

`model` and `effort` resolve independently — the operator can
override one without the other.

Rationale: dispatch is a deliberate human action with explicit
intent and should win. Commit trailers are the in-band override
for push triggers, requiring no UI but sticking to the change in
git history. Vars are the repo default. Baked-in default is the
safety net for unconfigured repos.

Alternatives considered:

- **Per-change file in `openspec/changes/<name>/`.** Lives close
  to the artifacts but adds a new file format and an extra step
  per change. Rejected; the commit trailer covers the same need
  with less ceremony.
- **PR comment slash-command (`/opsx-apply-model opus`).** Adds a
  re-trigger path that doesn't fit the current "push to change
  branch = one run" mental model. Rejected.

### D3. `effort` is the Claude Code thinking budget

remcc treats `effort` as a small enum (`low`, `medium`, `high`)
that maps to whatever Claude Code's current "thinking budget" CLI
surface is. The enum is what operators set; the flag is what the
workflow constructs.

At implementation time, the current Claude Code CLI exposes
`--effort <level>` with accepted levels `low`, `medium`, `high`,
`xhigh`, `max`. remcc's enum is a subset that maps 1:1 to the
first three: the workflow appends `--effort low`,
`--effort medium`, or `--effort high` to the `claude` invocation.
remcc intentionally does not surface `xhigh`/`max` in v1 — adding
them later is a strict extension of the enum, and keeping the
public surface to three levels keeps cost intuition simple
(`low` < `medium` < `high`).

Rationale: the enum is forward-compatible with future Claude Code
flag renames — the spec contract is "high effort means more
thinking budget than low effort," not a specific flag name. If
Claude Code retires `--effort`, only the small `case` block in the
workflow has to change.

Alternatives considered:

- **Drop `effort` entirely, only support `--model`.** Simpler, but
  the user explicitly asked for both knobs and Sonnet-with-high-
  effort vs Sonnet-with-low-effort is a real trade-off.
- **Opaque CLI-args string.** Maximum flexibility, but ships the
  Claude Code flag surface through to the operator with no
  abstraction; defeats the point of having a default.

### D4. Resolved values surface in the PR body and logs

The workflow records the resolved `model` and `effort` in the PR
body next to the apply/validate exit codes, and echoes them at the
top of `apply.log` (without echoing the API key). Comments on
existing PRs (the rerun path) include the values for that run too.

Rationale: a PR reader should be able to answer "what did this
run use?" without opening the run logs. For runs that comment
rather than open a PR, the comment carries the same information,
preserving the audit trail for reruns with different settings.

### D5. Bootstrap writes variables; does not block on them

`gh-bootstrap.sh` gains a new step that prompts for (or reads from
env) `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` and writes them as
repo variables via `gh variable set`. The prompts accept empty
input, in which case the variable is not written and the
workflow's baked-in default takes over for that knob.

Rationale: the variable layer is convenience, not contract. A
bootstrap that pre-empts the operator with `sonnet` / `high`
duplicates the workflow's baked-in defaults; one that prompts and
allows empty input lets the operator opt in only when they want a
non-default. Idempotency: writing the same value twice is a no-op.

### D6. No validation of `model`; light validation of `effort`

The workflow does not validate the model name. If the operator
supplies `gpt-5-turbo`, the `claude` CLI will fail at invocation
and the workflow's existing failure path (draft PR, exit code in
body) surfaces the error cleanly.

The workflow does validate `effort` against the enum
{`low`, `medium`, `high`} and fails early with a clear message if
the resolved value is something else — because an unrecognised
effort can't be translated into a flag and would otherwise produce
a confusing CLI error.

Rationale: model names change frequently; an allowlist in remcc
would lag every Claude release. `effort` is a remcc-owned
abstraction, so remcc owns the enum.

## Risks / Trade-offs

- **Commit-trailer parsing surface area** → A subtle bug in
  trailer extraction could silently use the wrong model. Mitigated
  by using `git interpret-trailers` (or an equivalent strict
  parser) rather than ad-hoc regex, and by surfacing the resolved
  values in the PR body so a wrong override is visible.

- **Variable visibility for forks/PRs from forks** → Repository
  variables are not exposed to workflow runs from forked PRs by
  default. The workflow only fires on push to `change/**` in the
  repo itself (per `apply-workflow`'s existing trigger model), so
  forks are out of scope; documented in SETUP.md for completeness.

- **Effort enum drift** → If Claude Code retires its
  thinking-budget surface or replaces it with something differently
  shaped, the enum-to-flag mapping breaks. Mitigated by keeping
  the mapping in one place in the workflow (a small shell case
  statement), so a future change can swap it cleanly.

- **Cost cliff from a misconfigured override** → A typo'd
  `Opsx-Model: opus-99` in a commit message could route an
  expensive run before the human notices. Mitigated by the PR body
  showing the resolved model, the Anthropic admin-console budget
  cap (per `apply-workflow`'s existing cost-ceiling decision), and
  the workflow's 180-minute timeout.

- **Default change for existing adopters** → After this change
  lands, any adopter who re-copies the workflow gets `sonnet` +
  `high` explicitly, which may differ from Claude Code's implicit
  default at the time of original adoption. Mitigated by the
  resolved values being visible in the PR body and by the
  defaults being themselves overridable via vars/dispatch/trailer.

## Migration Plan

remcc itself does not run `/opsx:apply` (per the existing v1
non-recursion decision). The "migration" is just adopter-facing:

1. Adopters who re-copy the workflow file pick up the new
   resolution logic. With no variables set and no overrides, they
   get `sonnet` + `high`.
2. To take advantage of the new surface, an adopter runs the
   updated `gh-bootstrap.sh` (or `gh variable set` manually) to
   set `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT`.
3. There is nothing to roll back: removing the variables reverts
   the default, removing the workflow update reverts the feature.

## Open Questions

(none — D3 records the resolved flag and enum mapping)
