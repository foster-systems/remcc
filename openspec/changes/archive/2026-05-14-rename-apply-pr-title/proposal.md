## Why

The `opsx-apply` workflow opens PRs whose title is `/opsx:apply <change>` — the literal slash command it invoked. That string is visible in the PR list, in notifications, and in commit log subjects after squash-merge; it reads as "internal tooling shorthand" rather than as a description of what the PR contains. Renaming it to `Change: <change>` makes the title a human-readable label of *what changed*, while keeping the change name machine-recoverable for any tooling that scans titles.

## What Changes

- Change the PR title that the `opsx-apply` workflow uses when creating a new PR from `/opsx:apply ${CHANGE_NAME}` to `Change: ${CHANGE_NAME}`.
- Update the `apply-workflow` capability spec to reflect the new title format.
- This affects only newly-created PRs. Existing PRs are not renamed; the workflow only renames on `gh pr create`, not on subsequent runs that just comment on an existing PR.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `apply-workflow`: the "Open or update the change PR" requirement is tightened — the PR title MUST follow the format `Change: <change-name>` (not the previously-illustrative "change name in the title").

## Impact

- `templates/workflows/opsx-apply.yml` — the `--title` argument on the `gh pr create` invocation.
- `openspec/specs/apply-workflow/spec.md` — the "Open or update the change PR" requirement and its first scenario.
- No new dependencies. No code outside the workflow template. No effect on the bot's commit subject (`/opsx:apply <name>`), which is constrained by the self-loop guard and must NOT change.
