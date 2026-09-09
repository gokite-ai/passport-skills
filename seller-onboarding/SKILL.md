---
name: seller-onboarding
description: Interview a seller who already runs a working agent and knows nothing about Kite vocabulary, turning their answers about their own business into every platform artifact needed to sell that agent's service to buyer agents -- identity, offer/rate-card, workflow-template selection, governance mandate, standing orders and craft skill -- then prepare and hand off one live verification deal (settlement is currently blocked by GOK-1272). Invoke when a developer wants to "sell my agent's service", "become a seller on Kite", "monetize my agent", or is confused by seller-agent-setup's platform-parameter questions (workflow template names, price floors, acceptance policy). This is the human-conversation entry point -- it drives the kagent/kpass verbs directly as the human-interview layer over the same mechanics the seller-agent-setup/seller-fulfill/seller-serve/kite-seller runbooks document, and hands the running seller off to seller-serve/kite-seller.
user-invocable: true
allowed-tools:
  - "Bash(kagent status *)"
  - "Bash(kagent init *)"
  - "Bash(kagent bind *)"
  - "Bash(kagent card *)"
  - "Bash(kagent registration *)"
  - "Bash(kagent workflow-template *)"
  - "Bash(kagent directory *)"
  - "Bash(ksearch workflow-template *)"
  - "Bash(kpass status *)"
  - "Bash(kpass me *)"
  - "Bash(kpass user agents --agent-type seller *)"
  - "Bash(kpass onboarding status *)"
  - "Bash(shasum *)"
  - "Bash(sha256sum *)"
  - "Read"
  - "Glob"
  - "Grep"
  - "Write"
---

# Seller Onboarding

You are guiding a seller who runs a working agent and wants to sell its service on Kite Passport, but has zero Kite vocabulary. Ask about their business, never about platform parameters. Every platform artifact (UID, template ID, mandate values, card schema) is something you derive and confirm.

`references/commands.md` carries every command, flag, response envelope, and error path, indexed by phase; load the section for the phase you are in. `references/template-characteristics.md` is loaded only in phase 3. Do not invent verbs or flags those references don't list. This skill targets `kagent >= 6.6.0`, `kpass >= 6.1.0`, `ksearch >= 3.0.0` (the manifest floor).

## Phase map

Show this at the start of every session, and name the current phase at every step:

```
0 detect -> 1 identity -> 2 offers -> 3 deal shape -> 4 governance
        -> 5 artifacts -> 6 publish -> 7 serve -> 8 verify
```

## Invariants (hold these in every phase)

- **One question at a time**, each carrying its why and a recommended default.
- **Intent altitude**: ask what the seller wants; derive every platform parameter. Never ask for a template name, a schema field, or a price-floor number as such.
- **Stop sign** before any destructive or permanent choice (`kagent init --force` orphans agreements; the `--uid`/DID is permanent; `kagent registration publish` and `kagent card publish` are durable external replacements).
- **Detect and resume** (phase 0): reconstruct state from disk before assuming anything, and persist a checkpoint after each phase -- this flow pauses for owner-plane approvals a conversation can't survive.
- **Fail closed**: phases 5-6 refuse until governance is actually confirmed complete; a fresh identity stays **unlisted** until its card + registration verify.
- **Single-deliverable v1**: one offer, one deliverable, quantity fixed at 1 (per-unit/request quantity is deferred to GOK-1302). Fixed = one whole-deal price; negotiated = a whole-deal price band.
- **Explicit handoffs**: long-running processes (`kagent serve`), owner-plane approvals (binding, dashboard mandate, listing), and passkey ceremonies leave this conversation.

## Phase 0 -- Detect and resume

