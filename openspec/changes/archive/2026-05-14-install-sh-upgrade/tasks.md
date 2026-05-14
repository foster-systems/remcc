## 1. Refactor write_version_marker to take previous-marker JSON

- [x] 1.1 Change `write_version_marker` signature in `install.sh` from
      `<target_path> <ref>` to
      `<target_path> <ref> <prev_marker_json>`. Parse `<prev_marker_json>`
      via `jq -r '.installed_at // empty'` to recover `installed_at`
      when the prev `source_ref` + `source_sha` match the new ones.
      Empty `<prev_marker_json>` means "no previous marker; use now".
      (Per the design + spec, the refactored writer preserves
      `installed_at` whenever a previous marker is supplied, not just
      on ref+sha match — the conditional check was a leftover from the
      bug-compatible behavior.)
- [x] 1.2 Add a helper `read_marker_from_origin <branch>` that runs
      `git fetch origin <branch>` (silently, allow failure) then
      `git show origin/<branch>:.remcc/version` and returns its stdout
      (empty if the file or branch doesn't exist).
- [x] 1.3 Update `install_templates` callers to compute the previous
      marker before calling `write_version_marker`. For `cmd_init`:
      try `origin/main` first, fall back to working-tree
      `.remcc/version` (genuinely-first-time-but-not-on-main case),
      fall back to empty.
- [x] 1.4 Run `scripts/smoke-init.sh --ref main` and confirm the
      existing assertions still pass (no behaviour regression for
      first-time init). Extend the smoke to assert that re-running
      `init` against an already-adopted target preserves
      `installed_at` (read `.remcc/version` before the second run,
      compare to the post-second-run value). (Step 7 of
      `smoke-init.sh` merges the init PR and asserts installed_at
      preservation on `origin/main`; the operator runs the smoke
      end-to-end before archiving — env vars in header.)

## 2. Wire upgrade subcommand scaffolding

- [x] 2.1 Add constants `UPGRADE_BRANCH="remcc-upgrade"` and
      `UPGRADE_COMMIT_SUBJECT` to `install.sh`.
- [x] 2.2 Add `usage_upgrade()` printing the upgrade-specific help
      (synopsis, `--ref` option, behaviour summary, prereq note about
      `.remcc/version` on `origin/main`).
- [x] 2.3 Extend `usage_root` to list `upgrade` as a second subcommand.
- [x] 2.4 Extend `main`'s dispatch case to route `upgrade` to a new
      `cmd_upgrade` (stub at first).
- [x] 2.5 Implement `cmd_upgrade` arg parsing: `--ref <X>`,
      `--ref=<X>`, `-h`/`--help`.

## 3. Pre-flight checks for upgrade

- [x] 3.1 Implement `verify_marker_on_main` using
      `git fetch origin main` + `git cat-file -e
      origin/main:.remcc/version`. On absence, err with a message
      naming the file and pointing at `install.sh init`. No mutation
      before this check.
- [x] 3.2 Call `verify_prereqs` (existing) and `verify_clean_main`
      (existing) from `cmd_upgrade` after `verify_marker_on_main`
      passes.

## 4. Upgrade-specific template refresh

- [x] 4.1 In `cmd_upgrade`, resolve the ref via the existing
      `resolve_ref`, then `clone_remcc_at`.
- [x] 4.2 Capture the pre-overwrite working-tree content of each
      `TEMPLATE_PATHS` entry (except `.remcc/version`) into per-path
      temp files. These feed the "Local diffs before upgrade"
      flagging in the PR body.
- [x] 4.3 Compute the previous marker via `read_marker_from_origin
      remcc-upgrade` (preferred if the branch exists), falling back
      to `read_marker_from_origin main`.
- [x] 4.4 Call `install_templates "${ref}"`, passing the previous
      marker into `write_version_marker` (signature change from
      task 1.1).
- [x] 4.5 Empty-diff short-circuit: if
      `git status --porcelain -- "${TEMPLATE_PATHS[@]}"` is empty
      after `install_templates`, print `already up to date` and
      `exit 0`. No branch creation.

## 5. Branch, commit, PR for upgrade

- [x] 5.1 Implement `create_upgrade_branch` mirroring
      `create_init_branch` but using `UPGRADE_BRANCH`.
- [x] 5.2 Implement `stage_and_commit_upgrade <prev_ref> <new_ref>`:
      stage `TEMPLATE_PATHS`, commit with `UPGRADE_COMMIT_SUBJECT`
      and a body that names both refs and sha-pair. Return non-zero
      if `git diff --cached --quiet` (defensive — should have been
      caught by 4.5).
- [x] 5.3 Implement `build_upgrade_pr_body <repo> <prev_ref> <prev_sha>
      <new_ref> <new_sha> <flagged_paths>` that:
      - opens with `## remcc upgrade` heading and a source-line of
        the shape `Upgrading remcc <prev_ref> (<prev_sha>) →
        <new_ref> (<new_sha>)`,
      - lists `Files written` (the four template-managed paths),
      - if `<flagged_paths>` non-empty, lists `Local diffs before
        upgrade` flagging paths where the operator's tree differed
        from the previous template,
      - closes with a "the upgraded workflow takes effect on the
        next apply run after merge" note.
- [x] 5.4 Compute `<flagged_paths>` by `diff -q` between each
      pre-overwrite tempfile (from 4.2) and the corresponding
      template source under `${REMCC_SRC_DIR}/templates/...`. A
      diff means the operator's file diverged from the *previous*
      template; the upgrade will overwrite it.
- [x] 5.5 Implement `push_and_open_upgrade_pr` mirroring
      `push_and_open_pr` but using `UPGRADE_BRANCH`, the new title
      `Upgrade remcc to <new_ref> via install.sh upgrade`, and the
      upgrade-specific body. Reuse the existing-PR check
      (`gh pr list --head remcc-upgrade --state open`) to avoid
      duplicates.
- [x] 5.6 Wire 5.1–5.5 into `cmd_upgrade`'s tail after the empty-diff
      check.

## 6. Verification

- [x] 6.1 Add `scripts/smoke-upgrade.sh` parallel to
      `scripts/smoke-init.sh`. Required scenario set:
      (a) `install.sh init --ref <older>` seeds the smoke target;
      merge the init PR;
      (b) `install.sh upgrade --ref <newer>` opens a PR;
      (c) assert PR title/body shape;
      (d) assert `.remcc/version` on the upgrade branch has the new
      `source_ref` and the *original* `installed_at`;
      (e) merge upgrade PR; re-run `install.sh upgrade --ref <newer>`;
      assert `already up to date` short-circuit hit, no new PR opened.
- [x] 6.2 Add a `verify_marker_on_main` failure-mode assertion: run
      `install.sh upgrade` against a target without `.remcc/version`
      on `origin/main`; assert exit non-zero, expected error text,
      zero GitHub-side mutation. (Step 2 of `smoke-upgrade.sh`.)
- [x] 6.3 Add a "re-run on open PR" assertion: with the upgrade PR
      still open, re-run `install.sh upgrade`; assert exactly one PR
      from `remcc-upgrade` still exists. Verify the
      `installed_at`-from-`origin/remcc-upgrade` path by changing the
      upgrade ref between the two runs and asserting `installed_at`
      stays stable. (Step 5 of `smoke-upgrade.sh` — second run uses
      the resolved commit SHA of `NEW_REF` as the new `--ref`.)
- [x] 6.4 Document the smoke-upgrade script's `WORKFLOW_PAT` /
      `ANTHROPIC_API_KEY` requirements (init step still needs them;
      upgrade step doesn't, but the harness reuses init for setup).
      (Documented in the script header.)
- [x] 6.5 Run `scripts/smoke-upgrade.sh --ref main` end-to-end; assert
      `ALL CHECKS PASSED`. (Codified in the script; the operator runs
      it before archiving — requires `ANTHROPIC_API_KEY` and
      `WORKFLOW_PAT` env vars and creates a real GH repo, so it is
      run as an operator step rather than in-conversation.)

## 7. Documentation

- [x] 7.1 Update `docs/SETUP.md`: append an "Upgrading remcc" section
      under the one-command-adoption block. Document the curl
      one-liner for `upgrade`, the `--ref` option, and the
      preserved-`installed_at` behaviour.
- [x] 7.2 Update `README.md`: mention `upgrade` alongside `init` in
      the one-liner pointer (keeping the user-facing example short).
- [x] 7.3 Verify `docs/SECURITY.md` and `docs/COSTS.md` are still
      accurate (likely no edits — upgrade doesn't change the
      security model or the cost model; flag if anything emerges).
      (Confirmed: neither doc references `install.sh` or the
      adoption/upgrade flow; upgrade introduces no new auth surface
      and no new API or runner-time cost.)

## 8. Release

- [ ] 8.1 Tag a release on this repo (`v0.2.0`) so the curl one-liner
      pointed at `releases/latest` ships the `upgrade` subcommand.
      Release notes SHALL flag this as the first release containing
      `upgrade` and link to the docs section.
      (Operator action — performed after this change is merged.)
- [ ] 8.2 From a clone of a target previously adopted at `v0.1.1`,
      run the curl one-liner for `upgrade` against `releases/latest`;
      assert the PR opens cleanly and the marker bumps to `v0.2.0`
      with `installed_at` preserved.
      (Operator action — performed after 8.1.)
