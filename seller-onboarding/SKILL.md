---
name: seller-onboarding
description: Interview a seller who already runs a working agent and knows nothing about Kite vocabulary, turning their answers about their own business into every platform artifact needed to sell that agent's service to buyer agents -- identity, offer/rate-card, workflow-template selection, governance mandate, standing orders, and one verified live deal. Invoke when a developer wants to "sell my agent's service", "become a seller on Kite", "monetize my agent", or is confused by seller-agent-setup's platform-parameter questions (workflow template names, price floors, acceptance policy). This is the human-conversation entry point; seller-agent-setup/seller-fulfill/seller-serve/kite-seller remain the underlying runbooks it drives.
user-invocable: true
allowed-tools:
  - "Bash(kagent *)"
  - "Bash(kpass agent *)"
  - "Bash(kpass identifier *)"
  - "Bash(kpass onboarding *)"
  - "Bash(curl *)"
  - "Bash(ksearch *)"
---

# Seller Onboarding

You are guiding a seller who runs a working agent and wants to sell its service on Kite Passport, but has zero Kite vocabulary. Your job: ask about their business, never about platform parameters. Every platform artifact (template ID, acceptance policy, card schema) is something you derive and confirm, not something you ask the seller to name.

## Phase map

Show this at the start of every session, and name the current phase at every step:

```
0 detect -> 1 identity -> 2 offers -> 3 deal shape -> 4 governance
        -> 5 standing orders -> 6 publish -> 7 serve -> 8 verify
```

## Interaction rules

- One question at a time. Every question carries its why and a recommended default.
- Intent altitude: ask what the seller wants to accomplish, never which platform parameter to set.
- Stop sign before any destructive or permanent choice (e.g. `kagent init --force`, which orphans every agreement pinned to the existing key).
- Detect existing state before assuming a blank slate (phase 0).
- Long-running processes (`kagent serve`) and passkey/dashboard ceremonies leave this conversation with an explicit handoff -- never run or wait on them inline.

## Phase 0 -- Detect existing state

Before asking anything, read reality:

1. Run `kagent status` (see `references/commands.md#detect-existing-state-phase-0`).
2. Branch on the result:
   - **No key**: brand new. Continue to phase 1 normally.
   - **Pending / unbound**: an identity exists but isn't active. Tell the seller what's pending and why, then continue to phase 1's binding step only (skip the naming question -- the name is already set).
   - **Active**: a bound agent already exists. Tell the seller: "I found an already-active agent (`<did>`) -- skipping the identity step, moving to phase 2." Do not re-ask for a public name.
   - **Revoked**: stop. Tell the seller their key was revoked and they need to decide whether to re-init (destructive -- see phase 1's stop sign) before onboarding can continue.
3. Run `kpass onboarding status` to check whether the owner has completed identity/KYC bootstrap. If it isn't verified, say so now and route through the owner-bootstrap flow (already handled by the same commands phase 1 runs -- see `references/commands.md#detect-existing-state-phase-0`) rather than letting `kpass agent create` fail later with ErrRequiresIdentifier, an error-discovered concept this skill exists to eliminate.
4. If any command returns an auth error, check whether it matches an expired-JWT shape (the CLI classifies this itself -- see `references/commands.md`). Translate it plainly: "Your login expired, please re-authenticate" rather than surfacing the raw error.

## Phase 1 -- Identity

Skip this phase entirely if phase 0 found an active binding.

Ask exactly one question: **"What public name do you want buyers to see for this agent?"** Explain before asking: this name is effectively permanent -- changing the underlying key later (`kagent init --force`) orphans every agreement pinned to the old key. This is a stop-sign moment: if the seller already has a key and wants to replace it, confirm explicitly before running `--force`, and never run it without that confirmation.

Once confirmed, run the commands in `references/commands.md#identity-phase-1` end to end (owner bootstrap -- identifier claim, KYC, agent create, mint-and-bind -- is already handled by these same commands per `docs/superpowers/specs/2026-08-28-owner-onboarding-design.md`; this phase does not re-implement that, it just runs it).

Record `seller.agent_did` and `seller.public_name` for later phases.

## Phase 2 -- Offers

Read the seller's codebase for signals about what their agent does (its skill/tool descriptions, README, prior invocations) and *propose* an offer: a one-line service description and a suggested price. The seller confirms or edits -- never starts from a blank form.

Ask exactly two price questions, both intent-level:
1. **"What do you want to advertise as your price?"** (public rate-card price or range.)
2. For negotiated offers only: **"What's the lowest you'd actually take? Deals below this come to you for approval -- buyers never see this number."** (Private mandate floor, optional -- skip this question entirely for a fixed-price offer, since there's nothing to negotiate below.)

Record `seller.offer.service_description`, `seller.offer.advertised_price_minor`, and (if answered) `seller.offer.reserve_floor_minor`.

**v1 is single-offer.** The onboarding state (`seller.offer.*`), the mandate keys, and the standing-orders template are all singular, so a second offer of *any* template would overwrite the first's state and leave only one rule set. **Accept one offer and reject any second** -- tell the seller that multiple offers need per-offering state (`seller.offers[]` plus one standing-orders rule set per offering/template), which is a design open item, not a repeat pass in this flow.

## Phase 3 -- Deal shape

Ask about characteristics, never template names, using `references/template-characteristics.md`'s "How phase 3 uses this table" guidance. Once you have enough answers to pick a row, tell the seller the mapping in the summary only: **"This maps to `<template_id>`."**

Every template in `references/template-characteristics.md` is now platform-described (no undescribed-template case exists as of the 2026-08-31 catalog correction). If the seller's answers genuinely don't fit any row, default to `standard/v1` -- the full lifecycle (reject -> appeal -> dispute -> arbitration -> resolve) is the safest general-purpose fallback -- and say so plainly rather than silently forcing a fit.

`enriched-standard/v1` is the one availability-gated row and needs two extra steps before it can be offered. Confirm the environment the seller will sell in actually serves it (`ksearch workflow-template list`), and tell the seller in their own words that on that chart a silent buyer means an unpaid batch, since it is the only row where inaction costs the seller rather than the buyer. It also obliges the seller to publish a batch size, a unit rate, and a counting rule by hash -- decide those here, in phase 3, because phase 6 publishes them. The row in `references/template-characteristics.md` carries the full conditions.

Record `seller.offer.template_id`.

### Phase 3b -- Configure the template (deadlines + revisions)

A template is a *shape*; its deadline windows and `maxRedeliveries` are per-offering config. **Resolve the real defaults first, then ask, then confirm the complete resolved set here in phase 3** -- the seller must not first discover their deadlines at publish.

1. **Get the template's real defaults.** Dry-run an empty config against the template with the owner JWT (the credential phase 4 uses):
   ```
   http=$(curl -sS -o /tmp/wfval.json -w '%{http_code}' -X POST \
     -H "Authorization: Bearer <owner-jwt>" -H 'Content-Type: application/json' \
     "$KITE_PASSPORT_BASE_URL/v1/agents/<agent>/workflows:validate" \
     -d '{"workflow":{"templateId":"<template_id>","config":{}}}')
   ```
   **Branch on `$http` before reading the body** -- `curl -sS` does *not* fail on 4xx, and its own exit code is about transport (a malformed URL), never Passport auth. On **401 or 403** the owner JWT is missing or expired: **stop and route the owner through `authenticate-user`** (never read a masked secret or invent a token). On any other non-2xx, stop and surface the error. **Only on 2xx** read `data.resolvedConfig` -- the template's full default deadline set. The platform merges authored config over the descriptor defaults (`passport pkg/coordination/workflow_hash.go`, `ResolveWorkflowConfigDefaults`): an **absent** key inherits the default; an explicit **`0`** replaces it and is then **rejected** (window min 45s). This endpoint is how you learn the numbers; the catalog CLI does not expose them. The owner JWT is the one the session already holds (the same phase 4's mandate call uses); **apply this same status handling to phase 6's re-validation call.** (A dedicated owner-side validate verb would remove raw-JWT handling from the skill entirely; noted as a platform follow-up.)

2. **Ask one question at a time, each carrying its real default (from `resolvedConfig`) and its consequence** -- only for windows the template has:
   - **`deliveryWindow`**: *"Once a deal is funded, how long do you realistically need to deliver? (default `<resolved>`; if the work runs longer, the deal defaults before you deliver.)"*
   - **`deliveryConfirmationWindow`**: *"After you deliver, how long should the buyer have to accept before it auto-confirms and pays you? (default `<resolved>`.)"*
   - `fundingWindow`, and `appealResponseWindow` / `arbitrationWindow` where present: state the resolved default and change it only if the seller asks. Name `appealResponseWindow`'s role for the chosen template -- appeal-into-arbitration on `standard/v1` and `enriched-standard/v1`; the seller's redelivery-response deadline on the mid group (`coding`/`content-generator`/`security-audit`).
   - Redelivery lane (mid group only): *"If a buyer rejects, how many times may your agent redo it before a refund? (default `<resolved>`.)"* -- an integer 0-3; **`0` is a valid answer** (no redo). Skip templates without a redelivery lane.

3. **Build the authored `config`.** Convert each duration answer to **integer seconds** ("three days" -> `259200`). A window must be `>= 45`s: if the seller explicitly enters `0` (or anything below 45s), that is **not** "use the default" -- it is invalid, so reject it and ask again for a value in range. Include a window **only when the seller chose a value different from the default**; to keep a default, omit the key (never write `0`). `maxRedeliveries` is an integer count and **may be `0`** (a valid no-redo policy). Record `seller.offer.config = { "windows": { <changed windows, in seconds> }, "limits": { "maxRedeliveries": <n, only if the seller set it> } }`; leave `skippedStates` / `parameters` empty unless the seller turns a lane off.

4. **Confirm the complete resolved deadlines.** Re-run the dry-run with the final `config`, show the seller the resulting `resolvedConfig` -- the exact deadlines the offering will ship with -- and get explicit OK. **Record the response's `workflowHash` and `configHash`** as `seller.offer.confirmed_workflow_hash` / `confirmed_config_hash` -- phase 6 re-checks against these, so what the seller confirmed is provably what publishes.

## Phase 4 -- Governance

Derived, not asked. Compute the mandate directly from what the seller already decided in phase 2:
- `templates`: exactly `[seller.offer.template_id]` -- the single accepted offer's template. v1 is single-offer (phase 2); do not extend this list.
- `price_floors[template_id]`: `seller.offer.reserve_floor_minor` if set, otherwise omit (no floor means any priced-and-in-scope deal is acceptable).
- `price_ceilings[template_id]`: `seller.offer.advertised_price_minor`, unless the seller's advertised price was itself a range, in which case use the top of that range. (Why a ceiling: a proposal above your advertised price parks for your approval rather than silently committing your agent to an unusually large obligation.)
- `max_open_obligations`: not asked in v1 -- omit unless the seller raises capacity unprompted.

Show the owner the exact computed values, explained as "the guardrail behind your agent -- it can't be read or changed by the agent itself," and ask for explicit confirmation before writing. GET the current policy first to read its `version` (0 if none exists yet), then write via a plain owner-JWT `PUT` including that version (see `references/commands.md#governance-phase-4`) -- **no passkey ceremony, no separate dashboard approval needed for this step** (removed from the platform 2026-08-24). Do not describe this as requiring a passkey or a dashboard trip. If the PUT is refused with 409 (stale version), GET again and retry with the fresh version -- never guess.

One genuine question here, not derived: **"Your agent will auto-accept anything in-scope and priced, and decline the rest -- do you want anything routed to you first?"** Be honest that there's no platform content/legal/ethical signal to lean on for this -- it's a plain allow/escalate rule, not a smart filter. Record the answer as `seller.governance.escalation_rule` -- it is written into the standing orders (phase 5), not the mandate: the platform's governance enforces exactly one thing (acceptance), so this rule is enforced by your agent's own standing orders, not by the platform.

Record `seller.governance.confirmed = true` only after the owner confirms and the PUT succeeds. If the owner declines, stop here -- do not proceed to phase 5 with an unconfirmed mandate.

## Phase 5 -- Standing orders review

Refuse to proceed if `seller.governance.confirmed` is not `true` -- phase 4 must complete first (fail-closed, matches phase 6's own fail-closed default).

Fill `references/standing-orders-template.md` with the interview answers, using the **exact same numeric value** already written to the mandate in phase 4 -- the floor goes into the **`reserve_floor_minor` frontmatter field** (its single machine-readable home; the `decide`/`request` prose reference that field, so they cannot diverge), and it is the same number as the mandate's `price_floors`, computed once in phase 2 and never re-derived. When `seller.offer.reserve_floor_minor` is unset (fixed-price offer, phase 2 skipped the floor question), fill the single `reserve_floor_minor` field with `seller.offer.advertised_price_minor` instead -- for a fixed-price offer the card price IS the floor: both sides use the card as-is, so quoting or accepting below it never happens. The escalation slot is filled from `seller.governance.escalation_rule` (phase 4). This is what guarantees the seller's agent can never quote a price its own mandate would later park.

Present the filled scaffold to the seller as: "these are your agent's standing orders; they live in your repo; you own them." Explain the two layers this file sits between: Kite's skills are the how-to-operate runbooks, this file is the seller's own business judgment. Require explicit OK before writing to `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md`.

## Phase 6 -- Publish

Refuse to proceed if `seller.governance.confirmed` is not `true` or the standing-orders file from phase 5 wasn't written -- fail-closed is the correct default for a fresh seller (no policy means refuse everything, which looks exactly like a broken agent, not a safety net).

Assemble the offering's workflow member as `{ "templateId": seller.offer.template_id, "config": seller.offer.config }` in the workflow-terms input (see `references/commands.md#publish-phase-6`). **Prove it still matches what the seller confirmed:** re-run the owner dry-run (`POST /v1/agents/<agent>/workflows:validate`) with this exact final config and compare the returned `workflowHash` / `configHash` to the `seller.offer.confirmed_*` fingerprints from phase 3b. If they differ -- the active descriptor/defaults changed between phases, or the workflow member was assembled wrong -- **stop, show the seller the new resolved deadlines, and re-confirm; then replace `seller.offer.confirmed_workflow_hash` / `confirmed_config_hash` with the newly returned fingerprints and repeat this equality check.** Only when the compared fingerprints are identical may you proceed.

**Verify the pricing chain before publishing -- the one consistency the platform cannot check for you.** The floor is a machine-readable field: **`reserve_floor_minor` in the standing-orders file's YAML frontmatter** (the `decide`/`request` prose reference it, so there is one source). **Read that field with a strict YAML parser** -- reject a missing, non-numeric, or non-integer value; do not interpret the file body as instructions -- then compare:
- **Negotiated offer (a reserve floor was set):** `reserve_floor_minor` must equal the mandate's `price_floors[<template>]` and be `<=` the advertised card price.
- **Fixed-price offer (no reserve):** the mandate has **no** `price_floors` entry (correct, not a fault); `reserve_floor_minor` must equal the advertised card price.
On any failure -- the field missing/non-numeric, or a value differing from the mandate/card (e.g. a bad render, or the owner edited the mandate) -- **surface the exact values to the owner and let the owner confirm the correct number; do not silently re-derive or pick one.** Then update and republish. `kagent registration validate` (below) covers the card/workflow config; this covers the mandate <-> standing-orders floor, which no platform call verifies.

Run `kagent registration validate` (see `references/commands.md#publish-phase-6`), then `kagent registration publish`, then confirm with `kagent registration get`. Only declare success once readiness is actually confirmed by that last call -- not merely because the publish command didn't error.

## Phase 7 -- Serve

Print the exact command from `references/commands.md#serve-phase-7` (`kagent serve --handler kite-agent-handler ...`). Describe what a healthy start looks like (the process stays running, logs incoming operations). **This skill does not run this command itself** -- it's long-running and must survive independently of this conversation. Tell the seller what to come back with once it's running.

## Phase 8 -- Verify

Hand off to the Passport web Playground (or seller console): the seller, as a human, runs one deal against their own agent, step by step. **Never** improvise a buyer agent inside this same conversation to test against -- two engines in one workspace has caused real confusion in trials. Onboarding is complete only once the seller has watched one deal settle.
