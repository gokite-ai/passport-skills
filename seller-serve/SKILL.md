---
name: seller-serve
description: >-
  Put this seller to work: run it under `kagent serve --config
  kite.config.yaml`, the default integration — one binary holds the platform
  stream and the signing key and answers every item by running the seller's own
  model with the seller's skills and MCP tools, so the seller writes no platform
  code. Covers the seller directory the run happens in, the config file, the two
  skills the seller must author (its craft and its acceptance standard), the
  card facts the model reads from disk, the budgets and timeouts a real run
  needs, and how to prove it works before a buyer arrives. Invoke after
  seller-agent-setup, when a seller asks how to start taking work, or when a
  served seller quotes wrong, refuses every proposal, or answers nothing at all.
user-invocable: true
allowed-tools:
  - "Bash(kagent *)"
---

# Seller: Serve Work

`seller-agent-setup` gave this seller an identity and a published offering. This
skill makes it actually take work.

**The default integration is `kagent serve --config kite.config.yaml`.** One
binary holds the platform stream and the seller's signing key and, for each
item a buyer creates, runs the seller's own model in-process: the harness the
config names (Claude Code or Codex), in the seller directory, with the seller's
skills and MCP servers, one conversation per agreement. The model decides and
produces; serve validates, signs and publishes. The seller writes **no platform
code**: a published card, a short config file, plus two markdown skills, is a
working seller. Requires kagent **6.6.0** or later (`kagent --version`).

Use the CLI lane (`seller-fulfill`) instead only when one of these is true:

- the seller cannot keep a process running, or cannot run the model runtime on
  that machine;
- the seller already has its own agent or business system that must own the
  loop, and Kite is one integration inside it;
- the work needs something the served brain cannot express: a deliverable
  that is not inline JSON (binary, base64, a custom `evidenceType`, `units`), or
  a `moot` answer to an item that no longer matters.

Neither lane is more supported than the other, and both sign the same way. The
served lane is the default because it is the one with no seller code in it.

`kagent serve --handler <executable>` is the same seam with a process boundary:
serve hands each item to a program of the seller's (the bundled
`kite-agent-handler` is one) on stdin and reads the answer on stdout. It stays
available as an integration and debugging seam, not as the product path — reach
for it only when a seller must run its brain as a separate process it already
owns. `kite-seller` documents the answer contract both share.

## Where the run happens — read this before anything else

The config file's directory **is** the seller directory: serve runs the model
there for every item, whatever directory serve itself was started from. Three
consequences, and every one of them has bitten someone:

1. **Skills load from that directory.** The seller's own skills live in
   `<seller>/.claude/skills/`, or in the directory `tools.skills` names, which
   serve links under both harnesses' skill paths (`.claude/skills`,
   `.agents/skills`) at startup. Point `--config` at a file somewhere else and
   the seller silently loses its craft and its acceptance standard.
2. **Files the model reads are relative to it**, including the card facts below.
3. **The model is open by design, with one hard boundary.** It has the built-in
   file and web tools, the seller's MCP servers and the network. It has **no
   shell** unless the config opts one in (`tools.allowed`), cannot call `kagent`
   or `kpass`, cannot read the signing key — serve's state directory and the key
   file are denied to its file tools — and never sees `KAGENT_*`/`KITE_*`
   variables. Signing is serve's job, and the reason the seller's key is never
   in reach of an injected prompt.

## The seller directory

```
<seller>/
  kite.config.yaml              the brain: harness, model, budgets, sessions, tools — REQUIRED
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
item, and the registration read needs the agent's key, which the model never
holds. It reads a file instead. Write it
after every `registration publish`:

```bash
cd <seller>
kagent registration get --output json > out/active-registration.json
```

Without it a negotiated seller answers every buyer "I cannot quote right now" —
politely, with a healthy log and no error anywhere. `out/` is runtime state: a
fresh checkout of a seller repo has none, and the same `git clean` that removes
it also removes the quote records that keep one quote from licensing two deals.

## The config file

`kite.config.yaml` sits in the seller directory and describes the brain. Every
key is checked at startup — a misspelled key is refused rather than silently
becoming a default:

```yaml
brain:
  harness: claude-code          # claude-code | codex
  model: claude-sonnet-5        # optional; any model the harness (or baseUrl) serves
  apiKeyEnv: ANTHROPIC_API_KEY  # the NAME of the variable holding the key — never the key itself
  maxSteps: 30                  # claude-code --max-turns
  maxBudgetUsd: "2.50"          # claude-code --max-budget-usd, as a string
  timeout: 5m                   # per-item budget; default 5m — see below
  maxTurnsPerStart: 48          # optional; how many `working` turns one start may spend
  session: per-agreement        # per-agreement | none
