## 1. Workflow template

- [x] 1.1 In `templates/workflows/opsx-apply.yml`, in the "Open or update PR" step's `gh pr create` invocation (currently around line 415), change the `--title` value from `"/opsx:apply ${CHANGE_NAME}"` to `"Change: ${CHANGE_NAME}"`. Do not change any other `--title`, `-m`, or `-p` string in this file. In particular, leave the agent-output commit subject at `templates/workflows/opsx-apply.yml:339` (`git commit -m "$(printf '/opsx:apply %s\\n…')"`) and the `claude -p "/opsx:apply ${CHANGE_NAME}"` argument (around line 277) unchanged.
- [x] 1.2 Re-read the self-loop guard immediately after the commit (the `grep -q '^@change-apply'` check) and confirm it is unchanged and still references `@change-apply` (not `/opsx:apply`).

## 2. Verification

- [x] 2.1 Run `git diff templates/workflows/opsx-apply.yml` and visually confirm that the only line changed is the `--title` argument; the `/opsx:apply` strings on the `claude -p` line and the `git commit -m` line MUST still be present byte-for-byte.
- [x] 2.2 Run `grep -nE '/opsx:apply' templates/workflows/opsx-apply.yml` and confirm that both load-bearing occurrences remain: the `claude -p "/opsx:apply ${CHANGE_NAME}"` argument (line 277) and the `git commit -m "$(printf '/opsx:apply %s\\n…')"` commit subject (line 339). Comment/doc mentions of `/opsx:apply` are not load-bearing and may also appear.
- [x] 2.3 Run `grep -nE '"Change: \\$\\{CHANGE_NAME\\}"' templates/workflows/opsx-apply.yml` and confirm exactly one match (the `gh pr create --title` line).
- [x] 2.4 Run `openspec validate rename-apply-pr-title` and confirm it passes.