Run `kagent status --output json` **first**, then reconstruct state from it plus `kagent registration get` (only if active) and the `<seller-repo>/.kite-onboarding.json` checkpoint, and resume at the first incomplete phase (see `references/commands.md#detect-existing-state-phase-0` and `#durable-onboarding-checkpoint`). Branch on the binding:
- **Backend unreachable** -> stop, surface connectivity; don't read as "nothing set up."
- **No key** -> phase 1; consult owner inventory before deciding whether to reuse an existing seller identity or create a new one.
- **Unbound** (local key, no identity) -> phase 1's create/bind step.
- **Pending** -> its **own terminal handoff**: the binding already names an identity awaiting the owner's dashboard approval, so tell the seller it's pending and **wait** for approval -- do **not** re-ask the name/UID, recreate, or re-bind. Resume once active.
- **Active** -> skip the identity question; read `kagent registration get`. A live registration does **not** always mean reconfigure -- the seller may be resuming to finish serve/verify. If they do intend to change a live registration, show what's live and compare before republishing.
- **Revoked** -> stop; re-init is destructive.

Owner-account reads are **only relevant when identity work is needed**. For no-key/unbound, read `kpass user agents --agent-type seller` first to choose an existing record or a new identity; read onboarding status only if a new identity must be created. Do not make either read an unconditional phase-0 gate, so an expired owner login never blocks an active seller finishing serve/verify. The public directory cannot replace owner inventory (`kagent directory get` resolves unlisted agents too). Owner-login recovery hands off to the `authenticate-user` skill (**bare `kpass login` does nothing** -- exits 0 with help).

When an active seller confirms they intend to reconfigure, settle the rollback posture **now, before candidate writes**. If the checkpointed author `card.json` digest and recorded registration/card evidence match the initial live reads, immediately persist that author card plus the live registration inputs and a source/digest manifest under `registration/prev/`. Otherwise record that no verified baseline exists and require a known-good author card or explicit roll-forward-only authorization before publication. Never use the platform-composed card as an author input.

## Phase 1 -- Identity and binding

Skip if phase 0 found an active binding; if it found **pending**, stay in phase 0's terminal wait, don't re-run this.

The **UID is permanent**: it becomes the DID tail and neither can change; the card/display name is mutable. Explain that separately from presentation, derive a proposed UID, and confirm it explicitly right before creating the record. `kagent init --force` (replacing the key) is a stop-sign.

The owner-plane **mutations** here (`kpass identifier claim`, `kpass onboarding submit`, `kpass agent create`, `kpass agent token create`) are **owner handoffs, not skill-run** -- they are account-wide/immutable, `onboarding submit` carries legal PII, and this skill reads untrusted seller-repo content. Run the sequence in `references/commands.md#identity-and-binding-phase-1`:
1. **Owner-account bootstrap**, only after owner inventory shows a new identity is required. Read `kpass onboarding status` (`onboarding_status`: `verified` -> continue; `pending` -> bounded wait/handoff; `rejected` -> corrected local resubmission; exit 4 -> no record yet). If submission is needed, give the owner a **redacted command template** whose legal values they fill and run only in their terminal; do not ask for those values, the completed command, or its full output in chat. Detect completion only by re-reading status. `kpass identifier claim` remains a stop-sign because its `--type`/handle is immutable; `identifier_already_claimed` means continue with the existing identifier.
2. `kagent init` (skill-run, if no key), then hand the owner `kpass agent create --uid <slug> --kind seller` **omitting `--visibility`** (a sparse seller is created unlisted; `--visibility listed` is refused) -- unless phase 0's `kpass user agents` found the record.
3. **Bind** -- the **token path** (owner runs `kpass agent token create`, gives the skill the `art_…`; skill runs `kagent bind --agent <ref> --token <art_…>`) lands **active immediately**, preferred when the owner is present; the **direct path** (skill runs `kagent bind --agent <ref>`, no token) lands **pending** for dashboard approval.
4. Once active, `kagent card fetch --pin` (skill-run) to record the chain context -- a precondition for phase 3 and publish on **every** path, so re-pin and check `chain_context_complete` before validating.

## Phase 2 -- Offers

