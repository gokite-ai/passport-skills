# Request Session — Worked Examples

End-to-end walkthroughs for the `request-session` skill. Per-command syntax lives in `commands.md`; the canonical 8-step Full Session Creation Flow lives in `SKILL.md`. This file gives concrete examples of those steps applied to real scenarios.

## Preflight and Create a New Session

**Context:** The user says "I want to query the weather API at https://weather.example.com/v1/forecast"

**Step 1:** Register the agent.
```bash
kpass agent:register --type <agent-type> --output json
# Replace <agent-type> with your agent's identity: claude, cursor, codex, cline, etc.
```
Output: Agent already registered. Display "Agent Already Registered" card.

**Step 2:** Merchant URL is already known: `https://weather.example.com/v1/forecast`

(No manual session-list pre-check — `create` in Step 6 auto-detects any reusable session. Here we assume none covers the request, so it creates a new one.)

**Step 3:** Preflight the merchant URL.
```bash
curl -s -w "\n%{http_code}" -X POST https://weather.example.com/v1/forecast -H "Content-Type: application/json"
```
Output:
```
{"error":"payment required","payment":{"accepts":[{"asset":"USDC","amount":"1.00","network":"eip155:8453"}]},"resource":"/v1/forecast"}
402
```
Parsed: the service requires **1.00 USDC** per request for `/v1/forecast`. (`network` is CAIP-2 — `eip155:8453` is base; an EVM chain is `eip155:<chainId>`, a Solana endpoint advertises `solana:<…>`. You only need `asset` and `amount` to build the delegation; the backend settles on the merchant's chain — base, tempo, or solana — automatically.)

**Step 4:** Construct the delegation. The user wants to query forecasts. Set per-tx to match the price, total budget for a few queries, scope to the known endpoint.

Pass this inner object directly to `--delegation`. The CLI wraps it under `{"delegation": …}` for transport — do NOT wrap it yourself.
```json
{
  "task": {
    "summary": "Query the weather forecast API at weather.example.com."
  },
  "payment_policy": {
    "max_amount_per_tx": "1",
    "max_total_amount": "10",
    "ttl_seconds": 3600
  },
  "execution_constraints": {
    "x402": {
      "scope_mode": "scoped",
      "allowed_endpoints": [
        {
          "method": "POST",
          "host": "weather.example.com",
          "path_prefix": "/v1/forecast"
        }
      ]
    }
  }
}
```

**Step 5:** Create the session.
```bash
kpass agent:session create --delegation '{"task":{"summary":"Query the weather forecast API at weather.example.com."},"payment_policy":{"max_amount_per_tx":"1","max_total_amount":"10","ttl_seconds":3600},"execution_constraints":{"x402":{"scope_mode":"scoped","allowed_endpoints":[{"method":"POST","host":"weather.example.com","path_prefix":"/v1/forecast"}]}}}' --output json
```
Output:
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

Display the mandatory approval card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Approval Required

A spending session needs your approval:

🌐 https://passport.dev.gokite.ai/approve/req_abc123

📝 Task:           Query the weather forecast API at weather.example.com.
💰 Per-tx limit:    1 USDC
💰 Total budget:    10 USDC
⏰ Valid for:       1 hour
📋 Request ID:      req_abc123

👆 Open the link, review, and approve with passkey.
⏳ I'll wait automatically...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 6:** Poll for approval.
```bash
kpass agent:session status --request-id req_abc123 --wait --output json
```
Output (user approves):
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
        "summary": "Query the weather forecast API at weather.example.com."
      },
      "payment_policy": {
        "max_amount_per_tx": "1.00",
        "max_total_amount": "10.00"
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

Display the mandatory approved card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 Session Approved -- Ready to Transact!

🎫 Session:     session_xyz789
📝 Task:        Query the weather forecast API at weather.example.com.
💰 Per-tx:      Up to 1.00 USDC
💰 Budget:      10.00 USDC
📊 Spent:       0.00 / 10.00
⏰ Expires:     2026-03-17T13:00:00Z
✅ Status:      Active

All set. I can now execute payments on your behalf.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ready to execute transactions with the `x402-execute` skill.

---

## Reuse an Existing Session

You do not pre-check with `list`. Just construct the delegation and run `create` as usual — it detects a covering active session and returns `reuse_available` instead of creating a new request.

**Step 1:** Create as normal (current goal: "query weather forecast at weather.example.com", expected spend ~2 USDC). Build the **same scoped delegation** you would for a fresh session — keep `execution_constraints.x402.allowed_endpoints`. Do NOT drop scoping just because you expect a reusable session: an unscoped request is broader than a scoped session, so reuse would be missed, and if none is found you would create an over-broad session.
```bash
kpass agent:session create --delegation '{"task":{"summary":"Query the weather forecast API at weather.example.com."},"payment_policy":{"max_amount_per_tx":"1","max_total_amount":"5","ttl_seconds":1800},"execution_constraints":{"x402":{"scope_mode":"scoped","allowed_endpoints":[{"method":"POST","host":"weather.example.com","path_prefix":"/v1/forecast"}]}}}' --output json
```
Output (an existing session already covers this request):
```json
{
  "reuse_available": true,
  "reuse_candidates": [
    {
      "session_id": "session_xyz789",
      "expires_at": "2026-03-17T13:00:00Z",
      "max_amount_per_tx": "1.00",
      "remaining_budget": "7",
      "task_summary": "Query the weather forecast API at weather.example.com."
    }
  ],
  "_version": "1",
  "status": "success",
  "hint": "Detected 1 existing active session(s) that cover this request. Confirm the goal matches, then reuse — or pass --no-reuse to create a new one.",
  "next_command": "kpass agent:session use --session-id session_xyz789 --output json"
}
```

The CLI has already confirmed asset/per-tx/budget/TTL/scope fit. Your only check is the **goal match**: `task_summary` is the same merchant ("weather.example.com") and the same kind of action (forecast queries) → safe to reuse. (If it named a different merchant or action, you would re-run with `--no-reuse` instead.)

**Step 2:** Run the returned `next_command` to reuse it.
```bash
kpass agent:session use --session-id session_xyz789 --output json
```

`agent:session use` only returns `current_session_id`, so build the confirmation card from the **`reuse_candidate` fields** you already have (not from the `use` output, and do not use the `🚀 Session Approved` card, which needs `delegation`/`usage`/`expires_at` that `use` does not return):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Reusing Existing Session — Ready to Transact!

🎫 Session:     session_xyz789
📝 Task:        Query the weather forecast API at weather.example.com.
💰 Per-tx:      Up to 1.00 USDC
💰 Remaining:   7 USDC
⏰ Expires:     2026-03-17T13:00:00Z
✅ Status:      Active

No new approval needed. I can execute payments on your behalf.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ready to execute transactions — no new approval needed.

## Create a Scoped-Card Session (`--use-card`)

**Context:** The user says "Buy this item from a store that only takes a card — budget $40." The merchant does not support x402, so the agent needs a session-bound virtual card.

**Step 1:** Register the agent (same as any session).
```bash
kpass agent:register --type <agent-type> --output json
```

**Step 2:** No 402 preflight — the merchant is card-only. The budget comes from the user ($40 total; size per-tx to the expected charge).

**Step 3:** Confirm parameters, marking it as a card session.
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Proposed Session Parameters

🏪 Merchant:         card-only-store.example
📝 Task:             Buy one item from card-only-store.example
💰 Per-tx limit:     40 USDC
💰 Total budget:     40 USDC
⏰ Session duration: 1 hour
🔒 Payment method:   Scoped virtual card (limit 40 USDC, multi-use until limit reached or expiry)

Shall I proceed with creating this session?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 4:** On confirmation, create with `--use-card` and the individual flags (no `--delegation`; `--max-total-amount` is required).
```bash
kpass agent:session create --use-card \
  --task-summary "Buy one item from card-only-store.example" \
  --max-amount-per-tx 40 \
  --max-total-amount 40 \
  --ttl 1h \
  --output json
```

The CLI pre-flights card eligibility and refuses early if it is not met:

- **Not card-verified** → exit 2, `error: "This account can't use a scoped card yet (card verification status: pending). Complete card verification in the Passport dashboard (Cards) …"`. Tell the user to finish card verification in the dashboard (Cards); do not retry until done.
- **Cards disabled on this backend** → exit 2, `error: "The cards feature is not enabled on this environment. Retry without --use-card …"`. Offer a normal session if the merchant supports x402.
- **Sandbox mode** → exit 2, `error: "--use-card is not available in sandbox mode. Run 'kpass sandbox off' …"`.

**Step 5:** On success the output is the usual `human_action_required` envelope. Show the Approval Required card, open the URL, and poll with `agent:session status --request-id <id> --wait --output json` — identical to a normal session. The scoped card is issued when the user approves. Reuse is skipped automatically, so a fresh session (and card) is always created.
