# R5 — Adopter install surface, org-owned vs user-owned (private account)

> Snapshot taken 2026-05-15 from `templates/gh-bootstrap.sh`, `install.sh`,
> `openspec/specs/repo-adoption/spec.md`, `docs/SETUP.md`, `docs/SECURITY.md`.
> Feeds the R5 question: "do private accounts still make sense, what are
> the gaps?"

## TL;DR

The install is **identical** for org-owned and user-owned (private-account)
repos *except* secret scanning + push protection, which require GitHub
Advanced Security and so are skipped (with a warning) on user-owned private
repos. Nothing in `install.sh` or `gh-bootstrap.sh` branches on owner type;
the only branch is `secret_scanning_available()`, which keys on
`repo.private` and `repo.security_and_analysis`.

## What every adopter gets (both account types)

Written by `install.sh init` into the adopter repo:

- `.github/workflows/opsx-apply.yml` — apply workflow
- `.claude/settings.json` — runner-safe Claude Code defaults
- `openspec/config.yaml` — baseline OpenSpec config
- `.remcc/version` — install marker (ref + `installed_at`)

Applied by `gh-bootstrap.sh` to the GitHub side:

- Branch ruleset `remcc: require approval on main` on the default branch:
  `pull_request` (≥1 approval), `non_fast_forward`, admin bypass. Spec
  explicitly: "applies uniformly to user-owned and organization-owned
  repositories — no conditional branching on ownership type."
- Actions setting: `default_workflow_permissions=write`,
  `can_approve_pull_request_reviews=true` (lets `GITHUB_TOKEN` open PRs).
- Repo secrets: `ANTHROPIC_API_KEY`, `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`.
- Repo variables: `REMCC_APP_SLUG` (required), `OPSX_APPLY_MODEL` and
  `OPSX_APPLY_EFFORT` (optional; baked-in defaults: `sonnet` / `high`).
- Legacy `WORKFLOW_PAT` secret removed if present (post-migration cleanup).
- Idempotency smoke test on every run.

The remcc GitHub App itself is created **once by the operator** under their
personal account or org and reused across all their adopter repos — it is
not part of per-repo bootstrap.

## The one real difference

| Aspect | Org-owned repo | User-owned private repo |
|---|---|---|
| Secret scanning + push protection | Enabled if public, or private with GHAS | **Skipped** — GHAS is org-level only; script prints a warning and continues |
| Everything else above | Identical | Identical |

Code path: `gh-bootstrap.sh:166-199` (`secret_scanning_available`,
`configure_secret_scanning`). Logic: public → always available; private →
only if `security_and_analysis` is non-null (GHAS signal). User-owned
private repos cannot enable GHAS, so they land in the warn-and-continue
branch. The fallback is GitHub Actions log redaction of `ANTHROPIC_API_KEY`
— documented in `docs/SECURITY.md:121` ("Limitations on
private-without-GHAS repositories").

## Not differences (worth flagging, often assumed)

- **Ruleset** is identical. Spec line 489-498 makes this an explicit
  invariant.
- **GitHub App permissions, identity, PR authorship** are identical (App
  is operator-scoped, not repo-scoped).
- **Workflow file, Claude settings, OpenSpec config, version marker** are
  byte-identical.
- **Reversibility** (`install.sh` uninstall path / `gh-bootstrap.sh
  --uninstall`) is identical.

## Implications for R5

1. The "support both account types" promise is cheap to keep — there is
   exactly one code path that diverges, and it diverges via a feature
   detect, not an owner-type check.
2. The one real gap on user-owned private repos (no secret scanning) is
   a GitHub product limitation, not a remcc one. Closing it would require
   either dropping support for user-owned private adopters or accepting
   the documented Actions-log-redaction-only posture (current choice).
3. R2.3 (opt-in `.github/**` push ruleset) is the one piece of the
   roadmap that **would** introduce an org-only feature — needs
   re-scoping in that light.

## Resume notes

- If R5 narrows scope to org-only: the only code to delete is the
  `secret_scanning_available()` check and the warn branch. SETUP.md
  and SECURITY.md sections on "private-without-GHAS" go away.
- If R5 keeps both: no code work; this note is the answer to "what's
  the difference?" and the existing docs already say the same thing.
