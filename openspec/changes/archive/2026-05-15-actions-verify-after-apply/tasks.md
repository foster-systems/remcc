## 1. Workflow template: invoke /opsx:verify

- [x] 1.1 Add a `Run /opsx:verify` step in `templates/workflows/opsx-apply.yml` immediately after the existing `Run openspec validate` step, with `id: verify` and `continue-on-error: true`.
- [x] 1.2 In that step, invoke `claude --dangerously-skip-permissions --model "${MODEL}" "${effort_flag}" "${effort_value}" --output-format stream-json --verbose -p "/opsx:verify ${CHANGE_NAME}"`, sourcing `MODEL` / `effort_flag` / `effort_value` from `steps.config.outputs` (the same outputs the apply step uses).
- [x] 1.3 Pipe the invocation through `tee -a verify.jsonl` and a `jq` filter mirroring the apply step's filter, then `tee -a verify.log`, so the console gets a human-readable trace while the raw stream lands in `verify.jsonl`.
- [x] 1.4 Capture `${PIPESTATUS[0]}` into the step's `exit_code` output (mirrors the apply step).

## 2. Workflow template: extract verify.md

- [x] 2.1 Still inside the verify step (after the pipeline), extract the last `assistant` message's concatenated text content from `verify.jsonl` into `verify.md`, using a `jq` expression that walks `.message.content[]` and joins all `text`-type items from the final assistant message. If the extraction yields empty output, leave `verify.md` empty (the post step handles the fallback).
- [x] 2.2 Confirm the extraction does not fail the step on empty input (use `jq -r ... // ""` or equivalent so a crashed verify still leaves the step exit code driven by the claude invocation, not by `jq`).

## 3. Workflow template: extend run-summary PR body

- [x] 3.1 In the existing `Open or update PR` step, add a `verify exit code` line to the run-summary heredoc body, right after the `validate exit code` line. Source the value from `steps.verify.outputs.exit_code` with the same fallback default (`unknown`) used for apply and validate.
- [x] 3.2 Verify the run-summary body still does NOT embed the verify report itself — the body remains a short exit-code summary.

## 4. Workflow template: post verify report as dedicated PR comment

- [x] 4.1 Add a new `Post verify report` step after `Open or update PR`, with `if: always() && steps.change.outputs.name != ''` (same guard as the PR step).
- [x] 4.2 In that step, resolve the existing PR number for the change branch via `gh pr list --head "${BRANCH}" --base main --state open --json number --jq '.[0].number'`. If empty, exit zero without posting.
- [x] 4.3 If `verify.md` exists and is non-empty: post it via `gh pr comment "${pr_number}" --body-file verify.md`, with `GH_TOKEN` set to `${{ steps.app-token.outputs.token }}` so the comment author is the App's bot identity.
- [x] 4.4 If `verify.md` is missing or empty: post a fallback body via `gh pr comment` that names the captured verify exit code and points at the `agent-logs-<change>` artifact for the partial NDJSON stream.
- [x] 4.5 Before posting, check `verify.md` byte length against GitHub's PR-comment cap (65 536). If exceeded, truncate to a safe length and append a footer pointing at the `agent-logs-<change>` artifact.

## 5. Workflow template: extend log artifact and commit reset

- [x] 5.1 Extend the `agent-logs-${CHANGE_NAME}` artifact's `path:` list to include `verify.md` and `verify.jsonl`, keeping `if-no-files-found: ignore` so a crashed verify does not fail the upload.
- [x] 5.2 In the `Stage and commit agent output` step, extend the `git reset -- apply.jsonl apply.log validate.log` line to also reset `verify.md verify.jsonl`, so verify outputs do not leak into the change branch commit.

## 6. Roadmap update

- [x] 6.1 In `openspec/ROADMAP.md`, flip line 10's R4 checkbox to `[x]` and append a "Shipped via `actions-verify-after-apply`, archived YYYY-MM-DD" suffix matching the format used for R1/R2.x/R3/R5. The archive date is filled at archive time.

## 7. Automated checks (best-effort, no end-to-end run)

End-to-end testing is deferred — the operator will exercise the
updated workflow on an adopter repository by pushing a real
`@change-apply` trigger commit. The tasks below are the best-effort
local checks that can run without GitHub Actions.

- [x] 7.1 Lint the updated `templates/workflows/opsx-apply.yml` with `actionlint` (or document why `actionlint` is unavailable). Fix any errors; warnings about shellcheck inside `run:` blocks may be addressed inline if cheap. (`actionlint` is not on PATH on this workstation — no `brew` formula installed, no `go` toolchain, and no `rhysd/actionlint` Docker image cached. Linting is deferred to CI / a follow-up environment with `actionlint` available; the YAML itself parses cleanly via `python3 -c "yaml.safe_load(...)"` — see 7.2.)
- [x] 7.2 Run `yq` / `yamllint` (whichever is already on PATH) over the workflow file to confirm valid YAML syntax. (`yq` and `yamllint` are not installed; `python3 -c "import yaml; yaml.safe_load(open('templates/workflows/opsx-apply.yml'))"` returns clean — equivalent YAML syntax check.)
- [x] 7.3 Eyeball-check the step order matches the spec: `apply` → `validate` → `verify` → `stage+commit` → `push` → `open or update PR` → `post verify report` → `upload agent logs`. Confirm `verify.md` and `verify.jsonl` appear in the `git reset` line and in the artifact `path:` list.

## 8. Validate before archive

- [x] 8.1 Run `openspec validate actions-verify-after-apply --strict` and resolve any reported issues.
