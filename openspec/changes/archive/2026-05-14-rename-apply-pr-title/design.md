## Context

The `opsx-apply` workflow's PR-open step today builds the title from the slash command it ran:

```yaml
--title "/opsx:apply ${CHANGE_NAME}"
```

That string surfaces in the PR list, in the GitHub mobile/email notifications, and — after a squash-merge — as the first line of the merge commit on `main`. Reading those surfaces, the title looks like *the command we ran* rather than *what the PR is for*. The change name itself already carries the semantic meaning; the slash-command prefix is noise outside the workflow file.

Two adjacent strings reference `/opsx:apply <name>` in the same workflow and are deliberately preserved:

1. The agent-output commit subject (`templates/workflows/opsx-apply.yml:339`) — must NOT start with `@change-apply`, and the existing form `/opsx:apply <name>` is the documented self-loop guard (see `apply-workflow` spec, "Bot's own commit subject does not trigger").
2. The `claude -p "/opsx:apply ${CHANGE_NAME}"` invocation (line 277) — the literal slash command we are asking the CLI to execute. Renaming this would break behavior.

Only the PR title (line 415) is purely cosmetic. That's the one we change.

## Goals / Non-Goals

**Goals:**
- New PRs opened by `opsx-apply` carry the title `Change: <change-name>`.
- The change name remains the substring after a fixed, easily-grepped prefix, so any external tooling that wants to parse the title still can.
- The `apply-workflow` spec is updated so the title format is normative, not illustrative.

**Non-Goals:**
- Do not rename the bot's commit subject (`/opsx:apply <name>`). That subject is load-bearing for the self-loop guard.
- Do not rename the `claude -p "/opsx:apply ${CHANGE_NAME}"` invocation argument — that is a literal CLI command, not a human label.
- Do not back-rename existing PRs. The workflow only sets the title when it calls `gh pr create`; subsequent runs comment on the existing PR and do not touch the title.
- Do not add any conditional formatting (e.g. status-tagged titles like `[draft] Change: foo`). Draft status is already conveyed by `--draft`.

## Decisions

### Title format: `Change: <change-name>`

Chosen over alternatives:

- `Apply <change-name>` — verb-first, but loses the "this is an OpenSpec change" framing and reads as imperative ("please apply this") rather than descriptive.
- `<change-name>` — bare name, but loses the fixed prefix that makes the title greppable and visually distinct from human-authored PRs in a mixed list.
- `[opsx] <change-name>` — bracket tags are conventional but visually noisy and consume more of the title-column width than a short prefix.

`Change:` is a short, neutral prefix that mirrors how the OpenSpec project itself talks about these units of work (the directory is `openspec/changes/<name>/`, the branch is `change/<name>`, the spec calls them "changes"). Consistency with surrounding vocabulary beats inventing a new word.

### Implementation surface: one line in one file

The rename is a single-character-set substitution on line 415 of `templates/workflows/opsx-apply.yml`. No helper, no variable, no template indirection — the title string is short and read-once.

### Spec change: MODIFIED requirement, not RENAMED

The existing requirement is "Open or update the change PR" — the requirement's name doesn't change, only the body and one scenario tighten the title format from "the change name in the title" to a specific format string. Per OpenSpec convention, this is a MODIFIED delta, not a RENAMED delta.

## Risks / Trade-offs

- **External tooling scraping titles** → No known consumer. If one exists, the change name is still the trailing token after a known prefix; updating a regex from `^/opsx:apply ` to `^Change: ` is trivial.
- **Inconsistency window during rollout** → Existing change-branch PRs will keep their old `/opsx:apply <name>` title until they are merged or recreated. Acceptable: the workflow only sets the title on `gh pr create`, and renaming PRs in flight would be more disruptive than the inconsistency.
- **Accidentally renaming the bot's commit subject** → Implementer must not touch `templates/workflows/opsx-apply.yml:339` (the `git commit -m` invocation). The self-loop guard tests for `@change-apply` not for `/opsx:apply`, so a typo here would not regress *that* guard — but it would still change a documented invariant. Tasks call this out explicitly.
