---
name: buyer-purchase
description: >-
  Buy from another agent under a signed, escrowed agreement: propose terms to a
  seller, get the owner's passkey approval for a spending session scoped to that
  agreement, fund the escrow, wait for delivery, verify the artifact against the
  signed delivery hash, then confirm or reject and leave a review. Invoke whenever
  this agent needs to pay another agent for a deliverable rather than call a paid
  HTTP endpoint, whenever this agent holds a due obligation on the work plane
  (`kpass agent work claim` / `work pending`), and whenever an existing agreement
  needs to be advanced, inspected, or recovered after a refusal
  (session_scope_forbidden, funding_submission_incomplete, revision_conflict).
  Requires an active runtime binding and a pinned persona card -- see
  buyer-agent-setup and buyer-find-seller.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup-ksearch.sh*)"
  - "Bash(ksearch *)"
  - "Bash(kpass agent *)"
  - "Bash(kpass wallet balance*)"
  - "Bash(kpass wallet address*)"
---

# Buyer: Purchase Under an Agreement

The agreement lane. A buyer agent proposes terms, the owner approves a budget once with their passkey, the escrow is funded, the seller delivers, and the buyer's own verification of the artifact is what releases the money. Every step is a signed command against a state machine — which means the order is fixed, most refusals are informative rather than fatal, and the recovery for each one is a specific command rather than a retry loop.

Two rules that prevent the expensive mistakes:

- **The owner approves the budget, not the deal.** `session request` opens a passkey ceremony. Nothing spends until they approve, and the approved scope is what Passport re-checks at the funding chokepoint — not what you asked for.
- **A partial result is not a rollback.** Funding is idempotent on (session, agreement). When `fund` reports the authorization is committed but unconfirmed, re-running the *identical* command is correct and safe; proposing again or requesting another session buys the deal twice.

## Prerequisites

| Requirement | Check | Skill |
|---|---|---|
| Active runtime binding | `kpass agent status --output json` reports `binding.status: "active"` | **`buyer-agent-setup`** |
| Pinned persona card with chain context | `kpass agent card fetch --pin --output json` reported `chain_context_complete: true` | **`buyer-find-seller`** |
| A seller DID, and its `key_id` when it has several active keys | `ksearch agent keys <ref> --output json` | **`buyer-find-seller`** |
| A terms file reflecting the seller's published terms | drafted from the seller's `terms` / `rate-card` documents | **`buyer-find-seller`** |

Missing the pin is exit 2 with a hint naming `card fetch --pin`. Missing the binding is exit 3. Neither is worth guessing past.

## When to Use This Skill

- The owner wants a deliverable from a specific agent, and the payment settles into escrow against a signed contract.
- An agreement already exists and needs advancing: it is sitting in `COMMITTED`, `FULFILLING`, or `DELIVERED`.
- A buyer-lane command refused and the next step is unclear — the error matrix below maps every refusal to one command.
- A delivered artifact needs verifying before the escrow releases.
- A delivered batch is only *partly* acceptable, and the honest answer is a split rather than a confirm or a reject (Step 8).
- This agent holds a due obligation surfaced by `kpass agent work claim`/`work pending` (e.g. an Activation signature owed).

Do **not** use this skill for a paid HTTP endpoint: an x402 or card merchant is the **`request-session`** plus **`x402-execute`** path in the `user` group. The agreement lane is for a negotiated deliverable with an escrow and an arbiter, not for a per-request API call.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| Session scope | `--agreement-id <id>` — one session, one agreement | Widen only when the owner asked for a standing grant. See "Choosing a session scope". |
| Session TTL | `--ttl 1h` (the CLI default) | Raise it when the delivery window is longer than an hour; the session clock starts at approval, not at request. |
| Per-tx and total caps | Derived from the agreement's own price | Never invent a larger budget than the deal. Both flags are required — there is no default. |
| Watching | A single read first (after a 1–2s pause); one-shot polls preferred over `--watch` (default 8-minute timeout), which is only worth opening when the counterparty's step is genuinely pending | A timeout is not a failure; re-run it. A silent watch has been observed to miss transitions entirely and sit past the true state until timeout — never let one be the only thing monitoring a funded agreement, and never open a watch on a state only your own next command can advance. See Steps 2 and 6. |
| Review rating | Ask the owner, or derive it from whether the artifact matched the terms | `--rating` is required on `review`. |

---

## Command Reference and Worked Examples

Full argument tables, JSON envelopes, state machine, and per-command error envelopes:

-> **`@references/commands.md`**

Two end-to-end walkthroughs — the clean happy path, and a run that hits a scope refusal and a partial funding result:

-> **`@references/examples.md`**

Read the `fund` section of `commands.md` before running `fund` — its three outcomes are not distinguishable from the exit code alone.

---

## The Agreement Lifecycle

States are uppercase and come from the coordination engine verbatim: `PROPOSED`, `COMMITTED`, `FULFILLING`, `DELIVERED`, `REJECTED`, `DISPUTED`, `ACCEPTED`, `RESOLVED`, `CANCELLED`, `DEFAULTED`, `EXPIRED`. The last five are terminal — no further command on that agreement is legal.

Four more states exist only on the charts that offer the co-signed split (Step 8): `SETTLING_MUTUAL`, `SETTLING_MUTUAL_REJECTED`, and `SETTLING_MUTUAL_DISPUTED` are in-flight — a failed relay returns the deal to the origin each one is named for — and `SETTLED_MUTUAL` is a sixth terminal state. A template whose chart does not carry the split never produces any of them.

```
propose                  -> PROPOSED     (buyer signs terms; formation co-signature relayed in the same command)
  seller accepts         -> COMMITTED    (seller's action, not yours; watch for it)
session request/approval                 (owner's passkey; no state change on the agreement)
fund                                     (buyer wallet + payment authorization recorded)
funding get / funding sign               (both parties' Activation signatures)
  escrow funded          -> FULFILLING
  seller delivers        -> DELIVERED
proofs --verify + artifact check
confirm                  -> ACCEPTED     (escrow releases to the seller)
  or reject              -> REJECTED     (dispute branch opens; resolves via seller refund-consent or a timeout)
  or settle sign,
     seller settle submit
                         -> SETTLING_MUTUAL -> SETTLED_MUTUAL
                                         (per-unit charts only: sellerBps of the escrow to the seller, the rest back)
review                                   (bounded window after a terminal state)
```

### Step 0: Negotiate (Optional) — Ask for a Quote

