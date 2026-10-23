# x402 Execute — Worked Examples

End-to-end walkthroughs for the `x402-execute` skill. Per-command syntax, arguments, and JSON shapes live in `commands.md`; the mandatory display card lives in SKILL.md.

---

## Complete Worked Example: Pay From the Account Allowance

**Context:** The user asks "What's the weather in Austin right now?". `kite-discovery` picked a weather endpoint at USD 0.001. No session is current.

**Step 1:** Execute. No session step comes first: with no usable session current, the CLI binds the account allowance and pays from it, with no approval request.
```bash
kpass session execute \
  --url https://x402.example.com/weather/now?city=Austin \
  --method GET \
  --idempotency-key 5b0d7e3a-2f41-4c6e-9a8b-0e1d2c3b4a59 \
  --output json
```
Output (abridged):
```json
{
  "status": "success",
  "source": "allowance",
  "allowance_id": "allow_abc",
  "user_message": "Paid USD 0.001 from your account allowance. Left this week: USD 0.79 of USD 0.80. It resets Tue 27 Oct, 00:00 UTC.",
  "x402": { "status_code": 200, "parsed_response_body": { "temp_f": 71 } }
}
```
Answer with the weather and put `user_message` in the same reply.

**If the CLI says the allowance can't pay** (`allowance_unavailable`, `allowance_disabled`, `recurring_budget_exhausted`), put its `user_message` in your reply. A separate spending session goes through `request-session`, which shows the user the CLI's preview before any passkey request.

---

## Complete Worked Example: Access a Paid API With an Approved Session

**Context:** The user asks "Query the weather API for a 5-day forecast." There is already an active session the user approved separately, with an appropriate delegation.

**Step 1:** Verify there is an active session (optional but recommended).
```bash
kpass session list --status active --output json
```
Output confirms an active session exists with delegation for the weather API, budget of 10.00 USDC with 3.00 spent.

**Step 2:** Execute the request.
```bash
kpass session execute \
  --url https://weather.example.com/v1/forecast \
  --method POST \
  --body '{"city": "San Francisco", "days": 5}' \
  --idempotency-key 3f1c2a9e-8b7d-4c51-9e0a-6d2b1f4a7c83 \
  --output json
```
Output:
```json
{
  "session_id": "session_xyz789",
  "session_status": "active",
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
    "spent_total": "4.00",
    "reserved_total": "0.00"
  },
  "payment_requirement": {
    "asset": "USDC",
    "amount": "1.00"
  },
  "x402": {
    "status_code": 200,
    "response_body": "{\"forecast\": [{\"day\": 1, \"temp\": \"72F\", \"condition\": \"sunny\"}]}",
    "parsed_response_body": {
      "forecast": [{"day": 1, "temp": "72F", "condition": "sunny"}]
    },
    "wallet_address": "0xabc123...",
    "chain_id": 8453
  },
  "_version": "1",
  "status": "success",
  "hint": "x402 request to https://weather.example.com/v1/forecast completed with HTTP 200.",
  "next_command": ""
}
```

Display the mandatory card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ Payment Processed

🎯 Target:     https://weather.example.com/v1/forecast
📡 Method:     POST
📊 HTTP:       200
💰 Paid:       1.00 USDC
📊 Budget:     4.00 / 10.00 spent
🏦 Wallet:     0xabc123...

📦 Response received successfully.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 3:** Present the result to the user.
Extract `x402.parsed_response_body.forecast` and present it naturally.

---

## Complete Worked Example: GET Request with Custom Headers

```bash
kpass session execute \
  --url https://data.example.com/v1/report/2026-q1 \
  --method GET \
  --headers '{"Accept": "application/json"}' \
  --idempotency-key 9a4e6b21-0c3f-4d8a-b7e5-1f2c3d4e5a6b \
  --output json
```

Note: No `--body` is needed for GET requests.

---

## Complete Worked Example: Using a Specific Session

If the user has multiple sessions and wants to use a specific one:

```bash
kpass session execute \
  --url https://api.example.com/v1/resource \
  --session-id session_specific123 \
  --idempotency-key 7c2e9f10-4a3b-4d5c-8e6f-a1b2c3d4e5f6 \
  --output json
```
