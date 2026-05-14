## Context

The current `README.md` is 71 lines of plain prose. It correctly states what remcc does and how to install it, but:

- predates the **GitHub App** migration (the bot now authenticates as an App with `REMCC_APP_ID` / `REMCC_APP_PRIVATE_KEY` / `REMCC_APP_SLUG`, not via `WORKFLOW_PAT`);
- predates the **`@change-apply` opt-in trigger** (pushing to `change/<name>` only triggers the workflow when the head commit subject opts in);
- predates the **`OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT`** repository variables and trailer-based overrides;
- predates the **`install.sh upgrade`** flow and the `.remcc/version` marker;
- has no logo, no badges, no visual hierarchy, and no skimmable value-prop framing.

GitHub-style landing pages have converged on a recognisable shape: centred hero (logo + tagline + badges), one-paragraph pitch, quickstart-above-the-fold, a "why this exists / what you get" block, then deeper links. The current README has none of that scaffolding, which makes the project feel earlier-stage than it is.

This is a **documentation-surface change only**: no workflow, install-script, or template behaviour changes. The README is the source repo's landing page; it is not shipped to adopters.

## Goals / Non-Goals

**Goals:**
- Communicate the value proposition of remcc in under 30 seconds of scanning.
- Make the install one-liner the most prominent actionable element after the hero.
- Reflect *current* functionality accurately (GitHub App, opt-in trigger, model/effort knobs, upgrade flow).
- Adopt a GitHub-best-practice visual shape (centred hero, badges row, skimmable sections, link-outs to `docs/`).
- Add a project logo at a conventional path (`assets/logo.png`) so it can be referenced from the README and reused (social cards, future docs site).
- Keep the page short: hero + value prop fit one screen; total length ≤ ~200 lines.

**Non-Goals:**
- Replacing `docs/SETUP.md`, `docs/SECURITY.md`, or `docs/COSTS.md`. The README links into them; it does not duplicate them.
- Building a docs site, social card, or marketing site.
- Adding new CI jobs, link checkers, or badge-generation tooling.
- Generalising the README to non-pnpm or non-Claude-Code adopters — v1 scope still applies.
- Changing the template README (if any) shipped to adopters — this change only touches the source repo's landing page.
- Editorial copy in `docs/*.md` beyond the minimum needed to keep cross-links accurate.

## Decisions

### Decision: Use a centered hero block with HTML `<div align="center">`

GitHub markdown does not centre images or text through CommonMark alone. We will use a small inline `<div align="center">…</div>` wrapper for the hero (logo, project name, tagline, badges row). This is the convention used by repos like `vite`, `astro`, `bun`, and `oven-sh/bun`, and it renders correctly on github.com and in most rendered mirrors.

*Alternatives considered:*
- *Left-aligned only* — works but reads as less polished and gives less room for badges; rejected because the user explicitly asked for "best GitHub style".
- *A picture/source-tag hero with light/dark variants* — defer until we have a dark-mode logo asset; not in scope.

### Decision: Place the logo at `assets/logo.png`

Conventional location, matches the answer chosen in the proposal flow, and keeps a clear namespace for future assets (favicons, dark variant, social card) without polluting the repo root. The image is referenced from the README via the relative path `assets/logo.png` so it resolves both on github.com and in offline mirrors.

*Alternatives considered:*
- *`docs/logo.png`* — couples the logo to the docs set; rejected.
- *Root-level `logo.png`* — clutters the repo root; rejected.

### Decision: Use shields.io for badges, no custom badge service

Badges are sourced from `img.shields.io` URLs only, so we incur no infra: license badge (static from `LICENSE`), "powered by Claude Code" (static endpoint link), "OpenSpec" (static endpoint link), GitHub last-commit (dynamic shields endpoint against `premeq/remcc`). All four are hot-linked PNG/SVG with no build step.

*Alternatives considered:*
- *Self-hosted SVG badges committed to `assets/`* — rejected; static badges drift quickly.
- *No badges at all* — rejected; the user asked for GitHub-best-practice style and badges are part of that idiom.

### Decision: README structure (top-to-bottom)

