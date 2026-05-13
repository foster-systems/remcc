# Goal

I want to run Claude Code authoring code in unattended mode where where and I don't have to confirm different commands that it needs to execute. This requires Claude Code to have (almost?) full permissions in the environment (settings.json deny empty?), so apparently it cannot be localhost on my private macos for security reasons. The result of the work that Claude Code is authoring will be source code which will be pushed to a GitHub repo -- I think I can set up specific permissions to avoid destructive actions.

# Roadmap

- [ ] R1: Be able to complete the whole spec-driven flow end to end on the change branch. See: openspec/roadmap-items/R2-apply-flag.md
- [ ] R2: Automate onboarding and update delivery for new adopter repos, making it as easy as possible (e.g. run one script, minimze manual actions).
- [ ] R3: cloud run `opsx:verify` after apply and... automatically fix? or: highlight in PR -> human review -> another go.
- [ ] R4: Codify the working loop: describe the bigger problem → propose → iterate → split into smaller bite-size changes → apply changes one-by-one via remcc.
