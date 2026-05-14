<div align="center">

<img src="assets/logo.png" width="180" alt="remcc logo">

# remcc

Run Claude Code unattended — push a change branch, get a PR.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Powered by Claude Code](https://img.shields.io/badge/powered%20by-Claude%20Code-6f42c1.svg)](https://claude.com/claude-code)
[![OpenSpec](https://img.shields.io/badge/spec-OpenSpec-2ea44f.svg)](https://github.com/Fission-AI/OpenSpec)
[![Last commit](https://img.shields.io/github/last-commit/premeq/remcc.svg)](https://github.com/premeq/remcc/commits/main)

</div>

Push a `change/<name>` branch carrying an OpenSpec proposal and an `@change-apply` opt-in commit; remcc runs `/opsx:apply` with [Claude Code](https://claude.com/claude-code) on a GitHub-hosted runner and opens a pull request for normal review.

## Why remcc

- **No laptop tether.** The Claude Code loop runs on a GitHub-hosted runner, so changes proceed while you do something else.
- **Normal PR review.** Output lands as a branch + PR; the usual review, CI, and branch-protection guardrails apply.
- **Tight safety boundary.** The bot authenticates as a GitHub App scoped to `change/**`, `main` is branch-protected, and a `change/**` ruleset blocks force-push and deletion.

## Quickstart

From a clean clone of the target repository on `main`:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) init
```

This verifies prerequisites, configures GitHub-side controls (branch protection, rulesets, `ANTHROPIC_API_KEY`, apply defaults), writes the template files, and opens a `remcc-init` PR. See [docs/SETUP.md](docs/SETUP.md) for the full flow and a manual fallback.

## What you get

- **Change-branch trigger with `@change-apply` opt-in.** Pushing to `change/<name>` only fires the workflow when the head commit subject opts in — see [docs/SETUP.md#the-canonical-trigger-commit](docs/SETUP.md#the-canonical-trigger-commit).
- **GitHub App identity scoped to `change/**`.** The bot authors PRs as `app/<slug>` via `REMCC_APP_ID` / `REMCC_APP_PRIVATE_KEY` / `REMCC_APP_SLUG`, with installation permissions limited to the change-branch surface.
- **Branch-protected `main`.** Direct pushes to `main` are blocked; the bot's only path is a PR.
- **Per-run model and effort overrides.** Defaults live in repo variables `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT`; trailers on the trigger commit or `workflow_dispatch` inputs override per run — see [docs/SETUP.md#configuring-the-apply-model](docs/SETUP.md#configuring-the-apply-model).
- **Draft PR on failure.** If `/opsx:apply` errors, remcc still opens a draft PR with logs attached so you can debug from the diff.
- **`install.sh upgrade`.** Refresh the template-managed files at a newer remcc ref via a `remcc-upgrade` PR — see [docs/SETUP.md#upgrading-remcc](docs/SETUP.md#upgrading-remcc).

## Limitations

remcc v1 is intentionally narrow:

- **Claude Code only.** No other AI coding agents.
- **GitHub Actions only.** No GitLab, Bitbucket, CircleCI.
- **OpenSpec `/opsx:apply` only.** No arbitrary prompts.
- **pnpm-managed JavaScript repos only.** The workflow runs `pnpm install --frozen-lockfile`.
- **One invocation per change.** Push or `workflow_dispatch`, then watch the PR.

Deeper hardening caveats (org-vs-user-owned repo, GHAS-gated controls) live in [docs/SECURITY.md](docs/SECURITY.md).

## Upgrade

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) upgrade
```

Opens a `remcc-upgrade` PR with the template diff against the pinned ref — see [docs/SETUP.md#upgrading-remcc](docs/SETUP.md#upgrading-remcc).

## Docs

- [docs/SETUP.md](docs/SETUP.md) — prerequisites, App setup, automated and manual adoption, configuration knobs, smoke tests.
- [docs/SECURITY.md](docs/SECURITY.md) — threat model, identity boundary, hardening caveats by repo ownership.
- [docs/COSTS.md](docs/COSTS.md) — Anthropic API and GitHub Actions cost guidance.

## Status & license

remcc v1 targets single-repo adoption and is stable enough for trial use; the historical change record lives under [`openspec/changes/archive/`](openspec/changes/archive/). MIT — see [LICENSE](LICENSE).
