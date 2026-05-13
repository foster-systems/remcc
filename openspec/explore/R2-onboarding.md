# R2 — Automate onboarding and update delivery

> Status: **explore in progress** (started 2026-05-13). No proposal yet.
> Resume by reading this file, then `/opsx:explore` to continue.

## Roadmap one-liner

> Automate onboarding and delivery of updates for adopter repos, making
> it as easy as possible (e.g. run one script, minimize manual actions).

## Today's adoption journey

Eight manual touches, condensed from `docs/SETUP.md`:

1. Eyeball-verify 7 prerequisites.
2. Copy `templates/workflows/opsx-apply.yml` into `.github/workflows/`.
3. Decide whether/how to merge `templates/claude/settings.json`.
4. Decide whether/how to merge `templates/openspec/config.yaml`
   ("merge the remcc baseline block into your `rules.tasks:`, don't
   duplicate top-level keys" — human-judgment merge).
5. Create a `setup-remcc` *regular* feature branch, PR it to main,
   merge. Must not be `change/**` — the ruleset isn't in place yet,
   and once it is, you'd be blocked from landing the workflow.
6. Glance-verify the workflow YAML.
7. Run `gh-bootstrap.sh` (interactive prompts: API key, model, effort).
8. Manual smoke test (push change branch, push `@change-apply` trigger
   commit, watch Actions tab).

`gh-bootstrap.sh` is already idempotent and tight — it is not the
bottleneck. The friction concentrates in:

- **Template-merge semantics** for `settings.json` and
  `openspec/config.yaml`. Hand-merge YAML is error-prone.
- **Two-clones-side-by-side pattern.** `REMCC=../remcc; cp …` is
  awkward, version-ambiguous, and leaves no breadcrumb of *which*
  remcc commit was adopted.
- **Setup-branch vs change-branch context flip.** Documented but a
  footgun.

## Today's update delivery

Nothing. Once templates are copied, the adopter is frozen at that
remcc commit. Workflow bug fix lands here? Every adopter re-diffs
and re-copies by hand. No version marker in the adopter repo
identifies which remcc snapshot they're running.

## Design space — three composable building blocks

### Block A — Reusable workflow

Move `opsx-apply.yml` into this repo as a callable workflow.
Adopters install a ~10-line shim:

```yaml
jobs:
  apply:
    uses: premeq/remcc/.github/workflows/opsx-apply.yml@v1
    secrets: inherit
    # vars: …  (OPSX_APPLY_MODEL / OPSX_APPLY_EFFORT, etc.)
```

Update path for workflow internals: re-tag `v1` → all adopters pick
up the new code on their next run. Zero copy/paste.

**Cost.** Cross-repo `uses:` runs *our* code in adopter's env. Pin
to commit SHA for security-sensitive cases; document the tradeoff.

### Block B — `gh remcc init` (one-shot onboarding)

A `gh` extension distributed from this repo:

1. Prereq check (replaces the eyeball checklist).
2. Stage files into target repo (writes the shim, merges
   `settings.json` and `openspec/config.yaml` programmatically).
3. Open + auto-merge `setup-remcc` PR.
4. Run `gh-bootstrap.sh` inline.
5. Run smoke test (optional — see open thread).
6. Drop `.remcc/version` marker recording the source tag.

Adopter UX:

```
gh extension install premeq/remcc
cd my-target-repo
gh remcc init
```

One command. Replaces SETUP.md steps 1–4.

### Block C — `gh remcc upgrade` (refresh non-workflow assets)

Reads `.remcc/version`, fetches templates at the latest tag,
three-way merges `settings.json` + `openspec/config.yaml` (showing
diff, asking before applying), updates the shim's `@v1` ref if
needed, bumps `.remcc/version`.

Pull-based, operator-triggered. Enough for v1; adopters can wire
this into Renovate/Dependabot-style schedules later.

## Block dependencies

```
   ┌──────┐
   │  A   │   reusable workflow
   └───┬──┘
       │ defines shim interface
       ▼
   ┌──────┐
   │  B   │   gh remcc init
   └───┬──┘
       │ writes .remcc/version
       ▼
   ┌──────┐
   │  C   │   gh remcc upgrade
   └──────┘
```

A and B can land independently; C depends on B's version marker.
Working hypothesis: split R2 into R2.1 (A), R2.2 (B), R2.3 (C) and
land in order.

## Open threads (awaiting decisions)

**(1) Scope of R2.** All three blocks under one roadmap item, or
split as R2.1 / R2.2 / R2.3 with separate proposals?

**(2) CLI distribution channel.**

| Shape | Install | Update |
|---|---|---|
| `gh` extension | `gh extension install premeq/remcc` | `gh extension upgrade remcc` |
| curl-pipe | `curl … \| sh` | re-run installer |
| npm package | `npm i -g @premeq/remcc` | `npm update -g` |

Leaning `gh` extension (adopters already need `gh` authenticated;
bootstrap is `gh api` end-to-end). Open.

**(3) Shim pin granularity.** `@v1` (major), `@v1.2.3` (exact), or
`@<sha>` (audit-friendly)? Working default: `@v1`, document
SHA-pinning for security-sensitive adopters.

**(4) The settings.json / openspec/config.yaml merge problem.**
Three options:

- A. Refuse to auto-merge — bail and ask operator to merge by hand,
  then re-run. Breaks the one-command promise.
- B. Known-keys merge — we know the exact keys remcc baseline adds;
  merge programmatically (e.g. `yq`), bail loudly on collision.
- C. Move all remcc-managed config into a separate file
  (`openspec/config.remcc.yaml`) loaded alongside the operator's
  own — sidesteps merging entirely **iff OpenSpec supports config
  layering**.

(C) is cleanest if feasible. Needs investigation of OpenSpec's
config loader: single fixed path, or composable?

**(5) Smoke test in `init`.** Triggering a real apply burns
Anthropic tokens (~$0.50–$5). Acceptable cost-of-entry, or stop
short and hand the operator a one-liner to fire it themselves?

## Notes for resume

- Spec files to revisit: `openspec/specs/repo-adoption/spec.md`,
  `openspec/specs/apply-workflow/spec.md`.
- Bootstrap script to factor against: `templates/gh-bootstrap.sh`
  (already idempotent — can be invoked from `gh remcc init`).
- SETUP.md will need a near-rewrite once Block B exists; today's
  step-by-step becomes the "manual fallback" appendix.
- Naming: this repo is `premeq/remcc`. The extension would be
  installed as `gh remcc`. The marker file would be `.remcc/version`.
