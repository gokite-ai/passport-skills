# Manage Agents — Command Reference

Full per-command reference and worked examples for the `manage-agents` skill. SKILL.md contains trigger logic and decision flow; this file contains command-level detail (argument tables, JSON outputs, error envelopes) plus end-to-end examples for listing agents, filtering sessions, paginating, and diagnosing common errors.

## `me` -- Check Current User

Returns the currently logged-in user. Useful for verifying authentication state before running other commands.

```
kpass me --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "user_id": "user_789xyz",
  "email": "user@example.com",
  "_version": "1",
  "status": "success",
  "hint": "Logged in as user@example.com.",
  "next_command": ""
}
```

### Error Output -- Not Logged In (exit code 3)

```json
{
  "_version": "1",
  "status": "error",
  "error": "Not logged in. Run signup or login first.",
  "hint": "Run 'kpass signup init --email <email> --output json' or 'kpass login init --email <email> --output json'.",
  "next_command": ""
}
```

See the **`authenticate-user`** skill for full documentation on `me`.

---

## `user agents` -- List Registered Agents

Lists all agents registered to the currently logged-in user. Optionally filter by agent ID or agent type.

```
kpass user agents --output json
```

Full form with optional filters:

```
kpass user agents --agent-id <AGENT_ID> --agent-type <AGENT_TYPE> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Agent ID filter | `--agent-id` | No | From prior `user agents` output or `agent:register` output | String agent ID (e.g., `agent_abc123`) |
| Agent type filter | `--agent-type` | No | Known agent type (e.g., `claude`, `cursor`, `codex`, `cline`) | String agent type identifier |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

All filter flags are optional. Omit them to list all agents.

### Success Output -- Agents Found (exit code 0)

```json
{
  "agents": [
    {
      "id": "agent_abc123",
      "type": "claude",
      "created_at": "2026-03-18T10:00:00Z"
    },
    {
      "id": "agent_def456",
      "type": "cursor",
      "created_at": "2026-03-17T08:30:00Z"
    }
  ],
  "_version": "1",
  "status": "success",
  "hint": "Found 2 agent(s).",
  "next_command": ""
}
```

**Key fields:**
- `agents` -- Array of agent objects. Each has `id`, `type`, and `created_at`.
- `agents[].id` -- The unique agent identifier.
- `agents[].type` -- The agent platform type (e.g., `claude`, `cursor`, `codex`, `cline`).
- `agents[].created_at` -- ISO 8601 timestamp of when the agent was registered.

### Success Output -- No Agents (exit code 0)

```json
{
  "agents": [],
  "_version": "1",
  "status": "success",
  "hint": "No agents found.",
  "next_command": ""
}
```

### What to Do After This Command

- If agents were found, present them to the user in a clear format (ID, type, creation date).
- If no agents were found and the user expected some, suggest registering an agent with the **`request-session`** skill (`agent:register --type <agent-type> --output json`, where `<agent-type>` is the agent's own identity).
- To see sessions for a specific agent, use `user sessions --agent-id <id>`.

---

## `user sessions` -- List Agent Sessions

Lists spending sessions across all agents registered to the user. Supports filtering by status, agent ID, agent type, session ID, and pagination.

```
kpass user sessions --output json
```

Full form with all optional filters:

```
kpass user sessions \
  --status <STATUS> \
  --agent-id <AGENT_ID> \
  --agent-type <AGENT_TYPE> \
  --session-id <SESSION_ID> \
  --limit <N> \
  --offset <N> \
  --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Status filter | `--status` | No | Use `active` to find usable sessions, `expired` for past ones | String: `active` or `expired` |
| Agent ID filter | `--agent-id` | No | From `user agents` output | String agent ID (e.g., `agent_abc123`) |
| Agent type filter | `--agent-type` | No | Known agent type (e.g., `claude`, `cursor`) | String agent type identifier |
| Session ID filter | `--session-id` | No | From `user sessions` or `agent:session list` output | String session ID (e.g., `session_xyz789`) |
| Limit | `--limit` | No | Default: server-determined. Pass to control page size. | Integer between 1 and 100 |
| Offset | `--offset` | No | Default: 0. Pass for pagination. | Non-negative integer (0 or greater) |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

All filter flags are optional. Omit them to list all sessions.

### Success Output -- Sessions Found (exit code 0)

```json
{
  "sessions": [
    {
      "id": "session_xyz789",
      "status": "active",
      "agent_type": "claude",
      "expires_at": "2026-03-19T13:00:00Z",
      "delegation": {
        "task": {
          "summary": "Query the weather forecast API at weather.example.com."
        },
        "payment_policy": {
          "assets": ["USDC"],
          "max_amount_per_tx": "5.00",
          "max_total_amount": "50.00"
        }
      },
      "usage": {
        "spent_total": "10.00",
        "reserved_total": "0.00"
      }
    },
    {
      "id": "session_old456",
      "status": "expired",
      "agent_type": "cursor",
      "expires_at": "2026-03-18T10:00:00Z",
      "delegation": {
        "task": {
          "summary": "Access paid data API."
        },
        "payment_policy": {
          "assets": ["USDC"],
          "max_amount_per_tx": "50.00",
          "max_total_amount": "200.00"
        }
      },
      "usage": {
        "spent_total": "75.00",
        "reserved_total": "0.00"
      }
    }
  ],
  "total": 2,
  "limit": 25,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "Found 2 session(s) (total: 2).",
  "next_command": ""
}
```

