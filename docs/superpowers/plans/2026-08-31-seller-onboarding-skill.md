# Seller Onboarding Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `seller-onboarding` skill in `passport-skills` — a conversational interview that takes a seller from zero Kite vocabulary to one live deal seen working end-to-end, deriving every platform artifact (identity, offer, deal shape, governance mandate, standing orders) from intent-level answers instead of asking for platform parameters directly.

**Architecture:** One new skill directory (`seller-onboarding/`) with a phase-driven `SKILL.md` (phases 0–8) plus three `references/` files (template characteristics, standing-orders template, command reference). The skill shells out directly to the same `kagent`/API calls `seller-agent-setup`/`seller-fulfill`/`seller-serve` already use — it does not delegate to them as subagents, and does not modify their mechanics. The one existing file this plan does modify is `kite-seller/SKILL.md`, to add two new per-operation standing-orders read instructions.

**Tech Stack:** Markdown skill files (Claude Code skill format), `kagent`/`kpass` CLI (passport-cli), direct REST calls via `curl` to the passport backend's `acceptancePolicy` endpoint, JSON config files (`skills.json`, `evals/evals.json`).

**Spec:** `docs/superpowers/specs/2026-08-31-seller-onboarding-skill-design.md`

## Global Constraints

- SKILL.md files in this repo follow a ~350-line split convention: if `seller-onboarding/SKILL.md` grows past that, split overflow into `references/` rather than let it grow unbounded (matches `request-session`/`shopping`/`kite-discovery` precedent).
- No new `passport-cli` or `passport` backend work is in scope — every task in this plan touches only `passport-skills`.
- No automated eval runner exists in this repo (`evals/README.md`, confirmed 2026-08-28). "Testing" a skill means: write the eval case in `evals/evals.json` first (short literal `assertions`), then after writing the skill content, dispatch a subagent that reads the relevant `SKILL.md`/`references/*.md` files and responds to the eval `prompt`, and manually check every string in `assertions` appears in its response.
- Governance (phase 4) writes to `PUT /v1/agents/{agent}/acceptancePolicy` with plain owner-JWT auth — **no passkey step-up** (removed in `passport` commit `39131fa9`, 2026-08-24). Never write skill copy implying a passkey ceremony for this endpoint.
- **Corrected 2026-08-31, mid-execution:** the workflow template catalog is now exactly 6 IDs — `standard/v1`, `recruiting/v1`, `data-seller/v1`, `content-generator/v1`, `coding/v1`, `security-audit/v1` — confirmed against `origin/main` in the `passport` repo (`git ls-tree -r --name-only origin/main -- pkg/a2a/templates/v1/`). The previously-referenced `fixed_outcome/v1`, `fast-clocks/v1`, `us-04-research-report/v1` were removed from the catalog (commit `25b4949f`, "remove the fast-clock test templates from the catalog") — there is no undescribed-template case to handle anymore. Every remaining template's descriptor JSON now also carries a `descriptor.presentation.name` and `descriptor.presentation.summary` field (added alongside the same commits) — a real, platform-authored one-line plain-English description, e.g. `standard/v1` → "Standard delivery" / "The full agreement lifecycle with delivery review, appeal, and third-party arbitration." This is authoritative source content for the "choose this when" column, not a curated guess. There is still no `evaluationMode`/oracle field — evaluation is always buyer-driven (implicit in whether `REJECTING`/`REJECTED` states are configurable), confirmed by grepping `evidence.items[].producer` across all 6 descriptors (only `buyer`/`seller`/`buyerOwner`/`chain`, never an oracle role).

---

## File Structure

| File | Responsibility |
|---|---|
| `seller-onboarding/SKILL.md` | Trigger description + phases 0–8: interview flow, stop signs, phase map |
| `seller-onboarding/references/commands.md` | Every `kagent`/`kpass`/curl command the skill shells out to, with exact flags |
| `seller-onboarding/references/template-characteristics.md` | The deal-shape table used in phase 3, loaded only then |
| `seller-onboarding/references/standing-orders-template.md` | The acceptance-skill scaffold template written in phase 5 |
| `kite-seller/SKILL.md` | Modified: add `request`/`rejected` standing-orders read instructions |
| `skills.json` | Modified: new `seller-onboarding` entry |
| `evals/evals.json` | Modified: new eval cases for this skill |
| `evals/README.md` | Modified: add a coverage-table row |

---

### Task 1: Scaffold the skill directory, `skills.json` entry, and phase-map skeleton

**Files:**
- Create: `seller-onboarding/SKILL.md`
- Modify: `skills.json`

**Interfaces:**
- Produces: the skill's frontmatter contract (`name: seller-onboarding`, `allowed-tools`) and the phase-map text every later task's phase section appends after.

- [ ] **Step 1: Write the eval case for triggering**

Add to `evals/evals.json` (append to the array; follow the existing `{id, prompt, expected_output, assertions}` shape — check the last `id` currently in the file and use the next integer):

```json
{
  "id": 102,
  "prompt": "I have an agent that does candidate sourcing for recruiters. I want to sell its service to other agents on Kite but I don't know anything about this platform. Where do I start?",
  "expected_output": "Routes to seller-onboarding, shows the phase map, and asks exactly one question (the agent's public name) rather than asking for platform parameters like a workflow template ID.",
  "assertions": ["seller-onboarding", "phase", "public name"]
}
```

- [ ] **Step 2: Verify the eval fails today**

