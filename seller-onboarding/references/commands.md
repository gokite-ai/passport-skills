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

- `kagent registration validate --storefront --rate-card --workflow-terms` -- local schema/money/negotiation checks before publish.
- `kagent registration publish --rate-card <f> [...]` -- atomic publish.
- `kagent registration get` -- readiness confirmation.

## Serve (phase 7)

- `kagent serve --handler kite-agent-handler --handler-timeout <secs> --sweep-interval <secs>` -- the skill prints this command and stops; it never runs it (long-running process, user's terminal).

## Verify (phase 8)

No command -- handoff to the Passport web Playground.
