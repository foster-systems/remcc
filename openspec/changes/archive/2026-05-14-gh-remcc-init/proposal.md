## Why

Today's adoption takes eight manual touches (prereq checklist, three
template files with hand-merge semantics, setup-branch + PR, bootstrap
script, smoke test). Friction concentrates in YAML hand-merges and the
two-clones-side-by-side pattern, neither of which leaves any version
breadcrumb in the adopter repo. R2 asks for one-command onboarding;
this change delivers the install half.

## What Changes

- Ship `install.sh` at this repo's root, invokable over curl as
  `bash <(curl -fsSL …/install.sh) init`. No new repo, no rename.
- Add subcommand `init`: prereq check → fetch templates and
  `gh-bootstrap.sh` from a pinned remcc ref → run bootstrap → write
  template-managed files → create `remcc-init` branch → open PR for
  operator review.
- Adopter repo gains a new file: `.remcc/version`, recording the
  remcc tag the templates were sourced from. Required for the future
  `upgrade` subcommand (out of scope here).
- Template-managed files written by `init`:
  - `.github/workflows/opsx-apply.yml`
  - `.claude/settings.json`
  - `openspec/config.yaml`
  - `.remcc/version`
- Init does **not** auto-merge with pre-existing files. It overwrites
  and opens a PR; the operator handles collisions in the diff.
- Init does **not** run a smoke-test apply. PR review is the operator's
  checkpoint; a smoke-test one-liner stays documented for them to run.
- `docs/SETUP.md` gains a new "one-command adoption" path at the top;
  the existing step-by-step is reframed as the manual fallback for
  adopters who can't or won't pipe a remote script to bash.

## Capabilities

### New Capabilities
- `remcc-cli`: the `install.sh` invocation surface — distribution
  shape (curl-piped), subcommands, version-marker contract,
  exit-code conventions.

### Modified Capabilities
- `repo-adoption`: requirements added for the automated install path
  (one-command onboarding via the curl-piped `install.sh`) and for the
  `.remcc/version` marker file. Existing manual-path requirements
  remain; they become the documented fallback.

## Impact

- New file in this repo: `install.sh` at the repo root.
- New file in adopter repos: `.remcc/version` (kebab path, minimal
  schema: source ref, source sha, installed_at).
- `templates/gh-bootstrap.sh` becomes a dependency fetched by
  `install.sh` at install time (via `git clone --depth 1` of this
  repo at the resolved ref); it is not separately vendored. Gains
  `WORKFLOW_PAT` prompt / upload / uninstall handling that mirrors
  the existing `ANTHROPIC_API_KEY` treatment — required because
  `opsx-apply.yml` has needed this secret since `efdee3b` and the
  bootstrap was the only adoption-time seam still missing it.
- `docs/SETUP.md` restructured: automated path first, manual path
  appendix. Prereq table gains a `WORKFLOW_PAT` row and a
  `package.json#packageManager` row (the latter required because
  `pnpm/action-setup@v4` has no `version:` input in the workflow
  template and errors when the field is absent — surfaced by the
  task 7.4 smoke run on a target seeded without it).
- `README.md`: top-level pointer to the curl one-liner.
- No changes to `apply-workflow` spec or workflow internals.
