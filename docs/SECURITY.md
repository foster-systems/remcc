# remcc security model

remcc lets a Claude Code agent run unattended with full shell access
on a per-change basis. The safety contract is two-layer: the inside
of the runner is intentionally permissive, and the outside (GitHub)
is intentionally tight. Each layer is independently load-bearing.
Both must hold for the contract to hold.

## Layer 1 — inside the runner

Claude Code is invoked with `--dangerously-skip-permissions`. The
agent has unrestricted shell access for the duration of the job. The
runner itself is the deny list.

### What this layer relies on

| Control | What it stops |
|---|---|
| GitHub-hosted Ubuntu runner | The agent has no access to your laptop, your shared infrastructure, or any persistent state. |
| Job-level isolation (one runner per job) | One run cannot pollute another. There is no caching of credentials or working directories between runs. |
| `timeout-minutes: 180` on the apply job | Bounded wall-clock cost — a runaway agent is killed by GitHub. |
| Anthropic admin-console budget cap | Bounded API cost across all runs. See `COSTS.md`. |
| `ANTHROPIC_API_KEY` redaction in logs | GitHub redacts secrets stored in the repo's secret store from job logs and commit content the workflow produces. |

### What this layer does NOT protect against

- An adversary who can already inject content into the repository
  (e.g. through a compromised dependency) before the workflow runs.
- A compromise of the `claude-code` or `openspec` npm packages.
  Mitigation is to track versions in the workflow and pay attention
  to dogfood-run surprises.
- Anthropic-side outages or behavioural drift in the apply skill.

## Layer 2 — outside the runner

This is the safety net. Even if the agent inside the runner does
something unintended, the GitHub-side controls bound the blast radius.

| Control | What it stops | Availability |
|---|---|---|
| Workflow `permissions:` limited to `contents: write, pull-requests: write` | The auto-provisioned `GITHUB_TOKEN` cannot read or write Actions secrets, packages, deployments, workflows, or repository administration. | Always |
| Branch ruleset on the default branch (only) requiring a PR with ≥1 approval and blocking force-push | The bot cannot land code on the production branch without an operator approving the PR, and cannot rewrite history. **The PR review is the single gate.** The operator (admin) bypasses for emergency merges. Deletion of the default branch is not blocked by this ruleset. | Always (user-owned and org-owned alike) |
| Secret scanning + secret push protection | A push containing a credential that matches a known pattern (including Anthropic API keys) is rejected at push time. Backstop against `ANTHROPIC_API_KEY` accidentally landing in a commit. | Public repos free; private repos require GHAS. |
| GitHub Actions log redaction of `${{ secrets.* }}` values | Secrets stored in the repo's secret store are redacted from job logs and step outputs. Does not catch secret-shaped content in *commits*. | Always |
| Workflow trigger limited to `push: change/**` and `workflow_dispatch` | The agent only runs in a syntactically obvious branch namespace. Any push outside `change/**` does not trigger the agent. | Always |
| Allow Actions to create PRs (per-repo toggle) | Permits the workflow's PR-creation step to succeed under `GITHUB_TOKEN`. Without this, the workflow fails at PR creation; with it, only the create-PR capability is exercised — the workflow does not approve PRs. | Always (`gh-bootstrap.sh` enables it) |

## GitHub App credentials

The workflow authenticates as a dedicated GitHub App rather than a
per-operator personal access token. The App's installation token is
minted at the start of every run (via `actions/create-github-app-token`),
used for checkout, push, and PR creation, and discarded when the job
ends. Tokens are short-lived (1 hour) and scoped to the installed
repo only — they are **not** admin tokens. The App is a non-admin
actor, so the main-branch approval ruleset's admin bypass does
**not** apply to it: the App can open a PR but cannot merge to the
default branch without an operator approval.

### App permissions

`gh-bootstrap.sh` documents the App permissions the workflow needs:
`Contents: write`, `Pull requests: write`, `Workflows: write`,
`Metadata: read`. No organisation or account permissions are
required. This is the same blast radius as a fine-grained PAT
scoped to the target repo — narrower than a classic PAT.

### Blast radius if the private key is exfiltrated

The private key is the long-lived secret. An attacker with the
`REMCC_APP_PRIVATE_KEY` can mint installation tokens for every repo
the App is installed on. For each such repo they can:

