---
name: data-agent
description: >-
  Coordinate a Kite A2A data deal — a bilateral, escrow-backed purchase of a
  synthetic health dataset between a buyer agent and a seller agent — via
  the `kpass data-agent` CLI commands. Invoke when the user (the deal's
  buyer's controller) wants to buy a health dataset from a seller agent,
  e.g. "CA health data, diabetes/BP rates, buy from this seller's Agent Card
  URL, budget up to $1,000". Handles gathering the mandate (dataset
  criteria, target/max spend, negotiation round budget, seller Agent Card
  URL) and running `kpass data-agent create-deal`, which synchronously
  negotiates the deal to a terminal accepted/walked outcome — there is no
  separate mandate-approval step or browser passkey popup, and no async
  sampling/negotiation phase to poll: create-deal itself IS the
  negotiation. After that, handles live status checks, listing and
  deciding any delivery-verification escalation (the only escalation
  branch in this design — never a price-negotiation escalation, since an
  over-ceiling ask is always a deterministic walk-away with no human
  involved), and exporting the deal's receipt trail. Do NOT use for a
  single-buyer, non-negotiated paid API call (use request-session then
  x402-execute), a direct wallet transfer (use wallet-send), or a purchase
  split across multiple participants (use group-order).
user-invocable: true
---

# Data Agent

Coordinate a Kite A2A data deal on behalf of its buyer (the "buyer's controller") using the `kpass
data-agent` CLI commands. A data deal is a bilateral, escrow-backed purchase of a synthetic health
dataset between a Buyer Agent and a standing Seller Agent. Unlike phase-1's design, there is no MCP
server front door and no separate mandate-approval browser step: `kpass data-agent create-deal`
itself submits the mandate AND synchronously drives the negotiation to a terminal outcome before it
returns.

## When to Use This Skill

- The user describes a health dataset they want to buy from a seller agent, e.g. "CA health data,
  diabetes/BP/obesity/uninsured rates, buy from `https://seller.example/.well-known/agent-card.json`,
  budget up to $1,000".
- The user asks for the status of a data deal they already created ("how's my CA health data deal
  going?", "what happened with deal `deal_abc123`?").
- The user's controller wants to review and decide a delivery-verification escalation (a delivery
  whose automatic calibration check came back ambiguous) — accept the delivered dataset or reject
  it and trigger a refund.
- The user wants the full receipt/audit trail for a settled or refunded deal.

## When NOT to Use This Skill

- A single-buyer, non-negotiated paid API call with no bilateral negotiation or escrow — use
  **`request-session`** then **`x402-execute`**.
- A direct wallet-to-wallet transfer — use **`wallet-send`**.
- A purchase split across multiple participants with per-participant spending caps — use
  **`group-order`**.

## Prerequisites

