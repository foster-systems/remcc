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

From a clean clone of the target repository on `main`:

```sh
cd <target-repo>
bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) init
```

This one-liner verifies prerequisites (GitHub admin, OpenSpec
initialised, `pnpm-lock.yaml` present, local tools), runs the
GitHub-side configuration (branch protection, rulesets,
`ANTHROPIC_API_KEY` secret, per-repo apply defaults), writes the
template files into the working tree, and opens a `remcc-init` pull
request for you to review and merge. Once merged, push a
`change/<name>` branch carrying an OpenSpec proposal and the
`opsx-apply` workflow takes over.

To refresh the template-managed files at a newer remcc ref later,
run the companion `upgrade` subcommand from the same kind of clean
clone:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) upgrade
```

`upgrade` opens a `remcc-upgrade` PR with the template diff; see
[docs/SETUP.md](docs/SETUP.md#upgrading-remcc) for the full flow.

Prefer not to pipe a remote script to bash, or want to inspect first?
The manual checklist in [docs/SETUP.md](docs/SETUP.md) is the verbatim
fallback. Cost guidance: [docs/COSTS.md](docs/COSTS.md). Security
model: [docs/SECURITY.md](docs/SECURITY.md).
