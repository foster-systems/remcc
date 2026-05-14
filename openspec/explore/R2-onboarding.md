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
bottleneck. The friction concentrates in template-merge semantics
(steps 3–4), the "two clones side-by-side" pattern (no version
breadcrumb), and the setup-branch / change-branch context flip.

## Today's update delivery

Nothing. Templates are frozen at the remcc commit the adopter copied.
No version marker, no refresh path.

## Decisions made 2026-05-13

- **No reusable workflow.** Block A (cross-repo `uses:`) is rejected:
  introduces a runtime dependency on remcc, supply-chain trust
  escalation, customization loss, and org-allowlist friction. Wins
  the auto-update story but the trust/availability costs outweigh
  the benefit at this project's scale.
- **Copy/paste stays the model.** Templates are physical files in
  the adopter repo. Updates are PRs that overwrite the files; the
  git diff is the conversation. Trust posture is "any other PR."
- **Trust the adopter.** Assume operators review PRs carefully and
  understand the scripts they run. No auto-merge of upgrade PRs,
  no scheduled cron — the operator triggers `gh remcc upgrade` when
  they want it. Stale templates are the operator's problem.
- **First install also uses overwrite-and-PR** (option B from prior
  thread). `gh remcc init` overwrites template-managed files if they
  exist and opens a PR; operator handles any customization
  collisions on their side.

## Approach: two commands, one shape

```
                       gh remcc init                gh remcc upgrade
                       ─────────────                ────────────────
prereqs                check                        skip
bootstrap config       run gh-bootstrap.sh          skip
templates              write all                    overwrite all
.remcc/version         write                        bump
PR                     open & link diff             open & link diff
smoke test             skip (see open thread)       skip
```

Same shape for both: write/overwrite files, open a PR, hand the
diff to the operator. Init does the extra one-time work
(prereq check, bootstrap). Upgrade is init minus the one-time bits.

### `gh remcc init`

One-time onboarding. Replaces SETUP.md steps 1–7.

1. Prereq check (replaces eyeball checklist).
2. Run `gh-bootstrap.sh` (configures GitHub-side controls; idempotent
   so safe to call from init).
3. Create branch `remcc-init` (regular branch, not `change/**`).
4. Write/overwrite template-managed files:
   - `.github/workflows/opsx-apply.yml`
   - `.claude/settings.json`
   - `openspec/config.yaml`
   - `.remcc/version` (marker, records source tag)
5. Commit, push, open PR.
6. Print "review the PR; if any of those files were yours, expect
   collisions in the diff. Merge when satisfied."

### `gh remcc upgrade`

Periodic refresh. Operator runs when they want updates.

1. Read `.remcc/version`.
2. Fetch new templates at the latest remcc tag (or specified ref).
3. If no change, exit (no PR opened).
4. Create branch `remcc-upgrade-<ref>`.
5. Overwrite the same template-managed files.
6. Bump `.remcc/version`.
7. Commit, push, open PR. Body lists files touched and a link to
   the remcc changelog between the previous and new ref.
8. Operator reviews diff, possibly amends to re-apply customizations,
   merges.

## Scope split

Working hypothesis: two changes.

- **R2.1 — `gh remcc init`.** Onboarding automation. Replaces
  SETUP.md steps 1–7. Depends on `.remcc/version` marker design.
- **R2.2 — `gh remcc upgrade`.** Update delivery. Depends on
  R2.1 (the marker, the file list).

R2.1 can ship independently — adopters can use it without ever
calling `upgrade`. R2.2 depends on R2.1 having written the marker.

## Remaining open threads

**(1) Distribution channel.** Lean `gh extension install premeq/remcc`
(adopters already need `gh` authenticated; bootstrap is `gh api`
end-to-end). Open alternatives: curl-pipe install, npm package.

**(2) Smoke test in `init`.** Auto-triggering a real apply burns
Anthropic tokens (~$0.50–$5). Two options: (a) end init at "PR
opened," let operator decide when to smoke-test; (b) prompt
operator whether to also fire a smoke-test apply. Lean (a) — the
PR review is itself the operator's checkpoint, and smoke testing
can be a documented one-liner.

**(3) What goes in `.remcc/version`.** Minimum: source tag/SHA.
Maybe also: list of file paths managed by remcc (so upgrade knows
what to overwrite even if the set changes between versions). Tied
to upgrade's design.

**(4) Templates not currently in `templates/`.** `gh-bootstrap.sh`
itself ships from remcc. Init invokes it inline. Should upgrade
also refresh `gh-bootstrap.sh` if it changes upstream? Probably
yes — but the script isn't copied into the adopter repo today,
it's invoked from a sibling clone. With `gh remcc` as an
extension, the bootstrap logic lives in the extension itself,
not in the adopter repo. Resolves cleanly.

## Notes for resume

- Spec files to revisit: `openspec/specs/repo-adoption/spec.md`,
  `openspec/specs/apply-workflow/spec.md`. Adoption spec will need
  significant rewrites once R2.1 ships.
- `templates/gh-bootstrap.sh` is already idempotent and can be
  invoked from the extension as-is.
- SETUP.md will need a near-rewrite once R2.1 ships; today's
  step-by-step becomes a "manual fallback" appendix for adopters
  who can't or won't install the `gh` extension.
- Naming: repo is `premeq/remcc`; extension installed as
  `gh remcc`; marker file `.remcc/version`.
