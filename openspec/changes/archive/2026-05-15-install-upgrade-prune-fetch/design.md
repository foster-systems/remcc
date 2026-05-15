## Context

`install.sh upgrade`'s `push_and_open_upgrade_pr` does, in order:

1. `git fetch origin "${UPGRADE_BRANCH}"` (errors swallowed).
2. Compare local `HEAD^{tree}` with `origin/remcc-upgrade^{tree}`; if
   identical, skip the push.
3. Otherwise `git push --force-with-lease -u origin
   "${UPGRADE_BRANCH}"`.

`--force-with-lease` without an explicit `<expected>` argument asserts
that the remote's current `remcc-upgrade` matches whatever the local
`refs/remotes/origin/remcc-upgrade` tracking ref points at. That works
fine on first-ever runs (no tracking ref → lease is trivially
satisfied) and on open-PR-rerun (fetch refreshes the tracking ref to
the current remote tip → lease asserts that tip → push wins). It
breaks in the middle case: the previous upgrade PR was merged and the
remote branch deleted (GitHub's default branch-deletion-on-merge),
but the local clone still has a stale tracking ref pointing at the
pre-merge commit. The next run's bare `git fetch origin
"${UPGRADE_BRANCH}"` does *not* delete missing refs by default — it
only fetches matching refs that exist on the remote, which here is
none. The stale local tracking ref survives, and the subsequent
force-with-lease push fails with `stale info` because the lease
expects the remote to hold the old commit and finds nothing.

This was first reproduced on `foster-systems/foster-systems`
immediately after merging the v0.5.0 upgrade PR; the operator's
re-run of `install.sh upgrade` aborted at the push step. Manual
`git fetch --prune origin` followed by `git push -u origin
remcc-upgrade` (no lease) succeeded, confirming the diagnosis.

## Goals / Non-Goals

**Goals:**

- Make `install.sh upgrade` succeed on the second run against an
  adopter whose first upgrade was merged and whose remote branch
  was deleted by GitHub's post-merge cleanup, without operator
  intervention.
- Preserve the existing `--force-with-lease` protection for the
  open-PR-rerun case (concurrent push from another operator on the
  same `remcc-upgrade` branch).
- Codify the fix in the `remcc-cli` spec so future refactors can't
  silently regress it.

**Non-Goals:**

- No broader rework of the upgrade flow's git plumbing.
- No removal of `--force-with-lease`. The lease still defends
  against accidental clobber when a PR is open and another operator
  has updated the branch tip.
- No new CLI flag or env var to control pruning. The fix is
  unconditional — pruning a missing remote ref is safe even when
  the branch exists (the fetch refreshes it as before).
- No change to the open-PR-rerun semantics: when a PR is open and
  the branch exists on origin, the fetch still refreshes the
  tracking ref and the lease still asserts the current tip.

## Decisions

### Decision: Prune via `--prune` flag on the existing single-branch fetch

Change `git fetch origin "${UPGRADE_BRANCH}"` to
`git fetch --prune origin "${UPGRADE_BRANCH}"`. With a single refspec
argument, `--prune` removes the local tracking ref *for that refspec*
only if the remote no longer has it — exactly the behaviour we want.
No other tracking refs are touched.

**Rationale:** smallest possible diff. Matches git's documented
intent for `--prune`. The fetch already exists in the right place
in the flow (immediately before the push and the tree-compare); a
flag on the same call avoids re-ordering steps or introducing a
second git invocation.

**Alternatives considered:**

- **Drop `--force-with-lease` entirely and rely on `-u origin
  ${UPGRADE_BRANCH}` plus the in-flow open-PR-rerun check.**
  Rejected: removes a real safety net. The lease still catches the
  case where the PR is open and another operator has pushed to
  `remcc-upgrade` between this run's fetch and push. Pruning is a
  precise fix for the precise bug; loosening the safety net is a
  wider change.

- **Explicit `git branch -d -r origin/${UPGRADE_BRANCH}` before the
  fetch, ignoring errors.** Rejected: more lines, same effect, and
  hides the "we fetched and pruned in one step" reading from anyone
  scanning the function later.

- **Fetch with `--force-with-lease=<branch>:''` (empty expected
  value) to assert the remote is absent.** Rejected: that's the
  inverse of what we want — we want the lease to pass in *both*
  cases (absent remote = new branch, present remote = refresh and
  reuse). `--prune` followed by an unparameterised lease gives us
  the right semantics in both branches.

- **Re-clone the target repo for each upgrade run, bypassing the
  operator's local clone entirely.** Rejected: changes the
  operator's working tree model and adds latency. Out of scope.

### Decision: Keep `--prune` scoped to the single `${UPGRADE_BRANCH}` refspec

The fetch passes `"${UPGRADE_BRANCH}"` as a single refspec, so
`--prune` only considers refs matching that refspec. It will not
prune `origin/main`, `origin/change/*`, or any other tracking ref
the operator's clone holds.

**Rationale:** least surprise. An `install.sh` invocation should not
silently mutate the operator's view of unrelated branches. A
broader `git fetch --prune origin` (no refspec) would also fix the
bug but would prune *every* now-missing tracking ref, which can
surprise operators who keep deleted feature branches around for
local archaeology.

**Alternatives considered:**

- **Prune everything (`git fetch --prune origin` with no refspec).**
  Rejected per above.

### Decision: No new test, document the regression in the spec scenario

The spec gets a new scenario in the existing "install.sh upgrade
opens a single reused branch pull request" requirement, asserting
that a second upgrade run after a merge-and-delete cycle pushes the
new tip successfully. Implementation verification is covered by the
spec scenario plus a one-line manual repro on a sandbox repo; no
new automated test.

**Rationale:** matches existing `install.sh` behaviour — its end-to-
end behaviour is exercised by adopter smoke tests, not unit tests.
A scenario in the spec is the long-lived guard against silent
regression; a unit test for "git fetch was called with --prune"
would tautologically lock the implementation without expressing the
intent.

## Risks / Trade-offs

- **[A future operator may rely on stale `origin/remcc-upgrade`
  tracking refs for local diagnostics]** → Mitigation: extremely
  unlikely (the branch is bot-managed and short-lived) and the
  prune only affects that one ref. If an operator wants to keep a
  pointer, they can `git tag` it before re-running upgrade.

- **[`--prune` interaction with credential helpers / shallow
  clones on exotic operator setups]** → Mitigation: `--prune` is a
  pure ref-state operation, independent of credentials and shallow
  history. No known incompatibilities; the existing flow already
  assumes a normal-depth working clone.

- **[Operators on git versions older than ~1.8 lacking
  `--prune` on `fetch`]** → Mitigation: not real — `--prune` has
  been available on `git fetch` since 1.6.5 (2009). Far older than
  any plausible operator environment.

## Migration Plan

1. Update `install.sh` line ~718's fetch to include `--prune`.
2. Update `openspec/specs/remcc-cli/spec.md` via the delta in this
   change.
3. Cut a patch release once merged. Adopters pick up the fix on
   their next `install.sh upgrade` run; no separate migration step
   required.

Rollback: revert the one-line `install.sh` change and the spec
delta. The fix has no persistent state (no new files, no schema
changes, no new config).

## Open Questions

- None at this time. Scope is locked.