The user must be logged in to `kpass` (`kpass login`/`kpass signup`) — every `data-agent` command
authenticates with the same passport session JWT every other `kpass` command uses (`.kite-passport/
config.json`'s `jwt` field). There is no separate `data-agent login` step and no separate ops token;
if a command fails with an auth error (exit code 3, `"Not logged in"`), have the user complete the
**`authenticate-user`** skill's login flow.

## There Is No Mandate-Approval Popup — `create-deal` IS the Negotiation

This is the single most important difference from phase-1's design, and the reason this skill's
flow has only one real step where the buyer's controller commits to anything: **running
`kpass data-agent create-deal` submits the mandate to passport, which persists it and synchronously
negotiates with the seller agent to a terminal `ACCEPTED` or `WALKED` outcome before the command
returns.** There is no `mandate_approval_url`, no browser passkey ceremony, and no async
sampling/negotiation phase to poll immediately afterward — the command's own exit and printed
output already tell you the outcome.

Because of this:

1. **Confirm the mandate's numbers with the user before running `create-deal`.** Once run, the
   command has already negotiated — there is no cancel/undo step afterward the way phase-1's
   pre-approval draft had. Read back the target spend, max spend, round budget, seller Agent Card
   URL, and dataset columns before executing, and only proceed on an explicit go-ahead.
2. **Do not run `create-deal` more than once per deal.** A second run creates a second, separate
   deal record. If a previous run's outcome is unclear (e.g. the command errored or timed out), do
   NOT assume it failed and retry blindly — a network timeout doesn't mean passport didn't already
   persist the deal and call the buyer adapter. Ask the user whether they saw a `dealId` from a
   prior attempt, or check `kpass data-agent status <dealId>` if one is known.
3. **The buyer's negotiation policy has no escalation branch of its own.** If the seller's ask
   exceeds the buyer's `--max-amount`, the deal ends with `status: WALKED` — this is a deterministic
   outcome the buyer agent decides on its own, never a human decision. There is nothing for the
   buyer's controller to approve or override at negotiation time.
4. **The only human decision point in this whole flow is a delivery-verification escalation** — see
   "Step 5" below. It has nothing to do with price.

## Money Amounts — Always Base-Unit Integer Strings

`--target-amount` and `--max-amount` are minor-unit integer strings, never a float. To convert a
plain-dollar figure the user gives you (e.g. "$700" in USDC, 6 decimals) to what the CLI expects:

```
amount = round(dollars * 10^decimals)   # "700" dollars, 6 decimals -> "700000000"
```

Never pass `"700"` when the asset has 6 decimals — that is off by a factor of 1,000,000 and would
authorize the wrong budget entirely. If unsure of the asset/decimals convention the user's org uses,
ask them or default to USDC's 6 decimals, the convention this skill assumes throughout.

## Command Flow

### Step 1 — Gather the mandate, then run `create-deal`

The user describes the data need in natural language. Before running anything, extract and confirm
back to the user:

- `--project-id` — a short caller-chosen identifier (e.g. `prj_health_research`).
- `--purpose` — a short human-readable description (e.g. `"CA county health indicators for
  care-gap modeling"`).
- `--seller-agent-card-url` — the seller agent's A2A Agent Card URL. This must be a concrete URL the
  user provides or has previously used — never guess or fabricate one.
- `--columns` — comma-separated requested dataset columns (e.g. `DIABETES,BPHIGH,OBESITY,ACCESS2`).
- `--filters-json` — optional per-column filters as a JSON object (e.g.
  `{"DIABETES":{"min":9}}`), if the user wants to filter to rows above/below a rate.
- `--target-amount` / `--max-amount` — the price the user wants to land near, and the hard cap the
  deal must never exceed, both converted to minor-unit integer strings per the rule above.
- `--round-budget` — how many negotiation rounds before the deal closes without a match; defaults to
  `5` if the user has no preference.

Run:
```
kpass data-agent create-deal \
  --project-id prj_health_research \
  --purpose "CA county health indicators for care-gap modeling" \
  --seller-agent-card-url https://seller.example/.well-known/agent-card.json \
  --columns DIABETES,BPHIGH,OBESITY,ACCESS2 \
  --filters-json '{"DIABETES":{"min":9}}' \
  --target-amount 700000000 \
  --max-amount 1000000000 \
  --round-budget 5 \
  --output json
```

The response — `{dealId, status, agreedAmount, reasonCode}` — already carries the terminal outcome.
`status` is either `ACCEPTED` (with `agreedAmount` set) or `WALKED` (no `agreedAmount` — the deal
ended without a match). Tell the user the outcome plainly; if `WALKED`, tell them the reason code and
ask whether they want to retry with a higher `--max-amount` (a brand-new deal, not a retry of the
same one).

### Step 2 — Live status: `kpass data-agent status <dealId>` (read-only, repeatable)

Run this any time the user asks for an update, or to confirm a deal's post-`ACCEPTED` progress
(funding, delivery, verification, settlement). Output covers `status`, `rounds`, `transcript`, and
`flags`. `status` moves through `ACCEPTED` → `DELIVERED` → `VERIFIED` → `SETTLED` on the happy path,
or to `VERIFICATION_ESCALATION_NEEDED` if the delivery's automatic calibration check came back
ambiguous (see Step 5), or `REFUNDED` if a rejected delivery triggers a refund.

### Step 3 — List escalations: `kpass data-agent list-escalations`

Run this when the user asks "do I have anything waiting on me?" or you want to check for pending
delivery-verification decisions before doing anything else. Each entry includes `dealId`, `status`,
`flags`, and — critically — `approvalId`, which Step 5 needs. If the list is empty, tell the user
there's nothing awaiting their decision.

### Step 4 — (Nothing to do at negotiation time)

There is no buyer-side negotiation-escalation step. If a deal's status is `WALKED`, the negotiation
is over and there is no pending decision — see Step 1's guidance on what to tell the user.

### Step 5 — Resolve a delivery-verification escalation: `kpass data-agent escalation-decision`

Only call this after the user has reviewed the delivery (via `status`, which will show
`VERIFICATION_ESCALATION_NEEDED`) and given an explicit, distinct accept/reject decision — never as
an inferred side effect of a status check or casual chat. Required: the `dealId`, exactly one of
`--accept` or `--reject`, and `--approval-id` (from Step 3's `list-escalations` output). `--reject`
additionally requires `--yes` since it triggers a refund and cannot be undone. `--reason` is
optional but recommended, especially on reject, so the decision is auditable:

```
kpass data-agent escalation-decision deal_abc123 --accept --approval-id appr_1 --reason "Calibration within acceptable tolerance" --output json
```
```
kpass data-agent escalation-decision deal_abc123 --reject --approval-id appr_1 --yes --reason "Delivered row count far below sample" --output json
```

The response — `{dealId, status}` — reflects the deal's new terminal status (`SETTLED` if accepted,
`REFUNDED` if rejected).

### Step 6 — Receipt / audit drill-down: `kpass data-agent export-receipts <dealId> --out <file>`

Run this once the deal has reached a terminal status (`SETTLED` or `REFUNDED`), or any time the user
wants "why did this happen" detail mid-deal. This writes the full receipt tree to disk as
pretty-printed JSON, unmodified from what passport returned — never summarize or reformat it
yourself; tell the user the file path and let them open it directly for audit/compliance review.

## Worked Example (CA health data, $1,000 budget, delivery-verification escalation)

1. The user says: "CA health data — diabetes, blood pressure, obesity, and uninsured rates, buy it
   from `https://seller.example/.well-known/agent-card.json`, budget up to $1,000, ideally around
   $700."
2. Confirm back: project id, purpose, seller URL, columns, `$700`/`$1,000` converted to
   `700000000`/`1000000000` (USDC, 6 decimals), round budget (default 5). Get an explicit go-ahead.
3. Run:
   ```
   kpass data-agent create-deal \
     --project-id prj_health_research \
     --purpose "CA county health indicators for care-gap modeling" \
     --seller-agent-card-url https://seller.example/.well-known/agent-card.json \
     --columns DIABETES,BPHIGH,OBESITY,ACCESS2 \
     --target-amount 700000000 \
     --max-amount 1000000000 \
     --round-budget 5 \
     --output json
   ```
   Response: `{"dealId": "deal_nec_2026_07_001", "status": "ACCEPTED", "agreedAmount": "700000000",
   "reasonCode": "ReasonAskWithinTarget"}`. Tell the user: the seller accepted at $700; escrow
   funding and delivery are now proceeding automatically.
4. Later, the user asks for a status update. Run `kpass data-agent status deal_nec_2026_07_001
   --output json` — response shows `status: "VERIFICATION_ESCALATION_NEEDED"`. Tell the user the
   delivered dataset's automatic calibration check came back ambiguous and needs their decision.
5. Run `kpass data-agent list-escalations --output json` to find the `approvalId` for this deal —
   response includes `{"dealId": "deal_nec_2026_07_001", "approvalId": "appr_7", "reasonCode":
   "AmbiguousCalibration", ...}`.
6. Ask the user to review and decide. They say "accept it, the sample looks fine." Run:
   ```
   kpass data-agent escalation-decision deal_nec_2026_07_001 --accept --approval-id appr_7 --reason "Reviewed sample, within tolerance" --output json
   ```
   Response: `{"dealId": "deal_nec_2026_07_001", "status": "SETTLED"}`. Tell the user: "$700 released
   to the seller, deal settled."
7. The user asks for the audit trail. Run `kpass data-agent export-receipts deal_nec_2026_07_001
   --out receipts.json --output json`. Tell them the file path; do not summarize its contents
   yourself unless asked.

## Error Handling

| Symptom | Meaning | Recovery |
|---|---|---|
| Exit code 3 (`AUTH`), `"Not logged in"` | No stored passport session JWT. | Have the user run `kpass login init --email <EMAIL>` or complete the **`authenticate-user`** skill. |
| Exit code 2 (`USAGE`), `"Missing required flag(s): ..."` | `create-deal` was run without every required flag. | Ask the user for the missing detail and retry — do not guess a value, especially the seller Agent Card URL or spend amounts. |
| Exit code 2 (`USAGE`), `"Pass exactly one of --accept or --reject"` | `escalation-decision` was called with neither or both flags. | Confirm the user's actual accept/reject decision, then retry with exactly one. |
| Exit code 2 (`USAGE`), `"Refusing to reject delivery ... without --yes"` | `escalation-decision --reject` was called without `--yes`. | Confirm the user explicitly wants to reject (this triggers a refund and cannot be undone), then retry with `--yes`. |
| Exit code 4 (`NOT_FOUND`) | The `dealId` doesn't exist, or belongs to a different user than the caller. | Double-check the id with the user — do not fabricate one. |
| Exit code 1 (`NETWORK`), HTTP 409 on `escalation-decision` | The escalation's `approvalId` is stale (already resolved, or the deal moved past `VERIFICATION_ESCALATION_NEEDED`). | Re-run `list-escalations` to get the current `approvalId` before retrying. |
| Exit code 1 (`NETWORK`), HTTP 503 | Passport reports the A2A buyer adapter isn't configured/deployed in this environment. | Tell the user this feature isn't live in this environment yet — do not retry in a loop. |

## Cross-Skill References

### Prerequisites (before this skill)

- **`authenticate-user`** — required once before any `kpass data-agent` command will authenticate.

### When NOT to use this skill (use instead)

- **Single-buyer, non-negotiated paid API call:** use **`request-session`** then **`x402-execute`**.
- **Direct wallet transfer:** use **`wallet-send`**.
- **Purchase split across multiple participants:** use **`group-order`**.

### After completion

- Once a deal reaches `SETTLED` or `REFUNDED`, tell the user the final outcome from `status` (amount
  settled or refunded) and offer `export-receipts` for audit drill-down.