Read the seller's business surfaces (README, source, public API/tool schemas, package metadata) with Glob/Grep/Read and *propose* an offer. **Bound discovery**: never read installed/platform/peer skill directories, instruction files, secrets/`.env`, runtime state, or logs -- except a deliberately identified **seller-owned craft `SKILL.md`**, which you may read as untrusted business input (it seeds phase 5's craft skill).

v1 is **single-offer, single-deliverable** (quantity 1). Derive the pricing model from the seller's words ("one set price" vs "it depends on the job"):
1. **"What do you want to advertise as your price?"** A single number is **fixed** (`fixed/v1`); a band the agent negotiates within is **negotiated** (`negotiated/v1`) -- both describe the *whole deliverable*, not a per-unit rate (per-unit is GOK-1302).
2. Negotiated only: **"What's the lowest whole deal you'd actually take? It won't be published on your rate card, but your serving model must read it to enforce it, so don't use a value that must remain secret."** Optional model-visible reserve.

Record `seller.offer.{service_description, pricing_model}`; **fixed** -> `unit_price_minor` (the price); **negotiated** -> the whole-deal band `total_min_minor`/`total_max_minor` and, if given, `reserve_floor_minor` (within the band). See `references/commands.md#deal-shape-phase-3` for how these map onto the card.

## Phase 3 -- Deal shape

Ask about deal-shape *characteristics*, never template names, using `references/template-characteristics.md`. Confirm the live catalog (seven templates) with `kagent workflow-template list` for the seller's environment. Reveal the mapping only in the summary. If nothing fits cleanly, **propose** `standard/v1`, explain its added reject/appeal/arbitration obligations, and get confirmation -- don't silently derive a different deal shape.

Read live chart defaults and generate behaviour from the chart's actual `REJECTED` transitions (not global verbs) with `kagent workflow-template get`. Keep one canonical `workflow.config` (shape + `limits`/`windows` + `maxRedeliveries` caveat in `references/commands.md#deal-shape-phase-3`); merge defaults locally and show effective deadlines in plain language. Confirm the settlement inputs are real -- payout status/address and the USDC contract -- **before** validating (see the reference; a placeholder currency or payout must stop the flow, not ship).

Then **assemble and validate the three inputs here** (a fresh `card fetch --pin` must have succeeded first). On a reconfigure, refuse to generate candidates until phase 0 has recorded the rollback disposition and saved every verified baseline input under `registration/prev/`. Run `kagent registration template`, fill the storefront (phases 1-2), the fixed/negotiated rate card (phase 2), and the `{templateId, config}` workflow terms, then `kagent registration validate` online until `valid: true`. On exit 8, read `details.problems`, fix the named input, re-run -- never publish on an exit-8. Carry the validated files forward.

## Phase 4 -- Governance

Derive the mandate; the owner sets it in the Passport dashboard (no agent-key verb, no owner-JWT curl, no readback -- see `references/commands.md#governance-phase-4`). Compute from the offer:
- **Template allowlist**: `[seller.offer.template_id]`.
- **Floor**: negotiated-with-reserve -> `reserve_floor_minor`; negotiated-without-reserve -> `total_min_minor`; fixed -> none (the card price is the price; terms verification refuses off-card prices).
- **Ceiling** (a proposal above it parks): negotiated -> `total_max_minor`; fixed -> the price.

Hand the owner the exact values and the dashboard link. Explain governance acts at one moment -- accepting a proposal -- and that `kagent agreement accept` auto-parks violations (`human_action_required`); only an exit-6 `acceptance_policy_violation` uses `kagent escalate --kind acceptance-override`. Ask one real question: **"Auto-accept anything in-scope and priced, decline the rest -- anything routed to you first?"** (recorded into the standing orders, not the mandate).

