## Context

remcc starts as an effectively empty repository: a proposal, a goals
file, and the OpenSpec scaffolding. The first change must establish
both the artifact pattern (templates, docs, bootstrap script) and the
workflow contract (what runs where, what's safe, what isn't) in a
form that downstream repos can adopt by copy-paste.

The first concrete adopter is `~/ws/prv/actr` — a pnpm-workspace
monorepo with NestJS + NextJS apps. actr already has `.claude/` and
`openspec/` in place, so adoption mostly means landing the workflow
file and configuring GitHub. This grounds the design: assumptions
that don't hold for actr should be revisited before they become spec.

The user authors OpenSpec changes locally on macOS but does not want
to run /opsx:apply locally — too much shared state and credential
exposure for permissive Claude Code. The runner needs to be ephemeral,
GitHub-native, and naturally per-change.

Stakeholders: a single operator (the user) for personal projects.
No team, no SSO, no multi-tenant concerns. Future scope (other teams
or non-GitHub runners) is acknowledged but explicitly deferred.

## Goals / Non-Goals

**Goals:**
- /opsx:apply runs unattended on a fresh GitHub-hosted runner, one
  run per change branch.
- Safety contract is layered: permissive inside the runner, tight at
  the GitHub boundary. Each layer is independently load-bearing.
- A second adopter can install remcc using SETUP.md alone, without
  asking the maintainer.
- remcc evolves through OpenSpec on itself (proposal, design, specs,
  tasks) but does not run /opsx:apply on remcc — recursion is rejected
  for v1.

**Non-Goals:**
- CLI scaffolder, npm package, brew formula, or any installable form.
- Reusable `workflow_call` shared workflow. The workflow is copied
  into the target repo and owned there.
- Auto-merge of agent PRs. Human review is the verification gate.
- Auto-retry on apply or validate failure. Failures surface as a
  draft PR; the next attempt is a new push.
- Deep `/opsx:verify` as a workflow gate. Cheap `openspec validate` is
  sufficient inside the workflow; deeper verification happens during
  human PR review.
- GitLab, Buildkite, self-hosted runners. GitHub-hosted Ubuntu only.
- Multi-repo orchestration or fleet management.

## Decisions

### D1. Distribution model: docs + copy-paste templates

The repo ships raw template files plus a SETUP.md checklist. A
target repo's adoption is a few `cp` commands plus running
`gh-bootstrap.sh`.

Alternatives considered:
- **Reusable workflow (`workflow_call`)**: tighter coupling between
  remcc and downstream, but updates flow automatically with a tag
  bump. Rejected: at one adopter, the operational benefit doesn't
  justify the moving parts.
- **Scaffolder CLI (`npx remcc init`)**: nicer UX, but adds a
  package + versioning + publish surface for a single user.
  Rejected as premature.
- **GitHub template repo**: appropriate for new repos only; doesn't
  handle the common case of adopting into an existing repo.

The decision is reversible: a future change can layer a reusable
workflow on top without breaking the copy-paste adoption.

### D2. Two-layer safety model

Inside the runner, Claude Code runs with
`--dangerously-skip-permissions`. The runner itself is the deny
list — its ephemerality and lack of persistent state are the
sandbox. Tool restrictions inside the runner are explicitly not
attempted.

Outside the runner, all of the following must hold simultaneously
for the safety contract to be met:
- Workflow `permissions:` block limits GITHUB_TOKEN to
  `contents: write` and `pull-requests: write`.
- Branch protection on `main` requires PR, blocks force-push and
  direct push.
- Push ruleset prevents GITHUB_TOKEN from editing `.github/**`.
- Workflow only triggers on `change/**` branches.
- Secret scanning + push protection enabled on the repo.

Alternatives considered:
- **Tool allow/deny inside the runner**: produces prompts the agent
  can't answer, defeating the unattended goal. Rejected.
- **Single-layer safety (only GitHub-side)**: works in practice but
  loses defence in depth if a future GitHub feature widens
  GITHUB_TOKEN scope. Rejected as too thin.
