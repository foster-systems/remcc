## 1. Logo asset

- [x] 1.1 Create `assets/` directory at the repo root
- [x] 1.2 Copy `/Users/przeluni/Downloads/remcc-logo.png` to `assets/logo.png` (verbatim, no re-encode)
- [x] 1.3 Verify `assets/logo.png` is a valid PNG (`file assets/logo.png` reports PNG image data)
- [x] 1.4 Stage `assets/logo.png` (binary; ensure git treats it as binary and not LFS unless an LFS attribute exists)

## 2. README rewrite — scaffold

- [x] 2.1 Replace `README.md` with the new structure: hero / pitch / why-remcc / quickstart / what-you-get / limitations / upgrade / docs / status-license
- [x] 2.2 Add centered hero block via `<div align="center">` containing logo (`<img src="assets/logo.png" width="180" alt="remcc logo">`), `# remcc`, and the tagline "Run Claude Code unattended — push a change branch, get a PR."
- [x] 2.3 Add badge row in the hero: license (shields static), "powered by Claude Code" (shields static endpoint link), "OpenSpec" (shields static endpoint link), GitHub last-commit (dynamic shields endpoint for `premeq/remcc`)

## 3. README rewrite — content

- [x] 3.1 Pitch paragraph: one paragraph naming the input (push to `change/<name>` with `@change-apply` opt-in commit), the work (Claude Code on a GitHub-hosted runner), and the deliverable (PR for normal review)
- [x] 3.2 "Why remcc" — three bullets covering: no laptop tether, normal PR review path, tight safety boundary (App-scoped token + branch protection + `change/**` ruleset)
- [x] 3.3 Quickstart section: the `install.sh init` one-liner in a fenced bash block, followed by one sentence summarising what it does, and a link to `docs/SETUP.md` for the full flow
- [x] 3.4 "What you get" section: 5–6 bullets covering the change-branch trigger with `@change-apply` opt-in, GitHub App identity scoped to `change/**`, branch-protected `main`, per-run model/effort overrides (link to SETUP.md anchor), draft-on-failure PRs, `install.sh upgrade` flow
- [x] 3.5 Limitations section: pnpm-only, Claude Code only, GitHub Actions only, OpenSpec `/opsx:apply` only, one invocation per change — kept tight (≤ ~10 lines including heading); deeper hardening caveats link to `docs/SECURITY.md`
- [x] 3.6 Upgrade section: `install.sh upgrade` one-liner, one sentence, link to `docs/SETUP.md#upgrading-remcc`
- [x] 3.7 Docs section: three-line link list to `docs/SETUP.md` / `docs/SECURITY.md` / `docs/COSTS.md`, each with a one-line description
- [x] 3.8 Status & license footer: one paragraph naming v1 single-repo adoption maturity, linking to `openspec/changes/archive/`, and stating "MIT — see [LICENSE](LICENSE)"

## 4. Content audit against current functionality

- [x] 4.1 Confirm README mentions GitHub App identity (App ID / slug / private key) and does NOT mention the retired `WORKFLOW_PAT`
- [x] 4.2 Confirm README mentions the `@change-apply` opt-in commit-subject trigger (not an always-on push trigger)
- [x] 4.3 Confirm README references `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` knobs without restating the full precedence table (link to SETUP.md)
- [x] 4.4 Confirm README references both `install.sh init` and `install.sh upgrade`
- [x] 4.5 Confirm no removed or fictional anchors are linked (verify `docs/SETUP.md#upgrading-remcc` exists in the doc)

## 5. Rendering check

- [x] 5.1 Render `README.md` locally (e.g. `gh markdown-preview` or any local markdown previewer) and confirm: logo renders, hero is centered, badge row aligns
- [ ] 5.2 Push to a `change/polish-readme-and-logo` branch and inspect the rendered README on github.com on the branch view; confirm hero + pitch are above the fold on a 1280×800 viewport
- [ ] 5.3 Confirm relative link `assets/logo.png` resolves on github.com (image renders, not broken-icon)

## 6. Validation

- [x] 6.1 Run `openspec validate polish-readme-and-logo --strict` and resolve any issues
- [x] 6.2 Run `openspec status --change polish-readme-and-logo` and confirm all required artifacts are `done`