1. **Hero** — `<div align="center">` with logo (≤180px wide), `# remcc`, one-line tagline, badges row.
2. **Pitch** — single paragraph: "Run Claude Code unattended on GitHub Actions. Push a `change/<name>` branch with an OpenSpec proposal and an `@change-apply` opt-in commit; remcc implements it on a runner and opens a PR for review."
3. **Why remcc** — three bullets (no laptop tether, normal PR review, tight safety boundary). Each bullet ≤ 2 lines.
4. **Full walkthrough in 3 minutes** — single end-to-end walkthrough replacing the originally planned separate `Quickstart` and `What you get` sections. Opens with a one-line summary of the three phases (author locally → apply on a runner → review and merge locally) and a small horizontal Mermaid flow diagram of those phases. Then eight numbered step subheadings (`01`–`08`, rendered as monospace pills) covering: prerequisites, installation (`install.sh init` one-liner), `claude /opsx:propose`, the `@change-apply` trigger commit with `Opsx-Model:` / `Opsx-Effort:` trailers, `/opsx:apply` on the ephemeral Ubuntu runner, the bot-authored PR via the GitHub App, local `claude /opsx:verify` + `claude /opsx:archive`, and approve-and-merge. Horizontal-rule + bold lane label between steps 4↔5 and 6↔7 marks the local→runner→local handoff. The capability points originally planned for `What you get` are folded into the corresponding walkthrough steps (App identity in step 6, model/effort overrides in step 4, draft-on-failure in step 6).
5. **Limitations** — keep the existing concise bullet list (Claude Code only, GitHub Actions only, OpenSpec only, pnpm-only, one invocation per change). Move org-vs-user-owned hardening caveat into `docs/SECURITY.md` link rather than inline.
6. **Upgrade** — the `install.sh upgrade` one-liner with one sentence; link to `docs/SETUP.md#upgrading-remcc`.
7. **Docs & links** — three-line link list to `docs/SETUP.md`, `docs/SECURITY.md`, `docs/COSTS.md`.
8. **Status & license** — one paragraph: maturity ("v1, single-repo adoption"), link to OpenSpec changes archive, license line ("MIT — see `LICENSE`").

This ordering puts the actionable one-liner above the fold for a returning user (now step `02` of the walkthrough), and the value-prop bullets above the fold for a drive-by. Limitations stay visible but no longer dominate. The merged walkthrough replaced the original 9-section structure during implementation because the install one-liner, capability snapshot, and review flow read more naturally as one end-to-end story than as three separate bullet-list sections.

### Decision: Tagline copy

"Run Claude Code unattended — push a change branch, get a PR." Short, verb-led, mentions the trigger surface and the deliverable. Avoids "AI" buzzword inflation and stays faithful to what the project actually does.

*Alternatives considered:*
- *"Claude Code on GitHub Actions"* — accurate but flat; rejected.
- *"Remote, unattended Claude Code runs"* — fine but doesn't convey the PR outcome; rejected.

### Decision: Logo provenance is the user-supplied PNG

The user is providing a PNG at `/Users/przeluni/Downloads/remcc-logo.png` (1024×820, RGBA, 19,855 bytes). We will copy it verbatim into `assets/logo.png`. No re-encoding, no resizing — GitHub handles inline scaling, and the source PNG is already small enough that page weight is not a concern.

*Alternatives considered:*
- *Down-sample to 256×~205* — premature optimisation; the file is < 20 KB.
- *Convert to SVG* — would require a re-trace; rejected.

## Risks / Trade-offs

- **Risk**: Cross-link rot — README will link into `docs/SETUP.md#upgrading-remcc`, `docs/SECURITY.md`, etc. → Mitigation: anchors used are existing ones (verify during implementation); no anchor changes in scope.
- **Risk**: Shields.io endpoint changes / latency → Mitigation: badges are decorative, not load-bearing; a broken badge degrades to GitHub's broken-image icon but does not block reading the page.
- **Risk**: HTML in markdown (the `<div align="center">` hero) renders inconsistently outside github.com (e.g. some markdown viewers ignore `align`) → Mitigation: content remains readable left-aligned; this is purely a cosmetic degrade.
- **Risk**: Logo size in repo (~20 KB) lives on `main` forever → Acceptable; comparable repos commit larger assets, and the file is small.
- **Risk**: README and `docs/` drift on subsequent functional changes → Mitigation: the new `project-readme` capability spec encodes required sections and content invariants, so future change-proposals that alter user-facing behaviour have a clear obligation to update the README. Verification stays at the spec level (no inline checks).
- **Trade-off**: Centred hero uses HTML — a small departure from pure markdown — but is the only practical way to achieve the GitHub-best-practice hero shape the user asked for. Accepted.

## Migration Plan

This is a documentation-surface change with no runtime impact. No migration is required; merging the change publishes the new README on `main`. Rollback is `git revert` on the resulting commit.

## Open Questions

None. The logo path, logo destination, README scope, and tagline are decided above; the spec will encode the structural invariants and the implementation tasks will fill in the prose.
