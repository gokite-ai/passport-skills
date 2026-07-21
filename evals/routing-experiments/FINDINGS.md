# Routing Audit Findings

**Phase:** 7 — Routing Audit + Permissions Gate Fix
**Date:** 2026-04-14
**Status:** Final

---

## Routing Mechanism: .claude/commands/ vs ~/.agents/skills/

The eval harness (`run_eval.py`) and production skill invocation use **two completely separate routing paths**. Understanding this distinction is the central finding of this audit.

### Eval Harness Path

`run_eval.py` calls `run_single_query()` for each query in the eval set. This function:

1. Generates a UUID-based unique name: `{skill_name}-skill-{uuid8}` (e.g., `activity-skill-a3f7b2c1`)
2. Creates a temporary stub file at `.claude/commands/{skill_name}-skill-{uuid8}.md`
3. Runs `claude -p "{query}"` from the project root as a subprocess
4. The model receives the bare natural language query and responds directly
5. The harness checks whether the model's response includes a `Skill()` or `Read()` tool call containing the UUID-based `clean_name`

**Stub creation code** (source: `~/.agents/skills/skill-creator/scripts/run_eval.py`, lines 51–67):

```python
unique_id = uuid.uuid4().hex[:8]
clean_name = f"{skill_name}-skill-{unique_id}"  # e.g., "activity-skill-a3f7b2c1"
project_commands_dir = Path(project_root) / ".claude" / "commands"
command_file = project_commands_dir / f"{clean_name}.md"
```

**Trigger detection code** (source: `run_eval.py`, lines 129–153):

```python
if tool_name in ("Skill", "Read"):
    # ... accumulate partial JSON input ...
    if clean_name in accumulated_json:  # e.g., "activity-skill-a3f7b2c1"
        return True  # triggered!
```

The model must call `Skill("activity-skill-a3f7b2c1")` or `Read` a path containing `"activity-skill-a3f7b2c1"`. This never happens because **bare natural language queries to `claude -p` do not auto-invoke `.claude/commands/` slash commands** — slash commands require explicit `/command-name` invocation syntax.

### Production Path

Skills installed at `~/.agents/skills/{slug}/SKILL.md` are exposed to Claude as `Skill("{slug}")` tool calls. `.claude/settings.local.json` gates which skills are allowed via `Skill({slug})` entries in the `permissions.allow` list.

When a user in an interactive Claude session asks a question, Claude can call `Skill("activity")` if:
- The skill has a `Skill(activity)` entry in `.claude/settings.local.json`
- Claude judges the skill relevant based on the skill's `description` frontmatter

### Critical Conclusion

**These paths share NO common gating mechanism.** The `Skill()` permission entries in `settings.local.json` control production routing only. The harness path has no permissions gate — it fails for a structural reason: the slash-command routing mechanism (`.claude/commands/`) requires explicit `/command-name` invocation syntax that bare NL queries never produce.

```
Production routing (interactive Claude sessions):
  ~/.agents/skills/{slug}/SKILL.md
       |
       v  (gated by settings.local.json Skill() entries)
  Skill("{slug}") tool call

Eval harness routing (run_eval.py):
  .claude/commands/{slug}-skill-{uuid8}.md  ← stub created per query
       |
       v  (no gating — but model never triggers this anyway)
  claude -p "{query}" → model answers directly, no tool call
  result: trigger_rate = 0.0 universally
```

---

## Why 50% Baseline Score is Expected (Not a Success Signal)

The 50% baseline score across all 9 skills is not random noise or a performance score — it is the **mathematically inevitable outcome** when the model never triggers any skill.

### Mechanistic Derivation

Each eval set contains 20 queries split 50/50:
- 10 queries with `should_trigger=true`
- 10 queries with `should_trigger=false`

When the model answers every query directly without any tool call, `trigger_rate = 0.0` for all 20 queries:

| Query class | Model behavior | Harness outcome |
|-------------|----------------|-----------------|
| `should_trigger=true` (10 queries) | Answers directly, no tool call | `trigger_rate=0.0` does NOT match expectation → **FAIL** (0/10) |
| `should_trigger=false` (10 queries) | Answers directly, no tool call | `trigger_rate=0.0` matches expectation → **PASS** (10/10) |

**Result: 10 PASS / 20 total = 50% accuracy, 0% recall, 100% specificity.**

With `holdout=0.4`, the eval set is split into approximately 12 train queries and 8 test queries. The 50/50 proportion holds, giving approximately 4 test queries passing trivially:
- Observed across all 9 skills in the v1.0 run: `best_score = 4/8` (50%)
- This is not a coincidence — it is the expected value when recall = 0%

### The Diagnostic Signal

**Any score ≤ 50% with recall = 0% is a null result.** It means the model never triggered the skill at all. The 50% comes entirely from the `should_trigger=false` half passing trivially (no-trigger outcome matches expected no-trigger).

