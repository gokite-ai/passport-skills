# BUILD-LOG

## T1: passport-skills: add the `passport-overview` skill

Date: 2026-10-15
Repo and branch: gokite-ai/passport-skills, main (direct push)
Files changed: passport-overview/SKILL.md (new), skills.json, .cursor-plugin/plugin.json, .grok-plugin/plugin.json, scripts/check-grok-plugin.py, README.md, BUILD-LOG.md (new), onboarding/RESULTS.md (new)
What the user sees differently: When the agent lists its skills, the passport-overview skill is now registered. The agent can use this skill to provide plain facts about Kite Passport for someone who has just installed it: what it is, what it costs, priced examples, and the rule that the agent asks before creating an account, contacting anyone or spending money.
Delta to today's Passport: The passport-overview skill is now available as the 17th user skill. The skill count in both plugin manifests, check-grok-plugin.py, and README.md all reflect 17 skills.
Deviation from the package: None. All files match the package specification at commit 82ba3e995113.
PR link: none (direct push to main)

## ATE-269 T6: Skill replacement in passport-skills

- Date: 2026-10-15
- Repo and branch: gokite-ai/passport-skills, main (direct push)
- Files changed: kite-discovery/SKILL.md (replaced), kite-discovery/references/commands.md (service search section added), kite-discovery/references/examples.md (service search section added), BUILD-LOG.md (entry added), RESULTS.md (created)
- What the user sees differently: The kite-discovery skill now uses the ksearch service search command instead of the node engine/search.mjs command. The skill description and behavior remain the same, but the command invocation has changed to use the consolidated ksearch CLI.
- Delta to today's Passport: The kite-discovery skill file has been updated to reflect the new ksearch command structure, with Step 0 preserved for CLI setup. Reference documentation now includes service search examples.
- Deviation from the package (none, or what and why): None. All files match the package specification at commit 848eba48c7e9 (tree 297a8d506133).
- PR link: none (direct push to main)