- **Single-layer safety (only runner-side)**: not possible —
  GITHUB_TOKEN is intrinsically present in the runner.

### D3. Trigger: push to `change/**` plus workflow_dispatch

The workflow fires on push to any branch matching `change/**`, and
also exposes `workflow_dispatch` for manual rerun with an explicit
change name.

Alternatives considered:
- **READY marker file in change folder**: prevents premature runs
  on incomplete changes, at the cost of one extra step per change.
  Rejected as friction the operator can avoid by simply not
  pushing until ready.
- **PR-ready transition**: requires opening a PR before kicking
  off the agent, which inverts the natural flow. Rejected.

### D4. Verify gate: `openspec validate` only, not `/opsx:verify`

The workflow runs `openspec validate <change>` after apply. This
is a cheap CLI check with a real exit code. Deep coherence
verification (`/opsx:verify`) is not run in CI — the operator
performs it during local PR review.

Alternatives considered:
- **Run /opsx:verify as a workflow step**: doubles token cost and
  produces prose, not a gate signal. Adds little value when the
  operator reviews every PR by hand. Rejected.
- **No validation at all**: loses a cheap, deterministic check
  that the change artifacts are still structurally valid after
  apply. Rejected.

### D5. Bot identity: workflow's auto-provisioned GITHUB_TOKEN

The workflow uses `${{ github.token }}`. No fine-grained PAT, no
GitHub App, no separate bot identity.

Alternatives considered:
- **Fine-grained PAT scoped per-repo**: requires per-adopter PAT
  creation, rotation, secret upload. Rejected as ceremony for no
  added security beyond the workflow's `permissions:` block.
- **GitHub App**: appropriate for multi-repo orgs, overkill here.

Trade-off: commit author shows as `github-actions[bot]` rather
than a remcc-branded identity. Acceptable.

### D6. Failure handling: draft PR, no auto-retry

If apply or validate exits non-zero, the workflow still commits any
output the agent produced, pushes the branch, and opens the PR as
a draft. The operator decides whether to push a fixup or abandon.

Alternatives considered:
- **Hard-fail the workflow with no PR**: loses the partial work,
  forces the operator to ssh into a dead runner to inspect.
  Rejected.
- **Auto-retry the apply step**: tends to burn tokens chasing
  the same wrong assumption. Rejected.
- **Open as ready-for-review even on failure**: misleading.
  Rejected.

### D7. Bootstrap shape: idempotent shell script using `gh api`

`gh-bootstrap.sh` is a checked-in POSIX shell script that uses
`gh api` to configure branch protection, push rulesets, secret
scanning, and the ANTHROPIC_API_KEY secret. Running it twice is
a no-op.

Alternatives considered:
- **Manual checklist in SETUP.md only**: error-prone, hard to
  verify completeness after the fact. Rejected.
- **Terraform / IaC**: overkill, adds a runtime dependency.
  Rejected.
- **Embed bootstrap in the workflow itself (self-bootstrapping)**:
  chicken-and-egg with `permissions:`. Rejected.

The script is small enough to read end-to-end, which is itself a
safety property — a reviewer can see exactly what it does to a
GitHub repo before running it.

### D8. Branch namespace: `change/**`

OpenSpec changes map to `change/<name>` branches. The workflow
trigger and the push ruleset both pin this prefix. This makes the
agent's blast radius syntactically obvious: the bot can only
push to branches starting with `change/`.

### D9. Who commits the agent's output

The workflow owns the commit. `/opsx:apply` edits files (including
`tasks.md` checkbox toggles) but leaves everything unstaged —
verified by reading the apply skill (`.claude/skills/openspec-apply-change/SKILL.md`).
The workflow's `git add -A && git commit` step is therefore
load-bearing, not defensive. If a future apply skill version starts
committing as it goes, the workflow's commit becomes a no-op and
the contract still holds.

### D10. remcc does not /opsx:apply itself

remcc uses OpenSpec for its own changes (proposals, designs,
specs, tasks) but does not run the apply workflow on its own
changes. The operator implements remcc's changes manually.