tools:
  skills: ./skills              # optional; omit when the skills already live in .claude/skills/
  mcpServers:                   # optional; the seller's own deterministic tools
    - { name: pricing, command: node, args: ["dist/mcp.js"] }
    - { name: backend, url: https://my-service/mcp }
  # allowed: [...]              # optional; replaces the built-in tool set — see "Tools"
```

- **`harness`** picks the model runtime: `claude-code` (the `claude` binary on
  `PATH`) or `codex` (the `codex` binary). `baseUrl` points codex at any
  OpenAI-compatible endpoint and claude at `ANTHROPIC_BASE_URL`; `effort`
  (`low|medium|high|xhigh`) is codex reasoning effort.
- **`apiKeyEnv`** names the variable; serve hands its value to the harness under
  the variable that harness reads. If it is unset when serve starts, serve warns
  and every item will fail at the model — export it first.
- **`session: per-agreement`** resumes one conversation across all of an
  agreement's items (`decide` → `start` → `rejected`/`settle` → `closed`), so
  the model that delivered is the one that answers the rejection. Sessions are
  recorded under `<config-dir>/brain/`; a session the harness no longer has is
  replaced by a fresh one. `none` starts every item cold.
- **`maxSteps` / `maxBudgetUsd`** cap each claude run. A run that hits either
  dies mid-answer and the item retries, so size them to the work, not to the
  example.
- **`maxTurnsPerStart`** (default 48) bounds a job that does not fit in one
  run. **It needs `kagent` 6.6.0 or newer — do not add the key under an older
  binary**: unknown config keys are refused at startup, so serve will not come
  up at all with it present. The brain may answer a `start` with a `working`
  checkpoint instead of a deliverable; serve journals it, signs nothing, and brings the same `start`
  back with the recent checkpoints in `history` (bounded at 64 KiB — the oldest
  are dropped first). A turn is not a retry — it
  spends no attempt — but the turns are capped, and spending them parks the
  item for you with the last checkpoint attached.

**If this seller takes long jobs, put its state on a real volume.** Two
directories decide whether a job survives a deploy: the seller directory (where
the brain writes its files, normally under `out/`) and the harness's own session
store (`$HOME/.claude` for claude-code, `CODEX_HOME` for codex). On an
`emptyDir` both vanish when the pod is recreated, and the next turn starts from
the checkpoint text alone — acceptable for a five-minute item, not for a job
that spans hours. Mount them, and keep `<config-dir>` (the journal, where the
turns themselves live) on the same persistent volume. While a start is still
turning, serve escalates to you once the delivery deadline gets closer than one
more turn plausibly needs — that escalation is your cue to look, not a failure.

### Tools — open by default, one boundary

The built-in set is every file and web tool (Read, Write, Edit, Glob, Grep,
WebFetch, WebSearch and the rest) plus every MCP server the config lists.
`tools.allowed` **replaces** the built-in set with an explicit list — use it to
narrow, or to opt `Bash` in; the MCP servers stay available either way. Opting
Bash in is a deliberate choice serve warns about at startup: Claude's deny rules
do not inspect shell commands, so a shell can read the signing key (and every
file this user can read) past every rule. Keep it only if this seller accepts
that. Codex ignores `tools.allowed`: its sandbox is `workspace-write` with the
network on, and the boundary there is the environment.

Only `ANTHROPIC_*`, `CLAUDE_*`, `OPENAI_*`, `CODEX_*` and a few base variables
(`HOME`, `PATH`, `USER`, `LOGNAME`) reach the model, plus the key `apiKeyEnv`
names. `KITE_*`, `KAGENT_*` and cloud credentials are stripped on purpose.

## Run it

```bash
cd <seller>
export ANTHROPIC_API_KEY=…                   # whatever brain.apiKeyEnv names
kagent serve --config kite.config.yaml --sweep-interval 30s
```

serve prints one line describing the brain it loaded — `[serve] brain:
claude-code model="…" session=per-agreement timeout=5m0s skills="" mcp=1` — and
a `[serve] warning:` line for each problem it tolerates (an unset key variable,
a `timeout` at or above the default message TTL, Bash opted in). Read those
before a buyer does.

- `--handler-timeout` is refused with `--config`: the per-item budget is
  `brain.timeout`. `--handler-parallel` (concurrent items, default 4) and
  `--handler-retries` (attempts before an item parks, default 5) apply to both
  lanes.
- **`brain.timeout` must match the actual work, not copy the example above.**
  The default `5m` is sized for a quote-only handshake (a quote run is typically
  well under a minute) — it is not a universal figure. It caps every operation
  (`start`, `decide`, `request` alike), and real deliverable work is longer: a
  code build measured 498s. Raise it to what the work actually takes; the
  agreement's own delivery window is days, not minutes.
- **Whatever value you land on, it must stay comfortably *below* the buyer's message TTL — this constraint only bites the `request`/`decide` message lane, not `start`/deliverable work.** serve only attempts a `request`/`decide` item whose remaining TTL is strictly greater than `brain.timeout`; one it could not finish before the message expires is discarded as `moot` before the model ever runs — no answer is ever produced. serve logs the moot on its own output, and for a request whose claim is still live it relays a `reply/v1` decline naming the TTL-vs-budget mismatch, so the buyer sees `replied` with a reason instead of a bare `expired`. Either way the deal doesn't advance: a buyer's default message TTL is 10 minutes (`buyer-purchase`'s `message send`), which is why serve warns at startup about a `timeout` of 10 minutes or more. If this seller's real deliverable work needs a longer `timeout` than that, the fix is **not** to shrink it back down — negotiation and acceptance-check messages would still be discarded either way — the fix is telling buyers negotiating with this seller to send request-frame messages with a longer explicit `--ttl` (up to `1h`) that clears whatever `timeout` this seller actually runs — sent as a fresh message (a new or omitted `--idempotency-key`), since reusing the expired send's key just returns the original message with its old TTL.
- After every delivery the brain produced, serve publishes a
  `runtime-declaration` evidence record on the agreement (`{harness, model,
  assurance: "declared"}`): the seller's declared provenance, signed by the
  seller's key, readable by the buyer. A declaration, not a proof.
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

The cheapest test needs no platform at all: the bundled `kite-agent-handler`
answers one item envelope on stdin, running Claude Code with the same skills
from the same directory. Feed it an item from the seller directory and read
what comes back.

```bash
cd <seller>
printf '%s' '{"operation":"decide","itemId":"t","attempt":1,
  "payload":{"terms_check":{"matches_published":false,"detail":"price below floor"}}}' \
  | "$HOME/.kpass/bin/kite-agent-handler"
