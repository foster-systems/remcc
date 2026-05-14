## 1. Installer scaffolding

- [x] 1.1 Decide distribution model (resolve design.md open question):
      gh-extension-in-this-repo, gh-extension-in-split-repo, or
      curl-piped install.sh. Record decision + rationale in design.md.
      Decision: curl-piped `install.sh`. Recorded in design.md.
- [x] 1.2 Add `install.sh` at the repo root with `init` subcommand
      dispatch and a `--ref <tag-or-sha>` flag.
- [x] 1.3 Implement `install.sh --help` and `install.sh init --help`
      output, listing `init` as an available subcommand.
- [x] 1.4 Verify both invocation shapes against a local clone:
      `bash <(curl -fsSL file://$(pwd)/install.sh) --help` and
      `bash install.sh --help` exit zero with the expected text.

## 2. Prerequisite verification

- [x] 2.1 Implement prereq checks matching `repo-adoption` (admin on target,
      `main` exists, OpenSpec initialised, `.claude/` committed,
      `pnpm-lock.yaml` at root, local tools: `gh`, `jq`, `git`, Node ≥ 20.19,
      `pnpm`).
- [x] 2.2 On any prereq failure: print which check failed, exit non-zero, and
      ensure no `gh api` mutating call has been issued and no files written.
- [x] 2.3 Manual test: run `install.sh init` in a repo missing `pnpm-lock.yaml`;
      confirm failure mode matches spec scenario "Missing pnpm-lock.yaml is
      detected before mutation". Verified 2026-05-14 against
      `premeq/remcc-pnpm-test`: exit 1, message `pnpm-lock.yaml not found
      at repo root`, zero rulesets / secrets / variables / protection
      applied, no template files written.

## 3. Ref resolution and clone

- [x] 3.1 Resolve the remcc ref: use `--ref <X>` if provided; else query
      `gh api repos/premeq/remcc/releases/latest --jq .tag_name`; else
      fall back to `main` with a warning.
- [x] 3.2 Shallow-clone `premeq/remcc` at the resolved ref into a tempdir
      (`git clone --depth 1 -b <ref>`). Register a cleanup trap so the
      tempdir is removed on any exit.
- [x] 3.3 Invoke the cloned `templates/gh-bootstrap.sh` against the
      target repo, passing through `ANTHROPIC_API_KEY` /
      `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` env vars when set.
      Interactive reads inside the script use `</dev/tty` so the
      `curl … | bash -s --` shape doesn't hang.
- [x] 3.4 Manual test: run `install.sh init` twice against the same repo;
      confirm no GitHub-side config diff between runs. Covered by
      `scripts/smoke-init.sh` Step 6 (protection / rulesets / actions-perms
      snapshots compared pre- vs post-second-run).

## 4. Template installation

- [x] 4.1 Copy templates from the cloned tempdir into the target tree:
      `opsx-apply.yml`, `claude/settings.json`, `openspec/config.yaml`.
- [x] 4.2 Before overwriting, snapshot which template-managed paths already
      exist in the target working tree (for the PR body).
- [x] 4.3 Write each template to its target path unconditionally, creating
      parent directories as needed.
- [x] 4.4 Generate `.remcc/version` containing `source_ref` (the resolved
      ref), `source_sha` (`git -C <tempdir> rev-parse HEAD`), and
      `installed_at` (ISO 8601 UTC). Write to target working tree.

## 5. Pull request creation

- [x] 5.1 Verify the operator is on `main` with a clean working tree before
      branching; refuse to run if working tree is dirty.
- [x] 5.2 Create branch `remcc-init` from current `main` (not `change/**`).
- [x] 5.3 Stage the four template-managed paths; commit with subject
      `Adopt remcc via install.sh init` and a body referencing the source ref.
- [x] 5.4 Push the branch to `origin`.
- [x] 5.5 Open a pull request to `main` via `gh pr create`. PR body MUST
      include: list of files written, explicit flag of any pre-existing
      paths from 4.2 ("you may have customizations here — verify the diff"),
      and a copy-pasteable smoke-test one-liner for post-merge.
- [x] 5.6 If the template diff is empty (re-install with no upstream
      changes), skip branch/commit/push entirely and print "already up to
      date".

## 6. Documentation

- [x] 6.1 Update `docs/SETUP.md`: hoist the `install.sh` one-liner to the
      top as the primary adoption flow; move the existing step-by-step
      checklist into a "Manual fallback" appendix preserved verbatim.
      Document both the `bash <(curl …)` and inspect-first shapes.
- [x] 6.2 Document the `.remcc/version` schema in SETUP.md.
- [x] 6.3 Update `README.md` to mention the curl one-liner as the primary
      install path.
- [x] 6.4 Ensure SECURITY.md and COSTS.md still accurately describe the new
      flow (likely no edits needed, but verify).

## 7. End-to-end verification

- [x] 7.1 Smoke-test `install.sh init` against a throwaway fresh target
      repo. Verify each `remcc-cli` spec scenario passes: install/help,
      prereq check, bootstrap idempotency, file overwrite + PR diff,
      version marker, PR opened with file list and pre-existing flags,
      no apply run triggered. Codified as `scripts/smoke-init.sh`; passed
      against `premeq/remcc-smoke` on 2026-05-14.
- [x] 7.2 Smoke-test against a target that already has a customized
      `.claude/settings.json`; verify the PR body flags it and the diff
      surfaces the overwrite. `scripts/smoke-init.sh` seeds an operator-
      shaped settings.json (`{"permissions":{"allow":["Bash(npm test)"]}}`)
      and asserts the seed token is absent from the post-init file —
      proving the overwrite — alongside the existing "PR body flags
      pre-existing paths" assertion.
- [ ] 7.3 Re-run `install.sh init` on the same target; verify "already up
      to date" path is hit (task 5.6). Automated by
      `scripts/smoke-postmerge.sh` Step 2 (after the PR merge in Step 1).
- [ ] 7.4 After merging the init PR, run the smoke-test one-liner from
      the PR body; confirm an apply run completes end-to-end. Automated
      by `scripts/smoke-postmerge.sh` Steps 3–4 (~$0.50–$5 Anthropic spend).

## 8. Release

- [x] 8.1 Tag a release on this repo so `install.sh`'s default ref
      resolution (`releases/latest`) returns a stable identifier rather
      than `main`. Released `v0.1.0` on 2026-05-14 targeting `main` at
      b70fe40; `gh api repos/premeq/remcc/releases/latest --jq .tag_name`
      now returns `v0.1.0`.
- [x] 8.2 Verify the curl one-liner against the tagged release for a
      third-party operator (uses `releases/latest`, fetches the script
      from the tag, clones the tag). Verified 2026-05-14 via
      `scripts/smoke-init.sh --ref auto`: ref resolved to `v0.1.0`,
      install.sh fetched from `/v0.1.0/install.sh`, install.sh omitted
      `--ref` and self-resolved via `releases/latest`, `source_ref`
      written as `v0.1.0`, all seven spec scenarios passed.
