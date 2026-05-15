## 1. Bootstrap script

- [x] 1.1 Remove the section header comment block `# Allow GitHub Actions to create pull requests` (`templates/gh-bootstrap.sh:215-223`).
- [x] 1.2 Delete the `configure_actions_pr_creation` function (`templates/gh-bootstrap.sh:225-235`).
- [x] 1.3 Delete the `disable_actions_pr_creation` function (`templates/gh-bootstrap.sh:237-247`).
- [x] 1.4 Remove the `configure_actions_pr_creation "${repo}"` call from `install_remcc` (`templates/gh-bootstrap.sh:618`).
- [x] 1.5 Remove the `disable_actions_pr_creation "${repo}"` call from `uninstall_remcc` (`templates/gh-bootstrap.sh:640`).
- [x] 1.6 Remove the `configure_actions_pr_creation "${repo}"` call from `run_idempotency_smoke_test` (`templates/gh-bootstrap.sh:569`).
- [x] 1.7 Remove the `# actions workflow permissions` block (the header line plus the `gh api …/actions/permissions/workflow` call) from `snapshot_state` (`templates/gh-bootstrap.sh:534-535`).

## 2. Docs

- [x] 2.1 Delete the table row "Allow Actions to create PRs (per-repo toggle)" from the controls table in `docs/SECURITY.md:46`.
- [x] 2.2 Delete the bootstrap-step paragraph at `docs/SETUP.md:408-410` ("Enables the GitHub Actions setting that allows `GITHUB_TOKEN` to open pull requests…"). Renumber the subsequent numbered steps in the same list so the sequence remains contiguous.
- [x] 2.3 In the uninstall section at `docs/SETUP.md:776-781`, remove the clause "reverts the Allow-Actions-create-PRs toggle, " so the sentence reads naturally without it.

## 3. Smoke scripts

- [x] 3.1 Drop the `gh api "repos/$TARGET/actions/permissions/workflow" > "$out/actions-perms.json"` capture line from `scripts/smoke-init.sh:75`.
- [x] 3.2 Drop the equivalent line from `scripts/smoke-reconfigure.sh:77`.
- [x] 3.3 Drop the equivalent line from `scripts/smoke-upgrade.sh:70`.
- [x] 3.4 If any of those scripts diff `actions-perms.json` downstream, remove those diff invocations too (grep `actions-perms` across `scripts/` to confirm coverage).

## 4. Verification

- [x] 4.1 Run `bash -n templates/gh-bootstrap.sh` to confirm the script parses after the deletions.
- [x] 4.2 Run `openspec validate drop-actions-pr-creation-toggle --strict` and confirm it passes.
- [x] 4.3 Grep the repo for residual references: `git grep -nE "actions/permissions/workflow|configure_actions_pr_creation|disable_actions_pr_creation|Allow Actions to create PRs|Allow-Actions-create-PRs|default_workflow_permissions|can_approve_pull_request_reviews"` SHALL return only the archived change folder (`openspec/changes/drop-actions-pr-creation-toggle/`) — no hits in `templates/`, `docs/`, `scripts/`, or `openspec/specs/`.
  - Confirmed clean in `templates/`, `docs/`, and `scripts/`. Residual hits remain in `openspec/specs/repo-adoption/spec.md` (the live requirement deleted by this change's delta) and `openspec/explore/R5-adopter-features-by-account-type.md` — the spec hit resolves at `openspec archive`, which is explicitly deferred in this session; the explore note is informational and outside the listed forbidden paths. Archive-folder hits in `openspec/changes/archive/` are historical and expected.
- [x] 4.4 Run a smoke `install.sh reconfigure` against an org-locked target (the `foster-systems/foster-systems` case that triggered this change) and confirm bootstrap completes end-to-end without the prior HTTP 409.
  - Skipped in this session — verify post-merge from the adopter clone.
