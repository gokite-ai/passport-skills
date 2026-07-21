# Request Session — Command Reference

Full per-command reference for the `request-session` skill. Read this when constructing a command, validating flags, or interpreting an error response. SKILL.md contains trigger logic and the canonical Full Session Creation Flow; this file contains command-level detail (including the 6-check session-reuse evaluation, which lives under `agent:session list`).

## `agent:register` — Register Agent Identity

Registers this agent with the Passport backend, linking it to the currently logged-in user. Saves the agent token locally.

```
kpass agent:register --type <agent-type> --output json
```

**The `--type` value is NOT user-provided.** Each AI agent passes its own identity automatically: `claude` for Claude Code, `cursor` for Cursor, `codex` for Codex, `cline` for Cline. Substitute `<agent-type>` with your own agent's identity. Never ask the user what to put here.

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Agent type | `--type` | Yes | Agent provides automatically — use your own agent name (e.g., `claude`, `cursor`, `codex`, `cline`) | String identifier for the agent platform. Never ask the user. |
| Owner ID | `--owner-id` | No | Auto-read from config (logged-in user's `user_id`) | Only pass if overriding |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "agent_id": "agent_abc123",
  "token": "agt_token_value",
  "type": "claude",
  "owner_id": "user_789xyz",
  "_version": "1",
  "status": "success",
  "hint": "Agent registered as claude.",
  "next_command": ""
}
```

### Already Registered Output (exit code 0)

If the agent is already registered for the current user, the command succeeds silently:

```json
{
  "agent_id": "agent_abc123",
  "type": "claude",
  "owner_id": "user_789xyz",
  "_version": "1",
  "status": "success",
  "hint": "Agent already registered for this user.",
  "next_command": ""
}
```

This is safe to call multiple times. It is idempotent for the same user.

### Owner Mismatch Behavior

If the agent was previously registered to a different user (e.g., the user logged out and a different user logged in), the command automatically re-registers the agent for the new user. This is not an error.

### What to Do After This Command

Proceed to check for existing sessions or create a new one.

**MANDATORY — After this command succeeds, you MUST display the appropriate card to the user.**

For a **new registration**:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 Agent Registered

🏷️  Type:     {type}
🆔 Agent ID: {agent_id}
👤 Owner:    {owner_email}
🔑 Token:    saved to project config

Your agent is ready.
Create a spending session to start.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{type}` | From JSON response field `type` |
| `{agent_id}` | From JSON response field `agent_id` |
| `{owner_email}` | From the user's email already known from the login/signup step (not in the register response) |

For the **already registered** no-op case (hint contains "already registered"):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 Agent Already Registered

🏷️  Type:     {type}
🆔 Agent ID: {agent_id}
✅ Status:   Ready
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## `agent:session list` — List Agent Sessions

Lists sessions for the registered agent, optionally filtered by status.

