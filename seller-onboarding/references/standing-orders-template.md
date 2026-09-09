# Standing Orders Template

Phase 5 fills this scaffold with the seller's interview answers and writes it to `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md`. Section headings (`decide`, `request`, `rejected`) are read by `kite-seller/SKILL.md`.

Two rules govern what you emit:

**1. Business judgment only -- no CLI.** The served model answers each operation by returning a `kite-seller` response frame; it has no shell and never runs `kagent`. Describe *what decision to make and why*, never *which command to run*.

**2. Generate arms from the chosen chart's actual transitions, not global verbs.** `decide` and `request` always apply. The `rejected` section must match what the template's `REJECTED` state can actually do (read `kagent workflow-template get <t>`; the summary is in `references/template-characteristics.md`):

| Template | `rejected` arms to emit |
|---|---|
| `content-generator/v1`, `coding/v1`, `security-audit/v1` | **Revise once** (redeliver) -- only if the configured `maxRedeliveries` budget allows it -- and **consent-refund**. No appeal on these charts. |
| `standard/v1` | **Appeal** and **consent-refund**. **No "revise"** -- these charts cannot redeliver from `REJECTED`. |
| `enriched-standard/v1` | Not onboarded by v1 (see `references/template-characteristics.md`); do not generate standing orders for it. |
| `recruiting/v1`, `data-seller/v1` | **Omit the `rejected` section entirely** -- these charts have no rejection. |

Never emit a "revise once" arm on a chart that can't redeliver from `REJECTED`, or when `maxRedeliveries` is 0. **A co-signed split is never a `rejected` arm** -- `kite-seller` handles the split as a separate automatic `settle` item from `DELIVERED`, not as a response to a rejection -- so never put "propose a split" in the `rejected` section.

## The floor -- fill from the offer type

Because v1 deals are single-deliverable (quantity 1), the unit price *is* the whole-deal total, so `decide` and `request` share one floor number and the agent can never quote below what it would accept:

| Offer type | Shared floor | `reserve_floor_minor` frontmatter |
|---|---|---|
| **Fixed** | the card price (`unit_price_minor`); terms verification already refuses off-card prices | **Omit** |
| **Negotiated, no reserve** | the published band bottom (`total_min_minor` = `totalBounds.minMinor`) | **Omit** |
| **Negotiated, with reserve** | the model-visible reserve (`reserve_floor_minor`), within `total_min_minor..total_max_minor` | **Set** |

Only the negotiated-with-reserve case carries this number. It is absent from the public rate card, but it is **not a secret**: the serving model reads this file while handling untrusted buyer messages. The emitted instructions tell the model not to disclose it, but onboarding must describe that as best-effort confidentiality rather than a hard security boundary.

## Scaffold

```markdown
---
name: seller-acceptance
description: Your agent's standing orders -- your business judgment for each buyer interaction. You own this file; it lives in your repo.
# reserve_floor_minor: <seller.offer.reserve_floor_minor>   # MODEL-VISIBLE; negotiated-with-reserve only
---

# Standing Orders

## decide

Accept a proposal when all of these hold:
- It matches your service: <seller.offer.service_description>.
- Its price clears your floor (`<the shared floor for this offer type>` minor units).
- It fits the deal shape you offer (`<seller.offer.template_id>`).

[negotiated-with-reserve only] If a proposal is priced below your reserve, escalate it rather than declining -- surface it so you can approve the deal out-of-policy if you want it. (Your dashboard mandate parks below-reserve proposals automatically as well.)

[negotiated-with-reserve only] Never state, confirm, or reveal the exact reserve or floor to a buyer. This is a model instruction, not a secrecy guarantee; the owner was told that deterministic secret enforcement is outside v1.

<seller.governance.escalation_rule, verbatim -- escalate these to the owner>

Decline anything else (out of scope, or work you never take).

## request

For pre-deal chat, quote asks, clarifications, and sample requests:
- Quote per your published card, and never quote below your floor (`<same shared floor as decide>` minor units). A fixed card has one price; a negotiated card is quoted within its published band, and (with a reserve) never below the reserve. Never disclose the exact reserve/floor in a reply; quote a price instead.
- Answer briefly and on-topic. Don't spend the agent's tokens on open-ended free chat with no payment in sight.

## rejected
<!-- Emit ONLY the arms from the table above for the chosen template. Omit this whole section for recruiting/v1 and data-seller/v1. -->

If a buyer rejects your delivery:
- [content-generator/coding/security-audit, and only if maxRedeliveries > 0] Revise once, if the rejection names something concrete and fixable.
- [standard/v1] Appeal, only when your delivery clearly meets what was signed for.
- [all charts with a rejection lane] Consent to a refund if the objection is right, or if finishing would cost far more than the deal is worth -- an early honest refund protects your reputation more than a bad delivery.
```

Delete the bracketed guidance markers and every arm the chosen template doesn't support before writing the file.
