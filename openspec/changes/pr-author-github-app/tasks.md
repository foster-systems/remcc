## 1. Workflow template: mint and use the App installation token

- [x] 1.1 Add a step `Mint GitHub App installation token` to `templates/workflows/opsx-apply.yml` that runs `actions/create-github-app-token@v1` with `app-id: ${{ secrets.REMCC_APP_ID }}` and `private-key: ${{ secrets.REMCC_APP_PRIVATE_KEY }}`. Place it immediately after the `Confirm trigger subject is case-sensitive match` step and before `Checkout`. Expose its `token` output to subsequent steps.
- [x] 1.2 Add preflight steps that exit non-zero with a clear `::error::` if `REMCC_APP_ID` or `REMCC_APP_PRIVATE_KEY` is unset (mirror the existing `Verify ANTHROPIC_API_KEY is set` step's shape). Remove the existing `Verify WORKFLOW_PAT is set` step.
- [x] 1.3 Add a preflight check that confirms `vars.REMCC_APP_SLUG` is non-empty and surfaces a clear `::error::` (with a pointer to `install.sh reconfigure`) if it is missing.
- [x] 1.4 Update `actions/checkout@v4`'s `token:` input to use the minted token (`steps.<id>.outputs.token`) instead of `secrets.WORKFLOW_PAT`.
- [x] 1.5 Update the `Open or update PR` step to set `GH_TOKEN` to the minted token instead of `${{ github.token }}`, so `gh pr create` / `gh pr comment` authenticate as the App.
- [x] 1.6 Replace the `Configure git identity` step's hardcoded `github-actions[bot]` identity with a step that (a) calls `gh api users/<slug>[bot] --jq .id` (using the minted token and `vars.REMCC_APP_SLUG`) to get the numeric ID, then (b) sets `user.name=<slug>[bot]` and `user.email=<id>+<slug>[bot]@users.noreply.github.com`.
- [x] 1.7 Add an `App-not-installed` failure-message annotation: when the token-mint step fails, emit a `::error::` linking to `https://github.com/settings/apps/<slug>/installations` so the operator knows where to install the App.

## 2. Bootstrap script: install App credentials, remove legacy PAT

- [x] 2.1 Add `configure_remcc_app_secrets` to `templates/gh-bootstrap.sh` that reads `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY` from env or `/dev/tty` (private key as multi-line via heredoc-style input — accept multi-line PEM cleanly) and uploads each via `gh secret set --repo <repo> < /dev/stdin`. Echo nothing of the values to stdout.
- [x] 2.2 Add `configure_remcc_app_slug_variable` that reads `REMCC_APP_SLUG` from env or `/dev/tty` (visible input, slug is not secret), errors on empty, and writes it via `gh variable set` using the existing `set_repo_variable` helper for idempotency.
- [x] 2.3 Add `remove_workflow_pat_legacy` that deletes `WORKFLOW_PAT` if present, no-op if absent. Wire it into `install_remcc` to run AFTER `configure_remcc_app_secrets` and `configure_remcc_app_slug_variable` succeed, so a failed App-secret install preserves the legacy PAT.
- [x] 2.4 Remove the existing `configure_workflow_pat_secret` and `read_workflow_pat_into_env` functions and their call sites in `install_remcc`. Keep `remove_workflow_pat_secret` only via its replacement in 2.3 (rename if useful).
- [x] 2.5 Update `--uninstall` (`uninstall_remcc`) to call new App-secret/variable removal helpers; keep WORKFLOW_PAT removal in the uninstall path for repos still on legacy state.
- [x] 2.6 Extend `snapshot_state` to include the presence/absence of `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY` (secrets — snapshot names only, not values), and `REMCC_APP_SLUG` (variable name+value), and to confirm `WORKFLOW_PAT` is absent. Re-run the existing `run_idempotency_smoke_test` flow over the new state.
- [x] 2.7 Update the file header comment to describe the new secrets/variable and remove the WORKFLOW_PAT description block.

## 3. install.sh: new reconfigure subcommand, updated init help

- [x] 3.1 Add a `reconfigure` subcommand dispatch arm to `main` in `install.sh`; add `cmd_reconfigure` that: resolves the target repo, calls `verify_marker_on_main` (refuse un-adopted targets), `verify_prereqs`, `verify_clean_main reconfigure`, `resolve_ref` + `clone_remcc_at`, then `run_bootstrap` and exits. No working-tree writes, no branch, no PR.
- [x] 3.2 Add `usage_reconfigure` with `--help` text (`--ref` option, behavior, env-var passthrough names: `ANTHROPIC_API_KEY`, `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, `REMCC_APP_SLUG`, `OPSX_APPLY_MODEL`, `OPSX_APPLY_EFFORT`).
- [x] 3.3 Update `usage_root` to list `reconfigure` alongside `init` and `upgrade`.
- [x] 3.4 Update `usage_init`'s "Environment passthrough" block: remove `WORKFLOW_PAT`; add `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, `REMCC_APP_SLUG`.
- [x] 3.5 Update `usage_init`'s behavior step (3) summary to name the new secrets/variables instead of WORKFLOW_PAT.

## 4. Smoke harness updates

- [x] 4.1 Update `scripts/smoke-init.sh` to require `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, `REMCC_APP_SLUG` env vars; remove the `WORKFLOW_PAT` requirement. Add an assertion that the post-init repo has the three new secrets/variable installed and that `WORKFLOW_PAT` is absent.
- [x] 4.2 Update `scripts/smoke-upgrade.sh` to require the new env vars (the init step still needs them). Extend the harness to drive the migration path: `init` at `--old-ref` (legacy WORKFLOW_PAT) → set new env vars → `upgrade` to `--ref` (template-only) → `reconfigure` → assert new secrets present and WORKFLOW_PAT absent.
- [x] 4.3 Add an assertion to `scripts/smoke-postmerge.sh` (or extend `smoke-init.sh` post-merge step) that the test-apply PR's `author.login` is `<REMCC_APP_SLUG>[bot]`, not the operator's username.
- [x] 4.4 Add `scripts/smoke-reconfigure.sh` exercising `install.sh reconfigure` against an already-adopted target: pre-state has `WORKFLOW_PAT`; post-state has App secrets and no `WORKFLOW_PAT`; re-running is idempotent (no GitHub-side diff).

## 5. Documentation

- [x] 5.1 In `docs/SETUP.md`, add a "Create the remcc GitHub App" subsection BEFORE the bootstrap step. Document: App name, homepage URL, webhook off, required permissions (`Contents: write`, `Pull requests: write`, `Workflows: write`, `Metadata: read`), private-key generation (download PEM), and how to install the App on the target repo.
- [x] 5.2 In `docs/SETUP.md`, update the secrets section to list `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY` (secrets) and `REMCC_APP_SLUG` (variable). Remove the `WORKFLOW_PAT` row.
- [x] 5.3 In `docs/SETUP.md`, add an "Upgrading from a remcc release before v0.3.0" subsection in the upgrade section with the migration steps: `install.sh upgrade --ref vNEW` → merge PR → `install.sh reconfigure` → verify next apply run shows `<slug>[bot]` as PR author → revoke the old `WORKFLOW_PAT` on GitHub.
- [x] 5.4 In `docs/SECURITY.md`, replace the `WORKFLOW_PAT` section with a "GitHub App credentials" section describing: App permissions, blast radius if the private key is exfiltrated, rotation procedure (regenerate key → `install.sh reconfigure` → revoke old key in App settings), and the fact that the App's installation token is short-lived (1 hour) and non-admin.
- [x] 5.5 In `docs/COSTS.md`, add a one-line note that App-credential setup is free (no additional GitHub seat required), and ensure any references to WORKFLOW_PAT are removed.

## 6. Roadmap + release

- [x] 6.1 Tick R3 in `openspec/ROADMAP.md` with a reference to this change.
- [x] 6.2 Run `openspec validate pr-author-github-app --strict` and address any new issues.
- [x] 6.3 Run the full smoke matrix (init, upgrade, reconfigure, postmerge) against `premeq/remcc-smoke-init` / `premeq/remcc-smoke-upgrade`. Confirm assertions pass and the test-apply PR is authored by the App.
- [ ] 6.4 Open the PR for this change. Once merged, cut release `v0.3.0` (BREAKING — adopters MUST migrate per SETUP.md).
- [ ] 6.5 Archive this change via `openspec archive pr-author-github-app`.