```

That one short-circuits without calling the model at all — it should print a
`decline` immediately. Then try a real `request` item and check the answer. This
proves the skills and the card facts; it does not read `kite.config.yaml`, so
the config itself is proven by starting serve and reading its startup line and
warnings. Then check the answer:

- a **quote** must carry the seller's own `registrationHash` and a
  `priceSchedule` derived from the published card. serve validates it with the
  same validator the platform runs at propose, so a schedule that does not match
  the card is refused and the run is wasted.
- a **reply** is also a legitimate answer — but it proves nothing about pricing.

## When a served seller misbehaves

| Symptom | Cause |
|---|---|
| Every proposal escalates to the owner | No `seller-acceptance` skill in `<seller>/.claude/skills/` (or under `tools.skills`) — or `--config` points at a file outside the seller directory |
| Every buyer is told "I cannot quote right now" | `out/active-registration.json` missing or stale |
| Quotes are refused and the item retries, then parks | The priceSchedule does not derive from the published card — read `kite-seller`'s derivation, and re-check the card the platform actually serves |
| Every item fails at the model, empty output | The model runtime failed. Reproduce the same run by hand in the seller directory (`claude -p` / `codex exec`) to see why — an unset `apiKeyEnv` variable is the common cause (serve warned at startup); a model whose safeguards flag the seller's own subject matter (security work is the other common one) fails exactly like this, and pinning a different `brain.model` fixes it |
| Items time out and retry | `brain.timeout` is below what the work takes, or the run hit `maxSteps` / `maxBudgetUsd` |
| serve refuses to start naming a config key | `kite.config.yaml` has a misspelled or unsupported key; every key is checked so a typo cannot become a default |
| `[serve] warning: tools.allowed opts Bash in` | Deliberate: a shell reads the signing key past the deny rules. Remove `Bash` from `tools.allowed` unless this seller accepts that |
| A buyer's message never becomes an item | The buyer sent it without the request-frame `--skill`; nothing is minted and nothing errors |
| A correctly-framed request is claimed but never quoted | Its remaining TTL was not strictly greater than `brain.timeout` when serve claimed it — discarded as `moot` before the model ran; serve logs the moot and the buyer receives a `reply/v1` decline saying so. Lower `brain.timeout`, or have the buyer resend with a longer `--ttl` as a fresh message (a new or omitted `--idempotency-key` — a reused key returns the expired original) |
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
