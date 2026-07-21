# Delegation Schema — Reference

Full schema definition, construction rules, examples, heuristics, validation checklist, and anti-patterns for the `delegation` object passed to `kpass agent:session create --delegation '<JSON>'`. SKILL.md walks through the preflight → confirm → construct flow; this file is the structured schema reference the agent reads when actually building the JSON.

## Schema

The delegation draft passed to `agent:session create --delegation '<JSON>'` must follow this shape:

**IMPORTANT: Do NOT wrap the delegation in an outer `{"delegation": ...}` object. The CLI does that automatically. Pass only the inner object directly.**

```json
{
  "task": {
    "summary": "string"
  },
  "payment_policy": {
    "max_amount_per_tx": "string",
    "max_total_amount": "string",
    "ttl_seconds": 3600
  },
  "execution_constraints": {
    "x402": {
      "scope_mode": "scoped",
      "allowed_endpoints": [
        {
          "method": "POST",
          "host": "api.example.com",
          "path_prefix": "/v1/example"
        }
      ]
    }
  }
}
```

### Field Requirements

| Field | Required | Notes |
|-------|----------|-------|
| `delegation.task.summary` | Yes | Human-readable task description |
| `delegation.payment_policy.max_amount_per_tx` | Yes | Max amount for any single payment |
| `delegation.payment_policy.ttl_seconds` | Yes | Session lifetime in seconds |
| `delegation.payment_policy.currency` | Optional | Budget denomination for the caps; backend defaults to `USD`. There is no `assets` field — the settlement token is merchant-driven and the session locks to the first settled asset automatically. |
| `delegation.payment_policy.max_total_amount` | Optional | Total budget. Recommended when task has bounded spend. |
| `delegation.execution_constraints` | Optional | Only when endpoint scope is known and stable |
| `delegation.execution_constraints.x402.allowed_endpoints` | Required when `scope_mode == "scoped"` | Each entry needs `method`, `host`, `path_prefix` |
| `delegation.routing_enabled` | Optional | Top-level boolean **override**. Omitted → inherits the server's routing config (**enabled** on the Kite multichain deployment, so cross-chain bridge/swap is automatic when the merchant's chain differs from where funds sit — the agent need not set this). Set `false` to force same-chain-only. See Construction Rule 7. |
| `delegation.routing_cost_cap_usd_micros` | Optional | Top-level integer. Max routing cost (bridge + swap fees) to tolerate, in USD micros (1 USD = 1,000,000). Bounds the cost whenever a payment is routed. Omitted → backend's configured default cap (may be non-zero); `0` = no cap. |

Sessions are protocol-agnostic — the settlement protocol (x402, paygate, tempo, crossmint) is detected per request and is not part of the delegation. A single session can settle any supported protocol the merchant speaks.

---

## Construction Rules

### 1. `task.summary`

Write one short sentence describing what the user is authorizing.

**Good:**

```json
"task": {
  "summary": "Query the weather API for a 5-day forecast."
}
```

```json
"task": {
  "summary": "Access paid article on news.example.com."
}
```

**Bad:**

```json
"task": {
  "summary": "Handle stuff."
}
```

Rules:
- Keep it short -- one sentence, under 80 characters
- Make it reviewable by a user on the approval screen
- Derive from the user's exact words -- do not invent detail
- Do not over-model task semantics into structured fields

### 2. Settlement asset — there is no `assets` field

Do NOT include an `assets` list in `payment_policy` — the backend has no such field and silently ignores unknown policy keys. Sessions are settlement-token-agnostic by design: the merchant's 402 dictates which token settles, the backend converts it into the budget `currency` (default `USD`) to enforce the caps, and the session locks to the first settled asset automatically (single-asset lock). If the user wants to bound WHICH endpoints can be paid, use `execution_constraints.x402`; the spend itself is bounded by `max_amount_per_tx` / `max_total_amount`.

### 3. `payment_policy.max_amount_per_tx`

Required. The maximum amount allowed for any single payment.

**Do NOT ask the user for this value.** Derive it automatically:
1. Use the price from the 402 preflight response as the baseline
2. Add a small buffer (1.5x to 2x the price) to account for price fluctuations
3. If the 402 response shows the exact price (e.g., "0.1 pieUSD"), set `max_amount_per_tx` to that price or slightly above (e.g., "0.2")
4. Only if the 402 response cannot be parsed at all AND you have no other information, use a conservative default (e.g., "1") and note this in the confirmation card

```json
"max_amount_per_tx": "0.2"
```

### 4. `payment_policy.max_total_amount`

Optional but strongly recommended. The total amount the session may spend across all executions.

**Do NOT ask the user for this value.** Derive it automatically:
1. Estimate the number of requests the task will need (default: 10 if unclear)
2. Multiply: `per_tx_price * estimated_requests`
3. For a single-request task (e.g., "pay this merchant once"), set `max_total_amount` equal to `max_amount_per_tx`
4. For multi-request tasks (e.g., "query this API multiple times"), set a reasonable multiple (e.g., 10x the per-tx price)
5. When in doubt, prefer a smaller budget — the user can always create a new session

