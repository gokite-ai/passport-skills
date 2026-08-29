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
kagent serve \
  --handler "$HOME/.kpass/bin/kite-agent-handler" \
  --handler-timeout 10m \
  --sweep-interval 30s
```

- `--handler` takes **one executable path**, not a shell string. A command that
  needs arguments needs a wrapper script.
- `--handler-timeout` defaults to **2 minutes**, which is short for real work: a
  code build measured 498s. Set it to what the work actually takes; the
  agreement's own delivery window is days, not minutes.
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

## Cross-Skill References

- **`seller-agent-setup`** — identity, card, registration, acceptance policy.
  Run it first; this skill assumes an active binding and a ready offering.
- **`kite-seller`** — what the model answers for each operation. The seller does
  not author or copy it; it is installed with this distribution.
- **`seller-fulfill`** — the CLI lane, for the cases listed at the top.
