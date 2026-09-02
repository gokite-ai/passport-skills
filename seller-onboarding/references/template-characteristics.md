# Template Characteristics

Loaded only during phase 3 (deal shape). The template name never appears in a question to the seller -- it appears only in the phase-3 summary ("this maps to `<template_id>`").

Three kinds of columns here:
- **Name / Summary** -- the platform's own `descriptor.presentation.name` and `.summary` fields (`pkg/a2a/templates/v1/*.json` in the `passport` repo). Authoritative, not curated -- quote them directly.
- **Structural** (Windows, Max redeliveries, Escalation path) -- also verified directly against the descriptor JSON. Re-read `pkg/a2a/templates/v1/*.json` in the `passport` repo if this table is ever suspected stale.
- **Choose this when** -- built from the Summary field plus the structural shape, not invented from scratch. There is still no `evaluationMode`/oracle field in any descriptor (confirmed 2026-08-31) -- evaluation is always buyer-driven, inferred from whether `REJECTING`/`REJECTED` states are configurable at all.

The catalog is these 6 templates as of 2026-08-31 (`origin/main`, `passport` repo) -- there is no undescribed/unavailable-template case to handle; every template a seller could pick has a real descriptor.

A 7th, `standard-enrichment/v1`, is listed separately below because it is **not served everywhere**: it installs into `local`, `dev`, and `staging` with the mutual-settlement work, and `prod` waits for the vault redeploy that ships `settleMutual`. Confirm it with `ksearch workflow-template list` against the environment the seller will actually sell in before offering it as a choice.

| Template ID | Name | Summary | Windows | Max redeliveries | Escalation path | Choose this when |
|---|---|---|---|---|---|---|
| `standard/v1` | Standard delivery | The full agreement lifecycle with delivery review, appeal, and third-party arbitration. | funding, delivery, deliveryConfirmation, appeal, arbitration | 0-3 | Full: reject -> appeal -> dispute -> arbitration -> resolve | Default choice for anything where a buyer might reasonably dispute quality and you want a formal appeal/arbitration escalation available as a last resort. |
| `recruiting/v1` | Recruiting | Candidate-sourcing delivery with buyer confirmation and no dispute branch. | funding, delivery, deliveryConfirmation | 0-3 | None: delivered or not; only `REFUNDING_UNDELIVERED` available | Candidate-sourcing / matching work where "delivered" is binary (a candidate list either arrived or didn't) -- no post-delivery quality dispute lane. |
| `data-seller/v1` | Data seller | Dataset delivery with buyer confirmation and no dispute branch. | funding, delivery, deliveryConfirmation | 0-3 | None: same shape as `recruiting/v1` | Data/dataset delivery where the artifact is verifiable at delivery time (hash match) and there's no meaningful "I don't like the data" rejection path. |
| `content-generator/v1` | Content generator | Content delivery with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: reject -> redeliver -> refund; no appeal/dispute/arbitration escalation | Creative/generated-content work where the buyer might reasonably ask for one redo, but a formal arbitration escalation is overkill. |
| `coding/v1` | Coding | Software-deliverable workflow with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: same shape as `content-generator/v1` | Code/implementation deliverables -- redeliver-on-reject fits "the tests didn't pass, try again" better than a dispute process. |
| `security-audit/v1` | Security audit | Audit-report delivery with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: same shape as `content-generator/v1` | Audit/report deliverables with a possible one-shot revision, no formal appeal process. |

## `standard-enrichment/v1` -- per-unit batches (availability-gated)

| Template ID | Name | Windows | Max redeliveries | Escalation path | Choose this when |
|---|---|---|---|---|---|
| `standard-enrichment/v1` | Enrichment batch | funding, delivery, deliveryConfirmation, appeal, arbitration | 0 (welded) | Full, plus a co-signed split (`kite.contract.settle_mutual`) available from `DELIVERED`, `REJECTED`, and `DISPUTED` | The deliverable is a **batch of countable units** and partial fulfilment is normal, not exceptional -- 100 enrichment records of which 62 come back valid is a routine outcome the seller expects to be paid 6200 bps for. |

Pick this row only when all three of these are true, because each one is a real obligation on the seller rather than a preference:

1. **The deliverable is per-unit and countable.** The buyer must be able to count acceptable units out of the delivered artifact without asking anyone. A single indivisible deliverable has nothing to apportion, and `standard/v1` is the right shape for it.
2. **The seller publishes `maxUnits`, the unit rate, and a content-addressed counting rule in its terms.** The platform never reads the delivered bytes and cannot check a count: `sellerBps` is derived by whoever counts, and the only thing that makes two independent counts agree is a rule both parties pinned by hash before the deal formed. Without it, the split is a negotiation with no shared basis, and a disagreement has nowhere to go but arbitration. This goes in the offering's rate card and workflow terms in phase 6, so decide it in phase 3.
3. **The seller accepts that silence favours the buyer.** This chart is **silence-is-refund**: the delivery-confirmation window lapsing with no buyer command refunds the buyer **in full**, the opposite of every other row in this table. It is the buyer-protective default of the chart, and it is deliberate -- a buyer holding a batch it has not counted should not be paying for it by inaction. The cost lands on the seller: it has **no unilateral escalation from `DELIVERED`** on this chart. It can ask (`kagent message send`) and it can sign a split for the buyer to co-sign, but nothing it does alone moves the deal, so a buyer that goes quiet cannot be pushed. Price the offering for that outcome. **`seller-fulfill`** Step 8 covers the operator's side.

Tell the seller point 3 plainly in the phase-3 summary, in their own terms ("if your buyer says nothing, you don't get paid"), before revealing the template id. It is the one place where this row is materially worse for the seller than `standard/v1`, and a seller who learns it after their first unpaid batch will not sell a second one.

The split verbs themselves (`kagent agreement settle sign` / `settle submit`) require `passport-cli` ≥ the release that ships `agreement settle`; see **`seller-fulfill`** for the availability check that does not depend on version strings.

## How phase 3 uses this table

Ask the seller about deal-shape *characteristics*, never the template name:
- "If a buyer isn't happy with what you deliver, do you want a chance to redo it, or is delivered-is-delivered?" -> maps to escalation-path column.
- "Could a delivery genuinely be disputed by a reasonable buyer, or is success obvious from the artifact itself?" -> distinguishes `standard/v1` (formal arbitration warranted) from the mid-lifecycle group.
- "Is what you deliver a batch of separate items, where some can be good and others not -- and would you expect to be paid for just the good ones?" -> a yes points at `standard-enrichment/v1`, and only then ask the two follow-ups that row requires: "How many items is one order, and how would your buyer tell a good one from a bad one?" (that answer becomes the published `maxUnits` and counting rule).

Then pick the matching row and only *afterward* reveal the template ID in the phase-3 summary.