Rationale: the workflow's behaviour on a project that contains
the workflow itself in `templates/` would be confusing. Recursion
adds no value at v1. Reconsider once the workflow is stable on
multiple non-meta adopters.

### D11. Runtime install: globals + workspace deps, no extra gates

The workflow installs two global CLIs
(`npm install -g @anthropic-ai/claude-code @fission-ai/openspec@latest`)
and runs `pnpm install --frozen-lockfile` in the target repo
before invoking `/opsx:apply`. No `tsc`, no test runner, no lint
gate inside the workflow.

OpenSpec CLI requires Node ≥ 20.19, so `setup-node` pins to a
recent LTS. The OpenSpec package name is `@fission-ai/openspec`
(verified against the Fission-AI/OpenSpec repo and npm registry).

Rationale for `pnpm install`: the apply skill never runs install
or build commands itself (verified by reading SKILL.md), but
individual tasks may require executing scripts in the target repo
to validate work. Installing once up front is cheap insurance.

Rationale for no extra gates: `openspec validate` (D4) is the only
structural gate. Type-check or test gates would either:
- Block PRs on pre-existing failures unrelated to the change, or
- Force the agent to fix unrelated breakage to ship.
Neither is desirable. Human PR review is the correctness gate.

Alternatives considered:
- **Pin OpenSpec to an exact SHA**: more reproducible but blocks
  routine bug-fix uptake. Rejected for v1; revisit if a breaking
  apply-skill change bites us.
- **Skip `pnpm install`**: faster cold start, but tasks that need
  to run scripts hit a missing-deps cliff. Rejected.
- **Add `pnpm tsc --noEmit` as a soft gate**: tempting, but
  amplifies pre-existing breakage into PR noise. Rejected.
- **Make the workflow package-manager-agnostic** (detect lockfile,
  pick install command): nicer scope, but multiplies the test
  matrix and adds branching to a template that should be readable
  end-to-end. Rejected for v1; v1 is explicitly pnpm-only and
  SETUP.md says so. Reconsider when a non-pnpm adopter actually
  arrives.

## Risks / Trade-offs

- **ANTHROPIC_API_KEY visible in runner env** → Claude can read it
  but the only egress endpoint that accepts it is api.anthropic.com,
  which is its destination anyway. GitHub's secret-redaction in
  logs is the backstop against accidental disclosure in commits or
  outputs.

- **Push ruleset for `.github/**` is the only thing stopping the
  agent rewriting CI** → Single point of failure. Mitigated by
  documenting it in SECURITY.md as a load-bearing control and
  including a smoke test that verifies the ruleset is enforced.

- **Cost runaway from a long apply run** → Mitigated by
  Anthropic admin console budget caps (operator-side, not
  workflow-side) and `timeout-minutes: 180`. No per-run kill switch
  in v1. Reconsider if real usage shows runaway risk.

- **Apply skill semantics may change** → The current contract is
  "apply edits files but does not stage or commit." If a future
  apply-skill version stages or commits its own work, the
  workflow's `git add -A && git commit` becomes a no-op (still
  safe). The riskier drift is the opposite: apply suddenly
  expecting a clean working tree to exit cleanly, or its stopping
  criteria changing. Mitigated by tracking
  `@anthropic-ai/claude-code` and `@fission-ai/openspec` versions
  in the install step and watching dogfood runs for surprises.

- **Single point of adopter (actr)** → Validation rests on one
  project's shape. The "second adoption succeeds from SETUP.md
  alone" criterion mitigates this in principle but cannot be
  exercised until a second project arrives.

- **Branch protection blocks force-push from operator too** →
  By design. If the operator needs to rewrite history on a
  `change/**` branch, they delete the branch and recreate.

## Open Questions

- Whether GitHub's push rulesets can pin path restrictions to a
  specific token/actor (rather than all non-admins). Affects
  whether the operator can still edit `.github/**` from main
  while the bot is blocked.

(Previously open: install command, apply commit behaviour, pnpm
install + tsc — all resolved. See proposal "Resolved decisions"
and design D9 / D11.)