- Push to any non-default branch (the bootstrap installs no
  branch-namespace or path restrictions on the bot; the only gate
  is the default-branch approval ruleset, which blocks merging,
  not pushing).
- Open pull requests as `<slug>[bot]`. Such PRs cannot land on the
  default branch without an operator's approval.

What the key **cannot** do, because the App has no such permissions:
read or write Actions secrets, modify repo settings, manage
collaborators, manage other repos the App isn't installed on, or
escalate to admin.

The credential is rotatable in seconds — see "Rotation procedure"
below. Compared to a per-operator PAT, the App key is narrower
(no account-level access) but installed on more repos (every
adopter). Treat the PEM with the same care you would any
production secret.

### Rotation procedure

If the private key is lost, leaked, or under suspicion:

1. Open <https://github.com/settings/apps> → your remcc App →
   **Private keys**.
2. Click **Generate a private key**. A new `.pem` downloads.
3. For every adopter repo, run
   `REMCC_APP_PRIVATE_KEY="$(cat <new-key.pem>)" install.sh reconfigure`
   to upload the new key. (The other two config items —
   `REMCC_APP_ID` and `REMCC_APP_SLUG` — are unchanged.)
4. Back on the App settings page, click the **trash icon** next to
   the **old** key to revoke it. From this point on, any installation
   token previously minted from the old key still works until it
   naturally expires (≤ 1 hour); no new tokens can be minted.

The rotation does not require touching the workflow file or
re-installing the App on the repos.

### Why this beats a per-operator PAT

A fine-grained PAT belongs to a human GitHub account, scopes to that
account's repo permissions, and (under "PR author cannot approve the
same PR" rules) blocks the operator from reviewing the bot's PRs.
The App identity is a separate actor: the operator (admin on the
adopter repo) can code-review and approve the App's PRs and merge
through the approval ruleset. The R3 unlock is the primary
motivation; the credential-shape improvement is the secondary win.

## Limitations on private-without-GHAS repositories

One of the Layer 2 controls in the table above is not universally
available:

- **Secret scanning + push protection on private repos require
  GitHub Advanced Security**, an organization-level paid feature.
  Free private user-owned repos cannot enable secret scanning;
  GitHub returns `"Secret scanning is not available for this
  repository"`. `gh-bootstrap.sh` detects this and skips with a
  warning. The substitution: GitHub Actions' built-in log redaction
  protects against secrets in workflow logs. It does **not** protect
  against secret-shaped content landing in a commit. Operators on
  this configuration should pay extra attention to commit diffs in
  agent PRs.

If the secret-scanning backstop matters to you, host the target
repository on a plan where secret scanning is available. There is
no remcc-side workaround.

### PR review is the load-bearing control

The bot has no ref-level or path-level restrictions: it can push
any branch other than the default and can modify any path
including `.github/**`. Nothing prevents it from *proposing* a
change that rewrites the workflow, removes the apply-skill
invocation, broadens the trigger pattern, or otherwise alters the
rules of the game.

What stops such a change from taking effect is the operator's PR
review and approval on the merge to the default branch. The
approval ruleset is therefore not a hardening control among many
— it is the foundational control. Treat every agent PR diff with
attention to `.github/**` changes, workflow edits, permission
widening, and trigger broadening; these are the categories an
adversarial agent would target first.

If you ever find yourself disabling the approval ruleset on a
remcc adopter, treat it as turning off the only thing keeping the
agent's output from auto-landing on the default branch.

## What this model does NOT protect against

- **Pre-existing repository vulnerabilities.** If the change the
  operator wrote is malicious or wrong, the workflow will faithfully
  apply it. Human PR review is the correctness gate.
- **Anthropic API key exfiltration via api.anthropic.com.** The
  agent has the key; api.anthropic.com is its destination anyway.
  Cost cap and audit logs in the Anthropic admin console are the
  defenses, not network controls.
- **Adversarial bypass-actor configuration.** If an admin configures
  additional bypass actors on the rulesets that include a service
  account or app the agent can reach, the model breaks. Keep the
  bypass list to repository-admin only.
- **Insider risk from anyone with admin on the target repo.** Admin
  bypasses every control. The model assumes a small operator set
  whose accounts are otherwise hardened (2FA, least-privilege).