```
kpass agent:session list --output json
kpass agent:session list --status active --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Status filter | `--status` | No | Pass `active` to filter for usable sessions | String: `active`, `expired`, or omit for all |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output — Sessions Found (exit code 0)

```json
{
  "sessions": [
    {
      "id": "session_abc123",
      "status": "active",
      "expires_at": "2026-03-17T13:00:00Z",
      "delegation": {
        "task": {
          "summary": "Query the weather API for forecasts."
        },
        "payment_policy": {
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
  "_version": "1",
  "status": "success",
  "hint": "Found 1 session(s).",
  "next_command": ""
}
```

### Success Output — No Sessions (exit code 0)

```json
{
  "sessions": [],
  "_version": "1",
  "status": "success",
  "hint": "No active sessions found.",
  "next_command": ""
}
```

### What to Do After This Command — Reuse Evaluation

**You usually do NOT need to run `list` for reuse anymore.** `agent:session create` performs the mechanical reuse checks automatically and returns `reuse_available` candidates (see `agent:session create` → "Automatic Reuse Detection"). Run `list` only for diagnostics, or when you want to inspect/compare sessions directly.

The six checks below are the full criteria. The CLI now enforces checks **2–6 mechanically** (asset, per-tx, budget, expiry, scope); your remaining responsibility on a `reuse_available` result is **check 1 (goal match)**, which is a semantic judgement the CLI cannot make. When evaluating a `list` result by hand, verify ALL six:

1. **Goal match** — The current user goal fits within the existing `delegation.task.summary`. The merchant/service AND the kind of action must match. If the new goal targets a different merchant, a different action, or a materially broader scope than the stored summary, this check FAILS. When in doubt, FAIL — a fresh session is cheap; a wrong-scope reuse is a policy violation.
2. **Asset settleability** — The required payment asset is a stablecoin Passport can settle on the merchant's chain (sessions are token-agnostic; there is no per-session asset allowlist).
3. **Per-tx fit** — The expected per-request price is ≤ `delegation.payment_policy.max_amount_per_tx`.
4. **Budget fit** — The expected total spend for the task is ≤ remaining budget, where `remaining = max_total_amount − usage.spent_total − usage.reserved_total`.
5. **Not expired** — `expires_at` is in the future AND leaves enough time to complete the task.
6. **Scope match** — If `execution_constraints.x402.scope_mode == "scoped"`, the target endpoint (`method`, `host`, `path_prefix`) MUST match one of `allowed_endpoints`. If `scope_mode` is unscoped or `execution_constraints` is absent, this check passes.

**MANDATORY — Before reusing, you MUST display the Session Reuse Evaluation card showing the per-check result:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔎 Session Reuse Evaluation

🎫 Session:      {session_id}
📝 Goal match:   {✅|❌} — {reason}
💱 Asset match:  {✅|❌} — need {asset}; budget enforced in {currency}
💰 Per-tx fit:   {✅|❌} — need ≤ {price}, limit {max_amount_per_tx}
💰 Budget fit:   {✅|❌} — need {estimate}, remaining {remaining}
⏰ Not expired:  {✅|❌} — expires {expires_at}
🎯 Scope match:  {✅|❌} — {scope_detail}

Decision: {Reuse this session | Create new session}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Resolution:

- **0 sessions returned** → proceed to create a new session.
- **All 6 checks pass for exactly one session** → reuse it. If it is not already the current session, call `agent:session use --session-id <id>` first. Then display the `🚀 Session Approved` card (from `agent:session status` below) so the user sees the active session details.
- **All 6 checks pass for 2+ sessions** → display the evaluation card for each candidate, then ask the user which to use.
- **No session passes all 6 checks** → proceed to create a new session. Briefly tell the user which check(s) failed so they understand why a new approval is needed.

---

## `agent:session create` — Create a Spending Session with Delegation

Creates a new spending session request using a delegation object. The user MUST approve it via the returned `approval_url` before the session becomes active.

```
kpass agent:session create --delegation '<JSON>' --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Delegation | `--delegation` | Yes for normal sessions (omit for `--use-card`) | Constructed from preflight + user context. See the **`form-session-delegation`** skill for the full schema and construction rules. | Must be a valid JSON string of the inner delegation object (top-level keys: `task`, `payment_policy`, optional `execution_constraints`). The CLI wraps it under `{"delegation": …}` for transport — do NOT pre-wrap. **Cannot be combined with `--use-card`.** |
| Request virtual card | `--use-card` | No | Pass when the merchant takes a card and the agent needs a session-bound scoped card | Boolean flag. Requires the individual amount/TTL flags below (not `--delegation`). See "Scoped-Card Sessions" below. |
| Task summary | `--task-summary` | No (recommended with `--use-card`) | The user's goal, incl. merchant | String |
| Per-tx limit | `--max-amount-per-tx` | With `--use-card` (or any individual-flag build) | Derived from the price | Decimal string |
| Total budget / card limit | `--max-total-amount` | **Required with `--use-card`** (becomes the card's spending limit) | The session budget | Decimal string |
| TTL | `--ttl` / `--ttl-seconds` | With `--use-card` | e.g. `1h`, `7d`, or integer seconds | Positive duration |
| Skip reuse detection | `--no-reuse` | No | Pass only when you have already decided to force a brand-new session | Boolean flag. Disables the automatic reuse check described below. Redundant with `--use-card` (reuse is always skipped for card sessions). |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Automatic Reuse Detection

Before minting a new session, `create` automatically scans the agent's existing **active** sessions (that this CLI can sign with locally) and checks each one **mechanically** against the requested delegation — asset coverage, per-tx limit, remaining budget, remaining TTL, and endpoint scope. This is the deterministic replacement for the manual list-then-eyeball flow; you no longer need to run `agent:session list` first.

If a covering session is found, behavior depends on the output mode:

- **`--output json` (agent mode):** `create` does **not** create a new request. It returns a `reuse_available` result (see below) so you can apply the one judgement the CLI cannot make — whether the **goal/merchant genuinely matches** — before reusing.
- **Interactive terminal (no `--output json`):** `create` prints the best match and prompts the human directly — `Reuse it instead of creating a new session? [Y/n]` (default **Yes**). On **Y**/Enter it sets that session as current and exits without a new approval; on **n** it proceeds to create a new session.

Pass `--no-reuse` to bypass detection entirely and always create.

### Scoped-Card Sessions (`--use-card`)

Use `--use-card` when the agent must pay a merchant by **virtual card** rather than x402/wallet transfer. It creates a session bound to a **scoped card**: issued at approval, spending limit = `--max-total-amount`, usable for multiple purchases until the limit is used up or it expires (lifetime-limit, not single-use). The CLI sends `execution_constraints.card.enabled=true`; the backend derives the card amount (= max total) and expiry (= TTL).

```
kpass agent:session create --use-card \
  --task-summary "<goal incl. merchant>" \
  --max-amount-per-tx <PER_TX> \
  --max-total-amount <CARD_LIMIT> \
  --ttl <DURATION> \
  --output json
```

Rules and built-in checks (all enforced by the CLI, before any approval):

- **Individual flags only** — `--use-card` cannot be combined with `--delegation`, and `--max-total-amount` is required.
- **Sandbox refused** — fails in sandbox mode; run `kpass sandbox off` first.
- **KYC pre-flight** — the CLI calls `GET /v1/cards/profile` and refuses if `capabilities.can_create_agent_card` is false (account not card-verified). It degrades gracefully (a stderr note, then proceeds) if the profile can't be fetched.
- **Backend cards-enabled** — if the environment has cards switched off, create fails with a friendly "cards feature is not enabled" usage error.
- **Reuse skipped** — a card session is always created fresh (an existing cardless session can't satisfy a card request).

On success the output is the **same `human_action_required` envelope** as a normal session (below) — approval + polling are identical; the card is issued when the user approves.

Card-specific failure outputs (all exit code 2, before any session/card is created):

```json
{ "_version": "1", "status": "error",
  "error": "This account can't use a scoped card yet (card verification status: pending). Complete card verification in the Passport dashboard (Cards) before creating a --use-card session.",
  "error_code": "scoped_card_not_ready",
  "hint": "Open Passport dashboard → Cards and complete card verification/funding before retrying --use-card.",
  "next_command": "" }
```
```json
{ "_version": "1", "status": "error",
  "error": "The cards feature is not enabled on this environment. Retry without --use-card, or use an environment where cards are enabled.",
  "error_code": "cards_feature_disabled",
  "hint": "Retry without --use-card for a normal session, or switch to an environment where Cards is enabled.",
  "next_command": "" }
```
```json
{ "_version": "1", "status": "error",
  "error": "--use-card is not available in sandbox mode. Run 'kpass sandbox off' before creating a scoped-card session.",
  "error_code": "sandbox_mode_forbidden",
  "hint": "Run 'kpass sandbox off' before retrying --use-card, or create a normal cardless session.",
  "next_command": "" }
```

Recovery for each is in SKILL.md → Error Handling → "Scoped-card (`--use-card`) errors".

### Reuse Available Output (exit code 0)

```json
{
  "reuse_available": true,
  "reuse_candidates": [
    {
      "session_id": "session_xyz789",
      "expires_at": "2026-03-17T13:00:00Z",
      "max_amount_per_tx": "5.00",
      "remaining_budget": "40",
      "task_summary": "Query the weather forecast API at weather.example.com."
    }
  ],
  "_version": "1",
  "status": "success",
  "hint": "Detected 1 existing active session(s) that cover this request. Confirm the goal matches, then reuse — or pass --no-reuse to create a new one.",
  "next_command": "kpass agent:session use --session-id session_xyz789 --output json"
}
```

**What to do when you get `reuse_available`:**

1. **Goal match (your job).** For the best candidate (the one in `next_command`), check that its `task_summary` is the *same merchant and same kind of action* as the current goal. The CLI already guaranteed asset/per-tx/budget/TTL/scope fit; the only remaining risk is reusing a session approved for a *different purpose*. When in doubt, do NOT reuse.
2. **If it matches** → run the `next_command` (`agent:session use --session-id <id>`). `use` only returns `current_session_id`, so build the confirmation card from the **`reuse_candidate` fields** you already have — do NOT use the `🚀 Session Approved` card (it needs `delegation`/`usage`/`expires_at` that `use` does not return). No new approval is needed:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   🔄 Reusing Existing Session — Ready to Transact!

   🎫 Session:     {session_id}
   📝 Task:        {task_summary}
   💰 Per-tx:      Up to {max_amount_per_tx} {asset}
   💰 Remaining:   {remaining_budget} {asset}
   ⏰ Expires:     {expires_at}
   ✅ Status:      Active

   No new approval needed. I can execute payments on your behalf.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

   | Placeholder | Source |
   |---|---|
   | `{session_id}` | `reuse_candidate.session_id` |
   | `{task_summary}` | `reuse_candidate.task_summary` |
   | `{max_amount_per_tx}` | `reuse_candidate.max_amount_per_tx` |
   | `{remaining_budget}` | `reuse_candidate.remaining_budget` (shows `unlimited` when the session has no total cap) |
   | `{expires_at}` | `reuse_candidate.expires_at` |
   | `{asset}` | The settlement asset from the merchant's 402 (e.g. `USDC`); omit if unknown |

3. **If it does NOT match** (different merchant/action), or the user prefers a fresh session → re-run `agent:session create … --no-reuse` to force a new session, and briefly tell the user why.
4. **Multiple candidates** → `reuse_candidates` is ordered best-first (latest expiry, most budget). Pick the goal-matching one; if several match, ask the user which to use.

**The `--delegation` flag accepts an inline JSON string.** Wrap with single quotes on the outside for shell safety. See the **`form-session-delegation`** skill for the complete schema.

### Success Output (exit code 0)

```json
{
  "action": "approve_session",
  "request_id": "req_abc123",
  "approval_url": "https://passport.dev.gokite.ai/approve/req_abc123",
  "expires_at": "2026-03-17T12:05:00Z",
  "_version": "1",
  "status": "human_action_required",
  "hint": "A session request was created. Show the approval URL to the user: https://passport.dev.gokite.ai/approve/req_abc123",
  "next_command": "kpass agent:session status --request-id req_abc123 --output json"
}
```

**Key fields:**
- `status` is `"human_action_required"` — NOT an error. Exit code is 0.
- `request_id` — needed for polling the approval status.
- `approval_url` — MUST be shown to the user. This is the URL where they review and approve the session.
- `next_command` — contains the `agent:session status` command to check approval.

### What to Do After This Command

1. **Show the approval URL to the user** by displaying the mandatory card below.
2. **MANDATORY — Open the approval URL in the user's default browser automatically.**
   ```bash
   open "{approval_url}"          # macOS
   xdg-open "{approval_url}"      # Linux
   start "{approval_url}"         # Windows
   ```
   Detect the OS and use the appropriate command. This saves the user from having to copy-paste the URL. If `open` fails, the URL is still in the card — the user can click or copy it manually.
3. **Immediately start polling for approval** using `agent:session status --request-id <request_id> --wait --output json`. Never skip this step. Never tell the user "let me know when done" without polling first.

**CRITICAL:** Do NOT attempt to execute any transactions until the session is approved. The session is not active until the user approves it.

**MANDATORY — After this command succeeds, display this card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Approval Required

A spending session needs your approval:

🌐 {approval_url}

📝 Task:           {task_summary}
💰 Per-tx limit:    {max_amount_per_tx} {currency}
💰 Total budget:    {max_total_amount} {currency}
⏰ Valid for:       {ttl_human_readable}
📋 Request ID:      {request_id}

👆 Open the link, review, and approve with passkey.
⏳ I'll wait automatically...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{approval_url}` | From JSON response field `approval_url` |
| `{task_summary}` | From the delegation `task.summary` you constructed |
| `{max_amount_per_tx}` | From the delegation `payment_policy.max_amount_per_tx` |
| `{max_total_amount}` | From the delegation `payment_policy.max_total_amount` (if set; omit line if not) |
| `{currency}` | From the delegation `payment_policy.currency` (defaults to `USD`). |
| `{ttl_human_readable}` | Calculate from the delegation `payment_policy.ttl_seconds` (e.g., `3600` → "1 hour") |
| `{request_id}` | From JSON response field `request_id` |

---

## `agent:session status` — Check Session Approval Status

Checks the current status of a session approval request. Use with `--wait` to automatically poll until approved, rejected, expired, or timed out (5 minutes).

```
kpass agent:session status --request-id <request_id> --wait --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Request ID | `--request-id` | Yes | From `agent:session create` output: `request_id` field | String starting with `req_` |
| Wait for resolution | `--wait` | Yes (MANDATORY) | Always pass | Polls every 3 seconds for up to 300 seconds (5 minutes) |
| Poll interval | `--poll-interval` | No | Default `3` (seconds) | Positive integer. Do not change unless instructed. |
| Timeout | `--timeout` | No | Default `300` (seconds = 5 minutes) | Positive integer. Do not change unless instructed. |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Polling Strategy — MANDATORY

**CRITICAL: After creating a session and showing the approval card, you MUST immediately start polling. Never skip polling. Never tell the user "let you know" without polling first.**

Use the `--wait` flag with default settings:

```
kpass agent:session status --request-id <request_id> --wait --output json
```

This polls the backend every 3 seconds for up to 5 minutes automatically.

**If approved within 5 minutes:** The command returns success with the session details. Display the "Session Approved" card and proceed.

**If 5 minutes pass without approval (timeout):** The command returns with a pending/timeout status. STOP polling and tell the user:

```
Still waiting for your approval. Please let me know once you've approved the session, and I'll check the status.
```

Then wait for the user to respond. When they indicate approval (e.g., "done", "approved", "I approved it", "ok"), do a single status check:

```
kpass agent:session status --request-id <request_id> --output json
```

If still pending after the user says they approved, retry 2–3 more times with short pauses, then inform the user there may be an issue:

```
The session still shows as pending. There might be an issue with the approval. Please try visiting the approval link again: {approval_url}
```

**The flow is always:**
1. Create session → show approval card (MANDATORY)
2. Start polling immediately with `--wait` (MANDATORY — never skip)
3. If timeout → ask user and wait for their signal
4. On user signal → single check (without `--wait`)

### Approved Output (exit code 0)

```json
{
  "request_id": "req_abc123",
  "session_id": "session_xyz789",
  "session": {
    "id": "session_xyz789",
    "status": "active",
    "expires_at": "2026-03-17T13:00:00Z",
    "delegation": {
      "task": {
        "summary": "Query the weather API for forecasts."
      },
      "payment_policy": {
        "max_amount_per_tx": "5.00",
        "max_total_amount": "50.00"
      }
    },
    "usage": {
      "spent_total": "0.00",
      "reserved_total": "0.00"
    }
  },
  "current_session_id": "session_xyz789",
  "_version": "1",
  "status": "success",
  "hint": "Session approved and set as current. Expires at 2026-03-17T13:00:00Z.",
  "next_command": ""
}
```

**Important:** When a session is approved, the CLI automatically sets `current_session_id` in the agent config. You do NOT need to run `agent:session use` separately.

**MANDATORY — After this command returns an approved session, display this card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 Session Approved -- Ready to Transact!

🎫 Session:     {session_id}
📝 Task:        {task_summary}
💰 Per-tx:      Up to {max_amount_per_tx} {currency}
💰 Budget:      {max_total_amount} {currency}
📊 Spent:       {spent_total} / {max_total_amount}
⏰ Expires:     {expires_at}
✅ Status:      Active

All set. I can now execute payments on your behalf.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{session_id}` | From JSON response field `session_id` or `session.id` |
| `{task_summary}` | From JSON response field `session.delegation.task.summary` |
| `{max_amount_per_tx}` | From JSON response field `session.delegation.payment_policy.max_amount_per_tx` |
| `{max_total_amount}` | From JSON response field `session.delegation.payment_policy.max_total_amount` (if set; show "unlimited" if not) |
| `{currency}` | From JSON response field `session.delegation.payment_policy.currency` (defaults to `USD`). |
| `{spent_total}` | From JSON response field `session.usage.spent_total` |
| `{expires_at}` | From JSON response field `session.expires_at` |

### Rejected Output (exit code 3)

```json
{
  "_version": "1",
  "status": "error",
  "error": "Session request was rejected by the user.",
  "hint": "Create a new session request with 'kpass agent:session create'.",
  "next_command": ""
}
```

If rejected, inform the user: "The session request was not approved. Would you like me to create a new one, perhaps with different terms?"

### Expired Output (exit code 3)

```json
{
  "_version": "1",
  "status": "error",
  "error": "Session request expired before approval.",
  "hint": "Create a new session request with 'kpass agent:session create'.",
  "next_command": ""
}
```

If expired, inform the user and offer to create a new session request.

### Pending Output (exit code 0)

```json
{
  "request_id": "req_abc123",
  "expires_at": "2026-03-17T12:05:00Z",
  "_version": "1",
  "status": "pending",
  "hint": "Session request is still pending approval.",
  "next_command": "kpass agent:session status --request-id req_abc123 --output json"
}
```

The user has not yet approved, rejected, or let the request expire. If you used `--wait` and received this after timeout, follow the stop-and-ask flow described in the Polling Strategy.

---

## `agent:session use` — Set Current Session

Sets a specific session as the current active session in the agent config. Use this when you want to switch to a different session.

```
kpass agent:session use --session-id <session_id> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Session ID | `--session-id` | Yes | From `agent:session list` or `agent:session status` output | String starting with `session_` |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "current_session_id": "session_xyz789",
  "_version": "1",
  "status": "success",
  "hint": "Current session set to session_xyz789. The agent is ready to transact.",
  "next_command": ""
}
```

**Note:** You usually do NOT need to call this command after `agent:session status` returns `approved`, because that command auto-sets the current session. Use `agent:session use` only when switching between multiple sessions.
