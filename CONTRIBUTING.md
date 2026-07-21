# Contributing to Kite Passport Skills

Thanks for your interest in contributing! This guide covers how to add new skills, update existing ones, and submit changes.

## Getting Started

1. Fork and clone the repository
2. Install dependencies:

   ```bash
   npm install
   ```

3. Run the bootstrap check:

   ```bash
   bash scripts/setup.sh
   ```

## Adding a New Skill

1. Create a directory named after the skill (use kebab-case):

   ```
   my-new-skill/
     SKILL.md
   ```

2. Write the `SKILL.md` following the conventions below.

3. Register the skill in `skills.json` — add an entry to the `skills` array with `slug`, `name`, `description`, `path`, `tags`, and `dependencies`.

4. Run validation:

   ```bash
   npm run validate
   npm run lint
   ```

## Skill File Conventions

Every `SKILL.md` must follow these patterns:

- **CLI invocation**: Always use `kpass <command> [flags] --output json`
- **Flags**: Include `--output json` on every command and `--no-interactive` where applicable
- **JSON output**: Document the exact response shape with field descriptions
- **Exit codes**: Reference the standard exit code table (0–5)
- **Error handling**: Include recovery steps for every error scenario
- **"Commands That DO NOT Exist"**: List common hallucinated commands to prevent agent mistakes
- **Dependencies**: Clearly state which skills must run first

## SKILL.md Layout — Progressive Disclosure

When a `SKILL.md` exceeds ~400 lines or includes more than ~3 commands with full argument tables, split it into:

```
my-skill/
  SKILL.md                       # trigger logic, decision flow, error matrix, 1 minimal example
  references/
    commands.md                  # full per-command reference (argument tables, JSON outputs, error envelopes, display cards)
    examples.md                  # multi-step worked examples
    <specialized>.md             # e.g. delegation-schema.md for a JSON contract
```

Why: trigger-time context is expensive. Material the agent needs only *after* committing to a skill should not block the routing decision. Cross-reference from SKILL.md with `@references/commands.md`-style links so the agent reads them on demand.

Aggregator skills (e.g. `kite-passport`, which dispatches to other skills) stay flat — they're routers; progressive disclosure doesn't help them.

## Rationale Over Imperative

Write guidance as `<action> — <reason>`, not as ALL-CAPS commands. Agents reason from the *why* and handle edge cases the imperative didn't anticipate; humans editing the file later can judge what's still load-bearing.

**Avoid:**

> **CRITICAL: You MUST always display the formatted status cards. This is NOT optional. Never skip them.**

**Prefer:**

> Display the formatted status card after every successful response — the eval transcript and user-facing output both depend on it; agents that summarize instead of rendering the card lose the structural signal users use to scan results.

The principle is the same for "Do NOT", "NEVER", "MANDATORY:" framing. Spell out the consequence. ALL-CAPS imperatives without a `why` are a code-smell — they tell the agent to follow a rule without giving it the context to recognize when the rule doesn't apply.

## Updating an Existing Skill

1. **Verify against the CLI source.** Every flag, output field, and exit code must match the `kpass` CLI implementation.
2. **Test the commands.** Run each command and verify outputs match the documented shapes.
3. **Check cross-references.** If you rename a command or flag, update all skills that reference it.
4. **Update "Commands That DO NOT Exist"** if you add or remove commands.

## Running Checks

```bash
# Validate skill structure and skills.json
npm run validate

# Lint all markdown files
npm run lint
```

Both checks run in CI on every pull request.

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes
3. Ensure `npm run validate` and `npm run lint` pass
4. Open a pull request using the PR template
5. Describe what changed and why