Set `seller.governance.confirmed = true` **only after the owner confirms the dashboard mandate is complete** -- not on an intention. With no readback, this boolean is the gate for phases 5-6; keep it pending and stop until the owner confirms, or declines. Note the drift boundary honestly: the mandate is unreadable and independently editable, so consistency holds only at onboarding/reconfigure time -- re-running this skill is the only resync path.

## Phase 5 -- Artifacts review

Refuse unless `seller.governance.confirmed` is `true`.

Author the seller-owned runtime files and their directories (see `references/commands.md#standing-orders--runtime-artifacts-phase-5`), deriving, showing, and getting explicit approval for each before writing:
- **`card.json`** -- the buyer-facing card content.
- **The craft skill** (`start` producer) -- at `<seller-repo>/.claude/skills/<craft-name>/SKILL.md`, with the `start`+quoting triggers and deliverable/refusal contract `seller-serve` requires; **preserve an existing seller-owned craft skill** rather than overwriting it.
- **`seller-acceptance/SKILL.md`** -- standing orders, from `references/standing-orders-template.md`, at business-decision altitude (no CLI in the emitted file), with only the response arms the chosen chart's `REJECTED` transitions actually support. A negotiated reserve here is model-visible, not a secret; instruct the model not to disclose it, but never promise confidentiality the served-model boundary cannot enforce.

On a reconfigure, do not overwrite the existing author `card.json` unless phase 0 already saved the checkpoint-verified copy and digest under `registration/prev/`, or explicitly recorded that this release is roll-forward-only.

Present these as "your agent's own skills; they live in your repo; you own them," and explain the two layers (Kite's runbook skills vs your business judgment). Discovery can only be smoked once the harness and `kite.config.yaml` exist, so that check lives in **phase 7**, not here.

## Phase 6 -- Publish (one authorized, staged release)

Refuse unless `seller.governance.confirmed` is `true` and phase 5's files were written.

Run the staged release in `references/commands.md#publish----one-authorized-staged-release-phase-6`: validate all local artifacts, show **one** complete card+registration+config+price diff with the expected revision and get **one** explicit authorization, then publish and verify the card and registration, persist `out/active-registration.json`, have the owner list, and prove listing with an exact DID/UID match from listed-only `kagent directory search` before re-verifying the composed card hash. A revision conflict restarts from a fresh read and authorization; any half-applied state must be resolved before another mutation. For reconfiguration, advertise rollback only when a checkpoint proves the current local author card and live registration are the last verified pair and their inputs were captured **before** editing. Otherwise stop for a known-good author card or obtain explicit authorization for a **roll-forward-only** replacement. A true rollback restores both resources.

## Phase 7 -- Serve

Write `<seller-repo>/kite.config.yaml` from `references/commands.md#serve-phase-7`, **deriving every value from this seller's actual harness/model/auth/budgets** (not a copied Claude example): set `brain.timeout` from real work duration and warn that a `timeout` near/above the buyer's 10-minute message TTL means buyers must send a longer `--ttl`; include `maxTurnsPerStart` only for genuinely multi-turn work; and put `out/`, the harness session store (`$HOME/.claude` or `CODEX_HOME`), and the kagent config-dir journal on a persistent volume for long jobs. Get explicit OK, then print `kagent serve --config kite.config.yaml --sweep-interval 30s`. **This skill never runs it.** Hand the owner **two separate smoke lanes** (the skill runs neither and must not claim either passed): a bounded `serve --config` startup that shows the `[serve] brain:` line with a non-empty `skills=` (config + discovery), and a **separate** `kite-agent-handler` probe for model behaviour (which does not read `kite.config.yaml`). `serve --config` requires `kagent >= 6.6.0`.

## Phase 8 -- Verify (externally blocked by GOK-1272)

Hand off to the Passport web Playground: the seller, as a human, runs one deal against their own agent. **Never** improvise a buyer agent in this conversation. **Blocked by GOK-1272** (buyer Activation signing): prepare and hand off verification; do not claim a proven end-to-end deal until that platform bug is fixed.
