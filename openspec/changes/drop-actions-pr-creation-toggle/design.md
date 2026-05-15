## Context

The `opsx-apply` workflow originally authenticated via `GITHUB_TOKEN` and a fallback `WORKFLOW_PAT`, both of which created PRs as the operator. Because GitHub does not grant `GITHUB_TOKEN` PR-creation rights by default, bootstrap had to flip two repo-level settings:

```bash
gh api --method PUT repos/${repo}/actions/permissions/workflow --input - <<'JSON'
{ "default_workflow_permissions": "write",
  "can_approve_pull_request_reviews": true }
JSON
```

R3 (archived 2026-05-14 as `pr-author-github-app`) replaced that auth path with a per-run GitHub App installation token. The workflow now reads `GITHUB_TOKEN` only for `github.event.head_commit.message` (`templates/workflows/opsx-apply.yml:75`); every other token reference is the App token (`steps.app-token.outputs.token` at lines 116, 236, 371 — used by `actions/checkout`, the git-identity step, and `gh pr create` at line 412).

Concrete trigger: on 2026-05-15, running `install.sh reconfigure` against `foster-systems/foster-systems` (newly transferred to an org whose Actions workflow-permissions policy is pinned read-only at the org level) returned `HTTP 409: Write permissions for workflows are disabled by the organization` at `configure_actions_pr_creation`. The smoke test step the same script ran one line earlier — secret scanning — succeeded. The toggle is the only org-policy-sensitive write the bootstrap performs.

## Goals / Non-Goals

**Goals:**
- Stop bootstrap from touching `actions/permissions/workflow`.
- Keep `gh-bootstrap.sh` strictly idempotent (no orphaned snapshot keys, no resurrected drift).
- Keep the spec, SETUP.md, and SECURITY.md aligned — no dangling references to the dropped step.

**Non-Goals:**
- No change to the `opsx-apply` workflow.
- No re-introduction of the legacy `WORKFLOW_PAT` path or any non-App PR-creation path.
- No bootstrap-side reversal of the setting on existing adopters (see "Migration").

## Decisions

### Remove rather than warn-and-continue

`secret_scanning_available()` (`gh-bootstrap.sh:166`) is the precedent for feature-detect + warn-and-continue. The Actions toggle is different in kind: the **workflow does not need it at all** under the current design, so the right move is to delete the step rather than wrap it in a detector. Warn-and-continue would leave a sticky comment block, a snapshot field, and an uninstall counterpart for a setting no remcc-managed code ever reads.

Alternative considered: keep a `secret_scanning_available`-style guard that PUTs only when the org policy permits. Rejected — adds code, doesn't fix anything (the workflow already works without the setting), and risks a future maintainer wondering whether the workflow secretly depends on it.

### Don't revert the setting on uninstall

`uninstall_remcc` currently calls `disable_actions_pr_creation`, which forces the repo back to `default_workflow_permissions=read` + `can_approve_pull_request_reviews=false`. After this change, uninstall stops touching the endpoint. Rationale: bootstrap installs no longer mutate it, so uninstall has nothing to revert; touching it would punish adopters whose repo had `write` set independently of remcc.

### Spec delta uses REMOVED, not MODIFIED

The requirement title "Bootstrap enables Actions to create pull requests" describes a behavior that disappears entirely. REMOVED with **Reason** + **Migration** is the right delta kind. MODIFIED would imply a different rule replacing the old one.

### One spec change, one capability

Only `repo-adoption` is affected. No `apply-workflow` change — the workflow template is unchanged, and the workflow's spec doesn't mention the org-level toggle.

## Risks / Trade-offs

- **Risk**: An adopter has a *custom* workflow step (outside the remcc-managed `opsx-apply.yml`) that relies on `GITHUB_TOKEN: write` being on by default at the repo level.
  **Mitigation**: Out of scope — we manage `opsx-apply.yml`, not arbitrary user workflows. The change does not turn the setting *off*; it just stops bootstrap from turning it *on*. Existing adopters' values are preserved.

- **Risk**: A future workflow-template change re-introduces a `GITHUB_TOKEN`-based mutation step and silently fails on org-locked adopters.
  **Mitigation**: Document in the spec (and in the bootstrap header comment) that all write operations must use the App token. This change adds that as an invariant.

- **Trade-off**: Existing adopters where bootstrap had set `write` keep it. The repo-side state diverges slightly from a freshly-bootstrapped repo. Acceptable — the workflow doesn't care, and reverting unilaterally could surprise operators.

## Migration Plan

1. Land this change on `main`.
2. `install.sh reconfigure` on `foster-systems/foster-systems` (the immediate-blocker repo) succeeds end-to-end without intervention on the org's Actions policy.
3. Old adopters re-running `reconfigure` after the change observe one fewer `==> Allow GitHub Actions to create pull requests` line in the bootstrap output and one fewer entry in the smoke-test snapshot. Their repo-level setting is untouched (whatever was there before stays there).
4. Old adopters running `--uninstall` after this change keep their pre-existing repo-level Actions setting (no `disable_actions_pr_creation` call). If they want it reverted, they do so by hand.

No rollback needed — the workflow has not depended on this setting since R3.

## Open Questions

None. The token-by-token audit of `templates/workflows/opsx-apply.yml` (head_commit.message read at line 75; all writes use the App token) closes the only ambiguity.
