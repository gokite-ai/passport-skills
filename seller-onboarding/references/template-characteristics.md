# Template Characteristics

Loaded only during phase 3 (deal shape). The template name never appears in a question to the seller -- it appears only in the phase-3 summary ("this maps to `<template_id>`").

Three kinds of columns here:
- **Name / Summary** -- the platform's own `descriptor.presentation.name` and `.summary` fields (`pkg/a2a/templates/v1/*.json` in the `passport` repo). Authoritative, not curated -- quote them directly.
- **Structural** (Windows, Max redeliveries, Escalation path) -- also verified directly against the descriptor JSON. Re-read `pkg/a2a/templates/v1/*.json` in the `passport` repo if this table is ever suspected stale.
- **Choose this when** -- built from the Summary field plus the structural shape, not invented from scratch. There is still no `evaluationMode`/oracle field in any descriptor (confirmed 2026-08-31) -- evaluation is always buyer-driven, inferred from whether `REJECTING`/`REJECTED` states are configurable at all.

The catalog is exactly these 6 templates as of 2026-08-31 (`origin/main`, `passport` repo) -- there is no undescribed/unavailable-template case to handle; every template a seller could pick has a real descriptor.

| Template ID | Name | Summary | Windows | Max redeliveries | Escalation path | Choose this when |
|---|---|---|---|---|---|---|
| `standard/v1` | Standard delivery | The full agreement lifecycle with delivery review, appeal, and third-party arbitration. | funding, delivery, deliveryConfirmation, appeal, arbitration | 0-3 | Full: reject -> appeal -> dispute -> arbitration -> resolve | Default choice for anything where a buyer might reasonably dispute quality and you want a formal appeal/arbitration escalation available as a last resort. |
| `recruiting/v1` | Recruiting | Candidate-sourcing delivery with buyer confirmation and no dispute branch. | funding, delivery, deliveryConfirmation | 0-3 | None: delivered or not; only `REFUNDING_UNDELIVERED` available | Candidate-sourcing / matching work where "delivered" is binary (a candidate list either arrived or didn't) -- no post-delivery quality dispute lane. |
| `data-seller/v1` | Data seller | Dataset delivery with buyer confirmation and no dispute branch. | funding, delivery, deliveryConfirmation | 0-3 | None: same shape as `recruiting/v1` | Data/dataset delivery where the artifact is verifiable at delivery time (hash match) and there's no meaningful "I don't like the data" rejection path. |
| `content-generator/v1` | Content generator | Content delivery with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: reject -> redeliver -> refund; no appeal/dispute/arbitration escalation | Creative/generated-content work where the buyer might reasonably ask for one redo, but a formal arbitration escalation is overkill. |
| `coding/v1` | Coding | Software-deliverable workflow with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: same shape as `content-generator/v1` | Code/implementation deliverables -- redeliver-on-reject fits "the tests didn't pass, try again" better than a dispute process. |
| `security-audit/v1` | Security audit | Audit-report delivery with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: same shape as `content-generator/v1` | Audit/report deliverables with a possible one-shot revision, no formal appeal process. |

## How phase 3 uses this table

Ask the seller about deal-shape *characteristics*, never the template name:
- "If a buyer isn't happy with what you deliver, do you want a chance to redo it, or is delivered-is-delivered?" -> maps to escalation-path column.
- "Could a delivery genuinely be disputed by a reasonable buyer, or is success obvious from the artifact itself?" -> distinguishes `standard/v1` (formal arbitration warranted) from the mid-lifecycle group.

Then pick the matching row and only *afterward* reveal the template ID in the phase-3 summary.
