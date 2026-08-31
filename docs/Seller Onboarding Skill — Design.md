# Seller Onboarding Skill — Design

**Status: draft · 2026-08-30 · Owner: Yusuke**  
Sources: brainstorm capture `~/.claude/brainstorms/agent_passport/2026-08-30-seller-onboarding-skill-redesign.md` (local, Yusuke's machine) · trial log `~/.claude/projects/-Users-not-so-fat-workspace-codes-agent-passport-recruiting-agent-claude/9ae0e25f-ca6e-446c-bdd7-f0e06fcf42ed.jsonl` (local) · trial substrate `recruiting-agent-claude/` (seller-acceptance, recruiting-intake skills). Supersedes: none.

**A seller who already runs an agent and knows nothing about Kite can put it up for business by answering questions only about their own business; the skill translates those answers into every platform artifact and proves the result with one live deal.**

_Orientation: this doc first shows why the current onboarding fails (§1–2), then the design that replaces it (§3–5), then boundaries, non-goals, and open items (§6–9). It seeds the development discussion; the raw Q&A behind every decision is in the brainstorm capture linked above._

## 1\. User story

**Who**: a developer who already runs a working agent (e.g. the recruiting agent) and knows their own business — but zero Kite vocabulary.  
**Wants**: to sell that agent's service to buyer agents on Kite.  
**So that**: the agent earns as an autonomous business entity.  
**Acceptance**: from nothing to _one deal seen working end-to-end_, without reading developer docs and without learning platform concepts up front.  
**Frequency**: once per seller, plus occasional reconfiguration.  
**Current pain**: the 2026-08-30 trial spanned ~4.5 hours (roughly 2.5 active, with an expert driving), hit 13 distinct friction events, and ended "Stop here — enough proof."

Near-term reality: the first people through this flow are pilot partners and demo evaluators — onboarding is the product's first impression. Designing for the developer persona serves them too.

## 2\. Why the current design fails

The official seller skills (`seller-agent-setup` 571 lines, `seller-fulfill` 422, `seller-serve` 193, `kite-seller` 258) are operator runbooks written for the _agent_: dense, mechanical, and — once inputs were locked — correct (4 minutes of flawless CLI execution in the trial). The failure is that **no layer owns the human conversation**. The implicit mental model is "the user knows our concepts and supplies parameter values." Trial evidence:

- Asked to pick a workflow template from 9 names, the user answered: _"honestly this information is impossible to understand, what template you have, what are the differences?"_ — and the platform could not help: 8 of 9 templates return `definition_available: false` from the API.
- Asked for 4 values at once (uid, template, offering, price), he could supply 2; the others he answered _"clarify what it is"_ and _"suggest something from this codebase."_ His actual input was a business intent — _"charge for my candidate sourcing based on success"_ — which no question had a slot for.
- The acceptance policy (a hard platform gate) was discovered only via an `owner_policy_restriction` error after publishing.
- The agent wrote the seller's standing orders (acceptance skill) without him noticing, triggering _"why installing logic into kite official skills? isn't it problematic?"_

The failed questions were parameter-level; the one question that worked instantly was intent-level ("what do you actually want to accomplish?"). That contrast is the design.

## 3\. Design decisions

| #   | Decision | Why |
| --- | --- | --- |
| 1   | New orchestrating skill, designed from scratch; existing skills stay as agent runbooks and repair paths | The intent is different (human interview vs agent runbook); rewriting `seller-agent-setup` would bloat an already-51KB file |
| 2   | Interview at intent altitude; every platform parameter is derived, never asked | Parameter questions demonstrably fail; intent questions demonstrably work |
| 3   | Seller decides exactly four things: identity, offer(s), deal shape, governance posture | Everything else (schemas, minor units, card publishing, payout wiring, policy JSON) the agent absorbs invisibly — it already did in the trial |
| 4   | Workflow-template choice is an _output_: skill interviews on characteristics (escrow? paid-regardless vs success-checked? buyer vs oracle evaluation? time windows?) against a manually curated table | 8/9 template definitions are API-invisible; the catalog is ~9 entries and grows slowly, so manual curation beats waiting on platform auto-explanation |
| 5   | Acceptance policy (the owner mandate) is derived, not taught: template allowlist and price bounds are computed from the offer answers, then handed to the owner as one dashboard approval | The mandate's only signals (templates, price floors/ceilings, capacity) are decisions the seller already made in the offer step; presenting it as a new concept is what caused the trial's confusion |
| 6   | Human price control = bounds + parking: public advertised price/range on the card, optional **private** reserve floor in the mandate; deals below the floor park for passkey approval | The card's negotiation range is public by design; the mandate floor is the only private lever, and it is real enforcement (parks even deals the model accepted). Per-quote pre-send approval does not exist today — filed as a platform consideration |
| 7   | Stated philosophy: bounds are an optional trust dial. Kite never decides prices for agents; it enforces bounds and carries messages. Making the agent answer the right price in a negotiation is the owner's responsibility. Fixed-price card = no negotiation, both sides use it as-is | Sets honest expectations about what the platform does and does not control |
| 8   | Seller-authored skills are **template + visible fill**, never invisible from-scratch authoring | The genuinely bespoke surface is tiny (2 markdown files, ~140 lines in the trial); from-scratch authoring produced phantom capabilities ("escalate on legal/ethical" — no such platform signal exists) and needed 3 review rounds; invisible authoring caused user alarm |
| 9   | Onboarding splits three layers: (1) mandatory parameters — interviewed; (2) per-step behavior — shipped as visible defaults, editable later; (3) deterministic controls — future SDK, out of scope | "You don't need to understand all the steps; we can guide you" is the promise. Interviewing all 7–8 interaction patterns up front would recreate the wall of concepts |

## 4\. The onboarding flow

The skill shows this phase map at the start and names the current phase at every step (the trial user lost orientation mid-flow: _"what are you doing now?"_).

```
0 detect → 1 identity → 2 offers → 3 deal shape → 4 governance
        → 5 standing orders → 6 publish → 7 serve → 8 verify
```

**0 — Detect existing state.** Read reality first (`kagent status`, existing registration, auth state) and branch. The trial began with a registration already live and a stale login; a blank-slate assumption breaks immediately.

**1 — Identity.** One question: the agent's public name. Permanence is explained _before_ asking; any destructive step (`kagent init --force` destroys the existing identity's key) gets an explicit stop sign.

