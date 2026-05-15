## Context

`templates/gh-bootstrap.sh` currently maintains three independent
GitHub-side controls on every adopter:

1. **Branch protection on `main`** via the legacy
   `/repos/{owner}/{repo}/branches/main/protection` endpoint. Blocks
   direct push, force-push, deletion; requires a PR for merge but
   sets `required_approving_review_count: 0`.
2. **Branch ruleset** named `remcc: restrict bot to change branches`
   confining non-admin actors (the bot) to `refs/heads/change/**`.
3. **Push ruleset** named `remcc: block bot edits under .github`
   blocking non-admin modifications under `.github/**`. Org-owned
   only — user-owned adopters get a warning and an empty slot.

Each control has its own JSON body, its own reconciler, its own
uninstall path, its own snapshot section, and (for #3) its own
user-vs-org-owned branching. The merge gate for `main`, however, is
identical in all three configurations: every change reaches `main`
through a PR that a human (the operator) reviews. The ruleset and
protection layers add ref/path-level interdiction *before* PR
review; they do not enforce review itself.

The user has decided to change the **default applied to new
adopters** to a single main-branch ruleset that enforces "PR + one
approval" and to drop the bot-side interdiction from that default.
Existing adopters are explicitly out of scope: the bootstrap MUST
NOT mutate any pre-existing branch protection or remcc-managed
rulesets. Adopters who want the new model opt in manually.

## Goals / Non-Goals

**Goals:**

- Make a single branch ruleset on the default branch (`~DEFAULT_BRANCH`)
  that requires a PR and ≥1 approval to merge and blocks
  force-push the only GitHub-side protection the bootstrap installs
  on new adopters. The ruleset does **not** block deletion of the
  default branch.
- Make `gh-bootstrap.sh` install/uninstall paths reconcile only
  this new ruleset; remove all code that touches
  `branches/main/protection` or the two legacy ruleset names.
- Keep behaviour uniform between user-owned and org-owned adopters
  (no more org-only push ruleset branch).
- Keep the bootstrap idempotent: re-running on a fresh adopter
  produces no diffs in the idempotency snapshot, which now covers
  only the new ruleset.

**Non-Goals:**

- Blocking deletion of the default branch via this ruleset. The
  user explicitly scoped the rule to PR-required, one-approval,
  and force-push-block only. Operators who want to also block
  deletion can add it in the GitHub UI.
- **Any modification of existing adopters' state.** The bootstrap
  SHALL NOT delete, edit, or migrate branch protection on `main`,
  the legacy `remcc: restrict bot to change branches` ruleset, or
  the legacy `remcc: block bot edits under .github` ruleset on any
  repository. Re-running the updated bootstrap on an old adopter
  layers the new ruleset on top of whatever already exists; legacy
  items remain in place until the operator removes them by hand.
- CODEOWNERS-based approval routing. The new ruleset requires one
  approval from any user with read access, not a code-owner.
- Higher approval counts, stale-review dismissal, status-check
  gating, signed-commit enforcement, or required linear history.
- Any bot-side branch confinement. The bot is no longer prevented
  at the ref level from pushing outside `change/**` or at the path
  level from touching `.github/**`. PR review on merge is the
  single gate.
- Changes to secret scanning, Actions PR-creation permission, or
  any of the secrets/variables the bootstrap manages.

## Decisions

### Use a branch ruleset for the new control, not legacy branch protection

GitHub exposes two equivalent surfaces for protecting a branch:
the legacy `branches/<name>/protection` endpoint and the modern
`rulesets` endpoint. We pick the ruleset surface for the new
control because:

- The reconciler (`reconcile_ruleset`, `find_ruleset_id`) is
  already written and exercised by the idempotency smoke test.
- Rulesets support bypass-actor configuration uniformly; legacy
  branch protection's `enforce_admins: false` is a coarser
  mechanism.
- Using only one surface lets us delete the legacy
  `branches/main/protection` code path entirely (no callers).

Alternative: keep using legacy branch protection on `main` and
add a `required_approving_review_count: 1` field. Rejected: it
would leave the snapshot still touching two surfaces, and the
`branches/main/protection` code would survive even though no
non-legacy code path needs it.

### Ruleset configuration

- **Name**: `remcc: require approval on main`. Distinct from the
  two legacy names so the new control is identifiable in the
  GitHub UI and in `gh api .../rulesets` output. Note: this is
  for identification only — the bootstrap does not look at legacy
  names at all (see next decision).
- **Target**: `branch`.
- **Conditions**: `ref_name.include: ["~DEFAULT_BRANCH"]`, `exclude: []`.
  `~DEFAULT_BRANCH` resolves to whatever the repo's default branch is at
  evaluation time; if an adopter renames `main` later, the
  ruleset follows.
- **Rules**: `pull_request` with `required_approving_review_count:
  1` and `dismiss_stale_reviews_on_push: false`,
  `require_code_owner_review: false`,
  `require_last_push_approval: false`; plus `non_fast_forward`.
  Force-push to the default branch is blocked. Deletion is
  deliberately **not** included as a rule — out of scope for this
  change.
- **Bypass actors**: admin (`actor_id: 5`, `actor_type:
  RepositoryRole`, `bypass_mode: always`), matching the existing
  pattern. The operator (admin) can still merge their own PRs and
  perform emergency operations.

### Bootstrap does NOT touch existing/legacy controls

The install path reconciles only the new ruleset. It does not
inspect, list, delete, or modify:

- The legacy `branches/<repo>/main/protection` endpoint.
- Rulesets named `remcc: restrict bot to change branches`.
- Rulesets named `remcc: block bot edits under .github`.

The uninstall path symmetrically removes only the new ruleset.
Operators on the legacy bootstrap who want to converge to the new
model do so manually: delete the legacy items in the GitHub UI,
then re-run the updated bootstrap.

Alternative considered: install path also removes legacy items
as a one-shot migration. **Rejected** by user directive — this
change is scoped to the new-adopter default; mutating existing
state is out of scope.

Consequence: an old adopter who re-runs the updated bootstrap
ends up with the new ruleset *plus* their pre-existing legacy
controls. This is a deliberate non-mutation choice; the resulting
state is more restrictive than the new default, not less, so it
is safe.

### Idempotency snapshot

`snapshot_state` collapses three sections (branch protection,
branch ruleset, push ruleset) into one (the new ruleset). The
snapshot is now scoped to "what this script installs" — it does
not include legacy items that the script no longer manages. On a
mixed-state repo (new ruleset + leftover legacy), the
idempotency check verifies only the new ruleset's stability.

### Uninstall

`uninstall_remcc` removes the new ruleset by name. It does not
remove legacy rulesets or branch protection — those are not
"managed by this version of the script" and the user directive
forbids touching them.

## Risks / Trade-offs

- **New adopters: the bot can push to any non-default branch and
  modify any path including `.github/**`** → Mitigation: every
  merge to the default branch requires a human approval;
  `docs/SECURITY.md` is updated to call out PR review as the
  single gate and removes the defense-in-depth claims tied to the
  two dropped controls.

- **Old adopters who re-run the updated bootstrap end up with a
  hybrid state** (new ruleset layered on top of legacy controls).
  → Mitigation: documented in `docs/SECURITY.md` and
  `docs/SETUP.md` as the expected behaviour. Hybrid state is
  strictly more restrictive than the new default, so it is safe
  — just untidy. Operators who want the clean new-default state
  remove the legacy items in the GitHub UI before re-running.

- **Old adopters who `--uninstall` the updated bootstrap leave
  legacy rulesets and branch protection behind.** → Mitigation:
  documented as a known limitation in `docs/SETUP.md`'s uninstall
  section. The legacy controls are static GitHub state that can
  be removed in the UI in seconds; the cost of a partially clean
  uninstall is small compared to the cost of an unwanted state
  mutation.

- **`required_approving_review_count: 1` doesn't dismiss stale
  approvals on new pushes** → Acknowledged. The prior model
  didn't enforce that either; out of scope.

- **`~DEFAULT_BRANCH` semantics differ from `refs/heads/main`** if an
  adopter has renamed their default branch. The prior controls
  hardcoded `main` in the branch-protection endpoint path. Using
  `~DEFAULT_BRANCH` is a deliberate generalisation — the ruleset
  protects whatever the operator has chosen as default.

## Migration Plan

1. Land this change: update bootstrap, spec, and docs in one PR.
2. New adopters: get the single-ruleset model on first
   `gh-bootstrap.sh` run.
3. Existing adopters: no automatic migration. To opt in: open
   GitHub → Settings → Rules → Rulesets and delete `remcc:
   restrict bot to change branches` and `remcc: block bot edits
   under .github`; open Settings → Branches and remove
   protection on `main`; then re-run the updated
   `gh-bootstrap.sh`. Documented in `docs/SETUP.md`.
4. Rollback for new adopters: `gh-bootstrap.sh --uninstall`
   removes the new ruleset; `git revert` this PR and re-run the
   prior bootstrap to restore the layered model.

## Open Questions

None blocking. Reviewer call: should `docs/SETUP.md`'s upgrade
section include an explicit "how to opt in to the new model"
recipe for legacy adopters, or just a one-line pointer to the
GitHub UI? Default in `tasks.md`: include the short recipe so
operators don't have to reverse-engineer it.
