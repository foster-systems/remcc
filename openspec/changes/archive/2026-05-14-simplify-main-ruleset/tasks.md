## 1. Refactor `gh-bootstrap.sh` ruleset/protection code

- [x] 1.1 Replace `RULESET_BRANCH_NAME` and `RULESET_PUSH_NAME` constants with a single `RULESET_MAIN_NAME="remcc: require approval on main"`; do **not** keep the legacy names anywhere in the script (the bootstrap must not reference, list, or touch legacy items)
- [x] 1.2 Add `want_main_ruleset_json` returning the new ruleset body — `target: branch`, `conditions.ref_name.include: ["~DEFAULT_BRANCH"]` and `exclude: []` (default branch only), rules exactly `pull_request` with `required_approving_review_count: 1` and `non_fast_forward` (no `deletion`, no `creation`, no other rules), admin bypass `actor_id: 5`, `actor_type: RepositoryRole`, `bypass_mode: always`
- [x] 1.3 Add `configure_main_ruleset` that reuses the existing `reconcile_ruleset` helper with the new name and JSON
- [x] 1.4 Remove `want_branch_protection_json`, `configure_main_protection`, `remove_main_protection`, `want_branch_ruleset_json`, `want_push_ruleset_json`, `configure_branch_ruleset`, `configure_push_ruleset`, `push_rulesets_supported`, and `owner_type` — no callers remain and the bootstrap must not touch these surfaces
- [x] 1.5 Update `install_remcc` to call `configure_main_ruleset` in place of the three removed configure_* calls; add no migration / cleanup logic for legacy items
- [x] 1.6 Update `uninstall_remcc` to remove only the new ruleset (`remove_ruleset_by_name "${repo}" "${RULESET_MAIN_NAME}"`); remove the calls that previously deleted the two legacy rulesets and branch protection
- [x] 1.7 Update the file's top-of-file comment block (lines 10–17) to describe the single-ruleset model (default branch only), remove the org-vs-user-owned caveats, and add a one-line note that this script does not mutate any pre-existing branch protection or legacy rulesets on the target repo

## 2. Update the idempotency snapshot

- [x] 2.1 Replace the three snapshot sections (`# branch protection on main`, `# branch ruleset`, `# push ruleset`) in `snapshot_state` with a single `# main ruleset` section that dumps the new ruleset's reconciled body
- [x] 2.2 Update `run_idempotency_smoke_test` to call only `configure_main_ruleset` (plus the unchanged calls for secret scanning, Actions PR-creation permission, App slug variable, legacy PAT removal, and apply-config variables) — drop the calls to the three removed configure_* functions

## 3. Update adopter documentation

- [x] 3.1 Rewrite `docs/SECURITY.md`'s defense-in-depth table: drop the three rows for branch protection on `main`, the `change/**` branch ruleset, and the `.github/**` push ruleset; add one row for the new main-branch approval ruleset that targets the default branch only (rules: PR + ≥1 approval + force-push block). Note in the row description that deletion of the default branch is not blocked by this ruleset
- [x] 3.2 Remove the `docs/SECURITY.md` "Limitations" subsections that were specifically about push-rulesets-on-user-owned-repos; keep the secret-scanning-on-private-repos limitation
- [x] 3.3 Rewrite the bootstrap step list in `docs/SETUP.md` (around lines 391–410): one bullet for "creates a branch ruleset on the **default branch only** that requires a PR and at least one approval to merge and blocks force-push (deletion of the default branch is not blocked)"; remove the three replaced bullets; remove the user-vs-org-owned caveat block
- [x] 3.4 Add a short "Opting in from a prior-version adopter" note to `docs/SETUP.md`'s upgrade section: explain that the updated bootstrap does NOT remove legacy branch protection or the two legacy rulesets, give the exact GitHub-UI path to delete each (Settings → Branches; Settings → Rules → Rulesets), and note that re-running the bootstrap afterwards leaves only the new ruleset
- [x] 3.5 Add a one-line note to `docs/SETUP.md`'s uninstall section that `--uninstall` removes only the new ruleset; legacy items from a prior bootstrap (if any) must be removed manually

## 4. Verify the change

- [x] 4.1 Run `openspec validate simplify-main-ruleset --strict` and confirm it passes
- [x] 4.2 Run `bash -n templates/gh-bootstrap.sh` to confirm the script still parses
- [x] 4.3 Run `shellcheck templates/gh-bootstrap.sh` (if installed) and resolve new findings introduced by this change — shellcheck 0.11.0 passed cleanly (exit 0, zero findings)
- [x] 4.4 Grep `templates/gh-bootstrap.sh` for the strings `branches/main/protection`, `restrict bot to change branches`, and `block bot edits under .github`; confirm zero matches (the bootstrap must not reference any legacy surface)
- [x] 4.5 Inspect the rendered ruleset JSON (e.g. `bash -c 'source templates/gh-bootstrap.sh; want_main_ruleset_json' | jq .`) and confirm: `conditions.ref_name.include == ["~DEFAULT_BRANCH"]` and `exclude == []` (default branch only); `rules` contains exactly two entries with `type` equal to `pull_request` (with `required_approving_review_count: 1`) and `non_fast_forward` and nothing else (no `deletion`, no `creation`, no status-check, no other rule types)
- [x] 4.6 Manual smoke test on a fresh adopter: run the updated `gh-bootstrap.sh` on a repo with no remcc-managed controls; confirm the new ruleset is created on the default branch, no branch protection or other rulesets are created, and a second invocation produces no diffs — executed against a throwaway repo `premeq/remcc-smoke-1778795034` (since deleted). Note: surfaced a bug — `~DEFAULT` (originally specified) is org-ruleset-only and is rejected at repo level with HTTP 422 "Invalid target patterns: '~DEFAULT'". Fixed to `~DEFAULT_BRANCH` in script + artifacts; re-run produced exactly the expected state: one ruleset (correct name/target/rules/bypass), no branch protection, idempotent snapshot diff is empty
- [x] 4.7 Manual smoke test on a legacy adopter: run the updated `gh-bootstrap.sh` on a repo that still has prior-version branch protection + the two legacy rulesets; confirm the new ruleset is added and the three legacy items are **unchanged** (verified via `gh api repos/<owner>/<repo>/branches/main/protection` and `gh api repos/<owner>/<repo>/rulesets`) — **cancelled by operator** (post-merge verification instead)
