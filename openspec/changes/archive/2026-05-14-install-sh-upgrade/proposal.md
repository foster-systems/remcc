## Why

R2.1 shipped `install.sh init` (curl-piped) so a fresh adopter can onboard in
one command, but adopted repos have no automated path back to remcc for
updates: the four template-managed files (`opsx-apply.yml`,
`.claude/settings.json`, `openspec/config.yaml`, `.remcc/version`) drift as
remcc evolves. Today an operator must hand-copy the new templates from a
sibling clone — the same friction R2.1 removed for onboarding. R2.2 closes
the loop with `install.sh upgrade`: read `.remcc/version`, resolve a newer
ref, overwrite the template-managed files, bump the marker (preserving
`installed_at`), and open a PR — mirroring `init` minus the one-time
bootstrap work.

## What Changes

- Add subcommand `upgrade` to `install.sh`: refresh the four
  template-managed files at a newer remcc ref and open a single PR.
- `upgrade` reuses `init`'s prereq verifier (admin on target, OpenSpec
  initialised, `.claude/` present, `pnpm-lock.yaml`, `package.json#
  packageManager: pnpm@<version>`, local tools) — operators who adopted
  via `init` already satisfy these.
- `upgrade` refuses to run on a target without `.remcc/version` at the
  repo root, with an error pointing at `install.sh init`.
- `upgrade` does NOT re-run `gh-bootstrap.sh`. Branch protection, rulesets,
  secrets, and repo variables are one-time `init` work; the upgrade
  workflow has no business touching GitHub-side config.
- Default ref resolution mirrors `init`: `releases/latest` on
  `premeq/remcc`, overridable via `--ref <tag-or-sha>`.
- Branch name: `remcc-upgrade` (single reused branch across upgrade
  attempts, mirroring `remcc-init`'s single-branch idempotency).
- Marker preservation: `.remcc/version`'s `installed_at` field SHALL be
  the date the operator first adopted, not the date of the most recent
  upgrade. `upgrade` reads the previous marker from
  `origin/main:.remcc/version` (or `origin/remcc-upgrade:.remcc/version`
  on re-run) — not from the working tree — to survive the
  branch-rebuilt-from-main step.
- Fix the latent same-bug site in `init`: `write_version_marker` reads
  from the working-tree path, but `create_init_branch` rebuilds the
  branch from `main` first so the prior file isn't there. The bug is
  harmless on `init` re-runs (same `source_ref`+`source_sha` → marker
  is bit-identical anyway) but the upgrade path exposes it by
  definition. Refactor the marker writer to take the previous marker's
  contents as input, with both callers reading from
  `origin/main:.remcc/version` (or the upgrade branch on re-run).
- PR body: title and body diff old → new ref/sha, list the four
  template-managed paths, flag any path whose pre-upgrade content
  differs from the new template (potential customization collision),
  and include a "watch your next apply run" pointer (no smoke-test
  one-liner — operator already ran one at `init`).
- Empty-diff short-circuit: if the new templates match what's already
  on `origin/main`, print `already up to date` and exit zero without
  creating a branch or PR (mirrors `init`'s 5.6 behaviour).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `remcc-cli`: ADD requirements for the `upgrade` subcommand (prereq
  reuse, marker presence check, ref resolution, template refresh,
  `installed_at` preservation, branch+PR, no-bootstrap-rerun, no-apply
  trigger). MODIFY the existing "install.sh init writes a version
  marker" requirement to clarify that `installed_at` survives `init`
  re-runs by reading the previous marker from `origin/main`, not the
  working tree (fixing the latent same-bug site).
- `repo-adoption`: MODIFY "Automated install path is provided" so it
  also covers the automated update path (`install.sh upgrade`). ADD a
  requirement that the `.remcc/version` marker's `installed_at` is
  preserved across upgrades.

## Impact

- New code in this repo: `cmd_upgrade` in `install.sh`, plus a small
  refactor of `write_version_marker` to accept the previous marker as
  input (so both `init` and `upgrade` can pass it from `origin/main`).
- New constants: `UPGRADE_BRANCH="remcc-upgrade"`,
  `UPGRADE_COMMIT_SUBJECT`.
- No changes to `templates/` content. `templates/gh-bootstrap.sh` is
  untouched (upgrade does not re-run it).
- New PR body builder: shares the file-listing scaffold with `init` but
  drops the smoke-test one-liner and the "pre-existing files" framing
  (every path pre-exists during an upgrade by definition).
- New verification surface: `scripts/smoke-upgrade.sh` mirroring
  `smoke-init.sh`'s shape (seed a target at an older remcc ref via
  `init`, merge the init PR, run `upgrade` pointed at a newer ref,
  assert PR opens with the expected diff and the marker bumps with
  `installed_at` preserved). Likely also a re-run-is-no-op assertion.
- `docs/SETUP.md`: append an "Upgrading remcc" subsection under the
  one-command-adoption block; document the curl one-liner for
  `upgrade` and the `--ref` override.
- `README.md`: mention `upgrade` alongside `init` in the one-liner
  pointer.
- No changes to `apply-workflow` spec, workflow internals, or the
  bootstrap script.
