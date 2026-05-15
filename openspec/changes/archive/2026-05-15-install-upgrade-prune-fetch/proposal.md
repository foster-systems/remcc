## Why

After an adopter merges a `remcc-upgrade` PR, GitHub's default
post-merge cleanup deletes the remote `remcc-upgrade` branch. The
operator's local clone still holds `refs/remotes/origin/remcc-upgrade`
pointing at the old commit. The next `install.sh upgrade` run does
`git fetch origin remcc-upgrade` (without `--prune`) which is a no-op
for a now-missing branch — the stale local tracking ref survives. The
subsequent `git push --force-with-lease -u origin remcc-upgrade` then
refuses with `stale info`, because the lease asserts the remote still
holds the commit named by the local tracking ref, and the remote has
nothing. Result: the second upgrade against the same adopter aborts
with a confusing error that has nothing to do with the actual remote
state. Observed today on `foster-systems/foster-systems` immediately
after merging the v0.5.0 upgrade PR.

## What Changes

- `install.sh`'s `push_and_open_upgrade_pr` SHALL prune stale local
  tracking refs for the upgrade branch before the force-with-lease
  push. Concretely: the pre-push `git fetch origin "${UPGRADE_BRANCH}"`
  gains `--prune` (or equivalently fetches with a refspec that prunes
  the single ref), so a remote-side post-merge deletion is reflected
  locally before the lease is computed.
- The `remcc-cli` spec's "install.sh upgrade opens a single reused
  branch pull request" requirement gains one normative scenario
  covering the "previously-merged-and-deleted upgrade branch" case,
  so future refactors can't regress this behaviour silently.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `remcc-cli`: extends "install.sh upgrade opens a single reused
  branch pull request" with stale-tracking-ref pruning semantics and
  a scenario asserting a second upgrade after a merge succeeds.

## Impact

- **Code** (`install.sh`): one-line change to the `git fetch` call
  inside `push_and_open_upgrade_pr`. No behavioural change for the
  open-PR-rerun case (the lease still protects the branch tip).
- **Spec** (`openspec/specs/remcc-cli/spec.md`): one modified
  requirement, one new scenario.
- **Adopters**: pick up the fix on their next `install.sh upgrade`
  via the existing upgrade flow. No new install step, no new secret,
  no new repository variable.
- **No change** to: the upgrade PR title/body format, the
  force-with-lease semantics for an open-PR-rerun, the `installed_at`
  preservation logic, the prerequisite verifier, or any GitHub-side
  configuration.

## Non-goals

- No broader refactor of the upgrade flow's git operations.
- No removal of `--force-with-lease` from the push. The lease still
  protects an open-PR-rerun case where a concurrent operator updated
  the branch tip out-of-band; pruning is strictly additive.
- No new flag, no new env var. The fix is unconditional.
