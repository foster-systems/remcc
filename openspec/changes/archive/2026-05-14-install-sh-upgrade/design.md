## Context

R2.1 delivered `install.sh init` (curl-piped): one command takes a fresh
target repo through prereqs → bootstrap → template install → PR. It
writes `.remcc/version` recording the source ref/sha and an
`installed_at` timestamp. The exploration doc
(`openspec/explore/R2-onboarding.md`) and the next-session briefing
(`openspec/explore/R2.2-upgrade.md`) both call for a companion `upgrade`
subcommand: the periodic refresh path that lets adopters pull newer
remcc templates without a hand-merge.

R2.2 inherits all R2.1 architectural decisions (curl-piped distribution,
Bash implementation, ref-pinned template fetch, write-don't-prompt
overwrite policy, single reused branch, `.remcc/version` schema).
Nothing in those decisions needs to be revisited. The work here is the
narrower question of how `upgrade` differs from `init` and how the
shared internals get refactored.

Two state-on-entry facts shape the design:

1. **`installed_at` preservation matters now.** For `init` it was
   informational and never re-read after the first write. For
   `upgrade`, `installed_at` is the operator's adoption date — losing
   it on every upgrade would defeat the purpose of recording it.
2. **`write_version_marker` has a latent bug.** It reads the previous
   marker from the *working tree* to preserve `installed_at`, but
   `create_init_branch` runs `git checkout -b … main` first, so the
   prior marker isn't in the working tree when the writer runs. The
   bug is harmless on `init` (same `source_ref`+`source_sha` →
   `now` is rewritten but the resulting file is bit-identical anyway)
   but the upgrade path exposes it by definition.

## Goals / Non-Goals

**Goals:**

- One command — `bash <(curl -fsSL …/install.sh) upgrade` — refreshes
  every template-managed file in an adopted repo and opens a single PR
  for operator review.
- Preserve `.remcc/version`'s `installed_at` across upgrades (and fix
  the latent same-bug site in `init`).
- Refuse to run on a target that hasn't been adopted (no
  `.remcc/version`) — steer the operator at `install.sh init` instead.
- Reuse `init`'s prereq verifier verbatim. Don't re-run
  `gh-bootstrap.sh`.
- Idempotent re-runs: running `upgrade` twice against the same target
  with the same source ref produces no second PR.

**Non-Goals:**

- Auto-merge of the upgrade PR. Operator reviews and merges.
- Cron / scheduled upgrade. Operator triggers `upgrade` when they want
  it (explore-doc decision 2026-05-13).
- Smoke-test apply during upgrade. The operator's next real apply run
  is the integration test; running a paid smoke for every upgrade adds
  cost without confirmation value.
- Three-way merge of template files. Overwrite-and-PR (same as `init`).
- Re-running `gh-bootstrap.sh`. Branch protection, rulesets, secrets,
  and repo vars are one-time `init` work.
- Recording a `managed_paths` list in `.remcc/version`. The new tag's
  `install.sh` knows the file list via its own `TEMPLATE_PATHS` array;
  that's authoritative.
- Generalising beyond the four current template-managed paths.

## Decisions

### `upgrade` mirrors `init`'s shape but skips bootstrap

`cmd_upgrade` runs: resolve target repo → verify prereqs (same checks
as `init`) → verify `.remcc/version` exists on `origin/main` → verify
clean `main` → resolve ref → clone remcc at ref → install templates →
short-circuit if no diff → create branch, commit, push, PR.

The two skips vs. `init` are:

- **No `run_bootstrap` call.** Bootstrap is one-time GitHub-side work
  done at adoption.
- **No "did `.claude/` exist before" snapshot.** During upgrade, every
  template-managed path exists by definition. The PR body's
  "pre-existing collision" framing from `init` is replaced by a
  per-path "this file differs from the template" flag computed by
  diffing the working-tree path against the new template source.

### Pre-flight check: `.remcc/version` must exist on `origin/main`

If `origin/main:.remcc/version` is absent, `upgrade` exits non-zero
with a message pointing at `install.sh init`. This is the "have you
adopted yet?" check.

Read from `origin/main`, not the working tree, for the same reason
the marker preservation reads from `origin/main`: it survives
`git checkout -b … main` and is unambiguous about what's actually
committed.

Implementation: `git fetch origin main` then
`git cat-file -e origin/main:.remcc/version` (exit code is the
existence check, no file contents needed for this step).

