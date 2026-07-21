---
name: manage-agents
description: >-
  Inspect registered agents and spending sessions on the user's account. Invoke for
  diagnostics, debugging "agent not registered" errors, reviewing active or expired
  sessions, checking budget remaining, or when the user asks what agents or sessions
  exist. Read-only -- does not create or modify anything.
user-invocable: true
allowed-tools:
  - "Bash(kpass user *)"
  - "Bash(kpass me*)"
---

# Manage Agents

List and inspect registered agents and their spending sessions from the user's perspective. These commands use the user's JWT (not an agent token) and show data across all agents registered to the user's account.

## When to Use This Skill

- The user asks "what agents are registered on my account?" or "show me my agents."
- The user asks "what sessions do I have?" or "show me active sessions."
- You need to debug an "agent not registered" or "no active sessions" error.
- You want to verify an agent registration or session was created successfully.
- The user asks for a history of agent sessions or wants to review session activity.

## When NOT to Use This Skill

- If you need to **create** a new session or **register** an agent, use the **`request-session`** skill instead. This skill is read-only.
- If you need to **execute** a payment through a session, use the **`x402-execute`** skill.
- If you need to list sessions from the **agent's** perspective (using the agent token), use `agent:session list` from the **`request-session`** skill.

## Prerequisites

The user MUST be authenticated before using this skill. If not logged in (exit code 3 with "Not logged in"), use the **`authenticate-user`** skill first.

No agent registration or spending session is required. These commands operate with the user's JWT directly.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|---------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Filters | Omit all filters (returns everything) | Only pass filter flags when the user asks to narrow results. |
| Limit | Server default (omit) | Only pass `--limit` if the user requests pagination or you need to limit results. |
| Offset | `0` (omit) | Only pass `--offset` for pagination when combined with `--limit`. |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

---

## Command Reference and Worked Examples

Full argument tables, JSON output examples, error envelopes for `me`, `user agents`, and `user sessions` — plus four end-to-end worked examples (list all agents, filter sessions by status, paginated listing, diagnose "agent not registered") — live in:

→ **`@references/commands.md`**

Read that file before running any command.

---

## Error Handling

| Exit Code | Meaning | Error Message Pattern | Recovery Action |
|-----------|---------|----------------------|-----------------|
| 0 | Success | `status: "success"` | Present the result to the user. |
| 1 | Network error | `network error: ...` | Check connectivity. Retry after a brief pause. |
| 2 | Usage error | `--limit must be an integer between 1 and 100`, `--offset must be a non-negative integer` | Fix the flag value. See validation rules in the arguments table. |
| 3 | Auth error | `Not logged in. Run ...` | Use the **`authenticate-user`** skill to log in. |
| 4 | Not found | `not found` | The requested resource does not exist. Check the filter values. |
| 5 | Rate limited | `rate limit` | Wait 30 seconds, then retry. |
| 6 | Session policy violation | N/A for manage-agents | Read-only commands do not use spending sessions. This exit code is not expected. |

### Specific Error Scenarios

**"Not logged in." (exit code 3):**
- Use the **`authenticate-user`** skill. After logging in, retry the command.

**"--limit must be an integer between 1 and 100" (exit code 2):**
- The `--limit` value must be a whole number from 1 to 100. Do not pass `0`, negative values, or decimals.

**"--offset must be a non-negative integer" (exit code 2):**
- The `--offset` value must be a whole number that is 0 or greater. Do not pass negative values or decimals.

---

## Commands That DO NOT Exist

Do NOT attempt any of the following. They will fail:

- `kpass user` (without a sub-command) -- must use `user agents` or `user sessions`
- `kpass user agent` (singular) -- does not exist; use `user agents` (plural)
- `kpass user session` (singular) -- does not exist; use `user sessions` (plural)
- `kpass user agents --status` -- the `--status` flag only exists on `user sessions`, not `user agents`
- `kpass user agents --limit` -- the `--limit` flag only exists on `user sessions`, not `user agents`
- `kpass user sessions --type` -- the flag is `--agent-type`, not `--type`
- `kpass user sessions --id` -- the flag is `--session-id`, not `--id`
- `kpass user delete-agent` -- does not exist
- `kpass user revoke-session` -- does not exist
- `kpass agents` -- does not exist; use `user agents`
- `kpass sessions` -- does not exist; use `user sessions`
- Any command with `--json` -- the correct flag is `--output json` (two separate tokens)

---

## Input Validation Checklist

Before running any command, verify:

1. **Authentication:** The user must be logged in. Use `me --output json` to check.
2. **Agent ID (`--agent-id`):** If provided, must be a string from a prior command's output. Do not fabricate values.
3. **Agent type (`--agent-type`):** If provided, must be a known agent type string (e.g., `claude`, `cursor`, `codex`, `cline`).
4. **Session ID (`--session-id`):** If provided, must be a string from a prior command's output. Do not fabricate values.
5. **Status (`--status`):** If provided, must be `active` or `expired`.
6. **Limit (`--limit`):** If provided, must be an integer between 1 and 100.
7. **Offset (`--offset`):** If provided, must be a non-negative integer (0 or greater).

---

## Cross-Skill References

- **Prerequisite:** User must be logged in. Use the **`authenticate-user`** skill.
- **To register an agent or create sessions:** Use the **`request-session`** skill. This skill is read-only and cannot create or modify agents or sessions.
- **To execute payments:** Use the **`x402-execute`** skill (requires an active session).
- **To check wallet balance or send tokens:** Use the **`wallet-send`** skill.
