# x402 Execute — Command Reference

Full command reference for the `x402-execute` skill. SKILL.md carries the trigger logic, prerequisites, defaults, the request-body construction rules, the async job/poll flow, and the mandatory Payment Processed display card; this file has the command-level detail (flags, validation, full JSON output/error shapes, and the exhaustive error-scenario list). Worked end-to-end examples live in `examples.md`.

---

## `agent:session execute` -- Execute x402 Request

Sends an HTTP request through the Passport backend, which handles payment negotiation with the target service.

**Timeout:** This command has a **5-minute timeout**. Payment operations involve on-chain transaction broadcasting and receipt polling, which can take 1-3 minutes. Payment now settles on **base, tempo, or solana** depending on the merchant's advertised network; a **cross-chain routed settlement (or a Solana settlement) can take ~90 seconds, and the whole flow up to ~2 minutes**. The CLI shows a progress spinner with elapsed time in non-JSON mode. Do NOT treat a slow response as a failure — wait for the full timeout before giving up.

```
kpass agent:session execute --url <URL> --output json
```

Full form with all optional flags:

```
kpass agent:session execute \
  --url <URL> \
  --method <METHOD> \
  --headers '<JSON_OBJECT>' \
  --body '<JSON_VALUE>' \
  --session-id <session_id> \
  --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Target URL | `--url` | Yes | The URL the user wants to access, or the URL you need to call | Must be a valid URL (https preferred) |
| HTTP method | `--method` | No | **Always set explicitly** — from discovery metadata, or inferred per the **Defaults** rule above. (If omitted, the CLI falls back to `POST`, which is wrong for GET-only endpoints.) | One of: `GET`, `POST`, `PUT`, `PATCH`, `DELETE` |
| Request headers | `--headers` | No | Only if target API requires custom headers | Must be a valid JSON object string (key-value pairs) |
| Request body | `--body` | No | Only if the request needs a payload | Must be a valid JSON string |
| Session ID | `--session-id` | No | Auto-read from agent config | Only pass to override the current session |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Important Notes on `--headers` and `--body`

- Both flags accept **JSON strings**. You must pass valid JSON.
- `--headers` must be a JSON **object** (not array, not string). Example: `'{"X-Custom": "value"}'`
- `--body` can be any valid JSON value (object, array, string, number, etc.).
- Quote the JSON with single quotes on the outside to avoid shell escaping issues.

**Correct:**
```bash
--headers '{"Content-Type": "application/json", "X-Api-Key": "abc123"}'
--body '{"query": "What is Kite?", "max_tokens": 100}'
```

**Incorrect:**
```bash
--headers {"Content-Type": "application/json"}    # Missing quotes -- shell will break this
--headers "Content-Type: application/json"         # Not JSON -- this is a raw header string
```

### Success Output (exit code 0)

```json
{
  "session_id": "session_xyz789",
  "session_status": "active",
  "delegation": {
    "task": {
      "summary": "Query the weather forecast API at weather.example.com."
    },
    "payment_policy": {
      "max_amount_per_tx": "5.00",
      "max_total_amount": "50.00"
    }
  },
  "usage": {
    "spent_total": "6.00",
    "reserved_total": "0.00"
  },
  "payment_requirement": {
    "asset": "USDC",
    "amount": "1.00"
  },
  "x402": {
    "status_code": 200,
    "response_body": "{\"forecast\": \"sunny, 72F\"}",
    "parsed_response_body": {
      "forecast": "sunny, 72F"
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

**Key fields:**
- `x402.status_code` -- The HTTP status code returned by the **target service** (not the Passport backend). This tells you whether the target request succeeded.
- `x402.response_body` -- The raw response body from the target service, as a string.
- `x402.parsed_response_body` -- If the response body is valid JSON, the CLI parses it for you. Use this field for structured data.
- `x402.wallet_address` -- The wallet address that settled the payment (informational).
- `x402.chain_id` -- The numeric chain ID of the chain the payment settled on (informational). Settlement happens on **base, tempo, or solana** per the merchant's advertised network; for Solana settlements the field is **omitted** (Solana has no EVM chain ID — treat an absent `chain_id` as Solana, same as the `activity` skill). Intermediate cross-chain routing (any bridge or swap) is **NOT** disclosed in the response — do not promise the user route details.
- `delegation` -- The session's delegation policy (confirms task, payment policy).
- `usage` -- Current usage tracking: `spent_total` (total spent so far) and `reserved_total` (amount currently reserved for in-flight payments).
- `payment_requirement` -- The payment that was made for this request: `asset` and `amount`.
- `session_status` -- The session's current status after this transaction.

### How to Present the Response to the User

1. Check `x402.status_code`. If it is a 2xx code, the request succeeded.
2. Use `x402.parsed_response_body` (if available) or `x402.response_body` to extract the data.
3. Present the relevant data to the user in a clear, readable format. Do NOT dump raw JSON unless the user asks.

See SKILL.md for the mandatory display card to show after this step.

---

## Error Handling — Full Reference

**Error envelope fields:** Error responses include `error` (raw backend message), `error_code` (machine-readable classification — prefer this for programmatic matching), and `hint` (recovery guidance). The `error` field is a passthrough of the backend's original message.

### Specific Error Scenarios

**"Missing --url flag" (exit code 2):**
- You forgot the `--url` flag. Always pass the target URL.

**"--headers must be a valid JSON object string" (exit code 2):**
- The `--headers` value is not valid JSON. Check for proper quoting and JSON syntax.

**"--headers must be a JSON object with key-value pairs (not an array or null)" (exit code 2):**
- You passed a JSON array or primitive instead of an object. Headers must be `{"key": "value"}` format.

**"--body must be a valid JSON string" (exit code 2):**
- The `--body` value is not valid JSON. Check for proper quoting and JSON syntax.

**"No active session specified" (exit code 2):**
- No `--session-id` was passed and no `current_session_id` is set in the agent config.
- Use the **`request-session`** skill to create and approve a session first.

**"Agent not registered" (exit code 3):**
- Use the **`request-session`** skill: run `agent:register --type <agent-type> --output json`. (The `--type` is your own agent identity — `claude`, `cursor`, `codex`, `cline`, etc. — never user-provided.)

**"Agent is registered to a different user" (exit code 3):**
- The user switched accounts. Re-register with `agent:register --type <agent-type> --output json`.

**"Asset not allowed by delegation" (exit code 6, `error_code: "session_asset_forbidden"`):**
- The payment required by the target service uses an asset not listed in the session's `delegation.payment_policy.assets`. Create a new session with the correct asset in the delegation.

**"Endpoint not in allowed scope" (exit code 6, `error_code: "session_endpoint_forbidden"`):**
- The target URL (method + host + path) does not match any entry in the session's `delegation.execution_constraints.x402.allowed_endpoints`. Either create a new session with broader scope, or create one without execution constraints.
- **Hitting this on a job/poll URL right after a successful paid call** means the delegation only scoped the generate endpoint. Prevent it up front: when building the delegation for a generation-style merchant (Async Paid Goods pattern above), scope the poll/status path alongside the generate path in the *same* session — see form-session-delegation's "Async job/poll merchants" rule; this avoids the extra passkey approval entirely. If the error has already happened, the fix above doesn't apply retroactively — create a new session with corrected scope as usual, then resume by polling the **existing** job (do not repeat the paid generation call — see Async Paid Goods above).

**"Amount exceeds per-transaction limit" (exit code 6, `error_code: "session_rule_exceeded"`):**
- The payment amount for this request exceeds the session's `delegation.payment_policy.max_amount_per_tx`. Create a new session with a higher per-tx limit.

**"Total spend would exceed budget" (exit code 6, `error_code: "session_total_exceeded"`):**
- The session's `delegation.payment_policy.max_total_amount` would be exceeded by this payment. Check `usage.spent_total` to see how much has been spent. Create a new session with a larger budget if needed.

**"Insufficient balance" (exit code 6, `error_code: "insufficient_balance"`):**
- The user's wallet does not have enough funds for this payment. Use the **`wallet-send`** skill to check balance and fund the wallet before retrying.

**"Payment cap exceeded" (exit code 6, `error_code: "payment_cap_exceeded"`):**
- The payment amount exceeds the system's per-transaction cap. Try a request that costs less, or contact support for higher limits.

**"Payment redirect not allowed" (exit code 6, `error_code: "payment_redirect_not_allowed"`):**
- The target URL redirected during payment preflight. Redirects are not allowed. Verify the URL is the final endpoint, not a redirect.

**"Merchant not allowed" (exit code 6, `error_code: "merchant_not_allowed"`):**
- The merchant URL is not allowlisted for payments. Verify the URL is correct and check the service discovery list using the **`kite-discovery`** skill.

**"No payment requirement" (exit code 2, `error_code: "no_payment_requirement"`):**
- The merchant returned no x402 challenge for this request — so there was nothing to pay. The most common cause is the **wrong HTTP method**, e.g. POSTing to a GET-only endpoint (the merchant 404s/405s instead of issuing a 402). Look up the endpoint's method in `kite-discovery` (`services get` → `featured_endpoints[].method`) and retry with the correct `--method` (try `GET` for read/search/lookup endpoints). Only conclude the merchant is unsupported after retrying with the correct method.
- Historical note: backends older than 2026-07 also returned this code when a merchant answered with a **SIWX identity challenge** (402 with empty `accepts[]` + `sign-in-with-x` extension — common on already-paid job/status URLs). Current backends answer SIWX automatically (see **Async Paid Goods** above); if you hit this code on a poll URL, retry once — a persistent failure means the backend predates SIWX support.

**"SIWX challenge invalid" (exit code 2, `error_code: "siwx_challenge_invalid"`):**
- The merchant asked for a wallet-identity signature (SIWX) but its challenge failed safety checks — cross-domain (challenge domain/uri does not match the merchant host), expired, or malformed. Passport refuses to sign such challenges to protect the wallet. **Retry once** (challenges are short-lived and a fresh one is minted per request); if it persists, the merchant's SIWX implementation is broken — report via the **`report-feedback`** skill.

**"SIWX chain unsupported" (exit code 2, `error_code: "siwx_chain_unsupported"`):**
- The merchant's identity challenge only accepts signatures on chains Passport cannot sign raw messages for (e.g. Solana ed25519). Not retryable. Report via **`report-feedback`** so the gap gets prioritized.

**"Merchant unsupported" (exit code 2, `error_code: "merchant_unsupported"`):**
- The merchant does not support a settlement protocol Passport can handle (e.g., does not expose the expected x402 challenge). Try a different merchant.

**"Provider unavailable" (exit code 1, `error_code: "provider_unavailable"`):**
- A routing/quote provider was temporarily unavailable. No funds moved. **Safe to retry** after a brief pause.

**Service temporarily unavailable (exit code 1, `error_code: "provider_unavailable"` or `"service is temporarily unavailable"`):**
- A transient backend/upstream-provider state (HTTP 503). No funds moved. Wait a few minutes and retry — do not treat it as a permanent failure or change the request.

### Cross-Chain Routing Errors

When the payment must move across chains, the backend may run a route (bridge and/or swap) before paying the merchant. **The route is invisible** — routed payments return the same envelope as a direct pay, and the response never discloses bridge/swap details. Do not promise the user route details. If a route fails, the backend returns one of these `error_code`s. These codes are **passed through verbatim** by the CLI (they are not specially mapped), and the exit code is derived from the HTTP status.

| `error_code` | HTTP | Exit | Funds | Retry guidance |
|---|---|---|---|---|
| `route_unavailable` | 422 | 2 | none moved | No. No feasible route. Fund the destination chain directly, or use a supported chain/asset. |
| `route_uneconomical` | 422 | 2 | none moved | No. Bridge cost exceeds the limit for this amount. Fund the destination chain directly, or increase the amount. |
| `routing_cost_exceeded` | 422 | 2 | none moved | No. Routing cost exceeds the session's `routing_cost_cap_usd_micros`. Create a new session with a higher cap, or fund the destination chain. |
| `slippage_exceeded` | 422 | 2 | none moved | No. Quoted swap slippage exceeds the cap. |
| `unsupported_asset` | 422 | 2 | none moved | No. Unsupported chain/asset for routing. Use USDC (base/tempo/solana) or PYUSD (solana). |
| `provider_unavailable` | 503 | 1 | none moved | **Yes — safe to retry** after a brief pause. |
| `bridge_failed` | 502 | 1 | **ambiguous** | Do NOT blindly retry. Check the **`activity`** skill first to see whether funds moved. |
| `swap_failed` | 502 | 1 | **ambiguous** | Do NOT blindly retry. Check the **`activity`** skill first. |
| `swap_slippage_realized` | 502 | 1 | swapped | No. The swap executed below the minimum out. |
| `payment_settled_unfulfilled` | 502 | 1 | **charged, unfulfilled** | Do NOT retry the payment. But first check the merchant body (the error's `merchant_body`, also in the **`activity`** failure detail): if it contains a **job id / poll URL**, the good may be **async** — poll it per **Async Paid Goods** above (no second charge). A job reference is NOT itself proof of fulfillment: only a successful terminal status with an artifact clears the condition; a failed, missing, or timed-out job still needs human follow-up. Otherwise the body states the merchant's rejection reason — compare it against the endpoint's catalog `pitfalls`: a matching tag means a known failure mode, not a transient. |

(`insufficient_balance` is handled separately → exit 6, in the table above.)

**Target service returns non-2xx status (in `x402.status_code`):**
- This is NOT a CLI error. The CLI still exits with code 0.
- Check `x402.status_code` and `x402.parsed_response_body` (or `x402.response_body`) for the error from the target service.
- Before retrying with a modified request, compare the failure against the endpoint's catalog `pitfalls` (see **Constructing the Request Body**) — a matching tag is a known failure mode, and re-paying for the same request shape will fail the same way.
- Present the error to the user and determine next steps based on the target API's documentation.

---

## Input Validation Checklist

Before running the command, verify:

1. **URL:** Must be a valid HTTP/HTTPS URL. Do not pass bare domains without protocol.
2. **Method:** Always set explicitly — from discovery metadata, or inferred per the **Defaults** rule (do not rely on the CLI's implicit `POST` fallback; it is wrong for GET-only endpoints).
3. **Headers JSON:** If specified, must be a valid JSON object. Wrap with single quotes for shell safety.
4. **Body JSON:** If specified, must be valid JSON. Wrap with single quotes for shell safety. Built from the endpoint's `example_request` when the catalog carries one (see **Constructing the Request Body**).
5. **Session exists:** Ensure an active session is set (via `agent:session status --wait` or `agent:session use`).
6. **Budget remaining:** Before executing, consider checking `usage.spent_total` against `delegation.payment_policy.max_total_amount` to ensure there is sufficient budget remaining for the request.