### `installed_at` preservation: read previous marker from `origin/main`

`write_version_marker`'s current shape — read previous values from a
filesystem path passed in — is right; the bug is in *which path* the
caller hands it. The fix is:

1. Refactor the caller side. Both `init` and `upgrade` resolve the
   previous marker contents before branching:
   - `init` reads `origin/main:.remcc/version` if it exists, falling
     back to the working tree (for the genuinely-first-time case),
     and stashes the JSON contents in a variable.
   - `upgrade` reads `origin/main:.remcc/version` (must exist; the
     pre-flight ensured it) and, if a `remcc-upgrade` branch already
     exists on origin, prefers `origin/remcc-upgrade:.remcc/version`
     to keep `installed_at` stable across re-runs.
2. Pass the previous JSON contents (or empty) to `write_version_marker`
   instead of having the writer read from disk.

Function signature changes from:

```bash
write_version_marker <target_path> <ref>
```

to:

```bash
write_version_marker <target_path> <ref> <prev_marker_json_or_empty>
```

`prev_marker_json` is the literal JSON bytes (parsed via `jq` inside
the function). Empty means "no previous marker; use `now`".

Why pass the JSON rather than a file path: the previous marker lives
in a git ref, not the filesystem. Writing it to a tempfile just to
pass a path is fussier than passing the bytes.

Alternative considered: keep `write_version_marker` reading from
disk, but stage the previous marker into the working tree first. Two
problems: (1) it pollutes the working tree with a file the operator
might mistake for current state; (2) it's an extra `git show` + write
+ overwrite step the call sites have to remember.

### Branch name: `remcc-upgrade` (single, reused)

Mirrors `init`'s `remcc-init`. The "PR already open for this branch"
idempotency check (the same `gh pr list --head <branch>` shape) drops
in verbatim. Force-with-lease push handles the "branch existed from a
previous abandoned attempt" case.

Alternative considered: tag-suffixed branch (`remcc-upgrade-<ref>`).
Cleaner audit trail per upgrade attempt, but breaks the simple
single-branch idempotency check and accumulates stale branches when
operators upgrade frequently. The PR title/body carry the ref
information already.

### Refuse `upgrade` on dirty working tree, mirroring `init`

`verify_clean_main` already errs on non-`main` HEAD or dirty working
tree. Reuse it verbatim. Operators who want to upgrade from a
non-`main` branch are doing something wrong (the upgrade PR has to
target `main` anyway, and rebuilding the branch from a non-`main`
base would lose unrelated commits).

### PR body shape

Reuse the `build_pr_body` scaffold but pivot the framing:

- **Title:** `Upgrade remcc to <new_ref> via install.sh upgrade`
- **Source line:** `Upgrading remcc <prev_ref> (<prev_sha>) → <new_ref>
  (<new_sha>)` so the reviewer sees both endpoints.
- **Files written:** same bullet list as `init`.
- **Replaces the "pre-existing files" section** with a "Local diffs
  before upgrade" section computed by `diff -q` between the
  working-tree file (before overwrite) and the template source. Paths
  whose `diff -q` shows differences are flagged: "this file diverged
  from the previous template; verify the merge in the PR diff."
- **No smoke-test one-liner.** Operator already ran one at `init`;
  the next real apply run exercises the upgraded workflow.
- **Pointer to next apply run:** brief note that the upgraded
  workflow takes effect once this PR merges — the operator's next
  `change/**` push is the real-world verification.

### Empty-diff short-circuit before opening PR

After `install_templates`, if `git status --porcelain --
"${TEMPLATE_PATHS[@]}"` is empty, print `already up to date` and exit
zero without branching. Mirrors `init`'s 5.6 path.

### `--ref` defaulting: latest release tag, same as `init`

`resolve_ref` already handles this. Reuse without modification. The
`main` fallback warning fires the same way when no releases exist.

### Do not extend `.remcc/version` schema