**2 — Offers.** The skill reads the seller's codebase and _proposes_ offers (service, deliverable, price); the seller confirms or edits. Multiple offers per seller are intended; their mechanics are an open item (§9). Price questions are two intent-level asks per offer: "what do you want to advertise?" (public card) and, for negotiated offers, "what's the lowest you'd actually take? Deals below this come to you for approval — buyers never see this number" (private mandate floor, optional).

**3 — Deal shape.** The characteristics interview from decision #4. The template name appears only in the summary ("this maps to `standard/v1`"), never in a question.

**4 — Governance.** Derived, not asked (decision #5). The skill computes the mandate values, explains them as "the guardrail behind your agent — it can't be read or changed by the agent itself," and hands the owner the exact values plus a dashboard link for the passkey approval. One genuine question here: escalation posture — "your agent will auto-accept anything in-scope and priced, decline the rest; do you want anything routed to you first?" — with the honest note that there is no platform content/legal/ethical signal to lean on.

**5 — Standing orders review.** The skill fills the acceptance-skill scaffold from the interview answers and presents it: "these are your agent's standing orders; they live in your repo; you own them" — with the per-step behavior defaults (§5) shown in the same review. Explicit OK required before writing. This is also where the two-line explanation of skill layering lives (Kite's skills = the how-to-operate runbooks; _your_ skills = your business judgment).

**6 — Publish.** Mechanical; delegated to the existing runbooks. Readiness verified before declaring success (the fresh-seller default is fail-closed: no policy = refuses everything and "looks exactly like a broken agent").

**7 — Serve.** Handoff out of the onboarding conversation: `kagent serve` is a long-running process and must not die with the assistant. The skill prints the command, says what a healthy start looks like, and tells the seller what to come back with.

**8 — Verify.** Handoff to the Passport web Playground (or seller console): the seller, as a human, runs one deal against their own agent step by step. Never by improvising a buyer agent in the same conversation — two engines in one workspace confused even an expert trial. Onboarding is done when the seller has watched one deal settle.

## 5\. Per-step behavior: the five operations

The platform already delivers every buyer interaction as one of five typed operations. This is the boundary (§6) made concrete, and the frame for layer-2 defaults:

| Operation | What arrives | Seller policy slot today | v1 default shipped | Example override |
| --- | --- | --- | --- | --- |
| `request` | Pre-deal chat, quote asks, clarifications, sample requests | **None** (model improvises) | Quote per card; answer briefly on-topic; don't engage open-ended free chat | "Route FAQ to my fixed endpoint; demand requirement clarification before quoting" (cost control: don't spend my agent's tokens on non-paying chat) |
| `decide` | A proposal naming this seller | Acceptance skill (exists) | Auto-accept in-scope + priced; decline rest; escalate genuine can't-tell | "Escalate everything above 50 USDC" |
| `start` | Funded, activated work | Craft skill (exists) | Produce per craft skill | Effort bounds |
| `rejected` | Buyer rejected delivery | **None** | Revise once if the rejection is concrete; consent-refund when the objection is right; appeal only when the delivery clearly meets the signed criteria | "Consent-refund early rather than deliver garbage" — giving up in 5 minutes on an impossible 3-day job beats a garbage delivery for the agent's reputation; refund has business meaning even without money benefit |
| `closed` | Thread bookkeeping | **None** | Standard bookkeeping | —   |

Note on `rejected`: today the platform contract admits exactly three answers (redeliver / appeal / consent-refund) — there is no escalate-to-owner arm on this operation. Routing a rejected fork to the owner is the plan, but until the contract carries it, defaults must stay within the three arms.

Only 2 of 5 operations have a seller policy slot today. Closing that gap is implementable in the skills layer we own (extend the standard handler's contract — `kite-seller` — to read per-operation sections of the standing orders file); it does not require a platform API change. The `request` slot is the important one (cost posture, clarify-before-quote).

Layer 3 — deterministic controls (e.g. "stop answering a buyer whose pre-proposal questions already cost 10,000 tokens") — is **not built today** and is not expressible as skill prose; it needs status-aware code hooks (SDK). Named here as roadmap direction only.

## 6\. The boundary

**Platform owns the choreography: which typed items arrive, what answer shapes are valid, signing, deadlines, retries, fail-closed discard. The seller owns the answer policy at each step.** (A companion boundary of the same kind — where smart-contract state ends and workflow-node logic begins — was drawn in a 2026-08-29 discussion with Leon; reference to be linked when shared.)

One consequence the skill teaches explicitly: **formation is the last moment to say no.** After funding, declining becomes the refund/appeal lane — so "this is too complicated for the deadline" belongs in the `decide` filter (and in `request`, by quoting high or demanding clarification), with early consent-refund as the honorable exit when the seller only realizes it later.

## 7\. Things worth NOT doing

- **No buyer agent inside the onboarding conversation** for testing — the Playground is the verification surface.
- **The skill never runs** `kagent serve` **itself** — long-running process, user's terminal.
- **No platform feature for auto-explaining templates** — manual curation wins at 9 templates; if the catalog ever grows fast, that's demand worth celebrating and revisiting.
- **No per-quote pre-send human approval in v1** — bounds + parking is the control model; note that a sent quote is already disclosure, so this stays on the platform-consideration list for the negotiation era.
- **No interviewing all interaction patterns at onboarding** — defaults + later editing, per decision #9.
- **No rewrite of the existing runbook skills** — they work for their actual audience (the agent).

## 8\. Deliverable shape

One new skill (working name `seller-onboarding`), SKILL.md kept small; the curated template-characteristics table ships as a `references/` file loaded only during the deal-shape phase (progressive disclosure). Table columns per template: payment trigger, evaluation mode (buyer / oracle / none), escrow behavior, time windows, choose-this-when. Curation is manual, in advance, by product.

Interaction rules (normative for the skill): phase map always visible; one question at a time, each carrying its why and a recommended default; intent altitude with parameters derived; stop signs before permanent or destructive choices; detect existing state first; long-running processes and passkey ceremonies leave the conversation with explicit handoffs.

## 9\. Open items

| Item | Interim rule | Closes when |
| --- | --- | --- |
| Early give-up mechanism at `start` (is there an obligation-fail/refund verb before the rejected stage?) | Filter at `decide`; consent-refund at `rejected` | Per-step template designed against actual CLI verbs |
| Dev vs prod lane | Dev only (seller lane exists only on passport.dev.gokite.ai today) | Seller lane ships to prod |
| Template table curation owner | Drafted in the development discussion | Owner assigned |
| Multi-offer mechanics (how phases 2–4 repeat per offer; one mandate covering several offers) | Design the flow for one offer; treat additional offers as a repeat pass | Mechanics designed in the development discussion |
| Development discussion timing/owner | Yusuke schedules | Scheduled |
| Success metric | Re-run the trial persona; count friction events vs the 13 baseline; target: no developer-docs reading, no error-discovered concepts | Next trial run |
| Platform bugs from the trial (template `definition_available:false`, stale-JWT mid-flow re-login, URL→URN migration break, handler stdout fail-closed flakiness, buyer Activation settlement-vs-runtime-key signature bug) | Tracked outside this design | Filed to platform/eng |

## 10\. Platform-bug filing status (2026-08-30)

- **Filed**: buyer Activation settlement-vs-runtime-key signature bug → [GOK-1272](https://linear.app/gokite-ai/issue/GOK-1272) (High). Platform/CLI fix — no skill wording can change which key the binary signs with, and it blocks phase 8 (verify) if the Playground buyer flow shares the signing path.
- **Deliberately NOT filed yet — revisit after the skill re-implementation**: (⚠ do not forget)
  - **URL→URN schema migration break**: the new skill's phase 0 (detect existing state) will detect-and-repair invalid registration files as a cushion. After the skill ships, come back and decide the platform ask (deprecation window / auto-migrate in `registration validate`) based on how well the cushion holds.
  - **Stale owner JWT mid-flow**: the new skill's phase 0 auth pre-check + a clear "login expired, re-login" translation is the cushion. After the skill ships, come back for the platform ask (token refresh or longer-lived owner session, distinguishable expiry error).
  - Rule applied: if a user without our skills hits the same wall it is a platform bug — the skill layer cushions, it must not become the permanent patch.
- **Also still unfiled** (no owner decision yet): template `definition_available:false` (workaround = curated table, decision #4); handler stdout fail-closed flakiness (fix belongs in `kite-agent-handler` JSON extraction, not skills).

## 11\. Post-draft clarifications (2026-08-30, owner)

### Governance and escalation — precise scope of what exists today

Two mechanisms are supported now, each governing exactly one point in the deal:

- **Governance controls the seller's actions, and today exactly one action is governed: accept.** When a proposal arrives, the governance module (the owner mandate) decides which proposals the seller may accept — nothing else.
- **Escalation evaluates the buyer's messages, and today exactly one message type is evaluated: the buyer's proposal.** A predefined rule decides whether that proposal is escalated to the seller's owner instead of being auto-decided.

Design consequence: the onboarding interview must present the controls exactly at this scope — "your controls today act at the moment of accepting a proposal" — and must not imply platform-enforced governance over quoting, delivery, or chat. Those are per-step defaults (§5) without platform enforcement today; §5's slot-gap plan is the path to widening this scope.

### Pricing-chain consistency (new design requirement)

The public rate card, the quotes the agent gives during the negotiation phase, and the proposals the seller finally accepts **must never conflict with each other**. A buyer who receives a quote and is later refused on the matching proposal has a degraded experience even if each rule was individually "correct."

- Two links the platform already enforces: terms verification (a proposal must match the published card) and quote replay (a live recorded quote must be honored at accept — the four-condition match in the standard handler).
- **The dangerous link is quote vs the private reserve floor**: the agent cannot read the mandate, so it can quote a price the mandate later parks — from the buyer's side, the seller just broke its own quote. Onboarding must therefore derive _all_ pricing artifacts from one set of interview answers: the advertised card, the private reserve floor in the mandate, **and the same floor written into the seller's repo-side standing orders**, so the agent never quotes below what accept will honor.
- Acceptance test for the onboarding skill: no configuration it produces may let the agent **quote what it cannot accept, or refuse what it quoted**.

## 12\. Corrections from implementation (2026-08-31, verified against `passport` / `passport-cli` source during the skill build)

Three of this doc's factual premises changed between drafting (2026-08-30) and implementation (2026-08-31). The shipped skill (`seller-onboarding/`, spec at `docs/superpowers/specs/2026-08-31-seller-onboarding-skill-design.md`) is built against the corrected facts; this section keeps the draft honest without rewriting its history.

- **§4 phase 4 / decision #5 — the passkey approval for the mandate no longer exists.** The acceptance-policy write is a plain owner-JWT `PUT /v1/agents/{agent}/acceptancePolicy` (with optimistic-concurrency `version`, 409 on stale); the passkey step-up was deliberately removed in `passport` commit `39131fa9` (2026-08-24, "drop the passkey step-up") to unblock automated seller standup. Phase 4 hands the owner an in-conversation confirmation, not a dashboard passkey trip. (The package docstrings in `pkg/a2a/acceptance_policy.go` still describe the step-up — the docstrings are the stale part, not the behavior.)
- **Decision #4's premise ("8 of 9 templates return `definition_available: false`") is obsolete.** The catalog is now exactly 6 templates (`standard/v1`, `recruiting/v1`, `data-seller/v1`, `content-generator/v1`, `coding/v1`, `security-audit/v1`) — the 3 test templates (`fixed_outcome/v1`, `fast-clocks/v1`, `us-04-research-report/v1`) were removed (`passport` commit `25b4949f`), and every remaining template carries a full descriptor plus a platform-authored `presentation.name`/`presentation.summary`. The curated characteristics table survives (the descriptors still carry no evaluation-mode field, and "choose this when" remains product judgment), but it is now schema-grounded for the whole catalog rather than hand-written around missing definitions. The skill's deal-shape fallback for a no-fit seller is `standard/v1`.
- **§5's slot-gap plan needs no platform or CLI change at all — and is now shipped.** `kite-agent-handler` (which lives in `passport-cli`, `internal/agenthandler/`) already invokes the identical subprocess with identical file access for every operation; the `decide`-only read of the seller's standing orders was purely a prompt-level convention in `kite-seller/SKILL.md`. That skill now reads `request` and `rejected` sections too, and the onboarding skill's standing-orders scaffold ships all three slots (`closed` stays bookkeeping-only).