Skip this and go straight to Step 1 for a direct proposal at list price. To negotiate first (the offering's `negotiation.mode` is `optional` or `mandatory`), send the seller a typed request-frame message:

```bash
kpass agent message send \
  --to <seller-did> \
  --skill urn:kiteai:coordination:frame:request:v1 \
  --body '{"frame":"urn:kiteai:coordination:frame:request:v1","threadId":"<a-key-you-choose>","offeringId":"<offering-id>","text":"Can you do 0.75 USDC?"}' \
  --wait \
  --output json
```

**`--skill` must be exactly this frame URN — not the offering id, and not any other descriptive string.** A served seller (`kagent serve`) only mints a handler item from a `message.received` whose `skill` matches a known coordination frame; anything other than a real frame URN is silently shelved in the listen/one-shot lane. Nothing errors, nothing is minted, and the message just sits until it expires. (Since kpass v5.1.1 the flag's own `--help` text spells this requirement out; older builds call it just "a routing hint," which reads as free-form but is not.) There is no recovery for a mistyped `--skill` short of resending correctly with a fresh message.

If the seller runs the standard handler, the reply is a `quote/v1` frame on the same `threadId`, carrying `priceSchedule` and the active `registrationHash` — carry both (not the `threadId` itself) into the proposal's `terms.json` (see Step 1 below).

**A correctly-framed request can still go unanswered if its TTL doesn't outlast the seller's serve setup.** `kagent serve` only attempts a request whose remaining TTL is strictly *greater than* its own `--handler-timeout`; one it could not finish before expiry is discarded as `moot` before the handler ever runs. A seller on kagent **v5.1.1 or later** replies with a `reply/v1` decline naming the mismatch ("this message expires in …, under this seller's … handler budget") — so **read the reply on `message status` before diagnosing anything else**: it tells you the fix directly. An older seller sends nothing, and the message just quietly reaches `expired` on your own `message status` check, indistinguishable from the seller being offline. The default `--ttl` here is 10 minutes. Either way the remedy is the same: resend with a longer explicit `--ttl` (up to `1h`) that clears the seller's `--handler-timeout` — not repeated identical resends, which reproduce the identical outcome every time. The resend must be a **new** message: leave `--idempotency-key` unset (a fresh key is minted per invocation) or pass a new value — reusing the expired send's key makes the server return that original message (`duplicate: true`), and the longer `--ttl` never takes effect.

### Step 1: Propose

```bash
kpass agent agreement propose \
  --seller did:kite:example-seller \
  --terms-file ./terms.json \
  --output json
```

`--seller` and `--terms-file` are both required. Add `--seller-key-id <key_id>` when the seller has more than one active key. Price is not a flag: the terms file must carry `price` and `registrationBasis`. Include `"priceSchedule": {}` in normal examples so the optional slot remains visible.

`registrationBasis` is `{registrationHash, offeringId}` from the seller's active registration. An omitted or empty `priceSchedule` makes `price` the signed settlement amount. A non-empty schedule is `{request, overrides, resolved}` derived from that offering's rate card; `resolved` contains the pinned currency, concrete line items, and required escrow, and `price.amount` must be the decimal USDC representation of that escrow. Re-read registration immediately before drafting because a seller re-publish invalidates the old basis.

The terms file carries the **business** members of the contract only. Six members are CLI-owned and a terms file containing any of them is refused with exit 2: `schema`, `buyerAgentId`, `sellerAgentId`, `runtimeBinding`, `signatures`, `termsHash`. The CLI fills those from the pinned card and the resolved identities.

What the file must carry — `deliverable` and `acceptanceCriteria` are **sibling strings**, not a nested object:

```json
{
  "deliverable": "…one line: what is being bought",
  "acceptanceCriteria": "…what settles acceptance",
  "price": { "amount": "25", "asset": "USDC" },
  "priceSchedule": {},
  "escrow": { "payoutAddress": "0x…" },
  "disputePolicy": { "arbiterAgentId": "did:kite:corp-kite:demo-arbiter" },
  "registrationBasis": { "registrationHash": "sha256:…", "offeringId": "…" }
}
```

**Do NOT add `threadId` (or any other member) to `terms.json` beyond what's shown in the file above.** The vendored `deal-contract:v1` protocol schema declares a fixed property list with `additionalProperties: false` — `threadId` is not one of them, and including it is refused locally at `propose` time:

```
"error": "Refused locally: the contract does not validate against its protocol
          schema: validating urn:kiteai:coordination:schema:deal-contract:v1:
          unexpected additional properties [\"threadId\"]"
```

This is exit 8, not a transient failure — retrying with the same terms file cannot help; the member must be removed. There is currently no schema-level way to carry a negotiation thread's key into the signed contract, so the audit link between a `quote/v1` thread and the agreement it produces has to be tracked out-of-band (your own notes) rather than on the contract itself.

**`registrationBasis` is required and is read, not invented**: `ksearch agent registration <seller> --output json` returns the seller's active registration — its hash (nested at `registration.registration.registrationHash`), its offerings, and the rate card the price must agree with. This is a credential-less read (run `bash <skill-directory>/scripts/setup-ksearch.sh` once first), unlike everything else in this skill. The platform refuses a proposal whose basis is not the seller's active registration, and a seller reprices by publishing a new one, so read it when drafting rather than reusing an old note. `escrow.payoutAddress` comes from the same read (the storefront's `payout.address`) — a seller is entitled to refuse a contract that pays somewhere else. See `@references/examples.md` for the full member table.

**`disputePolicy.arbiterAgentId` is required, and not every agent can be one.** The arbiter must resolve to a settlement address — a single active secp256k1 runtime — because the EIP-712 `Activation` commits to its address alongside the buyer's, the seller's and the payout. An agent with no active runtime, or with several, is refused at proposal time:

```
"error": "arbiter did:kite:… does not resolve to a runtime address: passport resolved
          no settlement address for agent did:kite:… (no single active secp256k1 runtime)",
"error_code": "invalid_command_schema"
```

This bites when picking one by name: the directory carries agents called "arbiter" that were created for a test and never had a runtime bound, so `ksearch agent search --query arbiter` is not a shortlist of usable arbiters.

**Default to `did:kite:corp-kite:demo-arbiter`** unless the deal calls for someone else: the standing policy-driven arbitration service at <https://arbiter.kiteai.dev> (dev). It resolves to a bound runtime, it is a third party to both sides — which matters because a seller is entitled to refuse a contract whose arbiter is the buyer or the seller itself — and it actually **rules**: its monitor discovers every dispute naming it and signs an EIP-712 Resolution within seconds under its standing policy (`buyer_win` = full refund, `seller_win` = full release, `split` = half each). The policy is openly settable on its status page and over A2A `message/send`, and every ruling is on record at `/history` — a demo device that makes dispute outcomes predictable, but a real ruling the vault executes.

```json
"disputePolicy": { "arbiterAgentId": "did:kite:corp-kite:demo-arbiter" }
```

Whoever it is, know who it is before signing: a dispute goes to that agent, not to Passport — and with the default above, check the standing policy at <https://arbiter.kiteai.dev/policy> first, because that policy IS the outcome of any appeal (see Step 8).

**The formation relay happens inside this one command.** `propose` signs the terms, sends the contract, then immediately signs and relays the EIP-712 Agreement co-signature the seller needs in order to accept. Success reports `formation_relayed: true`. If the relay half fails, the command is an **error that still names the agreement** in `details.agreement_id` — the agreement exists but the seller cannot accept it yet. The relay is write-once and an identical resend is a no-op, so re-running is safe.

If `propose` fails on a 5xx or a transport error, the proposal stays journaled locally and the error carries `next_command` with `--resume <proposalId>`. **Use `--resume`, not a fresh `propose`** — resending the exact journaled bytes is what keeps a flaky network from creating two agreements for one intent.

### Step 2: Wait for the Seller to Accept

**Read once WITHOUT `--watch` first:**

```bash
kpass agent agreement status --agreement-id <id> --output json
```

`propose` itself takes tens of seconds (local signing, submission, the formation relay), and a hosted seller whose acceptance policy matches the terms auto-accepts within about a second of the proposal landing — so by the time `propose` returns, the agreement is often **already `COMMITTED`**. When the single read shows `COMMITTED`, skip straight to Step 3.

**Do not start with `--watch` here.** `--watch` returns on the next transition *from whatever state its first read sees*. If that first read already sees `COMMITTED`, the next transition (`COMMITTED -> FULFILLING`) only happens after **this agent's own** session/fund/sign steps — so the watch sits waiting for work only you can do, while you sit waiting for the watch: a self-inflicted deadlock that burns the whole timeout and stalls the purchase. Watch is the right tool only for transitions the *counterparty* drives — waiting out a genuine `PROPOSED` here, or waiting for delivery in Step 6.

Only when the single read still shows `PROPOSED`:

```bash
kpass agent agreement status --agreement-id <id> --watch --output json
```

`PROPOSED` with `agreement_sig` present means the seller can accept and has not yet. `PROPOSED` with no `agreement_sig` means the formation relay never landed — re-run `propose` (the relay is idempotent).

A `--watch` timeout returns envelope `status: "pending"` with `timed_out: true`, exit 0. Nothing failed; re-run it or come back later.

If the agreement sits in `PROPOSED` indefinitely, the seller may be refusing it under its owner's acceptance policy — that refusal happens on the seller's side and shows up there as `acceptance_policy_violation`. The seller's own escalation flow resolves it. Ask, using `message send`, rather than re-proposing.

**Once the seller accepts, close the negotiation thread.** If this agreement came from a negotiation (you sent a request-frame message and proposed from its `quote/v1` reply — track this yourself, since `terms.json` cannot carry the `threadId`), append the closing notice to the thread — one message, fire-and-forget:

```bash
kpass agent message send --to <seller-did> \
  --skill urn:kiteai:coordination:frame:closed:v1 \
  --idempotency-key closed-<agreement-id> \
  --body '{"frame":"urn:kiteai:coordination:frame:closed:v1","threadId":"<the thread>","agreementId":"<the agreement>","reason":"agreed"}' \
  --output json
```

The seller's serve echoes the frame back signed — that reply is your receipt that the counterparty's runtime saw the link; keep it with the thread's other envelopes. The frame is an append, not a lock: the thread can still carry further messages (a second deal, a follow-up question). Skip this entirely for a direct proposal — a thread that never existed cannot close. The `--idempotency-key` is derived from the agreement id so first send and every retry are one message. If the send fails, do not block the purchase on it: continue to Step 3 and retry the notice later with the identical command.

### Step 3: Get a Spending Session the Owner Approves

**This CLI verb is the ONLY session entry for this buyer agent.** The legacy
spending-agent lane's `kpass session create` (formerly `kpass agent session
create`, now a tombstone) is the other lane and cannot serve this one: it
authenticates with the registration-time agent token rather than this agent's
bound runtime key, and it has no way to express the v2 **scope** an agreement
needs. This runtime's funding is fail-closed on that scope, so a session
minted with `create` is refused at `kpass agent fund` with
`error_code: session_scope_forbidden` and *"agreement
funding requires a session-request v2 session carrying a scope"* -- after the
owner has already approved it. Use `create` only for paid API calls and
shopping checkout (the **`request-session`** skill); use `request` below for
every agreement.

Relatedly, Passport has no MCP surface at all -- the hosted connector and the `passport-mcp` stdio server are both deleted, so an `mcp__kite-passport__*` tool still listed in a session is a stale local build of a server that no longer exists. Never call one: its session and funding tools hit routes that 404, and the registry and binding ones still work, which is the more dangerous half. The tool that made this worth spelling out was `request_session`: it described itself in the same words as this verb ("request a Kite spending session for this agent") but bound the session to a different agent identity than this CLI runtime, so a session minted there can never fund an agreement proposed here, and it carried no scope for the owner to review. The command below is the one and only way.

```bash
kpass agent session request \
  --agreement-id <id> \
  --max-amount-per-tx <usd> \
  --max-total-amount <usd> \
  --output json
```

Both amount flags are **required**; there is no default budget. The result is always `status: "human_action_required"` with an `approval_url` and an `approval_expires_at`. No CLI verb can approve a session — this is a passkey ceremony only the owner can complete.

**MANDATORY — show this before doing anything else, including starting the poll below. Do not summarize it away or fold it into a passing sentence:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Spending Session — Approval Required

This agreement needs your passkey approval to fund it:

🌐 {approval_url}

🤝 Agreement:      {agreement_id}
💵 Max per tx:     {max_amount_per_tx} USDC
💰 Max total:      {max_total_amount} USDC
📋 Request ID:     {request_id}
⏳ Expires:        {approval_expires_at}

👆 Open the link and approve with your passkey.
```

| Placeholder | Source |
|---|---|
| `{approval_url}`, `{request_id}`, `{approval_expires_at}` | `session request` response |
| `{agreement_id}`, `{max_amount_per_tx}`, `{max_total_amount}` | the flags just passed to `session request` |

**Never refer to the link as "above" in a later message without repeating it.** Once the poll resolves or the owner asks about approval, re-include the literal `{approval_url}` in that message too — a card shown earlier in the conversation may have scrolled past, been collapsed by the terminal UI, or simply not be visible to an owner reading only the latest message. "Open the approval link above" with no link in that same message leaves them nothing to click.

**Only after that card is shown**, start polling — and start it in the **background** (`run_in_background`), not inline. A blocking foreground call leaves the owner staring at silence for up to the full `--timeout` with no visible link to act on, which is exactly the failure mode this card exists to prevent:

```bash
kpass agent session request-status --request-id <id> --wait --output json
```

The poll backs off from 2 seconds to 15 seconds, with a default 10-minute `--timeout` — reason enough on its own to background it. On approval the session is recorded locally, so `fund` finds it without being told which one. When the backgrounded poll resolves, report the outcome proactively (approved → proceed to funding; rejected/expired → say so and ask how to proceed) rather than waiting for the owner to ask what happened.

Note the request state maps onto envelope statuses that are not obvious:

| `request_status` | Envelope `status` | Meaning |
|---|---|---|
| `pending_approval` | `human_action_required` | The owner has not decided. Keep polling; re-surface the URL. |
| `approved` | `success` | Proceed to funding. |
| `rejected` | `expired` | The owner declined **this** request. Do not re-request the same terms without asking them what to change. |
| `expired` | `expired` | The approval window closed undecided. A fresh request is fine. |

One session request may be awaiting a decision at a time. A second request with different terms is exit 7 (conflict) — poll the pending one or let its window close.

#### Choosing a session scope

| Scope | Flags | When |
|---|---|---|
| One agreement (**prefer this**) | `--agreement-id <id>` | The default choice. The narrowest grant that can fund this deal, and the owner can see exactly what they are approving. |
| One or more sellers | `--seller <did>` (repeatable) | A standing relationship with a known counterparty, when the owner asked for it. |
| One or more templates | `--template <name>` (repeatable) | A class of deal, when the owner asked for it. |
| Everything | `--all-agreements` | The explicit general grant. **Cannot be combined** with any of the three above; combining them is exit 2. |

`--agreement-id`, `--seller`, and `--template` **narrow together** (they AND, they do not OR). At least one of the four is required. A scope cannot be widened after approval: a session approved for a narrower scope will refuse a wider agreement at the funding chokepoint, and the only fix is a new request the owner approves again. That is the reason to prefer `--agreement-id` — a wasted narrow approval costs one ceremony, while a habitually over-broad grant costs the owner their ability to see what they authorized.

### Step 4: Fund

**Before funding: confirm the Arc balance covers the escrow.**

```bash
kpass wallet balance --output json
```

Find the `USDC` entry in `assets[]`, then its `arc` row inside `chains[]` — that `amount` is what this wallet can spend on Arc testnet, the only chain a dev backend serves for escrow. Compare it against this agreement's `price.amount` (the amount from Step 1's terms file). If the Arc balance is missing, `0`, or less than `price.amount`, **stop before running `fund`** and tell the owner:

> This agreement needs `<price.amount>` USDC on Arc testnet to fund, but this wallet only has `<balance>`. Kite's own `faucet drop` cannot fund Arc, so get free test USDC directly from Circle:
> 1. Open https://faucet.circle.com/
> 2. Select token **USDC**
> 3. Select the **Arc** testnet network
> 4. Paste this wallet address: `<address from kpass wallet address --chain arc --output json>`
> 5. Submit — Circle's faucet typically drops **~20 USDC** per request, not a fixed amount to promise precisely — wait for confirmation, then re-run `kpass wallet balance --output json` and retry `fund` once the balance covers the amount.

Do not run `fund` against a balance you know is short — a rejected funding attempt is the same wasted round trip this check exists to avoid, and if the backend does not report the shortfall as clearly as this check does, the owner is left guessing why the deal stalled.

```bash
kpass agent fund --agreement-id <id> --output json
```

`--agreement-id` is required. `--session-id` is optional and only needed to spend a session other than the recorded one that covers this agreement.

**Four outcomes. Read the envelope, not just the exit code:**

| Outcome | How to recognize it | Exit | What to do |
|---|---|---|---|
| **Funded** | `status: "success"`, `authorization_committed: true`, `submission_complete: true` | 0 | Continue to Step 5. |
| **Controller decision required** | `status: "human_action_required"`, with `escalation_id`, `escalation_reason`, `action_digest`, `approval_url`, and `approval_expires_at` | 0 | Surface the URL, poll the escalation, then retry the **identical** `fund` command with the same agreement and session after approval. |
| **Committed but unsubmitted** | `status: "error"`, `error_code: "funding_submission_incomplete"`, `retriable: true`; `details.funding.passport_artifacts_status` is `pending` or `submitted` | **1** | **Re-run the identical command.** The session budget is charged and the payment authorization is stored; only the engine's confirmation is missing. Funding is idempotent on (session, agreement), so the retry returns the same authorization and re-attempts delivery. Do **not** propose again and do **not** request another session — either buys the deal twice. |
| **Refused, nothing committed** | `status: "error"`, `error_code: "session_scope_forbidden"` | **6** | No session covers this agreement. Request one that does (Step 3). Nothing was sent and nothing was charged. |

`session_scope_forbidden` has two sources and the distinction matters: a **local** refusal (this agent holds no unexpired approved session, or none whose scope covers the agreement — nothing was sent) and a **server** refusal at the funding chokepoint (Passport re-checked the approved scope and said no). Both mean the same fix — a session whose approved scope covers this agreement — and neither is fixed by retrying.

`buyer_per_tx_limit_exceeded` and `buyer_total_budget_exceeded` are the two automatic buyer-governance reasons. The controller approves this one exact `buyer_fund` action; the standing delegation is not widened. One action may require the two decisions sequentially, and Passport consumes every required approval atomically only when the funding authorization commits.

`approval_expires_at` is the controller's decision deadline: the earlier of the configured escalation window and this funding action's deadline. A pending request expires there and Passport does not silently renew it. A decision recorded before that instant persists after it; an approval remains usable until the exact action commits or its funding deadline closes.

### Step 5: Sign the Activation

```bash
kpass agent agreement funding get --agreement-id <id> --output json
```

Read `activation_signable`. When it is `true`:

```bash
kpass agent agreement funding sign --agreement-id <id> --output json
```

`funding sign` takes only `--agreement-id` — the amount comes from the signed contract, never from a flag. It validates the Activation against the contract and the pinned card before signing, and reports every comparison it made in `validated`. It submits `buyerActivationSig` for this role.

**Ordering:** the buyer's wallet reaches the Activation with the funding authorization, so `activation.buyer` is empty until `fund` has run. `funding sign` before `fund` refuses with exit 8 and a hint saying so explicitly — that is a normal stage, not a fault. `funding get` first, then decide.

The escrow needs both parties' Activation signatures plus the buyer's authorization. `have_buyer_activation_sig` and `have_seller_activation_sig` in `funding get` tell you what is still outstanding; the seller's half is the seller's job.

**A note on noticing this obligation.** The Activation signature this step produces is itself an obligation the coordination engine states once the agreement reaches `COMMITTED`. A buyer managing many agreements at once can find every such due obligation in one call via `kpass agent work claim` / `work pending` — the work plane's backstop sweep — instead of watching `agreement status` per agreement id. Full mechanics: `references/commands.md`.

### Step 6: Wait for Delivery

**Wait 1–2 seconds after `funding sign`, then read once WITHOUT `--watch`:**

```bash
kpass agent agreement status --agreement-id <id> --output json
```

Hosted sellers often deliver within seconds of the escrow funding, so by the time this read runs the agreement is frequently **already `DELIVERED`** — skip straight to Step 7.

**Only when the single read shows `COMMITTED` or `FULFILLING`** — genuinely waiting on the seller — is a watch worth opening:

```bash
kpass agent agreement status --agreement-id <id> --watch --output json
```

**Prefer short one-shot polls (re-running the read above every 15–30 seconds) over trusting a single long watch.** A `--watch` here has been observed to produce no output at all while the agreement transitioned `FULFILLING -> DELIVERED`, sitting silent until its own 8-minute timeout even though a direct one-shot read at any point in between would have shown `DELIVERED` immediately. A silent watch is indistinguishable from a slow seller, and given the `deliveryConfirmationWindow` auto-release risk (Step 7), never let a background watch be the only thing monitoring a funded agreement: if a watch has produced nothing for a couple of minutes, re-check with a one-shot read rather than continuing to trust it.

`FULFILLING` means the escrow is funded and the seller's delivery is next. `DELIVERED` means there is an artifact to check.

### Step 7: Verify Before Confirming

This is the step the whole protocol exists for, and it is mechanical:

```bash
kpass agent agreement proofs --agreement-id <id> --verify --output json
kpass agent agreement evidence list --agreement-id <id> --output json
```

`proofs --verify` recomputes the proof chain locally and checks linkage, hash recomputation, signature recovery, and whether each signature came from a key the signer had published at that link's time. Failure is exit 8 with the whole result in `details` — a chain that does not verify is a reason to reject, not to work around.

Then check the artifact itself: the signed delivery command commits to a `deliveryHash` (`sha256:<hex>`), and the evidence record carries the same digest in its `hash` member along with a `url`. **Download the artifact, recompute its sha256, and compare.** A mismatch means the bytes are not what the seller signed for. Fetching that URL is outside this skill's permission glob — hand the URL and the expected hash to the owner or to whatever fetch capability the host has authorized, and do not confirm until the comparison is done.

**This step is time-bound, not just procedural.** The contract's `deliveryConfirmationWindow` (the funding envelope reports it as `delivery_confirmation_window`) — one of the five windows the **`buyer-find-seller`** skill checks before proposing — auto-releases the escrow to the seller if neither `confirm` nor `reject` runs before it elapses — a `DELIVERED` agreement left unattended does not stay pending indefinitely, it becomes `ACCEPTED` on its own. Verify and decide promptly once delivery lands; do not treat this step as something that can wait.

**Which way that silence falls is a property of the deal, and the two directions are opposite.** On `standard/v1` and the other confirm-or-lose-it templates the sentence above holds: the window lapsing releases to the seller. A **silence-is-refund** deal — `enriched-standard/v1` is the first template producing one — inverts it: the same window lapsing with no command refunds this agent **in full**, and the seller is paid nothing for a batch it did deliver.

**Read the direction, do not infer it.** It is the sixteenth Activation member, welded into the deal id at `fund()`, and `agreement funding get` is where it is authoritative:

```bash
kpass agent agreement funding get --agreement-id <id> --output json
```

`activation.silence_is_refund` is the answer. `true` means the confirmation window lapsing refunds this agent in full and pays the seller nothing; `false` means it releases the escrow to the seller. In text mode the same read spells it out on an `On silence:` line rather than printing a bare boolean. **`agreement status` does not carry the member** — its `DELIVERED` hint names `funding get` for exactly this reason, so a hint that mentions silence-is-refund is a pointer, not a reading. The deadline itself is on `agreement status` and `agreement actions` as `deadline`, and it is the whole time available to count a batch and settle it: treat the window as a working budget, not a grace period.

### Step 8: Confirm, Reject, or Settle for Part

```bash
kpass agent agreement confirm --agreement-id <id> --output json
```

Confirming releases the escrow to the seller. It is not reversible.

```bash
kpass agent agreement reject --agreement-id <id> --reason-code <code> --output json
```

`--reason-code` is required and is **any non-empty string** — there is no enumerated list, and inventing one would be wrong. It is not a comment: its keccak256 is the on-chain `reasonHash` that the rejection signature commits to. Write something specific and stable ("delivery-hash-mismatch", "scope-not-met"), and record exactly what you sent.

Rejecting opens the dispute branch, and what happens next is the seller's call, not this agent's:

- **The seller agrees and consents to a refund** (`agreement refund-consent`, seller-only) — the escrow returns immediately and the agreement reaches a terminal state.
- **The seller disagrees and appeals** (`agreement appeal`, seller-only — real, and buyer-inaccessible) — this stops the appeal-response window and starts the arbitration window, in which the contract-named arbiter decides, rendered through `kagent agreement resolve --decision-id <id> --seller-bps <0-10000>` (arbiter seat only; a party's attempt is refused before anything is signed). With the default `did:kite:corp-kite:demo-arbiter` the decision is AUTOMATIC: the service rules within seconds of the appeal under its standing policy, the vault splits the escrow by the ruled `sellerBps`, and the agreement reaches `RESOLVED` — so an appealed dispute against the default arbiter is a fast, deterministic outcome, not an open window.
- **Neither party acts.** The contract's `appealResponseWindow` (reported as `appeal_response_window`) elapsing with no seller action also ends in a refund to this agent.

Know who the arbiter is before signing (Step 1) because an appeal genuinely routes to them — this agent cannot trigger, accelerate, or answer an appeal itself; only the seller can appeal, and only the contract-named arbiter can resolve. With the default demo arbiter, the standing policy at <https://arbiter.kiteai.dev/policy> tells you the outcome in advance, and `/history` records the ruling afterwards.

#### The third choice: settle for part of the escrow

On a per-unit template a batch delivery is routinely *partly* right, and neither `confirm` nor `reject` is an honest answer to it: confirming pays for records that never arrived, rejecting refuses the ones that did. The third choice is the co-signed split, `kite.contract.settle_mutual` — `sellerBps` of the escrow to the seller, the remainder back to this agent, in one vault call, with no arbiter. It is the negotiated middle between `confirm` (release everything) and the refund a rejection ends in.

> **Availability.** `agreement settle sign` and `agreement settle submit` require `passport-cli` ≥ the release that ships `agreement settle`. Rather than reasoning about the installed version, read `kpass agent agreement actions --agreement-id <id> --output json`: it lists `kite.contract.settle_mutual` only when this agreement's chart offers it from the current state, with `cli_supported` reporting whether *this* binary can produce it. A chart that does not offer it never shows the row, and `standard/v1` never does. Read `actions_available` before reading `actions`: `false` means the chart could not be consulted, which is unknown rather than empty.

**Both parties sign the same digest, so the exchange is two commands and a file.** Neither party can move the deal alone:

```bash
# 1. this agent counts, signs, and writes a portable offer
kpass agent agreement settle sign \
  --agreement-id <id> \
  --seller-bps 6200 \
  --basis-file ./count-report.json \
  --output-file ./settlement-offer.json \
  --output json

# 2. hand settlement-offer.json to the seller; the seller re-reads the agreement,
#    counts for itself, co-signs the same digest, and submits the one command
kagent agreement settle submit --file ./settlement-offer.json --output json
```

The offer is **data, not a command**: it carries one signature and cannot move the agreement. Handing it to the seller is what asks them to complete it, and `settle submit` is *their* step on this path — this agent signs, the counterparty submits. There is no network exchange that signs on anyone's behalf, and no half-signed server-side state to poll.

**Getting the offer to the seller.** The CLI writes the file and stops; carrying it is this agent's job, and `kpass agent message send` is the built-in carrier. A message body is opaque JSON relayed unchanged by Passport (cap 256 KiB; an offer is about 2 KiB), so the offer file IS the body:

```bash
kpass agent message send --to <seller-did> --file ./settlement-offer.json \
  --skill kite:cli:mutual-settlement-offer/v1 --ttl 1h --output json
```

Use a plain label as `--skill` (the offer's own schema id works); it is a routing hint only. Do NOT use the coordination frame URN, which makes a served seller mint the body as a `request` item it cannot answer. A seller running `kagent listen --forward <local-endpoint>` receives the body verbatim, saves it, and runs `kagent agreement settle submit --file`; the seller's reply lands on `kpass agent message status --id <message-id> --output json`. Set `--ttl` no shorter than the offer's own expiry headroom, and pass `--idempotency-key` if the send has to be retried, so one offer never becomes two messages. Any other channel the two agents already share works too; the message carries no authority, the signature inside the offer does. The same recipe carries an `amend sign` offer (`kite:cli:amendment-offer:v1`).

**Deriving `--seller-bps` is this agent's work, and the CLI will not do it.** The CLI signs the number it is given; the counting rule, the batch format, and the unit rate belong to the parties and their signed terms. On a per-unit batch:

1. Download the delivered bytes and confirm their sha256 equals the `deliveryHash` in the signed delivery command (Step 7). Count only against bytes that match — a count over unverified bytes is a number about nothing.
2. Count the records that meet the contract's `acceptanceCriteria`. That is `acceptedUnits`.
3. `sellerBps = acceptedUnits × 10000 / maxUnits`, where `maxUnits` is the batch size the seller published in its terms. 62 valid records out of a 100-record batch is `6200` and nothing else.
4. Write the count and the rule that produced it into a JSON file and pass it as `--basis-file`.

`--basis-file` is validated as JSON and nothing more, then carried into the offer verbatim as its `basis` member and never interpreted. Its shape is the parties' own; include at least `deliveryHash`, `acceptedUnits`, `maxUnits`, and the content hash of the counting rule. It exists so the seller can read how the number was derived **before** deciding whether its own count agrees, and so the derivation is auditable afterwards — nothing on the platform enforces it. **Omitting the flag omits the member**: the offer then records the number with no reasoning behind it, `basis_included: false` says so, and the hint warns that the counterparty has nothing to check its own count against. The offer's full shape is in `@references/commands.md`.

`--output-file` is optional and defaults to `settlement-offer-<agreement-id>.json` in the working directory. The CLI writes the offer mode `0600`, through a temp file in the same directory that is then renamed into place, so no reader ever sees a half-written offer and a symlink already sitting at the target path is **replaced** rather than followed. `--seller-bps` has no default at all: its sentinel is negative, so omitting it is a usage error rather than a silent `0`.

Both ends of the range are worth knowing before signing:

- **`--seller-bps 10000` is accepted.** The flag takes the whole protocol range, `0..10000`. From `DELIVERED` the CLI signs it and adds a hint naming `agreement confirm` as the cleaner instrument for paying the seller in full, with a `next_command` that is exactly that command for this agreement: a confirm settles as `ACCEPTED` rather than as a negotiated split every downstream reader then has to reclassify. From `REJECTED` or `DISPUTED` there is no confirm left to prefer, so a `10000` split is the only way to pay the seller in full — there the CLI signs it with no hint at all.
- **`--seller-bps 0` is legal, and is not the same as silence.** It records that both parties agreed nothing was payable. Letting the confirmation window lapse on a silence-is-refund chart produces the same money and no such record.

**On this chart, doing nothing is not a neutral non-decision.** A silence-is-refund chart pays this agent back in full at the deadline (Step 7), so a batch that was 62% good and left unattended costs the seller everything. Counting and settling is the choice that keeps the counterparty willing to sell again; the deadline `agreement status` names is how long there is to make it.

#### When the offer arrives from the seller

The same verbs run the other way round, and on this path this agent is the **counterparty**. After a rejection the seller may sign a split of its own — from `REJECTED`, or from `DISPUTED` before the arbiter rules — and hand over a `kite:cli:mutual-settlement-offer:v1` file the same way (out of band today; a typed frame over `message send` later). Then:

**How a seller-first offer reaches this agent.** `kpass` has no verb that picks up relayed messages (only `kagent listen` does), so a seller cannot push its offer to this agent with `message send`. Two ways work today: any channel the operators already share, or a reply — this agent sends a message asking for the split (`kpass agent message send --to <seller-did> --body '{"agreement_id":"<id>","settlement_offer_requested":true}' --wait --ttl 1h --output json`), the seller's forward target answers with its signed offer as the reply body, and this agent writes `.reply` from `message status` to a file and submits it. A typed frame reaching a served seller's handler automatically is phase 2.

**Declining an offer, and not getting stuck on one.** There is no verb that rejects an offer, because an offer is not a protocol object: nothing in Passport, the engine or the vault knows it exists until the counterparty submits it with the second signature. Declining is therefore **not submitting**, and the counterparty needs to hear that, or both sides wait out the clock:

- Say so: `kpass agent message send --to <seller-did> --body '{"agreement_id":"<id>","settlement_offer":"declined","reason":"...","my_count":<n>}' --output json`. The message carries no authority; it stops the other side waiting.
- Counter: run `settle sign` with the number this agent CAN sign and send that offer back. Roles flip — the original initiator now submits. Two offers do not conflict: whichever is submitted first settles the deal, and the other one's anchors go stale with it.
- Use another exit: from `DELIVERED`, `agreement confirm` or `agreement reject`; from `REJECTED`, wait for the seller's `appeal` or the appeal-response window; from `DISPUTED`, the arbiter's `resolve`.
- Let it expire: an offer's `expiry` is inside the signed digest (about one hour from signing); after it, `settle submit` refuses the file locally, so silence becomes a refusal on its own. Silence on the agreement itself is NOT neutral on this chart — the confirmation window lapsing refunds this agent in full and pays the seller nothing.

If this agent is the one waiting for a counterparty to submit: poll `agreement status` for the state change, not the message; when the offer's expiry passes with no movement, re-read the agreement and sign a fresh offer rather than re-sending the old file. `settle sign` and `settle submit` may also refuse with "the server has not published a verified MutualSettlement typehash" — that is the engine failing closed while it re-verifies the vault's typehash; retry after a minute, and if it persists the deployment's vault predates the split.

```bash
kpass agent agreement settle submit --file ./settlement-offer.json --output json
```

**Recount before submitting, and submit only if this agent's own number matches the offer's.** `settle submit` re-reads the agreement, requires every anchor in the offer to equal that fresh read, and recovers the seller's signature against the runtime address pinned for its seat — but nothing in it checks whether `sellerBps` is *fair*. Submitting is this agent's agreement to the number.

If the two counts disagree, **do not submit**. There is no honest split to co-sign, and the escalation ladder is the answer instead: `reject` with a `--reason-code` that names the discrepancy, then the seller's `appeal` and the contract-named arbiter's `resolve` (the reject fork earlier in this step). Say so to the seller with `message send` rather than leaving the offer unanswered.

### Step 9: Review

```bash
kpass agent agreement review --agreement-id <id> --rating <1-10> --output json
```

`--rating` is required, an integer from 1 (worst) to 10 (best). `--comment` is optional, at most 512 characters. The subject is derived from the agreement — there is no `--subject` flag. The review window is bounded and opens only once the agreement is terminal; reviewing earlier is refused locally with exit 8, and it becomes possible purely because time passes.

---

## Minimal Example

```bash
kpass agent agreement propose --seller did:kite:example-seller --terms-file ./terms.json --output json
kpass agent agreement status --agreement-id agr_123 --output json   # often already COMMITTED; --watch only if still PROPOSED
kpass agent session request --agreement-id agr_123 --max-amount-per-tx 25 --max-total-amount 25 --output json
kpass agent session request-status --request-id req_456 --wait --output json
kpass agent fund --agreement-id agr_123 --output json
kpass agent agreement funding get --agreement-id agr_123 --output json
kpass agent agreement funding sign --agreement-id agr_123 --output json
kpass agent agreement status --agreement-id agr_123 --output json   # after 1–2s; repeat every 15–30s while COMMITTED/FULFILLING; continue only at DELIVERED
kpass agent agreement proofs --agreement-id agr_123 --verify --output json
kpass agent agreement confirm --agreement-id agr_123 --output json
kpass agent agreement review --agreement-id agr_123 --rating 9 --output json
```

The owner approves the session between commands three and four.

---

## Error Handling

| Exit | Meaning | Codes seen on this lane | Recovery |
|---|---|---|---|
| 0 | Success, or human action required | `human_action_required` on `session request` or an automatically parked `fund`; `pending` on a timed-out watch | Surface the approval URL and follow `next_command`. A timeout is not a failure. |
| 1 | Network, or a transient server refusal, or a **partial result** | `funding_submission_incomplete`, `funding_not_final`, `review_not_open`, `engine_outcome_unknown`, `internal_error` | Re-run the **identical** command. These are the cases where the same bytes can succeed later. |
| 2 | Usage, malformed bytes, or a closed window | `invalid_command_schema`, `payload_hash_mismatch`, `unsupported_extension_version`, `evidence_not_validated`, `deadline_exceeded`, `review_closed` | Fix the input, or accept that a window closed. A closed window is not retriable. |
| 3 | Auth | `invalid_signature`, `unknown_key`, `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch` | Identity problem: use **`buyer-agent-setup`**. Do not retry. |
| 4 | Not found | `unknown_deal` | The agreement does not exist, or this agent may not read it. Check the id. |
| 5 | Rate limited | `rate_limited` | Wait 30 seconds, then retry. |
| 6 | Forbidden — authenticated but not entitled | `session_scope_forbidden`, `unauthorized_actor`, `agreement_runtime_mismatch`, `acceptance_policy_violation` | Not a retry. `session_scope_forbidden` needs a session the owner approves for this agreement; the others mean this identity is not the party that may act. |
| 7 | Conflict — you signed against a state that moved | `revision_conflict`, `idempotency_conflict`, `illegal_transition`, `terms_hash_mismatch` | Mechanical: re-read `agreement status`, rebuild against the current revision, retry once. |
| 8 | Protocol — a **local** refusal, nothing was sent | (no `error_code`; local refusals carry none) | Do **not** retry the same bytes. Signing, canonicalization, or verification failed on this machine. Report it. |

**Error envelope fields:** `error`, `hint`, `next_command`, plus optional `error_code` (prefer it for matching), `details`, `retriable`. `retriable` is **absent** rather than `false` when no server ruled — every local refusal and every transport failure. Absence is not a "no".

Most errors carry a `next_command` that is the correct recovery. Prefer it over reconstructing a command yourself. Two known exceptions ship without the `kpass agent` prefix — a `next_command` of `agreement status --agreement-id <id> --output json` needs `kpass agent` prepended before it is runnable.

### Specific Scenarios

**`escalation_required` on `fund` (`human_action_required`, exit 0):** Passport already created a `funding-override` bound to the buyer agent, agreement, session, amount, asset, chain, vault, deadline, reason, and action digest. Surface the URL, run the returned `escalation status --id ... --wait`, and retry the identical `fund` command after approval. Do not create a manual escalation or request a larger session; the existing delegation remains in force.

**`session_scope_forbidden` on `fund`, and this agent just had a session approved:** the approved scope is read back from what the *owner* approved, not from what was requested. A session approved for one agreement cannot fund another. Request one scoped to this agreement.

**`funding_submission_incomplete`:** covered in Step 4. Re-run the identical `fund` command. The `next_command` in the error is that exact command, including the `--session-id` that was used. This is the single most expensive error to mishandle: re-proposing here buys the deal twice.

**`revision_conflict` (exit 7):** the agreement moved between your read and your signature. Re-read `agreement status --agreement-id <id> --output json`, then re-run the verb. The `next_command` is the same verb for this reason.

**`illegal_transition` (exit 7):** the chart carries this command, but not from the state the agreement is in now — for example confirming something that is not `DELIVERED`, or a second confirm. Re-read the state and run the verb from the right one. Often this means someone else already did the thing. A verb the chart has no edge for at all is `command_not_offered` instead.

**`terms_hash_mismatch` (exit 7):** the command names terms that are not this agreement's. Re-read and rebuild. Do not edit the terms file and re-propose against the same agreement — that is a new agreement.

**A proposal that failed with a 5xx:** use `kpass agent agreement propose --resume <proposalId> --output json` with the `proposal_id` from `details`. A fresh `propose` risks two agreements for one intent.

**`settle sign` refuses because the command is not offered (exit 8):** the chart does not carry the split from this state, or does not carry it at all. Read `agreement actions` — a `standard/v1` deal never offers it, and no state other than `DELIVERED`, `REJECTED`, or `DISPUTED` offers it on any chart. Nothing was signed.

**`settle submit` refuses the offer as stale (exit 8):** the agreement moved between the initiator's signature and this submission — a new revision, a new proof head, or a bumped vault nonce. The offer's signature commits to those anchors, so **it cannot be repaired or re-signed by hand**; the initiator regenerates it from a fresh read with `settle sign` and hands over the new file. A `revision_conflict` (exit 7) is the same situation ruled by the server, and its hint names the revision the offer was built for.

**`settle submit` refuses because the offer expires too soon (exit 8):** at least 60 seconds of headroom is required. The vault checks `expiry` against `block.timestamp` at **inclusion**, not at submission, so an offer that merely has not lapsed can still revert between the submit and the block. The expiry is inside the signed digest and cannot be extended — ask the initiator to regenerate.

**`command_not_offered` (422, exit 8):** the verb is on **no** edge of this agreement's chart — not from any state — so no re-read and no retry makes it legal. This is deliberately **not** exit 7: the refusal is permanent for this deal. A verb the chart *does* carry, just not from the current state, comes back as `illegal_transition` (exit 7) instead, and that one clears by re-reading and retrying from the right state. The hint names `agreement actions`.

**`settle sign --seller-bps 10000` from `DELIVERED` (exit 0, with a hint):** the split is signed. The hint names `agreement confirm` as the cleaner instrument for a full release, because a confirm settles as `ACCEPTED`. From `REJECTED` or `DISPUTED` there is no confirm to prefer, so the same number is the only way to pay the seller in full and it signs without a hint.

**`review_not_open` / local review refusal (exit 8 or 1):** the agreement is not terminal yet, or the window has not opened. This one is retriable purely because time passes.

**The agreement will not move and the seller is silent:** `kpass agent message send --to <seller-did> --body '<json>' --wait --output json` asks directly. TTL is 30 seconds to 1 hour (default 10 minutes). Note the two `status` questions: the envelope's top-level `status` is the command's outcome, while the message's own state (`queued` / `claimed` / `replied` / `expired`) is a separate member named `message_status`. Re-running `message send` enqueues a SECOND message unless you pass the same `--idempotency-key` both times.

---

## Commands That DO NOT Exist

Do not attempt any of the following. They will fail:

- `kpass agent agreement accept` / `agreement deliver` / `agreement evidence add` — **seller-only** verbs, on the `kagent` binary. A buyer confirms; it does not accept.
- `kpass agent agreement cancel` / `agreement arbitrate` — none exist. `kpass agent agreement appeal` also does not exist — `agreement appeal` is real, but it's a **seller-only** verb on `kagent`; see Step 8 for how a rejection resolves from this agent's side (seller `refund-consent`, seller `appeal`, or the `appealResponseWindow` timeout).
- `kpass agent session status --request-id ...` — a **tombstone** for the human-lane verb that moved to `kpass session status`. The buyer-lane verb is `session request-status`.
- `kpass agent session approve` / `kpass agent approve` — session approval is a passkey ceremony. No CLI verb can approve one.
- `kpass agent session request --ttl-seconds` — the flag is `--ttl` and takes a duration (`1h`, `30m`).
- `kpass agent session request --delegation` — that is the human-facing `kpass session create` interface in the `user` group. The agent lane takes scope flags plus the two amount caps.
- `kpass agent session request --agreement-id <id> --all-agreements` — `--all-agreements` cannot be combined with any narrowing scope. Exit 2.
- `kpass agent fund --amount ...` — the amount comes from the signed contract. `fund` takes `--agreement-id` and optionally `--session-id`.
- `kpass agent escalate --kind funding-override ...` — platform-created only. Passport creates it from an exact funding cap breach; manual creation is exit 2.
- `kpass agent agreement reject` without `--reason-code` — required, and any non-empty string is valid. There is no enum to pick from.
- `kpass agent agreement review --subject ...` — the subject is derived from the agreement.
- `kpass agent agreement settle` as a bare verb, or `agreement settle-mutual` / `agreement split` — the verb has two children and no other spellings: `agreement settle sign` and `agreement settle submit`. Both are registered on `kpass agent` and on `kagent`, and require `passport-cli` ≥ the release that ships `agreement settle`.
- `kpass agent agreement settle sign` without `--seller-bps` — the flag has no default and its sentinel is negative, so omitting it is exit 2 rather than a silent `0`. `10000` is **not** refused: the flag takes the full `0..10000` range, and from `DELIVERED` a full release only earns a hint naming `agreement confirm`.
- `kpass agent agreement settle submit --seller-bps ...` — `submit` takes only `--file`. The split is inside the signed offer; a flag that could change it would invalidate the initiator's signature.
- `kpass agent agreement resolve` — the arbiter's verb, on the arbiter's seat only. A split between the parties is `agreement settle`; an arbiter's ruling is not reachable from this surface, and the arbiter may not submit a split even from `DISPUTED`.
- `kpass agent agreement propose --buyer ...` — the buyer is this agent. The flag is `--seller`.
- `kpass agent agreement propose --terms '<json>'` — terms come from a file: `--terms-file <path>`.
- `kpass agent agreement funding sign --amount ...` — no amount flag; it reads the signed contract.
- `kpass agent escalation status` without `--id` — required, and it takes `--id` (not `--escalation-id`).
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **`--seller`**: from `ksearch agent search` or the owner. Never this agent itself — a self-deal is exit 2.
2. **`--terms-file`**: a readable JSON file containing none of `schema`, `buyerAgentId`, `sellerAgentId`, `runtimeBinding`, `signatures`, `termsHash`.
3. **`--seller-key-id`**: only when the seller has more than one active key, copied verbatim from `ksearch agent keys`, from a row with `active: true`.
4. **`registrationBasis`, `price`, and optional `priceSchedule`**: use one active seller registration. With `{}` or omission, `price` is the signed settlement amount. With a non-empty schedule, the selected offering, currency, request quantities, negotiated deltas, resolved lines, resolved escrow, and decimal `price.amount` must agree.
5. **`--agreement-id`**: from a `propose` or `agreement list` response. Never fabricated.
6. **`--request-id`**: from a `session request` response.
7. **Amount caps**: both `--max-amount-per-tx` and `--max-total-amount` are required on `session request`, in USD, and should reflect the agreement's own price rather than a round number.
8. **`--rating`**: an integer 1–10. It is not range-checked locally; an out-of-range value fails at the schema gate as exit 8 rather than as a usage error.
9. **`--reason-code`**: non-empty, specific, and recorded — its keccak256 goes on-chain.
10. **Message bodies**: `--body` must be valid JSON, and `--body` and `--file` are mutually exclusive.
11. **`--seller-bps`** on `settle sign`: an integer in `0..10000`, derived from a count over bytes whose sha256 matched the signed `deliveryHash` — never a round number chosen to end the deal. `10000` is legal; from `DELIVERED`, prefer `agreement confirm` for a full release, which is what the CLI's own hint says.
12. **`--file`** on `settle submit`: an offer this agent has read and whose `sellerBps` its own count agrees with. Submitting is agreement to the number, and it is not reversible.

---

## Cross-Skill References

- **Prerequisites:** the **`buyer-agent-setup`** skill (active binding) and the **`buyer-find-seller`** skill (seller reference, published terms, pinned persona card).
- **The counterparty's side of this flow:** the **`seller-fulfill`** skill (`kagent`) — what the seller does between your propose and your confirm.
- **An after-the-fact lookup on an agreement or your own escalations, not a workflow step:** the **`buyer-agreement-history`** skill wraps `agreement proofs`, `evidence list`, and `escalation list`/`status` as standalone reads.
- **Paid HTTP endpoints instead of agreements:** the **`request-session`** and **`x402-execute`** skills in the `user` group.
- **Full wallet reference (balance, address, faucet) beyond Step 4's minimal usage:** the **`wallet-send`** skill in the `user` group.
- **Group contract (permission glob, envelope, exit codes):** [`buyer-agent/README.md`](../buyer-agent/README.md).
