# remcc

remcc is a docs-and-templates kit for running OpenSpec's `/opsx:apply`
unattended on GitHub Actions. It is not a runtime, package, or service —
adopters copy the workflow, settings, and bootstrap script from
`templates/` into their own repository and follow a checklist. The
safety contract is two-layer: permissive inside an ephemeral runner,
tight at the GitHub boundary (branch protection, push rulesets,
minimal `GITHUB_TOKEN` scope).

Start with [docs/SETUP.md](docs/SETUP.md).
