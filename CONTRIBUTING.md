# Contributing to remcc

Thanks for your interest. remcc is a small docs-and-templates kit;
contributions land via fork + pull request.

## Before opening a PR

- For non-trivial changes (new features, behavior changes), please
  open an issue first so we can discuss scope before you write code.
- Typo fixes, doc improvements, and obvious bugs can go straight to
  a PR — describe what changes and why in the PR body.

## Workflow

- Fork the repo, branch from `main`, push, open a PR against
  `premeq/remcc:main`.
- Keep PRs focused — one concern per PR.
- The maintainer is solo and best-effort. Expect a few days'
  turnaround; ping the PR if it goes quiet for over a week.

## Scope

remcc v1 is intentionally narrow: Claude Code, GitHub Actions,
OpenSpec `/opsx:apply`, pnpm-managed JavaScript repos
(see [README.md](README.md#limitations)). Generalising any of those
is in scope but warrants an issue first so we don't duplicate effort.