```json
"max_total_amount": "50.00"
```

### 5. `payment_policy.ttl_seconds`

Required. Becomes the session expiration after approval.

Default to `3600` (1 hour) unless the user specifies a different duration or the task requires longer.

```json
"ttl_seconds": 3600
```

Common values:

| Duration | Seconds |
|----------|---------|
| 30 minutes | 1800 |
| 1 hour | 3600 |
| 24 hours | 86400 |
| 7 days | 604800 |

### 6. `execution_constraints`

Include only when the agent can plan execution scope ahead of time and Passport can enforce it. For `x402`, the current supported constraint is scoped HTTP endpoints.

```json
"execution_constraints": {
  "x402": {
    "scope_mode": "scoped",
    "allowed_endpoints": [
      {
        "method": "POST",
        "host": "api.example.com",
        "path_prefix": "/v1/data"
      }
    ]
  }
}
```

If the agent cannot plan endpoints ahead of time, **omit `execution_constraints` entirely** instead of guessing.

When the preflight clearly identifies a single endpoint (you know the host, path, and method from the merchant URL), you should include scoped constraints.

**Async job/poll merchants — scope both endpoints up front.** Generation-style services (video, image, audio, batch jobs) commonly answer the paid call with a job id and a poll/status URL rather than the finished artifact (see the **`x402-execute`** skill's "Async Paid Goods" pattern). If the merchant's 402 payment-required schema documents the poll URL shape (many do, e.g. an `extensions`/`bazaar` example body containing a `pollUrl`), or the endpoint summary/tags otherwise signal an async job pattern, add a **second** `allowed_endpoints` entry for the poll/status path in the *same* delegation as the paid call — do not scope only the generate endpoint and wait for the poll to fail. Scoping only the generate call forces a `session_endpoint_forbidden` on the first poll, which then requires creating a second session and burning a second passkey approval from the user — pure friction, since poll calls are typically free (SIWX-signed, not billed) and cost nothing extra to pre-authorize.

```json
"execution_constraints": {
  "x402": {
    "scope_mode": "scoped",
    "allowed_endpoints": [
      {
        "method": "POST",
        "host": "api.example.com",
        "path_prefix": "/v1/generate/video"
      },
      {
        "method": "GET",
        "host": "api.example.com",
        "path_prefix": "/v1/jobs"
      }
    ]
  }
}
```

Infer the poll path prefix from the 402 schema's example (`pollUrl`, `statusUrl`, etc.) or other reliable endpoint metadata. If you cannot determine the poll path, omit `execution_constraints` entirely rather than guessing — a wrong guessed prefix still fails polling, and an overly broad one authorizes endpoints beyond what the task needs.

### 7. Cross-chain routing (optional, advanced)

These are **top-level** delegation fields (siblings of `task`/`payment_policy`), not nested under `payment_policy`.

A payment always settles on the merchant's advertised chain. If the user's funds are on a **different** chain, whether the backend auto-bridges/swaps to get there is governed by `routing_enabled`:

- `routing_enabled` (boolean) — **optional override, not a flag the agent normally needs to set.** When omitted, cross-chain routing **inherits the server's routing config**. On the Kite multichain deployment routing is **enabled**, so if the user's funds are on a different chain than the merchant requires, the backend **auto-bridges/swaps without the agent setting anything**. Set `false` to force this session to **same-chain-only** (reject rather than bridge); set `true` to force-enable. Same-chain payments never route either way.
- `routing_cost_cap_usd_micros` (integer) — the maximum routing cost (bridge + swap fees) to tolerate, in USD micros (1 USD = 1,000,000; e.g. `500000` = $0.50). Bounds the cost whenever a payment is routed. When omitted, the backend's **configured default cap** applies (which may be non-zero); `0` means no cap.

If routing is enabled but no route exists or the route would exceed the cap, the payment is rejected **pre-spend** with a routing `error_code` (`route_unavailable`, `route_uneconomical`, `routing_cost_exceeded`, `slippage_exceeded`, `unsupported_asset`) and no funds move. The route itself (any bridge/swap) is never disclosed in the response. See the **`x402-execute`** skill's "Cross-Chain Routing Errors" for the full list and recovery guidance.

Example (allow cross-chain settlement, cap routing cost at $0.50):

```json
{
  "task": { "summary": "Query the data API on base, paying from any chain." },
  "payment_policy": { "max_amount_per_tx": "1", "max_total_amount": "10", "ttl_seconds": 3600 },
  "routing_enabled": true,
  "routing_cost_cap_usd_micros": 500000
}
```

---

## Complete Example -- Full Delegation

Scenario: The user wants to query a paid API at `api.example.com/v1/flights/search`. The 402 response indicates USDC at $5 per request. The user wants to make up to 10 queries.

```json
{
  "task": {
    "summary": "Search for flights on api.example.com within the approved budget."
  },
  "payment_policy": {
    "max_amount_per_tx": "5",
    "max_total_amount": "50",
    "ttl_seconds": 3600
  },
  "execution_constraints": {
    "x402": {
      "scope_mode": "scoped",
      "allowed_endpoints": [
        {
          "method": "POST",
          "host": "api.example.com",
          "path_prefix": "/v1/flights/search"
        }
      ]
    }
  }
}
```

## Minimal Example -- Budget Only

Use this when the task is bounded by spend but the agent cannot reliably predict exact endpoints:

```json
{
  "task": {
    "summary": "Complete the approved paid task within the authorized budget."
  },
  "payment_policy": {
    "max_amount_per_tx": "20",
    "max_total_amount": "100",
    "ttl_seconds": 3600
  }
}
```

## Shopping Checkout Example -- Cart-Based Budget

Use this when the payment amount is already known from a shopping cart total. No 402 preflight needed.

Scenario: User is checking out a shopping cart with estimated total $32.82. Budget = $32.82 × 1.5 = $49.23, rounded up to $50.

```json
{
  "task": {
    "summary": "Shopping checkout — estimated total $32.82"
  },
  "payment_policy": {
    "max_amount_per_tx": "50",
    "max_total_amount": "50",
    "ttl_seconds": 3600
  }
}
```

Note: No `execution_constraints` needed for checkout — the backend handles the payment flow internally rather than via direct merchant calls. The same session is also usable for x402 paid-API calls if the agent later needs them; sessions are protocol-agnostic.

---

## Practical Heuristics

**The agent should autonomously decide all session parameters. Never ask the user for individual parameter values.** The user's only interaction is confirming the "Proposed Session Parameters" card.

There are two derivation paths depending on the context:

### Path A: From 402 Preflight Response (paid-API access)

Use this when the agent is accessing a paid API or merchant that returns a 402 Payment Required response.

- `max_amount_per_tx`: from the 402 response price, with 1.5-2x buffer. For a 0.1 pieUSD price → set "0.2"
- `max_total_amount`: per-tx price * estimated requests. Single request → same as per-tx. Multiple → 10x per-tx as default
- `ttl_seconds`: 3600 (1 hour) for quick tasks, 86400 (24 hours) for longer tasks. Use judgment based on context
- `execution_constraints`: include scoped endpoints only when the merchant URL is known. Omit if uncertain
- `task.summary`: derive from the user's original request in one sentence

### Path B: From a Known Amount (shopping checkout)

Use this when the payment amount is already known before session creation — for example, a shopping cart total. **Skip the 402 preflight entirely.**

- `max_amount_per_tx`: known amount × 1.5, rounded up to the nearest whole number. This buffer accounts for price fluctuations and transaction fees
- `max_total_amount`: same as `max_amount_per_tx` (single checkout transaction)
- `ttl_seconds`: `3600` (1 hour — enough time for user to approve and complete checkout)
- `execution_constraints`: omit (not applicable for shopping checkout)
- `task.summary`: describe the purchase with the estimated total (e.g., `"Shopping checkout — estimated total $32.82"`)

---

## Validation Checklist

Before passing the delegation to `agent:session create`, verify:

1. `task.summary` is non-empty and describes the user's intent
2. `max_amount_per_tx` is present and is a positive decimal string
3. `ttl_seconds` is present and is a positive integer
4. If `max_total_amount` is set, it is >= `max_amount_per_tx` and consistent with the expected task budget
5. If `execution_constraints.x402.scope_mode == "scoped"`, every allowed endpoint has:
   - `method` (e.g., `GET`, `POST`)
   - `host` (e.g., `api.example.com`)
   - `path_prefix` (e.g., `/v1/data`)

---

## What Not To Do

Do not:
- **Ask the user for tx limits, total budget, or TTL** -- derive these automatically from the 402 response and task context. The user confirms via the "Proposed Session Parameters" card, not by answering questions about individual parameters.
- **Wrap the delegation in `{"delegation": {...}}`** -- the CLI wraps it automatically. Pass only the inner object: `{"task":{...},"payment_policy":{...}}`. Double-wrapping causes exit code 2.
- Set a protocol field on the delegation -- sessions are protocol-agnostic; the settlement protocol is detected per request from preflight. The legacy `allowed_payment_approaches` field is silently ignored by the backend if you include it; don't.
- Put hidden reasoning or internal notes into the delegation
- Guess endpoint constraints when the plan is uncertain -- omit them instead
- Rely on `task.summary` for enforcement -- it is descriptive only
- Omit `max_amount_per_tx` -- it is always required
- Set `max_total_amount` lower than `max_amount_per_tx`
- Pass the delegation as a file path -- it must be an inline JSON string in the `--delegation` flag

---

## Mental Model

The agent is doing 4 things:

1. **Discovering** payment requirements via preflight (curl the merchant)
2. **Summarizing** the user-authorized task
3. **Compiling** the spend envelope from 402 data + user context
4. **Optionally declaring** enforceable execution scope

The delegation is not free-form text. It is a structured policy proposal for user approval and backend enforcement.
