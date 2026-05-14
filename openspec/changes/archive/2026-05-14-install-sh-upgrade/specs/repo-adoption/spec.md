## MODIFIED Requirements

### Requirement: Automated install path is provided

The repo SHALL provide an automated install path via the curl-piped
`install.sh init` invocation (defined in `remcc-cli`) and an automated
update path via `install.sh upgrade`. `docs/SETUP.md` SHALL present
`install.sh init` as the primary adoption flow and SHALL preserve the
existing manual checklist as a fallback for operators who cannot or
will not pipe a remote script to bash. `docs/SETUP.md` SHALL also
document `install.sh upgrade` as the primary update flow once a repo
has been adopted, including the curl one-liner and the `--ref`
override. The automated paths SHALL replace the manual steps for
prerequisite verification, template-file copying, bootstrap-script
invocation (init only), and PR opening.

#### Scenario: Operator adopts via the automated path

- **WHEN** the operator runs the documented `install.sh init`
  one-liner in a target repository that satisfies the prerequisites
- **THEN** the adoption completes by opening a single pull request
  for the operator to review, and the operator was not required to
  copy any template files by hand

#### Scenario: Operator upgrades via the automated path

- **WHEN** the operator runs the documented `install.sh upgrade`
  one-liner in a target repository that was previously adopted via
  `install.sh init`
- **THEN** the upgrade completes by opening a single pull request
  refreshing every template-managed file at the new remcc ref, and
  the operator was not required to copy any template files by hand

#### Scenario: Manual fallback remains documented

- **WHEN** an operator who will not pipe a remote script to bash
  reads `docs/SETUP.md`
- **THEN** the document contains the manual step-by-step checklist
  (template copies, bootstrap invocation, smoke test) as an
  explicit fallback path

## ADDED Requirements

### Requirement: Version marker preserves installed_at across upgrades

The `.remcc/version` marker in an adopted repository SHALL retain its
`installed_at` value across `install.sh upgrade` invocations. The
`installed_at` field records the date the operator first adopted
remcc; it SHALL NOT be re-stamped to the upgrade date on subsequent
upgrades. The mechanism by which the value is preserved is specified
in `remcc-cli`.

#### Scenario: installed_at survives an upgrade-and-merge cycle

- **WHEN** an adopted repo's `main` branch records
  `installed_at: 2026-04-01T10:00:00Z` in `.remcc/version`
- **AND** the operator runs `install.sh upgrade` and merges the
  resulting pull request
- **THEN** `main` still records `installed_at: 2026-04-01T10:00:00Z`
  in `.remcc/version` after the merge
