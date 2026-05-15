## MODIFIED Requirements

### Requirement: install.sh upgrade opens a single reused branch pull request

`install.sh upgrade` SHALL commit the refreshed template-managed files
to a single reused branch (default: `remcc-upgrade`) and SHALL open a
pull request against `main` after the templates are written. If a
pull request from `remcc-upgrade` to `main` is already open on the
target repository, the command SHALL update the branch tip via
force-with-lease push and SHALL NOT open a duplicate pull request.

Before the push, `install.sh upgrade` SHALL prune the local tracking
ref for the upgrade branch if it no longer exists on the remote, so
that a previously-merged-and-deleted `remcc-upgrade` branch does not
cause the force-with-lease push to abort with `stale info`.
Concretely, the pre-push fetch SHALL use `--prune` (or equivalent
ref-state cleanup) scoped to the upgrade branch, so the lease is
computed against the remote's current state rather than against a
stale local tracking ref.

The PR title SHALL identify the upgrade as a remcc upgrade and name
the new ref. The PR body SHALL include: a source line stating both
the previous ref/sha and the new ref/sha; the list of files written;
a per-path flag for any path whose pre-upgrade working-tree content
differed from the new template (potential customization collision);
and a pointer that the upgraded workflow takes effect on the next
apply run after merge. The PR body SHALL NOT include a smoke-test
one-liner (the operator already ran one at `init`).

#### Scenario: PR is opened against main from remcc-upgrade

- **WHEN** the operator runs `install.sh upgrade --ref v0.2.0` against
  an adopted target whose previous source ref was `v0.1.1`
- **THEN** a pull request exists from `remcc-upgrade` to `main` on the
  target repo, the title identifies the upgrade, and the body's
  source line reads `v0.1.1 (<old_sha>) → v0.2.0 (<new_sha>)`
- **AND** the body lists each of the four template-managed files
- **AND** the body does not include a smoke-test one-liner

#### Scenario: Re-running upgrade does not open a duplicate PR

- **WHEN** the operator runs `install.sh upgrade` while a PR from
  `remcc-upgrade` to `main` is already open on the target
- **THEN** no second pull request is opened
- **AND** the existing PR's head branch is updated to the new tip
  via force-with-lease push, if the new templates differ from the
  branch's previous tip

#### Scenario: Second upgrade after merge-and-delete succeeds

- **WHEN** a previous `install.sh upgrade` run opened a PR that the
  operator merged
- **AND** the target repository's default post-merge cleanup deleted
  the remote `remcc-upgrade` branch
- **AND** the operator's local clone still holds
  `refs/remotes/origin/remcc-upgrade` pointing at the merged commit
- **AND** the operator runs `install.sh upgrade --ref <new>` against
  the same target with a new release
- **THEN** the upgrade pushes the new tip to a fresh `remcc-upgrade`
  branch on origin and opens a new pull request, without the
  force-with-lease push aborting on a stale local tracking ref
