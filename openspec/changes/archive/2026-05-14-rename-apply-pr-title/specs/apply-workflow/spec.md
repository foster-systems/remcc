## MODIFIED Requirements

### Requirement: Open or update the change PR

If the change branch has commits ahead of `main`, the workflow SHALL
ensure a PR exists from the change branch to `main`. If no PR exists,
the workflow SHALL create one with the title format
`Change: <change-name>` (the literal string `Change: ` followed by
the resolved change name as the entire title). If a PR already
exists, the workflow SHALL post a comment summarising the run and
SHALL NOT modify the existing PR's title.

#### Scenario: First successful run opens a PR

- **WHEN** the workflow completes successfully and no PR exists
  for the change branch `change/foo`
- **THEN** the workflow creates a PR with the title `Change: foo`
  and the apply/validate exit codes in the body

#### Scenario: Subsequent run on existing PR adds a comment

- **WHEN** the workflow completes and a PR already exists for the
  change branch
- **THEN** the workflow adds a comment to the PR with the latest
  apply/validate exit codes
- **AND** the existing PR's title is not changed
