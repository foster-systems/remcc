## Context

`docs/SETUP.md` walks a new adopter through 8 manual touches. The
bottleneck is template hand-merge plus the "two clones side-by-side"
pattern that leaves no version breadcrumb. Exploration in
`openspec/explore/R2-onboarding.md` rejected a reusable-workflow
approach (Block A) and settled on automated copy/paste with adopter
review via PR. This change delivers the install half (R2.1); the
upgrade half (R2.2) is a follow-on.

## Goals / Non-Goals

**Goals:**
- One command — `bash <(curl -fsSL …/install.sh) init` — replaces
  SETUP.md steps 1–7.
- Single repo, no rename: distribution stays under `premeq/remcc`.
- Write a `.remcc/version` marker so the future `upgrade` subcommand
  can identify the installed ref.
- Preserve the existing manual flow as a documented fallback.

**Non-Goals:**
- `upgrade` subcommand (deferred to R2.2).
- Three-way merge for pre-existing template files. Init overwrites;
  operator handles collisions in the PR diff.
- Smoke-test apply during install (would spend Anthropic tokens on
  every adoption).
- gh-extension distribution (rejected during implementation —
  `gh extension install` requires the repo to be named `gh-<name>`,
  which would force a rename of `premeq/remcc` or splitting the
  installer into a second repo).
- Reusable-workflow architecture (rejected during exploration).
- Generalising beyond pnpm-managed JavaScript repos (v1 scope holds).
- Update notifications, scheduled cron, auto-merge.

## Decisions

### Distribution: curl-piped `install.sh`

Adopters already need `gh` authenticated; `install.sh` is Bash +
`gh`/`git` end-to-end. Distributing as
`bash <(curl -fsSL .../install.sh) init` is the lowest-friction
single-command shape that keeps the repo named `premeq/remcc`.

Alternatives considered:
- **`gh` extension** — clean install + upgrade surface, but
  `gh extension install <owner>/<repo>` requires the repo name to
  start with `gh-`. Adoption would either force renaming
  `premeq/remcc` → `premeq/gh-remcc` (collides with the project
  name) or splitting the installer into a second repo (template
  edits would have to ripple across two repos at release time).
  Neither is worth the marginal ergonomic win over curl.
- **npm package** — adds a Node toolchain requirement for what is
  fundamentally a Bash + `gh api` script.

### Implementation language: Bash

The bootstrap script is already Bash. Keeping `install.sh` in Bash
lets it share idioms (and ultimately invoke) `gh-bootstrap.sh`
directly. Alternatives (Go, Node) trade install simplicity for a
compiled artifact or a runtime dependency. Not worth it for a tool
whose core is `gh api` + file copies.

### Templates and bootstrap: fetched at install time, ref-pinned

`install.sh` resolves a remcc ref (default: latest release tag on
`premeq/remcc`; overridable with `--ref <tag-or-sha>`) and shallow-
clones this repo at that ref into a tempdir. It then reads templates
and the bootstrap script from that clone. The clone is removed at
exit.

Rationale:
- The curl-piped shape rules out "sibling-file vendoring" — the
  installer arrives over stdin/fd, with no companion files on disk.
- Pinning to a tag (not `main`) gives a stable, identifiable
  `source_ref` to record in `.remcc/version` and removes
  HEAD-of-`main` race conditions during release windows.
- `git clone --depth 1 -b <ref>` works without GitHub auth for
  public repos and falls back through `gh` when needed.

### Prompt-handling: process substitution as the documented shape

`install.sh` reads `ANTHROPIC_API_KEY` (and optionally the apply
config vars) interactively. Under naive `curl … | bash` piping,
stdin is the curl pipe and prompts hang. The documented one-liner
uses `bash <(curl …)`, which keeps stdin attached to the TTY.
The `| bash -s --` shape continues to work because every prompt
inside the script reads via `</dev/tty`.

### File-overwrite policy: write, don't prompt

If a template-managed file exists, `init` overwrites it. The
operator sees the diff in the PR and decides what to keep.
Confirmed in exploration thread (2026-05-13): "leave it to adopter
to handle."

Alternative: refuse to overwrite, ask operator to merge by hand,
then re-run. Honest but breaks the one-command promise.

### PR branch name: `remcc-init`

Regular branch, not `change/**`. Reason: the bootstrap step will
install a ruleset that confines non-admin actors to `change/**`,
but the operator running `init` is admin (bypasses the ruleset),
and using `change/**` here would semantically suggest an OpenSpec
change branch — which this isn't.

### `.remcc/version` schema: JSON, minimal

```json
{
  "source_ref": "v0.2.0",
  "source_sha": "abc123…",
  "installed_at": "2026-05-13T10:30:00Z"
}
```

`source_ref` is the resolved tag (or `--ref` value). `source_sha`
is the commit `git clone --depth 1` landed on. `installed_at` is
informational. Future `upgrade` reads `source_sha` to compute the
diff between installed and desired refs.

### Smoke test: out of scope for `init`

The PR review *is* the operator's checkpoint. The PR body includes
a copy-pasteable smoke-test one-liner the operator can fire after
merging. Cost of an auto-smoke test (~$0.50–$5 in Anthropic tokens
per adoption) isn't worth the marginal confirmation.

## Risks / Trade-offs

**[Operator merges PR without reading diff]** → Mitigation: PR body
explicitly lists files written and flags pre-existing files by path
("these files existed before init; verify the diff hasn't
clobbered your customizations").

**[`curl … | bash` audit concern]** → Mitigation: README/SETUP
explicitly document the inspect-first form (`curl … -o install.sh
&& less install.sh && bash install.sh init`). `bash <(curl …)` is
the *promoted* one-liner; the audit-first form is one paragraph
away.

**[Network failure during install]** → Mitigation: the script does
exactly one clone (`git clone --depth 1 -b <ref> …`) and fails fast
with the underlying git error. No partial write — template install
runs only after a successful clone, and any `gh api` mutation also
runs after the clone.

**[Operator's gh CLI lacks admin perms]** → bootstrap already errs
out clearly on 403. `install.sh` runs the same bootstrap.

**[Adopter's repo has unusual layout (monorepo, non-root
pnpm-lock.yaml)]** → Out of scope. Prereq check fails fast with
the same message as today's manual flow.

**[Cross-platform: macOS vs Linux for Bash compatibility]** →
Bootstrap script already runs on both. `install.sh` follows the same
constraints (POSIX Bash, GNU and BSD `sed`/`grep` differences
already handled). `bash <( … )` process substitution works on
macOS bash 3.2 and modern Linux bash.

## Resolved Questions

- **Extension repo layout / distribution model** — resolved as
  curl-piped `install.sh` in this repo (see Decisions above). The
  earlier `gh` extension framing was rejected once it became clear
  that `gh extension install` requires a `gh-` repo prefix.
- **Target is not a git repo / no `origin` remote** — `install.sh`
  fails fast with a clear message (consistent with bootstrap).
