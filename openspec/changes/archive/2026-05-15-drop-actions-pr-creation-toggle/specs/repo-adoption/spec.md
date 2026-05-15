## REMOVED Requirements

### Requirement: Bootstrap enables Actions to create pull requests

**Reason**: The `opsx-apply` workflow no longer authenticates with `GITHUB_TOKEN` for the operations that create pull requests. Since the R3 GitHub App migration (archived 2026-05-14 as `pr-author-github-app`), every write operation in `templates/workflows/opsx-apply.yml` — checkout, push, git identity, `gh pr create` — uses the per-run App installation token (`steps.app-token.outputs.token`). `GITHUB_TOKEN` is read only at line 75 to fetch `github.event.head_commit.message`, which is covered by default read permissions. The org-level `default_workflow_permissions` setting therefore has no bearing on whether the workflow can open PRs, and bootstrap's repeated attempt to PUT it to `write` blocks adoption on org-owned repos whose org pins the policy read-only (e.g. `foster-systems`, where the PUT returned HTTP 409 on 2026-05-15).

**Migration**: No action required for existing adopters. Repos where bootstrap had previously set `default_workflow_permissions=write` retain that value (the new bootstrap neither writes nor reads the endpoint, and the uninstall path no longer reverts it). The `opsx-apply` workflow continues to function under either repo-level setting.
