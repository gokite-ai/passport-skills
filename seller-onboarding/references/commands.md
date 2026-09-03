# Seller Onboarding — Command Reference

Every command this skill shells out to. These are the same underlying calls `seller-agent-setup`/`seller-fulfill`/`seller-serve` already use -- this file exists so `seller-onboarding/SKILL.md` doesn't have to repeat flag syntax inline.

## Detect existing state (phase 0)

- `kagent status` -- reports registration state, key binding, auth state. State table: no key / pending / active / revoked / unbound (see `seller-agent-setup/SKILL.md:393-410` for the authoritative mapping).
- `kpass onboarding status` -- owner identity/KYC status, if phase 0 also needs to check whether owner bootstrap (see `docs/superpowers/specs/2026-08-28-owner-onboarding-design.md`) already ran.

## Identity (phase 1)

- `kagent init [--import-key] [--force]` -- `--force` overwrites an existing runtime key and orphans every agreement pinned to it. Always show the stop sign from `seller-agent-setup/SKILL.md:156` before passing it.
- `kpass agent create --uid <slug> --kind seller` -- owner-side identity registration (`seller-agent-setup/SKILL.md:169`).
- `kpass agent token create --agent <did>` then `kagent bind --token <art_...>` -- mint-then-bind path, no passkey step-up (`seller-agent-setup/SKILL.md:181`).

## Offers (phase 2)

- `ksearch workflow-template list` -- public read, no auth (`seller-agent-setup/SKILL.md:244`).
- `kagent card publish --file <f> [--workflow <id>]` -- identity card only, not pricing (`seller-agent-setup/SKILL.md:227,241`).
- `kagent docs publish --kind rate-card --file <f>` -- pricing document (`seller-agent-setup/SKILL.md:278`).
- `kagent docs publish --kind terms --file <f>` -- terms document (`seller-agent-setup/SKILL.md:277`).

## Deal shape (phase 3)

No new commands -- this phase is a lookup against `references/template-characteristics.md`, confirmed against `ksearch workflow-template get <family/version>` if the seller wants to double check a specific template's raw definition.

**Phase 3b (configuration)** also runs no command -- it only *computes* the offering's `workflow.config` from the seller's deadline/revision answers, which phase 6 then records in the workflow-terms input. The configurable surface (descriptor `configuration.schema`, verified against `pkg/a2a/templates/v1/*.json`):

- `windows` -- integer **seconds**, min 45, max 315360000 (~10y): `fundingWindow`, `deliveryWindow`, `deliveryConfirmationWindow`, and (only if the template has them) `appealResponseWindow`, `arbitrationWindow`. **Any window left unset (or `0`) resolves to the platform's deployment default** (`0`/absent means "use the default", not "no window" -- passport `pkg/a2a/routes.go`), so config is about business fit, not activation-safety. Set only the ones the seller cares about.
- `limits.maxRedeliveries` -- integer 0-3 (mid group only).
- `skippedStates`, `parameters` -- leave empty unless the seller explicitly turns a lane off.

Shape: `config = { "windows": { ... }, "limits": { "maxRedeliveries": <n> } }`. Inspect a template's exact required window set with `ksearch workflow-template get <id>` (the `deadline_edges` names).

## Governance (phase 4)

**Corrected 2026-08-31, mid-execution** (per `docs/Seller Onboarding Artifacts -- Runtime Key, Registration Files, Mandate.md` §7, user-supplied reference): the PUT requires optimistic concurrency. GET first, then PUT with the version it returned:

- `curl -H "Authorization: Bearer <owner-jwt>" https://<passport-api-host>/v1/agents/<agent-did>/acceptancePolicy` -- read the current policy (and its `version`) before writing. No policy yet = `version: 0`.
- `curl -X PUT -H "Authorization: Bearer <owner-jwt>" -H 'Content-Type: application/json' https://<passport-api-host>/v1/agents/<agent-did>/acceptancePolicy --data @policy.json` with a JSON body:
  ```json
  {
    "version": <integer -- echo what GET returned; 0 if none existed>,
    "templates": ["<template-id>"],
    "price_floors": {"<template-id>": "<minor-units-integer>"},
    "price_ceilings": {"<template-id>": "<minor-units-integer>"},
    "max_open_obligations": <integer-or-null>
  }
  ```
  A stale `version` is refused with 409 -- if that happens, GET again and retry with the fresh version, never guess. Field names and minor-units convention per `seller-agent-setup/SKILL.md:334-391`. No passkey step-up -- plain owner JWT is sufficient (`passport` commit `39131fa9`). Fail-closed: no row set = refuse everything, so this step is mandatory before phase 6 can succeed. `templates` must name exactly the workflow ids in the registration, and the floor must sit at or below the rate-card price -- otherwise the agent refuses the very deal it advertises (this is the pricing-chain consistency requirement, see phase 5).

## Standing orders (phase 5)

No CLI command -- this phase writes a file (`<seller-repo>/.claude/skills/seller-acceptance/SKILL.md`) from `references/standing-orders-template.md`.

## Publish (phase 6)

The workflow-terms input carries, per offering, a `workflow` member `{ "templateId": "<id>", "config": <phase-3b config> }`. `config` is recorded verbatim, content-addressed, not interpreted by the platform (`seller-agent-setup/references/commands.md`, workflow-terms v1 skeleton). Publish the phase-3b `config` so the seller's chosen deadlines are recorded; any window the seller left unset resolves to the platform default (an empty `config` still activates). To dry-run a `{templateId, config}` pair before publishing, `POST /v1/agent/workflows:validate` (seller runtime key) runs exactly the validation + hashing a publish would. Reconfiguring an offering's workflow later is a **registration republish** (atomic full-replace) -- there is no per-offering PUT.

**Pricing-chain verification (deterministic, no script).** Two layers, using only tools this skill already has:
1. `kagent registration validate` (above) is the platform's own check of the card / money / negotiation / workflow config.
2. The mandate <-> standing-orders floor is the one link no platform call verifies. Read it back and compare: `curl -H "Authorization: Bearer <owner-jwt>" .../acceptancePolicy` (the phase-4 GET) and assert `price_floors[<template>]` equals the reserve floor written into `seller-acceptance/SKILL.md`, and is `<=` the advertised card price. Both come from one number computed in phase 2, so a mismatch means real drift (usually a later dashboard edit) -- re-derive both and republish. This is the replacement for a standalone check script: the platform validates what it can, and this readback covers the gap it can't.

- `kagent registration validate --storefront --rate-card --workflow-terms` -- local schema/money/negotiation checks before publish.
- `kagent registration publish --rate-card <f> [...]` -- atomic publish.
- `kagent registration get` -- readiness confirmation.

## Serve (phase 7)

- `kagent serve --handler kite-agent-handler --handler-timeout <secs> --sweep-interval <secs>` -- the skill prints this command and stops; it never runs it (long-running process, user's terminal).

## Verify (phase 8)

No command -- handoff to the Passport web Playground.
