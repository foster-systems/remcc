## Why

The current adopter safety model layers three independent GitHub-side
constructs — branch protection on `main`, a branch ruleset confining
the bot to `change/**`, and (org-only) a push ruleset blocking
`.github/**` edits — each with its own JSON, idempotency surface, and
documentation footprint. The protection these layers add over "main
is protected by a ruleset requiring one PR approval" is small in
practice: every agent PR is human-reviewed before merge, and the
review is the load-bearing gate. The layered model adds cognitive
load to operators, drift surface to the bootstrap, and edge cases
(user-owned vs org-owned, GHAS vs not) that obscure the core
contract. For new adopters going forward, collapsing to a single
main-branch ruleset requiring one approval matches what reviewers
were already doing and removes the asymmetry between user-owned and
organization-owned targets.

## What Changes

- **BREAKING (default for new adopters only)** Replace the three
  current GitHub-side controls (branch protection on `main`, the
  `change/**` branch ruleset, the `.github/**` push ruleset) with a
  single repository **branch ruleset** targeting the default
  branch only, with exactly these rules: require a pull request and
  at least one approval to merge, and block force-push. Deletion of
  the default branch is **not** blocked by this ruleset (out of
  scope for this change).
- Drop the bot-side branch confinement from the bootstrap default:
  new adopters do not get the `refs/heads/change/**` restriction. The
  main-branch ruleset is the sole gate.
- Drop the `.github/**` push ruleset from the bootstrap default,
  along with its org-vs-user-owned conditional. New adopters get the
  same configuration regardless of ownership type.
- Update `gh-bootstrap.sh` install/uninstall paths, the idempotency
  snapshot, and the uninstall reconciliation to operate on the
  single new ruleset only.
- Update `docs/SECURITY.md` and `docs/SETUP.md` to describe the
  single-ruleset model and drop the user-vs-org-owned caveats that
  the push ruleset required.
- **Explicitly out of scope: existing adopters.** The bootstrap
  SHALL NOT modify, delete, or migrate any pre-existing branch
  protection, legacy remcc-managed rulesets, or any other repo
  configuration the previous bootstrap had installed. Operators
  whose repos were bootstrapped under the prior model keep whatever
  they currently have; opting in to the new model is a manual
  operator action (delete the legacy items in the GitHub UI, then
  re-run the updated bootstrap).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `repo-adoption`: the bootstrap script's branch-protection and
  ruleset requirements are replaced with a single main-branch
  ruleset requirement; the `change/**` confinement requirement and
  the `.github/**` push-ruleset requirement are removed. The
  bootstrap no longer touches `branches/main/protection` or the two
  legacy ruleset names at all.

## Impact

- `templates/gh-bootstrap.sh`: ruleset/protection code paths
  collapse to a single reconciler; idempotency snapshot and
  uninstall reconciliation simplify accordingly. No code touches
  legacy items.
- `openspec/specs/repo-adoption/spec.md`: three requirements
  removed, one new requirement added, scenarios rewritten.
- `docs/SECURITY.md`, `docs/SETUP.md`: defense-in-depth tables and
  bootstrap descriptions updated; user-vs-org-owned caveats removed
  where they were only about the push ruleset. Docs add a short
  note for legacy adopters explaining that the change is
  forward-only.
- Existing adopters: zero change to their GitHub-side state on
  bootstrap re-run. Re-running an updated bootstrap reconciles the
  new ruleset only; pre-existing legacy controls remain untouched.
- Security posture for new adopters: weakened in a narrow
  technical sense (bot is no longer prevented at the ref/path
  level from pushing outside `change/**` or into `.github/**`),
  but unchanged in practice because PR review was already the gate
  that mattered.