Run: dispatch a `general-purpose` subagent with this prompt: *"You are a Claude Code assistant with access to the skills listed in `passport-skills/skills.json`. A user says: 'I have an agent that does candidate sourcing for recruiters. I want to sell its service to other agents on Kite but I don't know anything about this platform. Where do I start?' Which skill would you invoke, and what's your first response?"*
Expected: the subagent has no `seller-onboarding` skill to route to (it doesn't exist in `skills.json` yet) — it should say so or misroute to `seller-agent-setup`. Confirms the eval is currently unsatisfiable.

- [ ] **Step 3: Create the skill file skeleton**

Write `seller-onboarding/SKILL.md`:

```markdown
---
name: seller-onboarding
description: Interview a seller who already runs a working agent and knows nothing about Kite vocabulary, turning their answers about their own business into every platform artifact needed to sell that agent's service to buyer agents -- identity, offer/rate-card, workflow-template selection, governance mandate, standing orders, and one verified live deal. Invoke when a developer wants to "sell my agent's service", "become a seller on Kite", "monetize my agent", or is confused by seller-agent-setup's platform-parameter questions (workflow template names, price floors, acceptance policy). This is the human-conversation entry point; seller-agent-setup/seller-fulfill/seller-serve/kite-seller remain the underlying runbooks it drives.
allowed-tools: Bash(kagent *), Bash(kpass agent *), Bash(kpass identifier *), Bash(kpass onboarding *), Bash(curl *), Bash(ksearch *)
---

# Seller Onboarding

You are guiding a seller who runs a working agent and wants to sell its
service on Kite Passport, but has zero Kite vocabulary. Your job: ask
about their business, never about platform parameters. Every platform
artifact (template ID, acceptance policy, card schema) is something you
derive and confirm, not something you ask the seller to name.

## Phase map

Show this at the start of every session, and name the current phase at
every step:

```
0 detect -> 1 identity -> 2 offers -> 3 deal shape -> 4 governance
        -> 5 standing orders -> 6 publish -> 7 serve -> 8 verify
```

## Interaction rules

- One question at a time. Every question carries its why and a
  recommended default.
- Intent altitude: ask what the seller wants to accomplish, never which
  platform parameter to set.
- Stop sign before any destructive or permanent choice (e.g. `kagent init
  --force`, which orphans every agreement pinned to the existing key).
- Detect existing state before assuming a blank slate (phase 0).
- Long-running processes (`kagent serve`) and passkey/dashboard ceremonies
  leave this conversation with an explicit handoff -- never run or wait on
  them inline.
```

- [ ] **Step 4: Add the `skills.json` entry**

Read `skills.json` first to find the exact array position and confirm the trailing structure. Add this object to the `skills` array (place it alongside the other `seller-agent` group entries, e.g. immediately before the `seller-agent-setup` entry):

```json
{
  "slug": "seller-onboarding",
  "name": "Seller Onboarding",
  "description": "Interview a seller who already runs a working agent and knows nothing about Kite vocabulary, turning their answers about their own business into every platform artifact needed to sell that agent's service -- identity, offer/rate-card, workflow-template selection, governance mandate, standing orders, and one verified live deal. Invoke when a developer wants to sell their agent's service, become a seller on Kite, or is confused by seller-agent-setup's platform-parameter questions.",
  "path": "seller-onboarding/SKILL.md",
  "group": "seller-agent",
  "tags": [
    "agent",
    "seller",
    "onboarding",
    "kagent",
    "interview",
    "governance",
    "rate-card"
  ],
  "dependencies": [
    "authenticate-user"
  ]
}
```

- [ ] **Step 5: Verify `skills.json` is still valid JSON**

Run: `python3 -c "import json; json.load(open('skills.json'))"`
Expected: no output, exit code 0.

- [ ] **Step 6: Re-run the eval, expect a routing pass**

Run: dispatch a `general-purpose` subagent with the same prompt as Step 2, this time telling it to first read `skills.json` to see available skills, including the new `seller-onboarding` entry.
Expected: the subagent names `seller-onboarding` as the skill to invoke. (Full phase-0/phase-1 behavior isn't implemented yet, so don't expect the "public name" assertion to pass until Task 3 — this step only confirms routing.)

- [ ] **Step 7: Commit**

```bash
git add seller-onboarding/SKILL.md skills.json evals/evals.json
git commit -m "feat(skills): scaffold seller-onboarding skill and phase map"
```

---

### Task 2: `references/commands.md` — command reference

**Files:**
- Create: `seller-onboarding/references/commands.md`

**Interfaces:**
- Consumes: nothing (pure reference, no runtime state)
- Produces: the exact command strings every later phase task cites by name (`kagent status`, `kagent init`, `kagent card publish`, the `acceptancePolicy` curl, etc.) — later tasks reference this file's headings rather than re-deriving flags.

- [ ] **Step 1: Write the reference file**

```markdown
# Seller Onboarding — Command Reference

Every command this skill shells out to. These are the same underlying
calls `seller-agent-setup`/`seller-fulfill`/`seller-serve` already use --
this file exists so `seller-onboarding/SKILL.md` doesn't have to repeat
flag syntax inline.

## Detect existing state (phase 0)

- `kagent status` -- reports registration state, key binding, auth state.
  State table: no key / pending / active / revoked / unbound (see
  `seller-agent-setup/SKILL.md:393-410` for the authoritative mapping).
- `kpass onboarding status` -- owner identity/KYC status, if phase 0 also
  needs to check whether owner bootstrap (see
  `docs/superpowers/specs/2026-08-28-owner-onboarding-design.md`) already
  ran.

## Identity (phase 1)

- `kagent init [--import-key] [--force]` -- `--force` overwrites an
  existing runtime key and orphans every agreement pinned to it. Always
  show the stop sign from `seller-agent-setup/SKILL.md:151` before passing
  it.
- `kpass agent create --uid <slug> --kind seller` -- owner-side identity
  registration (`seller-agent-setup/SKILL.md:169`).
- `kpass agent token create --agent <did>` then `kagent bind --token
  <art_...>` -- mint-then-bind path, no passkey step-up
  (`seller-agent-setup/SKILL.md:181`).

## Offers (phase 2)

- `ksearch workflow-template list` -- public read, no auth
  (`seller-agent-setup/SKILL.md:244`).
- `kagent card publish --file <f> [--workflow <id>]` -- identity card only,
  not pricing (`seller-agent-setup/SKILL.md:227,241`).
- `kagent docs publish --kind rate-card --file <f>` -- pricing document
  (`seller-agent-setup/SKILL.md:277`).
- `kagent docs publish --kind terms --file <f>` -- terms document
  (`seller-agent-setup/SKILL.md:278`).

## Deal shape (phase 3)

No new commands -- this phase is a lookup against
`references/template-characteristics.md`, confirmed against `ksearch
workflow-template get <family/version>` if the seller wants to double
check a specific template's raw definition.

## Governance (phase 4)

**Corrected 2026-08-31, mid-execution** (per `docs/Seller Onboarding
Artifacts -- Runtime Key, Registration Files, Mandate.md` §7, user-supplied
reference): the PUT requires optimistic concurrency. GET first, then PUT
with the version it returned:

- `curl -H "Authorization: Bearer <owner-jwt>" https://<passport-api-host>/v1/agents/<agent-did>/acceptancePolicy`
  -- read the current policy (and its `version`) before writing. No policy
  yet = `version: 0`.
- `curl -X PUT -H "Authorization: Bearer <owner-jwt>" -H 'Content-Type: application/json' https://<passport-api-host>/v1/agents/<agent-did>/acceptancePolicy --data @policy.json`
  with a JSON body:
  ```json
  {
    "version": <integer -- echo what GET returned; 0 if none existed>,
    "templates": ["<template-id>"],
    "price_floors": {"<template-id>": "<minor-units-integer>"},
    "price_ceilings": {"<template-id>": "<minor-units-integer>"},
    "max_open_obligations": <integer-or-null>
  }
  ```
  A stale `version` is refused with 409 -- if that happens, GET again and
  retry with the fresh version, never guess.
  Field names and minor-units convention per `seller-agent-setup/SKILL.md:334-391`.
  No passkey step-up -- plain owner JWT is sufficient (`passport` commit
  `39131fa9`). Fail-closed: no row set = refuse everything, so this step
  is mandatory before phase 6 can succeed. `templates` must name exactly
  the workflow ids in the registration, and the floor must sit at or below
  the rate-card price -- otherwise the agent refuses the very deal it
  advertises (this is the pricing-chain consistency requirement, see
  phase 5).

## Standing orders (phase 5)

No CLI command -- this phase writes a file
(`<seller-repo>/.claude/skills/seller-acceptance/SKILL.md`) from
`references/standing-orders-template.md`.

## Publish (phase 6)

- `kagent registration validate --storefront --rate-card --workflow-terms`
  -- local schema/money/negotiation checks before publish.
- `kagent registration publish --rate-card <f> [...]` -- atomic publish.
- `kagent registration get` -- readiness confirmation.

## Serve (phase 7)

- `kagent serve --handler kite-agent-handler --handler-timeout <secs>
  --sweep-interval <secs>` -- the skill prints this command and stops;
  it never runs it (long-running process, user's terminal).

## Verify (phase 8)

No command -- handoff to the Passport web Playground.
```

- [ ] **Step 2: Cross-check every cited line number is still accurate**

Run: `grep -n "kagent init" seller-agent-setup/SKILL.md | head -5` and similarly for `card publish`, `docs publish`, `acceptancePolicy`, `registration validate`, `registration publish`. Confirm the line ranges cited above still match; if `seller-agent-setup/SKILL.md` has moved since the 2026-08-31 research pass, update the citations in this file to match.
Expected: every grep hit falls within (or adjacent to) the cited range.

- [ ] **Step 3: Commit**

```bash
git add seller-onboarding/references/commands.md
git commit -m "docs(seller-onboarding): add command reference"
```

---

### Task 3: Phase 0 (detect existing state) and Phase 1 (identity)

**Files:**
- Modify: `seller-onboarding/SKILL.md`

**Interfaces:**
- Consumes: `references/commands.md`'s "Detect existing state" and "Identity" sections (Task 2)
- Produces: two conversation-state values later phases read — `seller.agent_did` (the bound agent's DID, set once phase 1 completes) and `seller.public_name`. Phase 2's task references these by name.

- [ ] **Step 1: Write the eval case**

Add to `evals/evals.json`:

```json
{
  "id": 103,
  "prompt": "Run seller-onboarding. `kagent status` on my machine already reports an active binding for did:kite:abc123:recruiter-bot.",
  "expected_output": "Phase 0 detects the active binding, skips phase 1's identity question entirely, tells the seller what was detected and why phase 1 is being skipped, and moves straight to phase 2.",
  "assertions": ["already", "skip", "phase 2"]
}
```

```json
{
  "id": 104,
  "prompt": "Run seller-onboarding. `kagent status` reports no key -- this is a brand new agent with nothing set up.",
  "expected_output": "Phase 0 detects nothing exists, phase 1 asks exactly one question: the agent's public name. Before running kagent init --force on any existing state it would show an explicit stop-sign warning; here there is no existing key so no warning is needed, but the skill should not silently skip explaining permanence of the name choice.",
  "assertions": ["public name", "permanent"]
}
```

- [ ] **Step 2: Verify eval 103/104 fail**

Run: dispatch a `general-purpose` subagent per prompt, telling it to read only `seller-onboarding/SKILL.md` as currently written (phase map + interaction rules, no phase 0/1 content yet).
Expected: FAIL — the subagent has no phase 0/1 instructions to follow yet, so it can't produce the expected branching.

- [ ] **Step 3: Append phase 0 and phase 1 to `SKILL.md`**

```markdown
## Phase 0 -- Detect existing state

Before asking anything, read reality:

1. Run `kagent status` (see `references/commands.md#detect-existing-state-phase-0`).
2. Branch on the result:
   - **No key**: brand new. Continue to phase 1 normally.
   - **Pending / unbound**: an identity exists but isn't active. Tell the
     seller what's pending and why, then continue to phase 1's binding
     step only (skip the naming question -- the name is already set).
   - **Active**: a bound agent already exists. Tell the seller: "I found
     an already-active agent (`<did>`) -- skipping the identity step,
     moving to phase 2." Do not re-ask for a public name.
   - **Revoked**: stop. Tell the seller their key was revoked and they
     need to decide whether to re-init (destructive -- see phase 1's stop
     sign) before onboarding can continue.
3. If any command returns an auth error, check whether it matches an
   expired-JWT shape (the CLI classifies this itself -- see
   `references/commands.md`). Translate it plainly: "Your login expired,
   please re-authenticate" rather than surfacing the raw error.

## Phase 1 -- Identity

Skip this phase entirely if phase 0 found an active binding.

Ask exactly one question: **"What name do you want buyers to see for
this agent?"** Explain before asking: this name is effectively permanent
-- changing the underlying key later (`kagent init --force`) orphans
every agreement pinned to the old key. This is a stop-sign moment: if the
seller already has a key and wants to replace it, confirm explicitly
before running `--force`, and never run it without that confirmation.

Once confirmed, run the commands in `references/commands.md#identity-phase-1`
end to end (owner bootstrap -- identifier claim, KYC, agent create,
mint-and-bind -- is already handled by these same commands per
`docs/superpowers/specs/2026-08-28-owner-onboarding-design.md`; this phase
does not re-implement that, it just runs it).

Record `seller.agent_did` and `seller.public_name` for later phases.
```

- [ ] **Step 4: Re-run eval 103 and 104**

Run: dispatch a `general-purpose` subagent per prompt, this time telling it to read the full current `seller-onboarding/SKILL.md` (phase map + interaction rules + phases 0/1).
Expected: PASS — eval 103's response mentions the detected DID, says "skip"/"already", and moves to phase 2; eval 104's response asks for the public name and mentions permanence.

- [ ] **Step 4b: Re-run eval 102 (deferred from Task 1) for a full pass**

Task 1 Step 6 only checked eval 102's routing behavior, deferring its `"public name"` assertion until phase 1 existed. Re-run eval 102's prompt now against the full current `SKILL.md`.
Expected: PASS — all three assertions (`seller-onboarding`, `phase`, `public name`) present in the response.

- [ ] **Step 5: Commit**

```bash
git add seller-onboarding/SKILL.md evals/evals.json
git commit -m "feat(seller-onboarding): add phase 0 (detect state) and phase 1 (identity)"
```

---

### Task 4: `references/template-characteristics.md` — deal-shape table

**Files:**
- Create: `seller-onboarding/references/template-characteristics.md`

**Interfaces:**
- Produces: the table phase 3 (Task 6) looks up by `template_id`. Columns are fixed here; phase 3's task depends on these exact column names.

**Corrected 2026-08-31, mid-execution (supersedes the version Task 4 originally shipped and passed review under):** the catalog is now 6 templates only — `fixed_outcome/v1`, `fast-clocks/v1`, `us-04-research-report/v1` were removed (see Global Constraints). Every remaining template's descriptor now also carries a real `descriptor.presentation.name`/`descriptor.presentation.summary` — platform-authored, not curated. Steps below are rewritten against this corrected ground truth; a prior version of `template-characteristics.md` describing 9 templates with 3 marked "needs curation owner input" is stale and must be replaced, not merely appended to.

- [ ] **Step 1: Confirm the structural facts and presentation summaries against the real descriptor JSON**

Run, for each of the 6 templates, from the `passport` repo (read-only, no changes there):

```bash
for f in standard recruiting data-seller content-generator coding security-audit; do
  echo "=== $f ==="
  python3 -c "
import json
d = json.load(open('/Users/spring-kite/Dev/gokite/passport/pkg/a2a/templates/v1/$f.json'))
props = d['descriptor']['spec']['configuration']['schema']['properties']
pres = d['descriptor']['presentation']
print('name:', pres['name'])
print('summary:', pres['summary'])
print('windows:', list(props['windows']['properties'].keys()))
print('maxRedeliveries max:', props['limits']['properties']['maxRedeliveries']['maximum'])
print('skippable states:', props['skippedStates']['items']['enum'])
"
done
```

If the local `passport` checkout is stale, fetch first: `cd /Users/spring-kite/Dev/gokite/passport && git fetch origin main --quiet` and read files via `git show origin/main:pkg/a2a/templates/v1/<f>.json` instead of the working tree, to avoid depending on which branch happens to be checked out locally.

Expected: output matches the groupings below (re-confirmed 2026-08-31 against `origin/main`):
- `standard`: name "Standard delivery", summary "The full agreement lifecycle with delivery review, appeal, and third-party arbitration." Full lifecycle (funding/delivery/deliveryConfirmation/appeal/arbitration windows; skip-eligible states include the full reject→appeal→dispute→arbitration→resolve chain).
- `recruiting`: name "Recruiting", summary "Candidate-sourcing delivery with buyer confirmation and no dispute branch." Short lifecycle (funding/delivery/deliveryConfirmation windows only; no reject/appeal/dispute states configurable; only `REFUNDING_UNDELIVERED` in the refund family).
- `data-seller`: name "Data seller", summary "Dataset delivery with buyer confirmation and no dispute branch." Same short-lifecycle shape as `recruiting`.
- `content-generator`: name "Content generator", summary "Content delivery with rejection and bounded redelivery, no arbitration." Mid lifecycle (funding/delivery/deliveryConfirmation/appeal windows; reject→redeliver→refund states configurable, no appeal/dispute/arbitration states).
- `coding`: name "Coding", summary "Software-deliverable workflow with rejection and bounded redelivery, no arbitration." Same mid-lifecycle shape.
- `security-audit`: name "Security audit", summary "Audit-report delivery with rejection and bounded redelivery, no arbitration." Same mid-lifecycle shape.

Also confirm no `evaluationMode`/oracle field exists anywhere in any of the 6 files, and that every `evidence.items[].producer` value is one of `buyer`/`seller`/`buyerOwner`/`chain` (never an oracle role) — this is what backs the claim that evaluation is always buyer-driven on this platform today.

- [ ] **Step 2: Write the reference file**

```markdown
# Template Characteristics

Loaded only during phase 3 (deal shape). The template name never appears
in a question to the seller -- it appears only in the phase-3 summary
("this maps to `<template_id>`").

Three kinds of columns here:
- **Name / Summary** -- the platform's own `descriptor.presentation.name`
  and `.summary` fields (`pkg/a2a/templates/v1/*.json` in the `passport`
  repo). Authoritative, not curated -- quote them directly.
- **Structural** (Windows, Max redeliveries, Escalation path) -- also
  verified directly against the descriptor JSON. Re-run Task 4 Step 1's
  script if this table is ever suspected stale.
- **Choose this when** -- built from the Summary field plus the
  structural shape, not invented from scratch. There is still no
  `evaluationMode`/oracle field in any descriptor (confirmed 2026-08-31)
  -- evaluation is always buyer-driven, inferred from whether
  `REJECTING`/`REJECTED` states are configurable at all.

The catalog is exactly these 6 templates as of 2026-08-31 (`origin/main`,
`passport` repo) -- there is no undescribed/unavailable-template case to
handle; every template a seller could pick has a real descriptor.

| Template ID | Name | Summary | Windows | Max redeliveries | Escalation path | Choose this when |
|---|---|---|---|---|---|---|
| `standard/v1` | Standard delivery | The full agreement lifecycle with delivery review, appeal, and third-party arbitration. | funding, delivery, deliveryConfirmation, appeal, arbitration | 0-3 | Full: reject -> appeal -> dispute -> arbitration -> resolve | Default choice for anything where a buyer might reasonably dispute quality and you want a formal appeal/arbitration escalation available as a last resort. |
| `recruiting/v1` | Recruiting | Candidate-sourcing delivery with buyer confirmation and no dispute branch. | funding, delivery, deliveryConfirmation | 0-3 | None: delivered or not; only `REFUNDING_UNDELIVERED` available | Candidate-sourcing / matching work where "delivered" is binary (a candidate list either arrived or didn't) -- no post-delivery quality dispute lane. |
| `data-seller/v1` | Data seller | Dataset delivery with buyer confirmation and no dispute branch. | funding, delivery, deliveryConfirmation | 0-3 | None: same shape as `recruiting/v1` | Data/dataset delivery where the artifact is verifiable at delivery time (hash match) and there's no meaningful "I don't like the data" rejection path. |
| `content-generator/v1` | Content generator | Content delivery with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: reject -> redeliver -> refund; no appeal/dispute/arbitration escalation | Creative/generated-content work where the buyer might reasonably ask for one redo, but a formal arbitration escalation is overkill. |
| `coding/v1` | Coding | Software-deliverable workflow with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: same shape as `content-generator/v1` | Code/implementation deliverables -- redeliver-on-reject fits "the tests didn't pass, try again" better than a dispute process. |
| `security-audit/v1` | Security audit | Audit-report delivery with rejection and bounded redelivery, no arbitration. | funding, delivery, deliveryConfirmation, appeal | 0-3 | Mid: same shape as `content-generator/v1` | Audit/report deliverables with a possible one-shot revision, no formal appeal process. |

## How phase 3 uses this table

Ask the seller about deal-shape *characteristics*, never the template
name:
- "If a buyer isn't happy with what you deliver, do you want a chance to
  redo it, or is delivered-is-delivered?" -> maps to escalation-path
  column.
- "Could a delivery genuinely be disputed by a reasonable buyer, or is
  success obvious from the artifact itself?" -> distinguishes
  `standard/v1` (formal arbitration warranted) from the mid-lifecycle
  group.

Then pick the matching row and only *afterward* reveal the template ID in
the phase-3 summary.
```

- [ ] **Step 3: Stage**

```bash
git add seller-onboarding/references/template-characteristics.md
```
(No commit -- this repo requires manual, GPG-signed commits by the owner.)

---

### Task 5: Phase 2 (offers) and Phase 3 (deal shape)

**Files:**
- Modify: `seller-onboarding/SKILL.md`

**Interfaces:**
- Consumes: `seller.agent_did` (Task 3), `references/commands.md#offers-phase-2` (Task 2), `references/template-characteristics.md` (Task 4)
- Produces: `seller.offer.service_description`, `seller.offer.advertised_price_minor`, `seller.offer.reserve_floor_minor` (optional), `seller.offer.template_id` — Task 7 (governance) and Task 9 (standing orders) consume these by name.

- [ ] **Step 1: Write the eval case**

```json
{
  "id": 105,
  "prompt": "Run seller-onboarding phase 2 for a seller whose agent does candidate sourcing for recruiters, charging based on successful placements.",
  "expected_output": "The skill proposes an offer (service description, suggested price) rather than asking the seller to fill in four platform fields at once, and asks two intent-level price questions: what to advertise publicly, and (for negotiated offers) the lowest they'd actually take, explaining that number is private and buyers never see it.",
  "assertions": ["propose", "advertise", "buyers never see"]
}
```

```json
{
  "id": 106,
  "prompt": "Run seller-onboarding phase 3. The seller says: 'if a buyer isn't happy, delivered is delivered, no do-overs, and honestly a placement either happened or it didn't.'",
  "expected_output": "Maps this to recruiting/v1 or data-seller/v1 (no reject/redeliver lifecycle) based on the characteristics table, and reveals the template ID only in the summary, never as a question.",
  "assertions": ["recruiting/v1"]
}
```

- [ ] **Step 2: Verify both fail**

Run: dispatch a `general-purpose` subagent per prompt, reading only the `SKILL.md` content that exists before this task (phases 0-1 only).
Expected: FAIL — no phase 2/3 instructions exist yet.

- [ ] **Step 3: Append phase 2 and phase 3 to `SKILL.md`**

```markdown
## Phase 2 -- Offers

Read the seller's codebase for signals about what their agent does (its
skill/tool descriptions, README, prior invocations) and *propose* an
offer: a one-line service description and a suggested price. The seller
confirms or edits -- never starts from a blank form.

Ask exactly two price questions, both intent-level:
1. **"What do you want to advertise as your price?"** (public rate-card
   price or range.)
2. For negotiated offers only: **"What's the lowest you'd actually
   take? Deals below this come to you for approval -- buyers never see
   this number."** (Private mandate floor, optional -- skip this
   question entirely for a fixed-price offer, since there's nothing to
   negotiate below.)

Record `seller.offer.service_description`, `seller.offer.advertised_price_minor`,
and (if answered) `seller.offer.reserve_floor_minor`.

Multiple offers are supported by repeating phases 2-4 once per offer
(source design doc open item -- treat as a repeat pass, not a parallel
flow, for v1).

## Phase 3 -- Deal shape

Ask about characteristics, never template names, using
`references/template-characteristics.md`'s "How phase 3 uses this table"
guidance. Once you have enough answers to pick a row, tell the seller
the mapping in the summary only: **"This maps to `<template_id>`."**

Every template in `references/template-characteristics.md` is now platform-described (no undescribed-template case exists as of the 2026-08-31 catalog correction). If the seller's answers genuinely don't fit any of the 6 rows, default to `standard/v1` -- the full lifecycle (reject -> appeal -> dispute -> arbitration -> resolve) is the safest general-purpose fallback -- and say so plainly rather than silently forcing a fit.

Record `seller.offer.template_id`.
```

- [ ] **Step 4: Re-run evals 105/106**

Run: dispatch subagents per prompt, reading the full `SKILL.md` through phase 3 plus `references/template-characteristics.md`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add seller-onboarding/SKILL.md evals/evals.json
git commit -m "feat(seller-onboarding): add phase 2 (offers) and phase 3 (deal shape)"
```

---

### Task 6: Phase 4 (governance)

**Files:**
- Modify: `seller-onboarding/SKILL.md`

**Interfaces:**
- Consumes: `seller.agent_did`, `seller.offer.template_id`, `seller.offer.reserve_floor_minor`, `seller.offer.advertised_price_minor` (Tasks 3, 5); `references/commands.md#governance-phase-4` (Task 2)
- Produces: `seller.governance.confirmed` (boolean — set only after the explicit confirmation step), consumed by Task 8's fail-closed check.

- [ ] **Step 1: Write the eval case**

```json
{
  "id": 107,
  "prompt": "Run seller-onboarding phase 4. The seller set an advertised price of 50 USDC and a private reserve floor of 35 USDC for recruiting/v1 in phase 2.",
  "expected_output": "The skill computes the mandate (template allowlist, price floor/ceiling from the phase-2 answers, capacity) and shows the owner the exact values before writing them via a plain owner-JWT PUT to /v1/agents/{agent}/acceptancePolicy -- it does not mention a passkey approval step or a separate dashboard trip for this write, and it asks for explicit confirmation before writing.",
  "assertions": ["acceptancePolicy", "confirm"]
}
```

- [ ] **Step 2: Verify it fails**

Run: dispatch a subagent reading `SKILL.md` through phase 3 only.
Expected: FAIL.

- [ ] **Step 3: Append phase 4 to `SKILL.md`**

```markdown
## Phase 4 -- Governance

Derived, not asked. Compute the mandate directly from what the seller
already decided in phase 2:
- `templates`: `[seller.offer.template_id]` (extend this list if the
  seller has run phases 2-4 more than once for multiple offers).
- `price_floors[template_id]`: `seller.offer.reserve_floor_minor` if set,
  otherwise omit (no floor means any priced-and-in-scope deal is
  acceptable).
- `price_ceilings[template_id]`: `seller.offer.advertised_price_minor`,
  unless the seller's advertised price was itself a range, in which case
  use the top of that range.
- `max_open_obligations`: not asked in v1 -- omit unless the seller
  raises capacity unprompted.

Show the owner the exact computed values, explained as "the guardrail
behind your agent -- it can't be read or changed by the agent itself,"
and ask for explicit confirmation before writing. GET the current policy
first to read its `version` (0 if none exists yet), then write via a
plain owner-JWT `PUT` including that version (see
`references/commands.md#governance-phase-4`) -- **no passkey ceremony, no
separate dashboard approval needed for this step** (removed from the
platform 2026-08-24). Do not describe this as requiring a passkey or a
dashboard trip. If the PUT is refused with 409 (stale version), GET again
and retry -- never guess the version.

One genuine question here, not derived: **"Your agent will auto-accept
anything in-scope and priced, and decline the rest -- do you want
anything routed to you first?"** Be honest that there's no
platform content/legal/ethical signal to lean on for this -- it's a plain
allow/escalate rule, not a smart filter.

Record `seller.governance.confirmed = true` only after the owner
confirms and the PUT succeeds. If the owner declines, stop here --
do not proceed to phase 5 with an unconfirmed mandate.
```

- [ ] **Step 4: Re-run eval 107**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add seller-onboarding/SKILL.md evals/evals.json
git commit -m "feat(seller-onboarding): add phase 4 (governance)"
```

---

### Task 7: `references/standing-orders-template.md`

**Files:**
- Create: `seller-onboarding/references/standing-orders-template.md`

**Interfaces:**
- Consumes: `seller.offer.reserve_floor_minor`, `seller.offer.template_id` (Task 5), `seller.governance.confirmed` (Task 6)
- Produces: the exact section headings (`## decide`, `## request`, `## rejected`) Task 9's `kite-seller/SKILL.md` edit must read by name.

- [ ] **Step 1: Write the template file**

```markdown
# Standing Orders Template

Phase 5 fills this scaffold with the seller's interview answers and writes it to `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md`. Section headings (`decide`, `request`, `rejected`) are read by `kite-seller/SKILL.md` -- do not rename them without updating that file too (see Task 9).

```markdown
---
name: seller-acceptance
description: Your agent's standing orders -- your business judgment for each buyer interaction. You own this file; it lives in your repo.
---

# Standing Orders

## decide

Accept a proposal when:
- The template matches: `<seller.offer.template_id>`.
- The price is at or above your private floor (`<seller.offer.reserve_floor_minor>` minor units) -- this number is enforced by the platform mandate too, so a deal your agent accepts here can never be parked by the mandate afterward.
- The scope fits what you actually offer: <seller.offer.service_description>.

Escalate (do not auto-decide) when:
- <owner's phase-4 escalation answer, verbatim>

Decline everything else.

## request

Pre-deal chat, quote asks, clarifications, sample requests:
- Quote per your published card -- never quote below `<seller.offer.reserve_floor_minor>` minor units, since that's the same number your mandate will refuse to let you accept.
- Answer briefly, on-topic. Don't engage open-ended free chat -- it costs your agent's tokens with no payment guarantee.

## rejected

If a buyer rejects your delivery:
- Revise once if the rejection names something concrete and fixable.
- Consent-refund if the objection is right, or if finishing would take far longer than the deal is worth -- an early honest refund protects your reputation more than a garbage delivery.
- Appeal only when the delivery clearly meets what was signed for.
```
```

- [ ] **Step 2: Commit**

```bash
git add seller-onboarding/references/standing-orders-template.md
git commit -m "docs(seller-onboarding): add standing orders template"
```

---

### Task 8: Phase 5 (standing orders review) — write the file and enforce pricing-chain consistency

**Files:**
- Modify: `seller-onboarding/SKILL.md`

**Interfaces:**
- Consumes: `seller.governance.confirmed`, `seller.offer.*` (Tasks 5, 6), `references/standing-orders-template.md` (Task 7)
- Produces: the written `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md` file, which Task 9's `kite-seller/SKILL.md` reads at runtime.

- [ ] **Step 1: Write the eval case**

```json
{
  "id": 108,
  "prompt": "Run seller-onboarding phase 5 after phase 4 confirmed a mandate with price_floors.recruiting/v1 = 35000000 (35 USDC, 6 decimals).",
  "expected_output": "Fills references/standing-orders-template.md with the same 35000000 floor used in the phase-4 mandate PUT -- the request section's quote-floor language uses the identical number, not a re-derived or re-asked value. Requires explicit owner OK before writing the file.",
  "assertions": ["35000000", "explicit"]
}
```

- [ ] **Step 2: Verify it fails**

Expected: FAIL — no phase 5 instructions exist yet.

- [ ] **Step 3: Append phase 5 to `SKILL.md`**

```markdown
## Phase 5 -- Standing orders review

Refuse to proceed if `seller.governance.confirmed` is not `true` -- phase 4 must complete first (fail-closed, matches phase 6's own fail-closed default).

Fill `references/standing-orders-template.md` with the interview answers, using the **exact same numeric values** already written to the mandate in phase 4 -- `seller.offer.reserve_floor_minor` appears in both the mandate's `price_floors` and this file's `request`/`decide` sections, computed once in phase 2 and never re-derived. This is what guarantees the seller's agent can never quote a price its own mandate would later park.

Present the filled scaffold to the seller as: "these are your agent's standing orders; they live in your repo; you own them." Explain the two layers this file sits between: Kite's skills are the how-to-operate runbooks, this file is the seller's own business judgment. Require explicit OK before writing to `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md`.
```

- [ ] **Step 4: Re-run eval 108**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add seller-onboarding/SKILL.md evals/evals.json
git commit -m "feat(seller-onboarding): add phase 5 (standing orders review)"
```

---

### Task 9: `kite-seller/SKILL.md` — read `request`/`rejected` standing-orders sections

**Files:**
- Modify: `kite-seller/SKILL.md` (currently reads the standing-orders file only for `decide`, per `kite-seller/SKILL.md:178-184`)

**Interfaces:**
- Consumes: the `decide`/`request`/`rejected` section headings from `references/standing-orders-template.md` (Task 7) as written into the seller's repo by phase 5
- Produces: nothing further downstream — this is the terminal consumer of the standing-orders file.

- [ ] **Step 1: Read the current `decide` handling to match its style**

Run: `sed -n '138,193p' kite-seller/SKILL.md` (the current `decide` section, per prior research) to see exactly how it currently instructs reading `seller-acceptance/SKILL.md`, so the new `request`/`rejected` instructions match its tone and structure rather than diverging.

- [ ] **Step 2: Write the eval case**

```json
{
  "id": 109,
  "prompt": "You are running under kagent serve --handler kite-agent-handler and receive a `request` operation: a buyer asking for a sample of your work before committing. Your repo has a .claude/skills/seller-acceptance/SKILL.md with a `## request` section saying to answer briefly and never quote below your floor.",
  "expected_output": "kite-seller reads the seller-acceptance file's request section (not just decide) and follows its quoting-floor instruction, rather than improvising an answer with no reference to the seller's own standing orders.",
  "assertions": ["seller-acceptance", "request"]
}
```

```json
{
  "id": 110,
  "prompt": "You are running under kagent serve --handler kite-agent-handler and receive a `rejected` operation after a buyer rejected your delivery. Your seller-acceptance/SKILL.md has a `## rejected` section saying to consent-refund if the objection is right.",
  "expected_output": "kite-seller reads the seller-acceptance file's rejected section and applies its stated policy (consent-refund vs revise vs appeal) rather than defaulting to always-appeal or always-revise.",
  "assertions": ["seller-acceptance", "rejected", "consent-refund"]
}
```

- [ ] **Step 3: Verify both fail against the current file**

Run: dispatch subagents per prompt, reading the current (unmodified) `kite-seller/SKILL.md`.
Expected: FAIL — per prior research, `kite-seller/SKILL.md:178-184` only reads the acceptance file for `decide`; the `request` (lines ~68-136) and `rejected` (lines ~195-217) sections don't currently reference it.

- [ ] **Step 4: Edit `kite-seller/SKILL.md`**

In the `request` section (around line 68-136), add a paragraph immediately after whatever currently describes default quoting behavior:

```markdown
Before quoting, check whether `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md` has a `## request` section. If it does, follow its quoting-floor and chat-engagement instructions exactly -- in particular, never quote below any floor it states, since that floor is the same number your owner's platform mandate will enforce at accept time. If no such section exists, use the v1 default: quote per your published card, answer briefly on-topic, don't engage open-ended free chat.
```

In the `rejected` section (around line 195-217), add a similar paragraph:

```markdown
Before choosing revise / consent-refund / appeal, check whether `<seller-repo>/.claude/skills/seller-acceptance/SKILL.md` has a `## rejected` section. If it does, follow its stated policy for which of the three arms to take. If no such section exists, use the v1 default: revise once if the rejection is concrete, consent-refund when the objection is right, appeal only when the delivery clearly meets the signed criteria.
```

- [ ] **Step 5: Re-run evals 109/110 against the modified file**

Expected: PASS.

- [ ] **Step 6: Run the existing `kite-seller` evals (98-101) to check for regressions**

Run: dispatch subagents against evals 98-101 from `evals/evals.json` (existing `kite-seller` coverage), reading the modified `kite-seller/SKILL.md`.
Expected: PASS, same as before this change — the edit only adds new paragraphs to `request`/`rejected`, it doesn't touch `decide`/`start`/`closed`.

- [ ] **Step 7: Commit**

```bash
git add kite-seller/SKILL.md evals/evals.json
git commit -m "feat(kite-seller): read standing-orders request/rejected sections"
```

---

### Task 10: Phase 6 (publish), Phase 7 (serve), Phase 8 (verify)

**Files:**
- Modify: `seller-onboarding/SKILL.md`

**Interfaces:**
- Consumes: everything from phases 0-5 (fail-closed check on `seller.governance.confirmed`), `references/commands.md#publish-phase-6` and `#serve-phase-7` (Task 2)
- Produces: nothing further — this is the terminal phase.

- [ ] **Step 1: Write the eval case**

```json
{
  "id": 111,
  "prompt": "Run seller-onboarding phase 6. Governance was never confirmed (phase 4 was skipped or declined).",
  "expected_output": "Refuses to publish -- explains the fresh-seller default is fail-closed (no policy means refuse everything, which looks exactly like a broken agent), and does not proceed to phase 7.",
  "assertions": ["fail-closed", "refuse"]
}
```

```json
{
  "id": 112,
  "prompt": "Run seller-onboarding phase 7 after a successful publish.",
  "expected_output": "Prints the kagent serve --handler kite-agent-handler command and describes what a healthy start looks like, but does not run the command itself -- it's a long-running process that must not die with the assistant.",
  "assertions": ["kagent serve", "does not run"]
}
```

```json
{
  "id": 113,
  "prompt": "Run seller-onboarding phase 8.",
  "expected_output": "Hands off to the Passport web Playground for the seller to run one deal against their own agent as a human, step by step -- never by improvising a buyer agent inside this same conversation.",
  "assertions": ["Playground", "never"]
}
```

- [ ] **Step 2: Verify all three fail**

Expected: FAIL — phases 6-8 don't exist in `SKILL.md` yet.

- [ ] **Step 3: Append phases 6, 7, 8 to `SKILL.md`**

```markdown
## Phase 6 -- Publish

Refuse to proceed if `seller.governance.confirmed` is not `true` or the standing-orders file from phase 5 wasn't written -- fail-closed is the correct default for a fresh seller (no policy means refuse everything, which looks exactly like a broken agent, not a safety net).

Run `kagent registration validate` (see `references/commands.md#publish-phase-6`), then `kagent registration publish`, then confirm with `kagent registration get`. Only declare success once readiness is actually confirmed by that last call -- not merely because the publish command didn't error.

## Phase 7 -- Serve

Print the exact command from `references/commands.md#serve-phase-7` (`kagent serve --handler kite-agent-handler ...`). Describe what a healthy start looks like (the process stays running, logs incoming operations). **Never run this command yourself** -- it's long-running and must survive independently of this conversation. Tell the seller what to come back with once it's running.

## Phase 8 -- Verify

Hand off to the Passport web Playground (or seller console): the seller, as a human, runs one deal against their own agent, step by step. **Never** improvise a buyer agent inside this same conversation to test against -- two engines in one workspace has caused real confusion in trials. Onboarding is complete only once the seller has watched one deal settle.
```

- [ ] **Step 4: Re-run evals 111-113**

Expected: PASS.

- [ ] **Step 5: Check `SKILL.md`'s total line count**

Run: `wc -l seller-onboarding/SKILL.md`
Expected: if over ~350 lines, split phases 6-8 (or another natural boundary) into a `references/publish-serve-verify.md` file per the repo's split convention, cross-referenced the same way `references/commands.md` already is. If under, no split needed.

- [ ] **Step 6: Commit**

```bash
git add seller-onboarding/SKILL.md evals/evals.json
git commit -m "feat(seller-onboarding): add phase 6 (publish), 7 (serve), 8 (verify)"
```

---

### Task 11: Update `evals/README.md` coverage table

**Files:**
- Modify: `evals/README.md`

**Interfaces:**
- Consumes: the final eval id range from Tasks 1-10 plus the mid-flight fallback-template correction (102-114)
- Produces: nothing — documentation only.

**Corrected 2026-08-31, mid-execution:** eval id 114 was added after Task 10 (a mid-flight fallback-template correction to Task 5's Phase 3 content, requested by the user) -- the coverage row must include it.

- [ ] **Step 1: Add a coverage-table row**

In the `## Coverage by skill` table, add:

```markdown
| 102-108, 111-114 | seller-onboarding | seller-agent |
```

(Ids 109-110 belong to `kite-seller`'s existing row, not a new one — they test `kite-seller`'s behavior, not `seller-onboarding`'s. Update the existing `kite-seller` row from `98-101` to `98-101, 109-110`.)

- [ ] **Step 2: Verify the full eval file is still valid JSON**

Run: `python3 -c "import json; d = json.load(open('evals/evals.json')); print(len(d))"`
Expected: prints a count equal to the previous count plus 13 (ids 102-114).

- [ ] **Step 3: Commit**

```bash
git add evals/README.md
git commit -m "docs(evals): add seller-onboarding coverage row"
```

---

## Self-Review

**Spec coverage:**
- File layout (SKILL.md, 3 references files, kite-seller edit, skills.json, evals) — Tasks 1, 2, 4, 7, 9, 1 (skills.json), 1/3/5/6/8/10 (evals) all covered.
- Phases 0-8 — Tasks 3, 5, 6, 8, 10.
- Standing-orders format extension + `kite-seller` update — Tasks 7, 9.
- Pricing-chain consistency — Task 8 Step 3 (same numeric value flows from phase 2 through phase 4's mandate PUT into phase 5's file).
- Error handling table from the spec — folded into phase 0 (auth translation), phase 1 (stop sign), phase 4 (decline stops the flow), phase 6 (fail-closed refusal) rather than a separate task, matching the task-sizing guidance to fold behavior into the phase that needs it.
- Testing — every phase task writes its eval case first, per repo convention (manual grading, no automated runner).
- Corrections table from the spec (template count, passkey removal, no-CLI-change, URL/URN) — all reflected in the relevant task's content (Task 4's structural facts, Task 6's phase-4 copy, Task 9's no-passport-cli-change framing, Task 3's dropped URL/URN cushion).

**Placeholder scan:** no TBD/TODO. **Superseded 2026-08-31:** Task 4 originally shipped with 3 templates marked "needs curation owner input" (no descriptor existed for them); the catalog has since dropped those 3 entirely and every remaining template now carries a platform-authored `presentation.name`/`.summary`, so that caveat no longer applies -- see Task 4's corrected content above.

**Type/name consistency:** `seller.agent_did`, `seller.public_name`, `seller.offer.service_description`, `seller.offer.advertised_price_minor`, `seller.offer.reserve_floor_minor`, `seller.offer.template_id`, `seller.governance.confirmed` — each introduced once (Tasks 3, 5, 6) and referenced identically by every later task that consumes it; checked no drift in naming across tasks 6, 7, 8.

---

Plan complete and saved to `docs/superpowers/plans/2026-08-31-seller-onboarding-skill.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
