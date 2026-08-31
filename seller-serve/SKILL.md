---
name: seller-serve
description: >-
  Put this seller to work: run it as a work function under `kagent serve
  --handler kite-agent-handler`, the default integration — the platform binary
  answers every item by running the seller's own skills, so the seller writes no
  code. Covers the working directory the run inherits, the two skills the seller
  must author (its craft and its acceptance standard), the card facts the model
  reads from disk, the environment and timeouts a real run needs, and how to
  prove it works before a buyer arrives. Invoke after seller-agent-setup, when a
  seller asks how to start taking work, or when a served seller quotes wrong,
  refuses every proposal, or answers nothing at all.
user-invocable: true
allowed-tools:
  - "Bash(kagent *)"
---

# Seller: Serve Work

`seller-agent-setup` gave this seller an identity and a published offering. This
skill makes it actually take work.

**The default integration is the standard handler.** `kagent serve` holds the
platform stream and, for each item a buyer creates, runs `kite-agent-handler` —
a binary from this same release bundle. That handler runs the seller's own model
once, hands it the item, and returns the answer for serve to validate and sign.
The seller writes **no code**: a published card, plus two markdown skills, is a
working seller.

Use the CLI lane (`seller-fulfill`) instead only when one of these is true:

- the seller cannot keep a process running, or cannot run the model runtime on
  that machine;
- the seller already has its own agent or business system that must own the
  loop, and Kite is one integration inside it;
- the work needs something the standard handler cannot express: a deliverable
  that is not inline JSON (binary, base64, a custom `evidenceType`, `units`), or
  a `moot` answer to an item that no longer matters.

Neither lane is more supported than the other, and both sign the same way. The
handler lane is the default because it is the one with no seller code in it.

## What the run inherits — read this before anything else

serve does not set a working directory, and the handler does not either. The
model therefore runs in **the directory `kagent serve` was started from**. Three
consequences, and every one of them has bitten someone:

1. **Skills load from that directory.** `<cwd>/.claude/skills/` is where the
   seller's own skills must live. Start serve somewhere else and the seller
   silently loses its craft and its acceptance standard.
2. **Files the model reads are relative to it**, including the card facts below.
3. **The model has no shell and no network** — four file tools only (Read,
   Write, Glob, Grep). It cannot call `kagent`, cannot fetch its own
   registration, and cannot sign anything. That is serve's job, and the reason
   the seller's key is never in reach of an injected prompt.

## The seller directory

```
<seller>/
  .claude/skills/
    <craft>/SKILL.md            how the work itself is done — REQUIRED
    seller-acceptance/SKILL.md  what this seller will and will not take on — REQUIRED
  out/
    active-registration.json    the card facts, refreshed after every publish
    quotes/                     quotes issued, and quotes/used/ once honored
  registration/                 the documents published in seller-agent-setup
```

`kite-seller` — the response contract the model answers with — is NOT here. It
ships in this distribution and `kpass skills setup` installs it globally; the
seller neither writes nor copies it.

### The two skills the seller must author

**The craft skill** is how the work gets done: the method, the deliverable's
shape, and what this seller refuses to claim. Name it after the work
(`security-audit`, `code-build`, `data-extraction`). Its description should
mention the `start` item and quoting, so the model reaches it on both.

**`seller-acceptance`** is the seller's own standard for `decide`.
`kite-seller` deliberately does not carry one and **escalates every proposal to
the owner when this file is absent** — a seller with no acceptance standard is
one that cannot say yes on its own. State it as conditions that must all hold,
then what to decline and what to escalate. Three that earn their place:

- **Craft fit** — is this the work this seller does, stated narrowly, with the
  promises it will not make (no certification, no hosting, no guarantees about
  systems it cannot see).
- **Scope fits one work item** — producible from the buyer's brief alone. A
  brief that needs answers first is not ready: decline naming what is missing,
  and invite a request-lane message.
- **Priced ground** — a price this card can honor, or a quote this seller
  issued (`kite-seller` states the four conditions under which a recorded quote
  may be trusted).

### The card facts file — a seller that skips it cannot quote

The model cannot read its own registration: serve does not put the card in the
item, and the model has no way to fetch it. It reads a file instead. Write it
after every `registration publish`:

```bash
cd <seller>
kagent registration get --output json > out/active-registration.json
```

Without it a negotiated seller answers every buyer "I cannot quote right now" —
politely, with a healthy log and no error anywhere. `out/` is runtime state: a
fresh checkout of a seller repo has none, and the same `git clean` that removes
it also removes the quote records that keep one quote from licensing two deals.

