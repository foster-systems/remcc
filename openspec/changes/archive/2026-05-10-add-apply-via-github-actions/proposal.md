---
name: add-apply-via-github-actions
status: proposed
---

# Add unattended /opsx:apply via GitHub Actions

## Why

I write OpenSpec changes locally and want the implementation phase
(/opsx:apply) to run somewhere that isn't my Mac, without being asked
to confirm every command. The local Mac is the wrong sandbox for
permissive Claude Code: too much shared state, real credentials in
scope, no clean "kill the box" recovery. GitHub Actions runners are
ephemeral, GitHub-native, and naturally per-change — one branch =
one run = one PR. The safety story is layered: inside the runner the
agent has full shell; outside, branch protection and minimal
GITHUB_TOKEN scope contain the blast radius.

remcc itself is the handbook and template kit other repos copy
from. It is not a runtime, not a service, not a package. Adoption
is a documented checklist.

## What

A docs-and-templates repo containing:

- A reference GitHub Actions workflow template that runs
  `/opsx:apply <change>` on push to `change/**` branches and opens a
  PR back to main.
- A `.claude/settings.json` template with minimal, safe defaults.
- A `gh-bootstrap.sh` script that configures a target GitHub repo
  (branch protection, push rulesets, secret) idempotently via `gh api`.
- Setup, security, and cost docs sufficient for a careful operator
  to adopt remcc into a fresh repo without external context.

First adopter: a local pnpm workspace (NestJS + NextJS).
remcc is considered v1 once an end-to-end change runs successfully
on the first adopter.

v1 explicitly supports pnpm-managed adopters only. The workflow
runs `pnpm install --frozen-lockfile` against the target repo.
Generalising to npm/yarn/no-package-manager is a future change,
not a v1 hidden constraint — adopters without `pnpm-lock.yaml`
are out of scope and SETUP.md says so.

## Scope

In scope
- Workflow template targeting GitHub-hosted Ubuntu runners
- `.claude/settings.json` template (minimal, runner-safe)
- `gh-bootstrap.sh` for one-time per-repo GitHub configuration
- SETUP.md, SECURITY.md, COSTS.md
- Dogfood validation against the first adopter

Out of scope (deferred or rejected)
- CLI scaffolder (npx / brew / shell installer)
- Reusable `workflow_call` shared workflow — copy-paste owns the file
- GitLab CI or other non-GitHub runners
- Multi-repo orchestration / fleet management
- Auto-retry on apply or verify failure (PR opens as draft instead)
- `/opsx:verify` as a workflow gate (cheap CLI `openspec validate`
  is sufficient; deep verify is the human PR review)
- remcc applying its own /opsx:apply via GitHub Actions (recursion
  adds confusion, not value at this stage)
- Auto-merge / bypass of human review on PR

## Affected capabilities

- ADD `apply-workflow` — the workflow contract: triggers, secret
  requirements, scope of GITHUB_TOKEN, behavior on apply/validate
  failure, PR creation semantics, log retention.
- ADD `repo-adoption` — the adoption contract: what files land
  where in a target repo, prerequisites, the GitHub configuration
  produced by `gh-bootstrap.sh`, the smoke test for a successful
  install.

## Approach

Safety model is two-layer and load-bearing for every other choice:

1. Inside the runner: `--dangerously-skip-permissions`. The runner
   IS the deny list. No tool restrictions; the ephemerality is the
   sandbox.
2. Outside the runner:
   - `permissions:` on the workflow limited to
     `contents: write, pull-requests: write`.
   - Branch protection on `main`: PR required, no force-push, no
     direct push.
   - Push ruleset blocks the workflow's GITHUB_TOKEN from editing
     `.github/**` paths.
   - Branch namespace: workflow only triggers on `change/**`; push
     ruleset only allows the bot to push there.
   - Secret scanning + push protection on the repo as backstop
     against accidental ANTHROPIC_API_KEY leakage in commits.

Workflow shape (to be specified concretely in `apply-workflow` spec):
- Trigger: push to `change/**` and `workflow_dispatch`.
- Concurrency: per-ref, cancel-in-progress.
- Steps: checkout → setup-node (Node ≥ 20.19, required by openspec) →
  setup-pnpm → `npm install -g @anthropic-ai/claude-code
  @fission-ai/openspec@latest` → `pnpm install --frozen-lockfile`
  (so the agent has working deps if tasks need them) → resolve
  change name from ref → run `/opsx:apply` → run `openspec validate`
  → `git add -A && git commit` (the apply skill leaves changes
  unstaged; the workflow owns the commit) → push → open or comment
  on PR. PR is opened as draft if apply or validate failed.
- No `tsc` or test gate inside the workflow. `openspec validate` is
  the only structural gate; correctness is the human PR review.
- Logs uploaded as artifacts for 14 days.

Adoption flow (to be specified in `repo-adoption` spec):
- Target repo prerequisites: OpenSpec installed, `.claude/` directory
  present (skills shipped with repo), main branch exists.
- Files copied from remcc/templates/ into target.
- `gh-bootstrap.sh` run once from inside target repo.
- ANTHROPIC_API_KEY added as repo secret (prompted by script).
- Smoke test: push a trivial `change/test-apply` branch, observe
  workflow run, observe PR creation, close PR without merging.

## Resolved decisions

- **OpenSpec install:** canonical command is
  `npm install -g @fission-ai/openspec@latest` (verified against the
  Fission-AI/OpenSpec repo and npm registry). Requires Node ≥ 20.19.
  Workflow pins to `@latest`; SETUP.md documents the same.
- **Commit ownership:** `/opsx:apply` edits files (including
  task-checkbox toggles in `tasks.md`) but leaves everything
  unstaged. The workflow is responsible for `git add -A && git
  commit` after apply + validate.
- **Cost ceiling:** rely on the Anthropic admin-console budget cap
  at the organization level. No per-run kill switch in v1; revisit
  if real usage shows a single change burning a meaningful share of
  the cap.
- **pnpm install + tsc:** the apply skill does not invoke either
  itself. The workflow runs `pnpm install --frozen-lockfile` before
  apply so the agent can execute scripts if tasks call for it.
  No `tsc` or test gate in the workflow — that's intentional, the
  human PR review is the correctness gate.

## Validation

- A trivial change applied end-to-end on the first adopter produces a reviewable PR
  whose contents match the change's tasks.md.
- Branch protection prevents the bot's GITHUB_TOKEN from pushing to
  main even when explicitly attempted in a test workflow.
- Push ruleset prevents the bot from modifying `.github/**` even on
  a `change/**` branch.
- A second adoption (any other repo) succeeds following SETUP.md
  alone, without questions back to remcc maintainer.
