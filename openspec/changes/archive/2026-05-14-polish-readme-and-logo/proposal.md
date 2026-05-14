## Why

The repository's `README.md` predates the GitHub App migration, the `install.sh upgrade` flow, and the `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` configuration knobs. It is also a plain prose page with no logo, no badges, no skimmable structure, and no clear value-proposition framing — which undersells the project to drive-by visitors. The repo is now stable enough to invite trial: it deserves a sleek, GitHub-best-practice landing page that explains *what remcc gives you*, shows the one-liner, and makes the on-ramp obvious.

## What Changes

- Add a project logo at `assets/logo.png` (sourced from a PNG the operator supplies locally) and reference it from the README hero.
- Rewrite `README.md` end to end as a GitHub-best-practice landing page: centered hero (logo + tagline + badges), one-paragraph value proposition, "Why remcc" benefits block, animated/static quickstart, capabilities snapshot, limitations, links to `docs/SETUP.md` / `docs/SECURITY.md` / `docs/COSTS.md`, and a "Status & license" footer. Tone is inviting, not exhaustive.
- Refresh the content for current functionality: `install.sh init` *and* `install.sh upgrade`, the GitHub App identity (App ID / private key / slug) instead of the legacy PAT, the `@change-apply` opt-in trigger, the `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` knobs, and the `.remcc/version` marker.
- Add a small badges row in the hero (license, "powered by Claude Code", OpenSpec, last-commit) sourced from public shields — no new CI required.
- Keep the README short (skimmable on one screen for the hero + value prop; full page ≤ ~200 lines). Detail lives in `docs/`.

## Capabilities

### New Capabilities
- `project-readme`: contract for the repository's root `README.md` and logo asset — required sections, the value-proposition framing, the install one-liner, the link-out set, and the logo asset location. Makes the README a first-class artifact rather than incidental prose, so future changes that alter user-facing behaviour have a clear obligation to update it.

### Modified Capabilities
*(none — the README is a new presentational surface; `repo-adoption` already covers the `docs/` set and is unchanged here.)*

## Impact

- **Files added**: `assets/logo.png` (binary, ~20 KB), `openspec/specs/project-readme/spec.md` once archived.
- **Files modified**: `README.md` (full rewrite).
- **No code, workflow, template, or install-script changes** — this is documentation-surface only.
- **No new dependencies, CI jobs, or runtime behaviour.** Badges link to public shields.io endpoints; rendering is GitHub-side.
- **Downstream**: target repos that adopt remcc are unaffected — the README is the source repo's landing page, not a template shipped to adopters.
