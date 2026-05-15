## 1. install.sh: prune stale upgrade-branch tracking ref before push

- [x] 1.1 In `install.sh`, locate the `push_and_open_upgrade_pr` function and the `git fetch origin "${UPGRADE_BRANCH}"` line that precedes the tree-compare/push block (currently around line 718).
- [x] 1.2 Change that fetch to `git fetch --prune origin "${UPGRADE_BRANCH}"`, preserving the existing `>/dev/null 2>&1 || true` suffix so a transient fetch failure still doesn't abort the function.
- [x] 1.3 Confirm the change is scoped to the single refspec — `--prune` here SHALL NOT affect tracking refs for other remote branches (this is git's documented behaviour when `--prune` is paired with an explicit refspec).

## 2. Spec delta: codify the regression guard

- [x] 2.1 Apply the delta in `openspec/changes/install-upgrade-prune-fetch/specs/remcc-cli/spec.md` to the main spec at archive time (handled by `/opsx:archive`'s sync step).
- [x] 2.2 Confirm the new "Second upgrade after merge-and-delete succeeds" scenario is the only addition under the MODIFIED requirement; existing two scenarios remain byte-identical.

## 3. Local verification

- [x] 3.1 Lint the updated `install.sh` with `shellcheck` (or document why `shellcheck` is unavailable) and resolve any new findings introduced by the diff.
- [x] 3.2 Run `bash -n install.sh` to confirm the file still parses.

## 4. Validate before archive

- [x] 4.1 Run `openspec validate install-upgrade-prune-fetch --strict` and resolve any reported issues.