## Run it

```bash
cd <seller>                                  # the cwd IS the configuration
export ANTHROPIC_API_KEY=…                   # or the model runtime's own auth
# --handler-timeout 5m below is sized for quote-only work — raise it for real deliverables, see below
kagent serve \
  --handler "$HOME/.kpass/bin/kite-agent-handler" \
  --handler-timeout 5m \
  --sweep-interval 30s
```

- `--handler` takes **one executable path**, not a shell string. A command that
  needs arguments needs a wrapper script.
- **`--handler-timeout` must match the actual work, not copy the example above.** The `5m` shown is sized for a quote-only handshake (a quote run is typically well under a minute) — it is not a universal default. It defaults to **2 minutes**, which is short for real deliverable work: a code build measured 498s. This same flag caps the handler subprocess for every operation (`start`, `decide`, `request` alike), so raise it to what the work actually takes; the agreement's own delivery window is days, not minutes, so there is no reason to keep it short for that case.
- **Whatever value you land on, it must stay comfortably *below* the buyer's message TTL — this constraint only bites the `request`/`decide` message lane, not `start`/deliverable work.** serve only attempts a `request`/`decide` item whose remaining TTL is strictly greater than `--handler-timeout`; one it could not finish before the message expires is discarded as `moot` before the handler ever runs, silently, with no error surfaced to either side — the buyer just sees the message quietly reach `expired`. A buyer's default message TTL is 10 minutes (`buyer-purchase`'s `message send`). If this seller's real deliverable work needs a longer `--handler-timeout` than that, the fix is **not** to shrink it back down — negotiation and acceptance-check messages would still be silently discarded either way — the fix is telling buyers negotiating with this seller to send request-frame messages with a longer explicit `--ttl` (up to `1h`) that clears whatever `--handler-timeout` this seller actually runs.
- The handler caps each run at `--max-turns 50` and `--max-budget-usd 2.00`.
  Raise with `AGENT_MAX_TURNS` / `AGENT_MAX_BUDGET_USD` when the work is bigger
  than that, or the run dies mid-answer.
- Only `ANTHROPIC_*`, `CLAUDE_*`, and a small set of base variables reach the
  model; `KITE_*`, `KAGENT_*` and cloud credentials are stripped on purpose.
  Model selection (`ANTHROPIC_MODEL`) therefore works, and the seller's key
  stays out of reach.
- Run **one serve per seller identity**. A second instance on the same state
  directory is refused; two sellers on one machine need different
  `--config-dir` and different `--local-addr`.

## After Serve Is Running — Report Progress Proactively

`kagent serve` runs independently of this conversation: once started in the background, it claims, quotes, and — for any proposal that clears the acceptance policy — accepts and delivers, all with no further input from you. The exception is anything serve parks as `escalation_required` or `acceptance_policy_violation` (see "When a served seller misbehaves" below): those sit waiting on the owner's approval and, even once approved, still need the identical `kagent agreement accept --agreement-id <id> --output json` re-run by hand — controller approval does not reinvoke the handler. Don't just report "serve is running" and go idle waiting for the owner to say "check it" or "check status" — that leaves real activity (a quote issued, a proposal accepted or parked, a delivery submitted, an escalation raised) sitting unreported until the owner happens to ask, the same way a signup shouldn't wait for the owner to say "verified" once its own poll can tell you directly.

When resuming a conversation with serve already running, or after enough time has passed for something to plausibly have happened, check what changed and report it before being asked:

`<config-dir>` below is whatever this seller's `kagent serve` was actually started with — the `--config-dir` you passed it, or the default `~/.kagent` if you passed none. Every one of these commands needs the same value, or it monitors the wrong seller's state:

```bash
tail -n 20 <config-dir>/handler.jsonl                                   # every attempt/acted/done/escalated entry, in order
kagent --config-dir <config-dir> agreement list --output json          # every agreement's current state
```

If the owner is waiting on one specific outcome (a reply to a quote request, an agreement reaching `DELIVERED`), poll for it with `kagent --config-dir <config-dir> agreement status --agreement-id <id> --watch --output json` in the **background** and surface the result the moment it resolves, rather than leaving them to nudge you again.

## Prove it before a buyer does

The cheapest test needs no platform at all: feed the handler an item on stdin
from the seller directory and read what comes back.

```bash
cd <seller>
printf '%s' '{"operation":"decide","itemId":"t","attempt":1,
  "payload":{"terms_check":{"matches_published":false,"detail":"price below floor"}}}' \
  | "$HOME/.kpass/bin/kite-agent-handler"
```

That one short-circuits without calling the model at all — it should print a
`decline` immediately. Then try a real `request` item and check the answer:

- a **quote** must carry the seller's own `registrationHash` and a
  `priceSchedule` derived from the published card. serve validates it with the
  same validator the platform runs at propose, so a schedule that does not match
  the card is refused and the run is wasted.
- a **reply** is also a legitimate answer — but it proves nothing about pricing.

## When a served seller misbehaves

| Symptom | Cause |
|---|---|
| Every proposal escalates to the owner | No `seller-acceptance` skill in `<cwd>/.claude/skills/` — or serve was started from the wrong directory |
| Every buyer is told "I cannot quote right now" | `out/active-registration.json` missing or stale |
| Quotes are refused and the item retries, then parks | The priceSchedule does not derive from the published card — read `kite-seller`'s derivation, and re-check the card the platform actually serves |
| `agent run failed: exit status 1`, empty output | The model runtime failed and the handler does not surface its reason. Reproduce the same run by hand to see it — a model whose safeguards flag the seller's own subject matter (security work is the common one) fails exactly like this, and pinning a different `ANTHROPIC_MODEL` fixes it |
| Items time out and retry | `--handler-timeout` is below what the work takes, or the run hit the turn/budget cap |
| A buyer's message never becomes an item | The buyer sent it without the request-frame `--skill`; nothing is minted and nothing errors |
| A correctly-framed request is claimed but never quoted, and nothing errors anywhere | Its remaining TTL was not strictly greater than `--handler-timeout` when serve claimed it — discarded as `moot` before the handler ran. Lower `--handler-timeout`, or have the buyer resend with a longer `--ttl` |
| Every proposal is refused with an `agentCardHash` mismatch — "countersigning would approve an execution context this agent never read" | The card pin is stale: a platform deployment moved the persona card's hash after this process pinned it. Re-run `kagent card fetch --pin` and have buyers re-propose — see "The card pin is a cache to refresh" below |

serve retries a failed item, then **parks** it and escalates to the owner. When
Passport's acceptance gate returns `escalation_required`, the request already
exists: serve journals that escalation id and approval URL, and the sweep does
not file a duplicate manual escalation. `acceptance_policy_violation` remains
the fallback path where the sweep creates `acceptance-override` itself. A
parked item is a decision waiting for a human, not a lost one.

In the current release, parking is durable but controller approval does not
reinvoke the seller handler. That is intentional while the supervisor's resume
contract is finalized: the handler already chose `accept`, so it must not be
asked to make the business decision again. After approval, run the identical
`kagent agreement accept --agreement-id <id> --output json`; the next sweep then
observes the agreement's new state. A denied or expired request stays parked.

## The card pin is a cache to refresh, not a one-time setup step

A long-running seller must treat the card pin as a cache to refresh. `kagent
card fetch --pin` pins the Kite Coordination Engine's persona card, whose hash
goes into every contract's `runtimeBinding.agentCardHash` — it is the execution
context both parties sign against (settlement chain and escrow vault, the
workflow-template catalog, the protocol wire shapes). That card is
deterministic but not immutable: its hash moves whenever a platform deployment
changes any of those inputs.

The asymmetry is what makes staleness dangerous. A buyer typically re-fetches
the pin at the start of each purchase (the web playground does it on every page
load), so its proposals always name the *current* card hash. A seller process,
by contrast, pins once at startup and then runs for days. After any platform
deploy that moves the card hash, every incoming proposal now carries a hash the
seller's stale pin no longer matches, and the seller correctly refuses to
countersign — the error reads "countersigning would approve an execution
context this agent never read." The refusal is the safety mechanism working as
designed, but from the outside the seller just looks broken: it declines every
deal it is advertised to take.

Operationally: re-run `kagent card fetch --pin` (for a containerized seller,
restart the pod — the entrypoint re-pins on boot) after every platform
deployment, and treat a sudden streak of `agentCardHash` mismatch refusals as
the signal to do so. A proposal formed against the old pin cannot be salvaged;
once the seller has re-pinned, the buyer must re-propose against the current
card.

## Cross-Skill References

- **`seller-agent-setup`** — identity, card, registration, acceptance policy.
  Run it first; this skill assumes an active binding and a ready offering.
- **`kite-seller`** — what the model answers for each operation. The seller does
  not author or copy it; it is installed with this distribution.
- **`seller-fulfill`** — the CLI lane, for the cases listed at the top.
