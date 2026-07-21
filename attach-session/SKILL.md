---
name: attach-session
description: >-
  Attach an existing attachable session to this agent using its session ID.
  Invoke when the user provides a session ID and asks to use, bind, or attach
  it — typically a session pre-created in the Passport web dashboard ("I made
  a session on the dashboard, here it is", "use session_abc123", "attach this
  session to my agent"). This skill binds an already-created session; it does
  not create sessions. If no session exists yet, use request-session instead.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kpass agent:register*)"
  - "Bash(kpass agent:session *)"
  - "Bash(open *)"
  - "Bash(xdg-open *)"
  - "Bash(cmd.exe /c start*)"
---

# Attach Session

Bind an existing **attachable session** to this agent. Attachable sessions are
created unbound — typically from the Passport web dashboard — with their
delegation policy (budget, per-tx cap, TTL) already defined by the owner. The
agent supplies a signing keypair at attach time and the owner approves the
bind via passkey. This is the counterpart to `request-session`: request is
for figuring out what session a task needs and creating it; attach is for
when the session already exists and the agent only needs to bind to it.

Key semantics (they shape every step below):

- **Once-only.** A session can be attached only while it is in the
  `unattached` state. After a successful attach it is bound permanently —
  there is no detach.
- **Same owner.** The calling agent and the target agent must belong to the
  session owner's account. A session ID from someone else's account fails
  with a forbidden error.
- **TTL starts at approval.** The session's countdown begins when the owner
  approves the attach, not when the session was created — a session that sat
  unattached for a week has its full duration left.
- **The attaching client signs.** The CLI generates the keypair during
  attach and registers the public key as the session's access key on
  approval, so this environment is the one that can execute payments.

## Step 0: Ensure CLI is Installed — MANDATORY

Run the setup script before any `kpass` command — the script verifies the CLI
is installed and configured for this user, and a missing or stale binary
surfaces as a confusing exit-3 ("Not logged in") rather than a clean "CLI not
installed" error if you skip it.

```bash
bash <skill-directory>/scripts/setup.sh
```

Where `<skill-directory>` is the directory containing this SKILL.md file.

**If setup succeeds** (`status: "ok"`): proceed.
**If setup fails** (`status: "error"`): **STOP immediately.** Show the user
the error and installation instructions. Do NOT search for the binary
elsewhere.

## When to Use This Skill

- The user provides a session ID (`session_…`) and asks to use, bind, or
  attach it.
- The user says they created a session in the Passport web dashboard (or
  another surface) and wants this agent to use it.
- Another surface (routine config, secrets manager, teammate) handed the
  agent an attachable session ID.

Do NOT use this skill when no session exists yet — deciding what session a
task needs and creating it is the **`request-session`** skill's job. Attaching
is only cheaper than creating when the owner has already defined the policy;
if the user just says "I want to pay for X", route to `request-session`.

## Prerequisites

- The user must be authenticated. If not logged in (exit code 3 with
  "No user_id found" or "Not logged in"), use the **`authenticate-user`**
  skill first.
- The agent must be registered (Step 1 below handles this — it is
  idempotent).

## Attach Flow

### Step 1: Ensure Agent is Registered

```bash
kpass agent:register --type <agent-type> --output json
# Replace <agent-type> with your agent's identity: claude, cursor, codex, cline, etc.
```

Idempotent, safe to call every time. The `--type` value is never
user-provided — pass your own agent identity. See the **`request-session`**
skill (`references/commands.md` there) for the full `agent:register`
reference and registration card.

### Step 2: Attach the Session

```bash
kpass agent:session attach --session-id <SESSION_ID> --output json
```

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Session ID | `--session-id` | Yes | Provided by the user (or the surface that created the session) | String starting with `session_`. Do not fabricate values. |
| Target agent | `--agent-id` | No | Omit — defaults to this agent | Only pass when the user explicitly asks to attach the session to a *different* agent they own. |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

The CLI generates the signing keypair, stores the private key locally as a
pending entry, and returns an approval request:

```json
{
  "action": "approve_attach",
  "request_id": "req_abc123",
  "approval_url": "https://passport.dev.gokite.ai/approve/req_abc123",
  "expires_at": "2026-03-17T12:05:00Z",
  "session_id": "session_xyz789",
  "agent_id": "agent_abc123",
  "public_key": "0x…",
  "_version": "1",
  "status": "human_action_required",
  "hint": "An attach request was created. Show the approval URL to the user: …",
  "next_command": "kpass agent:session status --request-id req_abc123 --wait --output json"
}
```

`status: "human_action_required"` is NOT an error — exit code is 0. The
session is not usable until the owner approves.

### Step 3: Show the Approval Card and Open the URL

Display this card verbatim after a successful attach request — the
horizontal-rule format is what users scan to confirm what is being approved:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Attach Approval Required

An agent wants to attach to your session:

🌐 {approval_url}

🎫 Session:    {session_id}
🤖 Agent:      {agent_id}
📋 Request ID: {request_id}
⏳ Expires:    {expires_at}

👆 Open the link, review, and approve with passkey.
⏳ I'll wait automatically...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{approval_url}` | JSON field `approval_url` |
| `{session_id}` | JSON field `session_id` |
| `{agent_id}` | JSON field `agent_id` |
| `{request_id}` | JSON field `request_id` |
| `{expires_at}` | JSON field `expires_at` |

Then open the approval URL in the user's default browser automatically —
this saves the user a copy-paste; if it fails, the URL is still in the card:

```bash
open "{approval_url}"                  # macOS
xdg-open "{approval_url}"              # Linux
cmd.exe /c start "" "{approval_url}"   # Windows (via Bash, e.g. WSL/git-bash)
```

### Step 4: Poll for Approval

Immediately start polling — never tell the user "let me know when done"
without polling first:

```bash
kpass agent:session status --request-id <request_id> --wait --output json
```

`--wait` polls every 3 seconds for up to 5 minutes. The approval lifecycle
(approved / pending / rejected / expired envelopes, timeout stop-and-ask
flow) is identical to the session-create flow — follow the **Polling
Strategy** in the `request-session` skill's `references/commands.md`
(`agent:session status`).

On approval, the pending entry is re-keyed to the now-active session, the
CLI sets it as the current session automatically (no `agent:session use`
needed), and the response includes the full `session` object with its
delegation. Display the approved card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔗 Session Attached -- Ready to Transact!

🎫 Session:     {session_id}
📝 Task:        {task_summary}
💰 Per-tx:      Up to {max_amount_per_tx} {currency}
💰 Budget:      {max_total_amount} {currency}
⏰ Expires:     {expires_at}
✅ Status:      Active