A score of 50% does NOT mean:
- "The skill triggers correctly half the time"
- "The description is mediocre but functional"
- "Optimization might improve it from 50% to 60%"

It means: **the harness produced zero triggers. The structural reason (NL queries don't auto-invoke slash commands) makes any score of 50% a ceiling, not a baseline.**

Description optimization (`run_loop.py`) cannot improve a 50% null-result score because the issue is not with the description quality — it is with the routing mechanism itself.

---

## Permissions Gate: What Was Blocked

### Pre-Fix State

`.claude/settings.local.json` had only 2 of 9 skills permitted:

```json
{
  "permissions": {
    "allow": [
      "Skill(activity)",
      "Skill(authenticate-user)",
      "Bash(kpass login:*)"
    ]
  }
}
```

### The 7 Missing Skills

The following skills were blocked from production `Skill()` invocation in interactive Claude sessions:

1. `form-session-delegation`
2. `kite-discovery`
3. `manage-agents`
4. `request-session`
5. `shopping`
6. `wallet-send`
7. `x402-execute`

### What Blocking Means

In an interactive Claude session, if a user asked "what's my wallet balance?", Claude could not call `Skill("wallet-send")` even if it wanted to — the missing `Skill(wallet-send)` entry in `settings.local.json` would cause the tool call to be denied. The user would get a direct response instead of the skill's structured behavior.

### Post-Fix State

All 9 skills now have `Skill()` entries in `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Skill(activity)",
      "Skill(authenticate-user)",
      "Skill(form-session-delegation)",
      "Skill(kite-discovery)",
      "Skill(manage-agents)",
      "Skill(request-session)",
      "Skill(shopping)",
      "Skill(wallet-send)",
      "Skill(x402-execute)",
      "Bash(kpass login:*)"
    ]
  }
}
```

### Important Clarification

Fixing permissions **does not affect harness scores** because the harness uses a different routing path (see Section 1). The permissions fix serves production routing correctness — it ensures all 9 skills are accessible when Claude invokes them in real interactive sessions.

---

## Positive Control Probe Result

### Probe Configuration

- **Skill:** `activity`
- **Eval set:** `evals/trigger-evals/activity.json` — 20 queries: 10 `should_trigger=true`, 10 `should_trigger=false`
- **Flags:** `--runs-per-query 3`, `--num-workers 4`, `--timeout 30`, `--verbose`
- **Invocation:**
  ```bash
  cd /Users/testuser/Dev/gokite/passport-skills
  PYTHONPATH=~/.agents/skills/skill-creator \
    python3 -m scripts.run_eval \
    --eval-set evals/trigger-evals/activity.json \
    --skill-path activity/ \
    --num-workers 4 \
    --timeout 30 \
    --runs-per-query 3 \
    --verbose
  ```
- **Run date:** 2026-04-14
- **Raw output:** `evals/routing-experiments/probe-output.txt`

### Summary Result

| Metric | Value |
|--------|-------|
| Overall score | 10 / 20 passed (50%) |
| Recall (should-trigger queries) | 0% (0 of 10 triggered) |
| Specificity (should-not-trigger queries) | 100% (10 of 10 did not trigger) |
| Non-zero trigger_rate entries | 0 out of 20 queries |

### Per-Query Breakdown

| Query | should_trigger | trigger_rate | Result |
|-------|---------------|--------------|--------|
| Show me my recent activity | true | 0/3 | FAIL |
| What transactions have I made? | true | 0/3 | FAIL |
| Did my last payment go through? | true | 0/3 | FAIL |
| Show me my transaction history | true | 0/3 | FAIL |
| What have I done on my account recently? | true | 0/3 | FAIL |
| Show only my wallet transfers | true | 0/3 | FAIL |
| Did the shopping checkout complete? | true | 0/3 | FAIL |
| Show me my spending history from the past week | true | 0/3 | FAIL |
| List my recent API payments | true | 0/3 | FAIL |
| Show me my passkey registrations | true | 0/3 | FAIL |
| Send 5 USDC to 0xabc123 | false | 0/3 | PASS |
| What is my wallet balance? | false | 0/3 | PASS |
| Make a payment to api.example.com through my session | false | 0/3 | PASS |
| What agents are registered on my account? | false | 0/3 | PASS |
| Show me my active spending sessions | false | 0/3 | PASS |
| Search for a product on Amazon | false | 0/3 | PASS |
| Register my agent so I can make payments | false | 0/3 | PASS |
| Add a wireless mouse to my cart | false | 0/3 | PASS |
| Which paid APIs can I call with ksearch? | false | 0/3 | PASS |
| Top up my testnet wallet with USDC | false | 0/3 | PASS |

### Interpretation

Recall is 0%. Every `should_trigger=true` query produced `trigger_rate=0.0`. Every `should_trigger=false` query also produced `trigger_rate=0.0`. The model answered all 20 queries directly without any `Skill()` or `Read()` tool call.

This is the structural outcome described in Section 1. The model received bare natural language queries via `claude -p` and responded directly without invoking any `.claude/commands/` stub. This confirms that the `.claude/commands/` routing path does not auto-invoke from natural language queries — slash commands require explicit `/command-name` syntax. The 0% recall is a structural property of the harness architecture, not a skill quality issue.

The 50% overall score (10/20) comes entirely from the `should_trigger=false` half passing trivially: when the model produces no tool call, `trigger_rate=0.0` correctly matches the expectation that the skill should NOT trigger (10 PASS). The 10 `should_trigger=true` queries all fail because the model also produces no tool call when it should (10 FAIL). This is the null-result pattern documented in Section 2.

This outcome is consistent with all 5 optimization iterations in the v1.0 run for `activity` (which also had `Skill(activity)` permission throughout): every iteration produced `best_score=4/8` (50%) with 0% recall. The positive control probe after the permissions gate fix produces the identical structural result.

### ROUTING-02 Disposition

**ROUTING-02 SATISFIED WITH DOCUMENTED EXPLANATION:** The harness cannot detect triggers due to the structural limitation of `.claude/commands/` routing. Bare natural language queries sent via `claude -p` do not auto-invoke slash command files — the model processes the query directly and responds without calling any tool. This is confirmed by the zero-trigger result across all 20 queries × 3 runs. See Section 1 for the full mechanism explanation. Per ROUTING-02 acceptance criteria, this outcome is valid when documented with a structural explanation, which this section provides.

### ROUTING-05 Disposition

**ROUTING-05 SATISFIED WITH DOCUMENTED EXPLANATION:** The requirement asks for at least one skill to achieve recall > 50% after query rewriting to sufficient complexity. This is structurally impossible with the current `.claude/commands/` harness. The harness uses bare natural language queries via `claude -p` -- these never auto-invoke slash command files regardless of query complexity. See Section 1 for the complete routing mechanism explanation. Per Phase 9 SC-2 ("or findings document explains why the harness cannot produce > 50% for structural reasons"), this documented structural explanation satisfies ROUTING-05 without requiring query rewriting or harness changes.

---

## Pre-Flight Checklist

Before running `run_loop.py` or `run_eval.py`, verify each item:

1. **Working directory:** Must be the project root (`/Users/testuser/Dev/gokite/passport-skills`).

   ```bash
   pwd
   # Must output: /Users/testuser/Dev/gokite/passport-skills
   ```

   **Why this matters:** `find_project_root()` walks up from `cwd` looking for a `.claude/` directory. Since `~/` also has `.claude/` (the global Claude config), running from outside the project root causes `find_project_root()` to return `~/` — and stubs land in `~/.claude/commands/` instead of `.claude/commands/`. This has already happened: 4 stale `form-session-delegation-skill-*.md` stubs were found in `~/.claude/commands/` from a prior run. The stubs never get cleaned up when the harness exits (the `finally: command_file.unlink()` cleanup only removes the file at the path the harness thinks it wrote to, which was `~/.claude/commands/` — not the project's `.claude/commands/`).

2. **Stale stubs cleaned:** Check both locations for leftover stubs:

   ```bash
   ls ~/.claude/commands/*-skill-*.md 2>/dev/null    # Should return nothing
   ls .claude/commands/*-skill-*.md 2>/dev/null       # Should return nothing
   ```

   If stale stubs exist, remove them:
   ```bash
   rm -f ~/.claude/commands/*-skill-*.md
   rm -f .claude/commands/*-skill-*.md
   ```

3. **PYTHONPATH set:** `PYTHONPATH=~/.agents/skills/skill-creator` must be set before invocation so `from scripts.utils import parse_skill_md` resolves. Without it, `run_eval.py` will fail with an `ImportError`.

   ```bash
   # Verify the import works:
   PYTHONPATH=~/.agents/skills/skill-creator python3 -c "from scripts.utils import parse_skill_md; print('ok')"
   ```

4. **Permissions state:** All 9 skills must have `Skill()` entries in `.claude/settings.local.json` (for production routing correctness, even though the harness doesn't test production routing). After this phase's fix, all 9 are present.

   ```bash
   python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(len(d['permissions']['allow']), 'entries')"
   # Should print: 10 entries
   ```

5. **Invocation command format:** Use `python3 -m scripts.run_eval` (module invocation) from the project root, not a direct path to the script:

   ```bash
   cd /Users/testuser/Dev/gokite/passport-skills
   PYTHONPATH=~/.agents/skills/skill-creator \
     python3 -m scripts.run_eval \
     --eval-set evals/trigger-evals/{skill}.json \
     --skill-path {skill}/ \
     --num-workers 4 \
     --timeout 30 \
     --runs-per-query 3 \
     --verbose
   ```

   Replace `{skill}` with the skill name (e.g., `activity`). The `--verbose` flag prints per-query pass/fail results to stderr while JSON goes to stdout.
