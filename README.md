# remcc: remote Claude Code

Run [Claude Code](https://claude.com/claude-code) unattended on GitHub
Actions instead of your laptop. Push an
[OpenSpec](https://github.com/Fission-AI/OpenSpec) change branch,
Claude implements it on the runner, and opens a pull request for
review.

## What it solves

Claude Code runs interactively in a terminal — every AI-driven change
needs an open laptop and a human watching the loop. remcc moves that
loop onto GitHub Actions so changes proceed while you do something
else, and so the work lands as a normal PR with the usual review and
branch-protection guardrails.

The trigger is deliberately narrow: pushing to `change/<name>` runs
`/opsx:apply` on a GitHub-hosted runner. The runner is permissive
(`--dangerously-skip-permissions`); the boundary is tight (GitHub
token confined to `change/**`, `main` protected, secrets redacted).

## Limitations

remcc v1 is a docs-and-templates kit, not a service or runtime. It
assumes:

- **Claude Code only.** No other AI coding agents.
- **GitHub Actions only.** No GitLab, Bitbucket, CircleCI, etc.
- **OpenSpec `/opsx:apply` only.** No arbitrary prompts.
- **pnpm-managed JavaScript repos only.** The workflow runs
  `pnpm install --frozen-lockfile`.
- **One invocation per change.** Push or `workflow_dispatch`, then
  watch the PR.
- Some hardening (push rulesets, secret push protection) requires an
  org-owned repo, a public repo, or GitHub Advanced Security; the
  user-owned-private case loses those two controls — see
  [docs/SECURITY.md](docs/SECURITY.md).

## How to use

1. Check prerequisites: GitHub admin on the target repo, an Anthropic
   API key, OpenSpec initialised, a pnpm lockfile.
2. Copy `templates/workflows/opsx-apply.yml` (and optionally
   `templates/claude/settings.json`, `templates/openspec/config.yaml`)
   into the target repo and merge to `main`.
3. Run `templates/gh-bootstrap.sh` once to install branch protection,
   rulesets, the API key secret, and per-repo `OPSX_APPLY_MODEL` /
   `OPSX_APPLY_EFFORT` defaults.
4. Push a `change/<name>` branch carrying an OpenSpec proposal. The
   `opsx-apply` workflow runs Claude Code, implements the change, and
   opens a PR.

Full walkthrough: [docs/SETUP.md](docs/SETUP.md). Cost guidance:
[docs/COSTS.md](docs/COSTS.md). Security model:
[docs/SECURITY.md](docs/SECURITY.md).
