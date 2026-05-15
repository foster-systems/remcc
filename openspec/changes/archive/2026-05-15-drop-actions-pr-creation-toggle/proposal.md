## Why

`gh-bootstrap.sh` enforces a GitHub setting (`default_workflow_permissions=write` + `can_approve_pull_request_reviews=true` on `repos/{owner}/{repo}/actions/permissions/workflow`) that became obsolete when R3 shipped the GitHub App migration on 2026-05-14. The `opsx-apply` workflow now mints a short-lived App installation token and uses it for every write operation — checkout (`token: ${{ steps.app-token.outputs.token }}`), push, `gh pr create`, git identity. `GITHUB_TOKEN` is only used to read `github.event.head_commit.message`, which read permissions cover. The stale setting now blocks bootstrap on org-owned adopters whose org pins Actions workflow permissions to read-only (e.g. `foster-systems`, which returned HTTP 409 "Write permissions for workflows are disabled by the organization" during `install.sh reconfigure` on 2026-05-15).

## What Changes

- Remove `configure_actions_pr_creation` and `disable_actions_pr_creation` from `templates/gh-bootstrap.sh`.
- Remove the corresponding calls from `install_remcc`, `uninstall_remcc`, and `run_idempotency_smoke_test`.
- Remove the `# actions workflow permissions` block from `snapshot_state`.
- Remove the header comment lines listing the Actions toggle in `templates/gh-bootstrap.sh`.
- Update `openspec/specs/repo-adoption/spec.md`: remove the requirement **"Bootstrap enables Actions to create pull requests"** and its scenario.
- Update `docs/SECURITY.md` and `docs/SETUP.md` to remove the references to the Actions PR-creation toggle (the bootstrap step list).
- **BREAKING for re-bootstrap behavior only**: existing adopters who already had `default_workflow_permissions=write` set will keep it (the script no longer reads or writes the setting); the uninstall path will no longer revert it.

## Capabilities

### New Capabilities

None — this is a removal.

### Modified Capabilities

- `repo-adoption`: drop the requirement that bootstrap enables Actions to create pull requests. The App-token path supersedes it.

## Impact

- `templates/gh-bootstrap.sh` — function removals + call-site removals + header comment.
- `openspec/specs/repo-adoption/spec.md` — one requirement deleted via delta.
- `docs/SECURITY.md` — remove the Actions-toggle entry from the safety-controls table (or rewrite to note it's no longer required).
- `docs/SETUP.md` — remove mentions of the Actions toggle from the bootstrap-step list (`docs/SETUP.md:398-414` neighborhood).
- No workflow-template changes: `templates/workflows/opsx-apply.yml` is unaffected because its existing `permissions: contents: write, pull-requests: write` block + App-token usage are already independent of the org-level toggle for the operations the workflow performs.
- No `install.sh` changes: it delegates to `gh-bootstrap.sh`.
- Adopters who run `install.sh reconfigure` after this lands: bootstrap no longer touches Actions workflow permissions, so org-locked policies (read-only) stop blocking bootstrap. The smoke test stops snapshotting that endpoint.