**Key fields:**
- `sessions` -- Array of session objects.
- `sessions[].id` -- The unique session identifier.
- `sessions[].status` -- Session status (`active` or `expired`).
- `sessions[].agent_type` -- The agent type that owns this session.
- `sessions[].expires_at` -- ISO 8601 timestamp of when the session expires (or expired).
- `sessions[].delegation` -- The delegation policy for this session, containing `task` (summary), `payment_policy` (approaches, assets, caps), and optionally `execution_constraints`.
- `sessions[].delegation.payment_policy.max_amount_per_tx` -- The per-transaction spending limit.
- `sessions[].delegation.payment_policy.max_total_amount` -- The total session budget (if set).
- `sessions[].delegation.payment_policy.assets` -- The allowed assets (e.g., `["USDC"]`).
- `sessions[].usage` -- Current usage: `spent_total` (total spent) and `reserved_total` (amount reserved for in-flight payments).
- `total` -- Total number of sessions matching the filter (for pagination).
- `limit` -- The page size used.
- `offset` -- The offset used.

### Success Output -- No Sessions (exit code 0)

```json
{
  "sessions": [],
  "total": 0,
  "limit": 25,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "No sessions found.",
  "next_command": ""
}
```

### What to Do After This Command

- Present the sessions to the user in a clear format (ID, status, agent type, task summary, budget, spent, expiry).
- If no active sessions exist and one is needed, use the **`request-session`** skill to create a new session.
- For paginated results, check if `offset + sessions.length < total`. If so, there are more pages -- run again with `--offset <next_offset>`.

---

## Complete Worked Example: List All Agents

**Context:** The user asks "What agents are registered on my account?"

**Step 1:** Verify authentication.
```bash
kpass me --output json
```
Output:
```json
{
  "user_id": "user_789xyz",
  "email": "user@example.com",
  "_version": "1",
  "status": "success",
  "hint": "Logged in as user@example.com.",
  "next_command": ""
}
```

**Step 2:** List all agents.
```bash
kpass user agents --output json
```
Output:
```json
{
  "agents": [
    {
      "id": "agent_abc123",
      "type": "claude",
      "created_at": "2026-03-18T10:00:00Z"
    },
    {
      "id": "agent_def456",
      "type": "cursor",
      "created_at": "2026-03-17T08:30:00Z"
    }
  ],
  "_version": "1",
  "status": "success",
  "hint": "Found 2 agent(s).",
  "next_command": ""
}
```

**Step 3:** Present to the user: "You have 2 registered agents: **claude** (registered Mar 18) and **cursor** (registered Mar 17)."

---

## Complete Worked Example: Filter Sessions by Status

**Context:** The user asks "Show me my active sessions."

```bash
kpass user sessions --status active --output json
```
Output:
```json
{
  "sessions": [
    {
      "id": "session_xyz789",
      "status": "active",
      "agent_type": "claude",
      "expires_at": "2026-03-19T13:00:00Z",
      "delegation": {
        "task": {
          "summary": "Query the weather forecast API at weather.example.com."
        },
        "payment_policy": {
          "assets": ["USDC"],
          "max_amount_per_tx": "5.00",
          "max_total_amount": "50.00"
        }
      },
      "usage": {
        "spent_total": "10.00",
        "reserved_total": "0.00"
      }
    }
  ],
  "total": 1,
  "limit": 25,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "Found 1 session(s) (total: 1).",
  "next_command": ""
}
```

Present to the user: "You have 1 active session: **session_xyz789** (claude agent, task: 'Query the weather forecast API', up to 5.00 USDC per transaction, 10.00 / 50.00 USDC spent, expires Mar 19 at 1:00 PM UTC)."

---

## Complete Worked Example: Paginated Session Listing

**Context:** The user has many sessions and you want to page through them.

**Page 1:**
```bash
kpass user sessions --limit 10 --offset 0 --output json
```
Output:
```json
{
  "sessions": [
    { "id": "session_001", "status": "active", "agent_type": "claude", "expires_at": "2026-03-19T13:00:00Z", "delegation": { "task": { "summary": "Weather API access." }, "payment_policy": { "assets": ["USDC"], "max_amount_per_tx": "5.00", "max_total_amount": "50.00" } }, "usage": { "spent_total": "10.00", "reserved_total": "0.00" } },
    { "id": "session_002", "status": "expired", "agent_type": "cursor", "expires_at": "2026-03-18T10:00:00Z", "delegation": { "task": { "summary": "Data API access." }, "payment_policy": { "assets": ["USDC"], "max_amount_per_tx": "50.00", "max_total_amount": "200.00" } }, "usage": { "spent_total": "75.00", "reserved_total": "0.00" } }
  ],
  "total": 15,
  "limit": 10,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "Found 2 session(s) (total: 15).",
  "next_command": ""
}
```
There are 15 total but only 2 returned (first page of 10, but server returned 2). Check: `0 + 2 < 15`, so there may be more pages. The next offset is the current offset plus the number of items just returned (`0 + 2 = 2`), not the `--limit` value.

**Page 2:**
```bash
kpass user sessions --limit 10 --offset 2 --output json
```
Continue until `offset + sessions.length >= total`.

---

## Complete Worked Example: Diagnose "Agent Not Registered" Error

**Context:** Running `agent:session list` fails with "Agent not registered." You want to check what agents the user actually has.

**Step 1:** Check from the user's perspective.
```bash
kpass user agents --agent-type claude --output json
```
Output:
```json
{
  "agents": [],
  "_version": "1",
  "status": "success",
  "hint": "No agents found.",
  "next_command": ""
}
```

No agent is registered for the current identity. Register one using the **`request-session`** skill:
```bash
kpass agent:register --type <agent-type> --output json
# Replace <agent-type> with your agent's identity: claude, cursor, codex, cline, etc.
```

---