All set. I can now execute payments on your behalf.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{session_id}` | JSON field `session_id` or `session.id` |
| `{task_summary}` | JSON field `session.delegation.task.summary` |
| `{max_amount_per_tx}` | JSON field `session.delegation.payment_policy.max_amount_per_tx` |
| `{max_total_amount}` | JSON field `session.delegation.payment_policy.max_total_amount` (show "unlimited" if not set) |
| `{currency}` | JSON field `session.delegation.payment_policy.currency` (defaults to `USD` if not set — there is no `assets` field; see the **`form-session-delegation`** skill) |
| `{expires_at}` | JSON field `session.expires_at` |

Note the delegation was authored by the owner when the session was created —
the agent did not construct it. Read `session.delegation` from the approved
response to learn the spending limits and scope you now operate under, and
respect them when executing.

### Step 5: Execute

The session is active and set as current. Hand off to **`x402-execute`** for
paid API calls or **`shopping`** for checkout.

## Error Handling

| Exit Code | Meaning | Error Message Pattern | Recovery Action |
|-----------|---------|----------------------|-----------------|
| 0 | Success or human action required | `status: "human_action_required"` | Show approval card, open URL, poll. |
| 1 | Network error | `network error: ...` | Check connectivity. Retry after a brief pause. |
| 2 | Usage error | `Missing --session-id flag`, `error_code: "session_not_attachable"`, `invalid session status` | See specific scenarios below. |
| 3 | Auth error | `Agent not registered`, `No user_id found`, attach request rejected/expired | See specific scenarios below. |
| 4 | Not found | `not found` | The session ID (or `--agent-id`) does not exist. Re-check the value with the user — do not retry with guessed IDs. |
| 5 | Rate limited | `rate limit` | Wait 30 seconds, then retry. |
| 6 | Forbidden | `error_code: "agent_not_same_owner"` (`target agent does not belong to the same owner`) | See specific scenarios below. |

**Error envelope fields:** errors include `error` (raw backend message),
`error_code` (machine-readable — prefer for programmatic matching), and
`hint` (recovery guidance).

### Specific Error Scenarios

**"agent session is not attachable" (`error_code: "session_not_attachable"`):**
- The session ID refers to a **dedicated** session, which is bound to its
  agent at create time. Ask the user for an attachable session ID, or create
  a new session via **`request-session`**.

**"invalid session status" (session is not `unattached`):**
- Attach is once-only. If the session is already attached to *this* agent,
  it may simply be usable — check `kpass agent:session list --output json`
  and set it current with `agent:session use`. If it is attached to a
  different agent, this agent cannot take it over; ask the user for a fresh
  attachable session or use **`request-session`**.

**"target agent does not belong to the same owner" (`error_code: "agent_not_same_owner"`, exit code 6):**
- The `--agent-id` you passed names an agent owned by a different account
  than the calling agent's owner — sessions can only be attached to agents
  under the same owner. Re-check the target agent ID with
  **`manage-agents`** (`user agents`), or drop `--agent-id` to attach to
  this agent. If the user recently switched accounts, re-register with
  `kpass agent:register` so the calling agent belongs to the current user.

**"Agent not registered" (exit code 3):**
- Run `kpass agent:register --type <agent-type> --output json` (Step 1),
  then retry the attach.

**"No user_id found. Run signup or login first." (exit code 3):**
- Use the **`authenticate-user`** skill, then retry.

**Attach request rejected (exit code 3):**
- The owner chose not to approve. Ask whether they want to retry (a new
  `attach` call creates a fresh approval request) or create a different
  session.

**Attach request expired (exit code 3):**
- The approval URL timed out before the owner acted. Re-run the attach
  command — the session is still unattached, so a new request is safe.

## Commands That DO NOT Exist

Do NOT attempt any of the following. They will fail:

- `kpass agent:session detach` — attach is permanent; detach was removed
  from the CLI
- `kpass agent:session attach <session_id>` (positional) — the session ID
  must be passed via `--session-id`
- `kpass agent:session attach --public-key …` — the keypair is generated by
  the CLI automatically; there is no key flag
- `kpass agent:session attach --request-id …` — `--request-id` belongs to
  `agent:session status`, not `attach`
- `kpass agent:session status --session-id` — the flag is `--request-id`
- Any command with `--json` — the correct flag is `--output json` (two
  separate tokens)

Also out of scope for this skill: `agent:session create --type attachable`
exists in the CLI, but creating attachable sessions is an owner-surface
concern (web dashboard). When the user needs a *new* session, use
**`request-session`** — do not create an attachable session and immediately
attach it yourself; that is two approvals' worth of friction for what
`request-session` does with one.

## Input Validation Checklist

Before running any command, verify:

1. **Session ID:** Comes from the user or the surface that created the
   session. Must start with `session_`. Do not fabricate or guess.
2. **Agent type:** Your own agent identity string (`claude`, `cursor`,
   `codex`, `cline`, …). Never ask the user.
3. **`--agent-id`:** Omit unless the user explicitly named a different
   target agent they own.
4. **Request ID:** Must come from the `attach` response. Do not fabricate.

## Cross-Skill References

- **Prerequisite:** The user must be authenticated — **`authenticate-user`**.
- **No session yet / needs a new session:** **`request-session`** discovers
  requirements and creates one. Its `references/commands.md` also holds the
  full `agent:register` and `agent:session status` references this skill
  relies on.
- **After the session is attached:** **`x402-execute`** for paid API
  requests, **`shopping`** for checkout.
- **Diagnostics:** **`manage-agents`** (`user agents`, `user sessions`) to
  inspect sessions from the user's perspective — useful to confirm a
  session's status when attach reports it is not attachable or not
  unattached.