Rationale (echoing the explore doc's resolved thread): `TEMPLATE_PATHS`
in the *new* tag's `install.sh` is the authoritative list of files
the upgrade manages. Since `upgrade` is *running* the new
`install.sh`, it already has this list. Recording it in the marker
would be a redundant copy that could go stale.

This means an upgrade that drops a template-managed file (e.g., a
future remcc tag that decides `openspec/config.yaml` is no longer
template-managed) would not auto-remove the file from adopted repos —
the array tells `upgrade` what to write, not what to clean up.
Out of scope here; flag if it ever comes up.

### Help text and `--help` integration

- `install.sh --help` (root `usage_root`) lists `upgrade` as a second
  subcommand.
- `install.sh upgrade --help` (new `usage_upgrade`) describes the
  flow, options (`--ref`), behaviour, and prereqs.
- `usage_init` already documents environment passthrough; `upgrade`
  needs none of those env vars (no `gh-bootstrap.sh` invocation, no
  `ANTHROPIC_API_KEY` or `WORKFLOW_PAT` prompt), so its help is
  shorter.

## Risks / Trade-offs

**[Operator runs `upgrade` after manually customizing template files
post-`init`]** → Mitigation: the upgrade PR shows the diff. The
"Local diffs before upgrade" section explicitly flags every path
where the working-tree content differed from the *previous* template,
giving the operator a list of files where their customizations are
about to be overwritten by the new template. Same overwrite-and-PR
policy as `init`; same operator-review checkpoint.

**[Operator hasn't merged a previous `remcc-upgrade` PR; runs `upgrade`
again]** → Mitigation: same single-branch+idempotency-check pattern as
`init`. The existing-PR check (`gh pr list --head remcc-upgrade`)
short-circuits before opening a duplicate. Force-with-lease push
updates the branch tip if the new templates differ from the abandoned
attempt. Operator sees one PR with the most-recent target ref.

**[`.remcc/version` is corrupt or missing fields]** → Mitigation:
`upgrade`'s pre-flight only checks existence on `origin/main`. The
marker writer uses `jq -r '.field // empty'` so missing fields fall
back to `now`/empty rather than crashing. A truly malformed JSON
file fails `jq` and is treated as "no previous marker" (i.e.,
`installed_at` resets to now). Documented in the spec scenario.

**[Operator on `v0.1.0` (which lacked `WORKFLOW_PAT` handling) runs
`upgrade` from a newer tag]** → Mitigation: not this change's
problem. `upgrade` doesn't re-run `gh-bootstrap.sh`, so any missing
secrets stay missing; that's documented under the v0.1.0 → v0.1.1
upgrade recipe in `releases/v0.1.1` notes. If a future remcc release
needs to add a secret, that's a `bootstrap-upgrade` workflow (out of
scope here).

**[The `init` marker-preservation refactor breaks R2.1's behaviour]** →
Mitigation: behaviour-equivalent. `init`'s previous code reads from
the working tree (which is empty after `create_init_branch` rebuilds
from main) and falls through to `now`. The refactor reads from
`origin/main` (also empty for the genuinely-first-time case) and
falls through to `now`. For the re-install case, the previous code
also fell through to `now` (working tree empty); the new code reads
from `origin/main:.remcc/version` (which exists on the re-install
case) and preserves `installed_at`. Net effect: re-runs of `init`
will now preserve `installed_at` (previously they re-stamped it),
which matches what the comment in `write_version_marker` already
claimed. Verify via `scripts/smoke-init.sh`'s existing assertions
plus a new "re-run preserves installed_at" check.

**[Cross-platform: `git cat-file -e` behaviour, GNU vs BSD]** →
`git cat-file -e <ref>:<path>` is part of git core; behaviour is
identical on macOS and Linux. No `sed`/`grep` quirks involved in the
upgrade-specific code paths. Bootstrap already handles
GNU-vs-BSD where it matters; `upgrade` doesn't go near those code
paths.

## Migration Plan

This is an additive change to `install.sh`. Deployment is the release
of a new remcc tag containing the `upgrade` subcommand. Adopters on
older tags continue to work via `init` (which is unchanged in
behaviour for the cases that matter; the `installed_at` preservation
becomes correct, not different in observable ways for already-running
adopters since their existing markers don't change until they re-run
`init` or run `upgrade`).

Rollback: tag a fix release if `upgrade` regresses. Operators not
running `upgrade` are unaffected.

## Open Questions

None blocking implementation. Two parking-lot items called out for
future iteration:

- **Template removals.** If a future remcc release drops a path from
  `TEMPLATE_PATHS`, `upgrade` does not clean up the prior file. Today's
  set is stable; revisit when it actually shifts.
- **`bootstrap-upgrade` flow.** If a future remcc release adds a new
  secret/var/ruleset to `gh-bootstrap.sh`, adopters need to re-run it.
  Out of scope here; would be a separate `install.sh` subcommand or a
  documented one-off `bash <(curl …/gh-bootstrap.sh)` invocation.
