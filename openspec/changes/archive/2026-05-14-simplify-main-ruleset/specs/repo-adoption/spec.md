## ADDED Requirements

### Requirement: Bootstrap configures main-branch approval ruleset

`gh-bootstrap.sh` SHALL configure a single repository **branch
ruleset** targeting the repository's default branch **only** —
via the GitHub ruleset condition `ref_name.include: ["~DEFAULT_BRANCH"]`
with `exclude: []` — whose rule set is **exactly** the
following, no more and no less:

- A `pull_request` rule with `required_approving_review_count: 1`
  (requires a pull request and at least one approval to merge
  into the default branch).
- A `non_fast_forward` rule (blocks force-push to the default
  branch).
- `bypass_actors`: the `RepositoryRole` admin (role id `5`) with
  `bypass_mode: always`, so the operator (admin) can still merge
  their own changes and perform emergency operations.

The ruleset SHALL NOT include a `deletion` rule, a
`creation` rule, status-check gating, signed-commit enforcement,
linear-history requirement, or any other rule beyond the two
listed above. Deletion of the default branch is intentionally
not blocked by this ruleset.

The ruleset SHALL be named `remcc: require approval on main` so
the new control is identifiable in the GitHub UI. The ruleset
SHALL apply uniformly to user-owned and organization-owned
repositories — no conditional branching on ownership type.

The bootstrap SHALL NOT modify, delete, or inspect any
pre-existing GitHub-side controls on the target repository,
including (but not limited to) branch protection on `main`
configured via the `branches/main/protection` endpoint and
rulesets named `remcc: restrict bot to change branches` or
`remcc: block bot edits under .github`. The new ruleset is
installed alongside whatever exists; legacy controls remain
untouched until the operator removes them by hand.

#### Scenario: Direct push to default branch is rejected after bootstrap on a new adopter

- **WHEN** the operator runs `gh-bootstrap.sh` on a fresh repo
  that has no pre-existing remcc-managed controls
- **AND** subsequently attempts `git push origin main` from a
  local checkout with new commits as a non-admin actor
- **THEN** GitHub rejects the push citing the ruleset

#### Scenario: PR merge to default branch requires an approval

- **WHEN** the workflow opens a PR targeting the default branch
  and no reviewer has approved it
- **THEN** the merge button is disabled / the merge API call is
  rejected citing the missing approval, regardless of repo
  ownership type

#### Scenario: Force-push to the default branch is rejected

- **WHEN** any actor (including admin via a token without bypass)
  attempts a force-push to the default branch on a repo
  configured by `gh-bootstrap.sh`
- **THEN** GitHub rejects the push citing the ruleset's
  `non_fast_forward` rule

#### Scenario: Deletion of the default branch is not blocked by this ruleset

- **WHEN** an actor with delete permission deletes the default
  branch on a repo whose only remcc-managed control is the new
  ruleset
- **THEN** the deletion succeeds (the ruleset does not include a
  `deletion` rule — out of scope for this change)

#### Scenario: Ruleset does not apply to non-default branches

- **WHEN** a non-admin actor pushes commits to any branch other
  than the default branch (e.g. `change/foo`, `feature/bar`) in a
  repo configured by `gh-bootstrap.sh`
- **THEN** the push is accepted; the approval ruleset does not
  block it (the ruleset's `ref_name.include` is `["~DEFAULT_BRANCH"]`,
  so only the default branch is gated)

#### Scenario: User-owned and org-owned new adopters get identical configuration

- **WHEN** the operator runs `gh-bootstrap.sh` against a
  user-owned repository with no pre-existing remcc-managed
  controls
- **AND** the operator runs `gh-bootstrap.sh` against an
  organization-owned repository with no pre-existing
  remcc-managed controls
- **THEN** both repositories end up with the same `remcc: require
  approval on main` ruleset and no other remcc-managed rulesets

#### Scenario: Re-running bootstrap on an already-bootstrapped new adopter is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` on a repo that
  already has the `remcc: require approval on main` ruleset
- **THEN** the idempotency smoke test passes with no diffs

#### Scenario: Bootstrap does not mutate legacy controls on an old adopter

- **WHEN** the operator runs the updated `gh-bootstrap.sh` on a
  repo that was bootstrapped under the prior three-layer model
  and still has branch protection on `main` plus the two legacy
  rulesets
- **THEN** the script creates the new `remcc: require approval
  on main` ruleset
- **AND** branch protection on `main` is left unchanged
- **AND** the ruleset `remcc: restrict bot to change branches`
  is left unchanged
- **AND** the ruleset `remcc: block bot edits under .github` is
  left unchanged

#### Scenario: Uninstall removes only what this version manages

- **WHEN** the operator runs `gh-bootstrap.sh --uninstall` on a
  repo that has the new ruleset and (optionally) leftover legacy
  controls from a prior bootstrap
- **THEN** the new ruleset `remcc: require approval on main` is
  removed
- **AND** any pre-existing branch protection on `main` or legacy
  rulesets are left in place (the script does not touch them)

## REMOVED Requirements

### Requirement: Bootstrap configures branch protection on main

**Reason**: The default GitHub-side protection installed for new
adopters is now a single branch ruleset on the default branch
(see `Bootstrap configures main-branch approval ruleset`). The
PR-required behaviour is expressed as the ruleset's
`pull_request` rule with `required_approving_review_count: 1`;
force-push is blocked by the `non_fast_forward` rule. The legacy
`branches/main/protection` endpoint is no longer used by the
bootstrap. Note: the new ruleset does **not** block deletion of
the default branch — a deliberate scope narrowing from the prior
model, where branch protection blocked deletion implicitly.

**Migration**: This change is forward-only. Existing adopters'
branch protection on `main` is **not** removed by the updated
bootstrap. Operators who want to converge to the new default open
GitHub → Settings → Branches and remove the protection manually,
then re-run `gh-bootstrap.sh` (which installs the new ruleset).

### Requirement: Bootstrap restricts bot to change/** branches

**Reason**: The bot-side branch confinement is dropped from the
new-adopter default. PR review on merge to the default branch is
now the single gate. The operator's review catches any change
the bot proposes, regardless of which branch the bot pushed to.

**Migration**: This change is forward-only. Existing adopters'
`remcc: restrict bot to change branches` ruleset is **not**
removed by the updated bootstrap. Operators who want to converge
to the new default delete the ruleset manually in GitHub →
Settings → Rules → Rulesets, then re-run `gh-bootstrap.sh`.

### Requirement: Bootstrap configures .github/** push ruleset when supported

**Reason**: The path-level push restriction on `.github/**` is
dropped along with the rest of the bot-side controls. `.github/**`
changes now land via the same PR-review path as any other change.
This also eliminates the user-owned vs organization-owned
asymmetry the original requirement introduced.

**Migration**: This change is forward-only. Existing org-owned
adopters' `remcc: block bot edits under .github` ruleset is
**not** removed by the updated bootstrap. Operators who want to
converge to the new default delete the ruleset manually, then
re-run `gh-bootstrap.sh`. Org-owned adopters who relied on the
push ruleset as a defense-in-depth layer should ensure their PR
review covers `.github/**` diffs explicitly; `docs/SECURITY.md`
is updated accordingly.
