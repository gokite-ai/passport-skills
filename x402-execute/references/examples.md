# x402 Execute — Worked Examples

End-to-end walkthroughs for the `x402-execute` skill. Per-command syntax, arguments, and JSON shapes live in `commands.md`; the mandatory display card lives in SKILL.md.

---

## Complete Worked Example: Access a Paid API

**Context:** The user asks "Query the weather API for a 5-day forecast." There is already an active session with an appropriate delegation.

**Step 1:** Verify there is an active session (optional but recommended).
```bash
kpass agent:session list --status active --output json
```
Output confirms an active session exists with delegation for the weather API, budget of 10.00 USDC with 3.00 spent.

**Step 2:** Execute the request.
```bash
kpass agent:session execute \
  --url https://weather.example.com/v1/forecast \
  --method POST \
  --body '{"city": "San Francisco", "days": 5}' \
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
kpass agent:session execute \
  --url https://data.example.com/v1/report/2026-q1 \
  --method GET \
  --headers '{"Accept": "application/json"}' \
  --output json
```

Note: No `--body` is needed for GET requests.

---

## Complete Worked Example: Using a Specific Session

If the user has multiple sessions and wants to use a specific one:

```bash
kpass agent:session execute \
  --url https://api.example.com/v1/resource \
  --session-id session_specific123 \
  --output json
```
