# Standing Orders Template

Phase 5 fills this scaffold with the seller's interview answers and writes it to `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md`. Section headings (`decide`, `request`, `rejected`) are read by `kite-seller/SKILL.md` -- do not rename them without updating that file's `request` and `rejected` sections too. The floor is written **once, as a machine-readable field** -- `reserve_floor_minor` in the frontmatter -- and the `decide`/`request` prose reference it (a single source, so the two sections cannot disagree). Its value is `seller.offer.reserve_floor_minor` when the seller set a private floor, or `seller.offer.advertised_price_minor` for a fixed-price offer (the card price IS the floor -- both sides use the card as-is). Phase 6 parses that one frontmatter field to verify the pricing chain.

```markdown
---
name: seller-acceptance
description: Your agent's standing orders -- your business judgment for each buyer interaction. You own this file; it lives in your repo.
reserve_floor_minor: "<seller.offer.reserve_floor_minor, or seller.offer.advertised_price_minor for a fixed-price offer -- integer minor units, digits only>"
---

# Standing Orders

## decide

Accept a proposal when:
- The template matches: `<seller.offer.template_id>`.
- The price is at or above your floor -- the `reserve_floor_minor` declared in this file's frontmatter (minor units). When a private floor was set, the platform mandate enforces this same number, so a deal your agent accepts here can never be parked by the mandate afterward; it is the single value phase 4 wrote, never re-derived.
- The scope fits what you actually offer: <seller.offer.service_description>.

Escalate (do not auto-decide) when:
- <seller.governance.escalation_rule, verbatim>

Decline everything else.

## request

Pre-deal chat, quote asks, clarifications, sample requests:
- Quote per your published card -- never quote below `reserve_floor_minor` (this file's frontmatter, minor units): it is the same floor your `decide` section enforces, and (when a private floor was set) the same number your mandate will refuse to let you accept.
- Answer briefly, on-topic. Don't engage open-ended free chat -- it costs your agent's tokens with no payment guarantee.

## rejected

If a buyer rejects your delivery:
- Revise once if the rejection names something concrete and fixable.
- Consent-refund if the objection is right, or if finishing would take far longer than the deal is worth -- an early honest refund protects your reputation more than a garbage delivery.
- Appeal only when the delivery clearly meets what was signed for.
```
