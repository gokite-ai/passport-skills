# Seller Onboarding Skill — implementation design

**Date:** 2026-08-31
**Status:** Draft — ready for spec review, then `writing-plans`
**Source design:** `docs/Seller Onboarding Skill — Design.md` (owner Yusuke, drafted 2026-08-30) — that document is the product/UX rationale (why the current flow fails, the 9 design decisions, the phase map, the operations table, the boundary, non-goals). This doc translates it into concrete `passport-skills` artifacts and corrects several assumptions that were true on 2026-08-30 but have since changed.
**Related:** `docs/superpowers/specs/2026-08-28-owner-onboarding-design.md` — a separate, already-shipped effort that folded owner identity/KYC/passkey bootstrap directly into `seller-agent-setup` (not a new skill). This design's phase 0/1 leans on that work rather than re-solving it.

## Why a translation doc, not just implementing the source design directly

Three of the source design's load-bearing assumptions no longer hold, discovered via direct repo/backend investigation on 2026-08-31 (see "Corrections" below). Implementing against the original doc as written would ship phase-4 copy describing a passkey ceremony that was removed a week earlier, and would over-scope the template-characteristics table to all 9 templates when 6 already have real descriptors. This doc is the corrected version to build against; the source doc's rationale (decisions #1–#9, §5's operations table, §6's boundary, §7's non-goals) still stands and is not repeated here except where it changed.

## Corrections to the source design (evidence-based, 2026-08-31)

| Source design assumption | Actual current state | Evidence |
|---|---|---|
| 8/9 workflow templates return `definition_available: false` (no machine-readable definition) | Only 3/9 now lack descriptors (`fixed_outcome/v1`, `fast-clocks/v1`, `us-04-research-report/v1`); 6/9 shipped real descriptors 2026-08-29/30 | `passport` repo `pkg/a2a/templates/v1/*.json`, commits `7449c1e9`, `a5ae3e53` |
| Phase 4 (governance) hands the owner a dashboard link for **passkey approval** | Passkey step-up for the acceptance-policy PUT was deliberately removed; plain owner-JWT `PUT /v1/agents/{agent}/acceptancePolicy` is sufficient | `passport` repo commit `39131fa9` ("drop the passkey step-up"), `pkg/a2a/acceptance_policy.go` / `pkg/service/acceptance_policy.go` (package docstrings still say step-up, code doesn't do it — docstrings are stale, not the behavior) |
| Extending the standing-orders slot-gap (§5) to `request`/`rejected`/`closed` needs a `kite-agent-handler` (passport-cli) code change | No CLI change needed — `kite-agent-handler` already invokes the identical subprocess with identical file access for every operation; the `decide`-only restriction is a prompt-level convention in `kite-seller/SKILL.md`, not code | `passport-cli` `internal/agenthandler/handler.go:78-181`, `exec.go:203-253` — no per-operation file gating, no `cmd.Dir` set anywhere |
| URL→URN migration may have broken stored registration files (phase-0 repair cushion proposed) | Migration (`passport` commit `1f99e0e0`, 2026-08-26) only changed schema `$id`s; the registration record's own `uri` field was explicitly left untouched — no evidence stored registration files can fail validation from this | `passport` repo `pkg/a2a/handler.go:1285-1308`, commit message for `1f99e0e0` |

Not a correction, but confirms a source-design premise: the platform-bug items the source design deliberately left unfiled (stale-JWT mid-flow, handler stdout fail-closed flakiness) are still real — the backend's JWT 401 path still collapses expired/invalid/garbage tokens into one generic response with no machine-readable error code (`pkg/middleware/auth.go:44-52`). The CLI's own expiry detection (regex on prose, `exitcode.go:70-72,289,297`) is what phase 0 leans on; it's a real cushion, not a fix.

## Goals (unchanged from source design)

A seller who already runs an agent, with zero Kite vocabulary, reaches one live deal seen working end-to-end by answering questions only about their own business — identity, offer(s), deal shape, governance posture — with every platform parameter derived, never asked directly.

## Non-goals (unchanged from source design §7)

No buyer agent inside the onboarding conversation, the skill never runs `kagent serve` itself, no platform auto-explanation of templates, no per-quote pre-send approval in v1, no interviewing all interaction patterns up front, no rewrite of the existing runbook skills.

## Design

### File layout

New directory `seller-onboarding/`:
- `SKILL.md` — trigger description + the 9-phase flow (0–8: detect → identity → offers → deal shape → governance → standing orders → publish → serve → verify). Target: stay under the repo's ~350-line split convention; if the phase logic alone pushes past it, split immediately rather than let it grow (see `project_skills_restructure_effort` precedent — `request-session`/`shopping`/`kite-discovery` already did this split).
- `references/template-characteristics.md` — the deal-shape table (columns: payment trigger, evaluation mode [buyer/oracle/none], escrow behavior, time windows, choose-this-when). Populated from real descriptor JSON for the 6 templates that have one (`coding`, `content-generator`, `data-seller`, `recruiting`, `security-audit`, `standard`); hand-curated for the remaining 3 (`fixed_outcome`, `fast-clocks`, `us-04-research-report`). Loaded only during phase 3 (progressive disclosure, per source design §8).
- `references/standing-orders-template.md` — the acceptance-skill scaffold template, parameterized by interview answers, with sections for all 5 operations (see "Standing-orders format extension" below).
- `references/commands.md` — the actual `kagent`/curl commands this skill shells out to, in the same style as `seller-agent-setup/references/commands.md`.

`skills.json`: new entry, `group: "seller-agent"`, `command_prefix: "kagent"`, `dependencies: ["authenticate-user"]`, tags `["agent","seller","onboarding","kagent","interview"]`.

**Relationship to existing skills (decided 2026-08-31):** `seller-onboarding` is a conversation layer that shells out to the same underlying `kagent`/API calls the existing skills already use — it does not delegate to `seller-agent-setup`/`seller-fulfill`/`seller-serve` as subagents, and those skills are not modified for their own mechanics (they remain the agent-facing runbooks and repair paths, per source design decision #1). The one exception is `kite-seller/SKILL.md`, which does need a direct edit (below), because it's the file that defines what the model reads per operation, not a CLI runbook.

### Phase-by-phase behavior

Phases 0, 1, 2, 3, 6, 7, 8 follow the source design as written (§4), with these changes:

- **Phase 0 (detect existing state):** reuse `kagent status`'s existing state table (no key / pending / active / revoked / unbound — already branch-able, `seller-agent-setup/SKILL.md:393-410`). Keep the stale-JWT translation cushion (leans on the CLI's existing regex-based expiry detection). Drop the URL→URN repair cushion — no evidence it's needed (see Corrections table). Also check whether the owner has already been through the owner-bootstrap flow (`kpass onboarding status`) — if `seller-agent-setup` was already run once, phase 0 should detect an active binding and skip straight past identity into phase 2, rather than re-asking.
- **Phase 1 (identity):** one question (public name), permanence explained before asking, explicit stop sign before `--force`. No separate owner-KYC/bootstrap handling needed here — `seller-agent-setup` already does that end-to-end (dev auto-approve) per the shipped owner-onboarding work; phase 0's detection plus a direct shell-out to `seller-agent-setup`'s init/bind commands covers it.
- **Phase 2 (offers):** template-table lookup as described in "File layout" above (6 auto-derived + 3 curated) — cheaper than the source design's "curate all 9" framing.
- **Phase 3 (deal shape):** unchanged from source design.
- **Phase 4 (governance):** derived, not asked, same as source design — but the handoff changes. Instead of "hands the owner a dashboard link for the passkey approval," the skill computes the mandate values (template allowlist, price floors/ceilings, capacity) and does the `PUT /v1/agents/{agent}/acceptancePolicy` directly (owner JWT only, no passkey ceremony — see Corrections). Still worth an explicit in-conversation confirmation ("here's exactly what I'm about to set as your agent's guardrail — OK?") before writing, for trust/UX reasons, even though the platform itself doesn't gate it.
- **Phase 5 (standing orders):** extended per below.

### Standing-orders format extension

`seller-acceptance/SKILL.md` (seller-authored, lives in the seller's own repo, scaffolded by phase 5) gains sections for `request` and `rejected` (per source design §5's defaults table — `closed` is pure bookkeeping and doesn't need a seller-authored slot). `kite-seller/SKILL.md` (in this repo) is updated to read those new sections when handling those operations — today it reads the acceptance-skill file only for `decide` (`kite-seller/SKILL.md:178-184`).

Confirmed 2026-08-31: no `passport-cli` change required. `kite-agent-handler`'s dispatch (`internal/agenthandler/handler.go`) runs the identical subprocess with identical `Read/Write/Glob/Grep` access and no per-operation working-directory restriction for every operation — the current `decide`-only reading is `kite-seller`'s own prompt instruction, not a code gate. So this is a two-file change entirely within `passport-skills`: the new template (phase-5 scaffold) and `kite-seller/SKILL.md`'s per-op read instructions.

### Pricing-chain consistency (source design §11)

Orchestration only, no new API: compute the reserve floor once from the phase-2 interview answers, then in the same step write it to both places — the phase-4 `acceptancePolicy` PUT (`price_floors`/`price_ceilings`) and the phase-5 standing-orders file. This guarantees the acceptance test from source design §11: the agent can never quote below what accept will honor, because both numbers come from one computation, not two independently-entered ones.

## Error handling

Follows the same shape as `2026-08-28-owner-onboarding-design.md`'s error table — skill-level handling on top of what the CLI already reports, never inventing new recovery paths the CLI doesn't support:

| Situation | Skill behavior |
|---|---|
| Phase 0 detects an already-active binding | Skip identity, go straight to phase 2, tell the seller what was detected and why phase 1 is being skipped. |
| Phase 0's stale-JWT cushion fires | Surface the CLI's re-login hint; do not attempt to work around it. |
| Acceptance-policy PUT fails for any reason (network, validation) | Surface the exact API error; do not silently retry with different values or fall back to skipping governance. |
| Owner declines the phase-4 confirmation | Stop; do not write standing orders that assume a mandate that was never set — phase 6 (publish) must refuse to proceed past readiness-check in this state (fail-closed, same as source design §4 phase 6). |
| Template characteristics lookup hits one of the 3 undescribed templates | Use the hand-curated entry; if the seller's business doesn't map to any of the 9, say so plainly rather than forcing a fit. |

## Testing

Add cases to `evals/evals.json` (short literal `assertions`, matching the existing 101-case convention) covering: phase-0 branching (fresh vs. already-active vs. stale-JWT), phase-2 template-table lookup for both a described and an undescribed template, phase-4 governance derivation and confirmation gate, and phase-5's standing-orders write including the `request`/`rejected` sections. Grade manually per `evals/README.md` — there is no automated eval runner in this repo (`functional-workspace`/`grade_all.py` never existed; corrected in `evals/README.md` on 2026-08-28).

Manual end-to-end verification (mirrors source design's own acceptance criterion): run the skill against a fresh dev account with no prior registration, reach a state where phase 8 hands off to the Passport web Playground, and watch one deal settle without reading developer docs or hitting an error-discovered concept.

## Files touched

- `seller-onboarding/SKILL.md`, `seller-onboarding/references/{template-characteristics,standing-orders-template,commands}.md` (all new)
- `kite-seller/SKILL.md` (add `request`/`rejected` standing-orders reads)
- `skills.json` (new entry)
- `evals/evals.json` (new cases)

## Open items carried from the source design (unresolved, tracked there — not blocking this implementation)

- Multi-offer mechanics (§9): build phase 2–4 for one offer, treat additional offers as a repeat pass, per the source design's interim rule.
- Dev-vs-prod lane (§9): dev only, seller lane doesn't exist in prod yet.
- Success metric: re-run the 2026-08-30 trial persona post-ship, count friction events against the 13-event baseline.
- Platform bugs already filed or deliberately unfiled per source design §10 — not re-litigated here.

## Depends on

Nothing outside `passport-skills`. All CLI/backend primitives this design needs already exist (see Corrections table and source design §6's boundary) — this can ship without any `passport-cli` or `passport` backend change.
