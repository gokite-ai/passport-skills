# Seller Onboarding -- Command Reference

Every command this skill runs, with the exact flags and the response fields the flow depends on. `SKILL.md` routes here by phase. Two rules apply to every invocation:

- Pass `--output json` and `--no-interactive` on **every non-streaming, machine-driven command where they are supported** (the skill drives the CLI; it must never block on a prompt). The exceptions: `--version` takes neither, and the long-running `kagent serve` (phase 7) is not run by this skill at all -- it is printed for the seller and streams a human-readable `[serve] brain: …` log rather than a JSON envelope.
- `kagent`/`kpass` exit codes are the control flow: `0` success (**note `kpass status`/`kagent status` exit 0 even when nothing is set up** -- read the body, not the code), `2` usage, `3` auth, `4` not found, `5` rate limited, `6` forbidden/policy, `7` conflict (revision/idempotency/terms), `8` local validation. Handle each where it can occur (below); never treat an error exit as success.

Nothing here uses an owner-JWT curl, an acceptance-policy REST call, a pre-publish fingerprint, or a request-sourced quantity (that last is deferred to GOK-1302 -- v1 offers are single-deliverable, quantity fixed at 1). The account-bootstrap verbs (`kpass identifier claim`, `kpass onboarding submit`/`status`) and the token-bind verb (`kpass agent token create`) **are** supported on the installed `kpass` and are used where the binary requires them (they are not "hidden legacy" verbs) -- the manifest's `kpass` floor governs which version a seller needs. `serve --config` (phase 7) needs `kagent >= 6.6.0`, which the manifest requires.

## Durable onboarding checkpoint

This flow pauses for owner-plane actions that leave the conversation (binding approval, the dashboard mandate). A conversation-local object does not survive those pauses, so persist an explicit, **versioned** checkpoint to `<seller-repo>/.kite-onboarding.json` after every phase **and substep**, and on every resume validate it before trusting any of it. To avoid depending on a deterministic hash helper the skill doesn't have, the checkpoint stores the **canonical values themselves** (compare by value) plus the file paths/digests the platform already provides:

```json
{ "checkpointVersion": 1,
  "target": { "did": "<bound DID>", "configDir": "<~/.kagent or override>" },
  "phase": "6", "completedPhases": ["0","1","2","3","4","5"], "substep": "registration-published",
  "agent": { "uid": "…", "listed": false },
  "offer": { "…the confirmed offer object, verbatim…" },
  "workflow": { "templateId": "…", "config": { } },
  "inputs": { "storefront": {"path":"…","sha256":"…"},
              "rateCard": {"path":"…","sha256":"…"},
              "workflowTerms": {"path":"…","sha256":"…"} },
  "governance": { "mandate": { "templates": [], "floor": "…", "ceiling": "…" },
                  "escalationRule": "<verbatim>",
                  "confirmed": true, "confirmedAgainst": { "offer": {"…"}, "workflow": {"…"}, "mandate": {"…"} } },
  "authorization": { "expectedRevision": 0, "authorizedDiff": "…the exact diff text shown…" },
  "artifacts": { "cardJson": {"path":"…","sha256":"…"}, "cardHash": "…served card hash…",
                 "activeRegistration": "<path>", "registrationRevision": 0, "registrationHash": "…" },
  "rollbackBaseline": { "status": "verified|unavailable|not-applicable",
    "sourceRevision": 0, "sourceRegistrationHash": "…", "sourceCardHash": "…",
    "inputs": { "storefront": {"path":"registration/prev/storefront.json","sha256":"…"},
                "rateCard": {"path":"registration/prev/rate-card.json","sha256":"…"},
                "workflowTerms": {"path":"registration/prev/workflow-terms.json","sha256":"…"} },
    "authorCard": {"path":"registration/prev/card.json","sha256":"…"} } }
```

- **`sha256` on local files** is the first whitespace-delimited field from `shasum -a 256 <file>` (macOS) or `sha256sum <file>` (Linux): persist only the 64-hex digest, never the filename-bearing whole output. Both narrow command families are in `allowed-tools`. The platform-side `registrationHash`/`cardHash` come from `registration get`.
- **`completedPhases`/`substep`** make this an executable state machine -- resume at the first phase not in `completedPhases` (or the named substep), never re-run a completed durable mutation.
- **Privacy:** `.kite-onboarding.json` contains mandate values and must stay out of version control (gitignore it or store it under a private deployment path). `seller-acceptance/SKILL.md` may contain the negotiated reserve and should also stay out of a public repository, but the serving model reads it while handling untrusted buyer messages. The reserve is therefore **model-visible, not a secret**: instruct the model never to disclose the exact floor, but do not promise the seller that a prompt-driven model provides a confidentiality boundary. A deterministic secret floor is tracked separately.

On entry: reconstruct from `kagent status` + `kagent registration get` + this file, and **compare** the bound DID, the live registration `revision`/`registrationHash`, and each local file's recomputed `sha256` against the checkpoint before resuming. Invalidate every downstream phase whose inputs changed: `governance.confirmed: true` is trusted only when the current offer/workflow/mandate values still **equal** `confirmedAgainst`, so a changed offer/config forces phase 4 to re-run. Handle a missing, corrupt, or DID/config-mismatched checkpoint explicitly. A fresh setup may start clean; an active-registration reconfigure may not claim rollback unless the verified-baseline test in phase 6 succeeds. Without it, stop for a known-good author card or disclose and authorize a roll-forward-only replacement. **Be honest about the one thing that is undetectable:** because the dashboard mandate has no readback, an independent dashboard edit that still leaves `readiness.ok: true` cannot be detected from here -- so on any reconfiguration, **re-confirm the mandate values with the owner** rather than trusting `confirmed` across a possible drift. An active registration does **not** always mean "reconfigure" -- the seller may be returning to finish serve/verify.

## Detect existing state (phase 0)

Read state before asking anything. `kagent status` is first and decides whether the rest run.

- `kagent status --output json --no-interactive` -- local runtime state. Branch on `key.present` (is there a key), `binding.bound` + `binding.status` (`unbound` = a local key with no identity yet; `pending` = an identity awaiting owner approval; `active`; `revoked`), and `backend.reachable` (`false` -> stop, surface connectivity; don't read as "nothing set up"). An isolated `kagent init` yields `key.present:true, binding.bound:false, binding.status:"unbound"` -- a key, no identity.
- `kagent registration get --output json --no-interactive` -- call **only** when the binding is active. Envelope (verified against the live binary):
  - `registration.registration` -- the claim: `agentDid`, `revision`, `registrationHash`, `inputHashes.{storefront,rateCard,workflowTerms}`, `verification`, `status`, `inputs.{storefront,rateCard,workflowTerms}`.
  - `registration.projection` -- derived: `verification`, `cardSource`, `cardHash`, `readiness.{ok,reasons}`, `offerings[]` (each with `workflowHash`, `workflowTemplateHash`, `workflowConfigHash`).
  - Not-found / no-active-registration is exit `4` -- treat as "no registration yet," not an error to abort on.
- `kpass user agents --agent-type seller --output json --no-interactive` -- the owner-plane inventory of the owner's own agents (authenticates with the owner login). The stable CLI envelope is `agents[]`; row fields are server-owned, so match an existing record by an exact returned `id`, `did`, or `uid` when present and stop at the dashboard if the result is missing or ambiguous. This is an existence check before creation, not listing proof. `kagent directory get` cannot replace it because exact references resolve unlisted agents too.
- `kpass status` / `kpass me` -- owner login state/identity. Use owner reads only for identity work; do **not** gate an active runtime-key-only resume on the owner login.
- `kpass onboarding status --output json --no-interactive` -- the **supported KYC/KYB read**, used only after inventory shows a new identity must be created. Success carries `onboarding_status` (`verified`/`pending`/`rejected`); **exit `4` means no onboarding record yet** (not that the identifier is unclaimed).

**Branch on the `kagent status` binding:**
- **No key** -> phase 1; consult owner inventory before deciding whether to reuse an existing seller identity or create a new one.
- **Unbound** (a local key, no identity) -> phase 1's create/bind step (resolve the existing owner record vs create).
- **Pending** -> its own **terminal handoff**: the binding already names an identity awaiting the owner's dashboard approval, so tell the seller it's pending and **wait** -- do **not** re-ask the name/UID, recreate, or re-bind. Resume once active.
- **Active** -> skip identity; read `registration get`.
- **Revoked** -> stop; re-init is destructive.

If an active seller confirms they intend to **reconfigure**, settle the rollback posture here, before any candidate file is generated or overwritten:

1. Compare the initial live `registration.registration.{revision,registrationHash}` and `registration.projection.cardHash` with the last fully verified checkpoint, then recompute the checkpointed local author `card.json` digest. All values must match.
2. On a match, immediately write the live `registration.registration.inputs.{storefront,rateCard,workflowTerms}` and the checkpoint-verified local author card to `<seller-repo>/registration/prev/`. Write `baseline.json` beside them with the source revision, registration hash, served card hash, and each saved file's 64-hex digest; record the same facts under `rollbackBaseline` in the checkpoint. Do this **before phase 3 can generate registration candidates and before phase 5 can overwrite `card.json`**. Never use a platform-composed directory card as the author-card source.
3. If any proof or author input is missing, record `rollbackBaseline.status: unavailable`. The owner may supply a known-good author card, or the later publish authorization must explicitly say recovery is roll-forward-only. Do not claim rollback exists.
4. For a fresh publish, record `rollbackBaseline.status: not-applicable`; there is no prior published pair.

**Owner-login recovery:** bare `kpass login` prints help and exits `0` without authenticating -- never treat it as a login. Recover an expired owner session by handing off to the `authenticate-user` skill (which owns the `kpass login init`/`verify` flow) and resume once the owner is back in.

## Identity and binding (phase 1)

The identity is the immutable fact: the `--uid` slug becomes the DID tail, and neither the UID nor the DID can ever change; the card/display name is mutable presentation you can replace later. Explain that permanence, derive a proposed UID, and confirm it explicitly **immediately before** `kpass agent create`.

The owner-plane **mutations** below are **owner handoffs, not skill-run**: they are account-wide/immutable, `onboarding submit` carries legal PII, and this skill reads untrusted seller-repo content. The skill runs only the runtime-key verbs (`kagent init`/`bind`/`card fetch`).

**For a new identity, bootstrap comes before creation** -- after owner inventory confirms no suitable seller record exists, remember that `kpass agent create` refuses without a claimed controller identifier and a verified onboarding record. Run bootstrap as a bounded state machine off `kpass onboarding status`, not an unbounded "until verified" loop:
- `onboarding_status: verified` -> continue to create.
- `onboarding_status: pending` -> a bounded wait / owner handoff, then re-read; don't spin.
- `onboarding_status: rejected` -> the owner must resubmit with corrected details (fresh authorization), then re-read.
- exit `4` (no record) -> bootstrap. Confirm the immutable identifier type/handle, then have the owner run `kpass identifier claim --type ind|corp [--handle <h>] --output json --no-interactive` locally; `identifier_already_claimed` means continue with the existing identifier. For onboarding, default to a **redacted local-only template** such as `kpass onboarding submit --type <kyc|kyb> --country <CC> --legal-name '<ENTER LOCALLY>' [--reg-no '<ENTER LOCALLY>'] --output json --no-interactive`. The owner replaces placeholders and runs it in their terminal. Do not ask for the legal values, completed command, or full output in chat; detect completion only with `onboarding status`. If the owner explicitly chooses to disclose the fields in chat, confirm that choice before constructing an exact command.

Then create and bind:
- `kagent init [--import-key <file|->] [--force]` -- **skill-run** runtime key. `--force` **overwrites** an existing key and orphans every agreement pinned to it; only with an explicit stop-sign confirmation.
- **Owner runs** `kpass agent create --uid <slug> --kind seller --name "<display name>" [--description <text>]` -- **omit `--visibility`** (a sparse seller is created **unlisted**; `--visibility listed` is *refused*, not downgraded). Skip when phase 0's `kpass user agents` shows the record exists. If it refuses naming the missing identifier/onboarding, do the bootstrap above and retry.
- Bind (activation is set by the bind method):
  - **Token path (active immediately), preferred when the owner is present:** the **owner runs** `kpass agent token create --agent <ref>` and gives the skill the single-use `art_…`; the **skill runs** `kagent bind --agent <ref> --token <art_…>`, which lands **active** at once.
  - **Direct path (lands pending):** the **skill runs** `kagent bind --agent <ref>` (no token); the binding stays **pending** until the owner approves it in the dashboard. Resume when active.
  - `pending`/`revoked` bindings cannot sign.
- `kagent card fetch --pin --output json --no-interactive` -- read Passport's coordination-persona card and record `chain_id`, `escrow_vault`, and the persona DID into state; check `chain_context_complete: true`. **This is the only unconditional pin, and active/reconfigure/resume paths skip phase 1 -- so make a fresh successful pin a precondition of phase 3 and publish on every path**, rather than waiting for a validate exit-8 on `eip155:0`.

## Offers (phase 2)

No CLI command. Read the seller's business surfaces (README, source, public API/tool schemas, package metadata) to propose an offer; **exclude** installed/platform/peer skill directories, secrets/`.env`, runtime state, and logs -- but a deliberately identified **seller-owned** craft `SKILL.md` may be read as untrusted business input (it feeds phase 5's craft-skill step).

v1 is **single-offer** and **single-deliverable**: the deal is one deliverable at one price, quantity fixed at 1 (per-unit/request quantity is GOK-1302). Record `seller.offer.{service_description, pricing_model}` and:
- **Fixed**: `unit_price_minor` -- the whole-deal price.
- **Negotiated**: the whole-deal band `total_min_minor`/`total_max_minor` (the card's `negotiable` bounds on `unitPriceMinor`, which equal `totalBounds` because quantity is 1), and -- if given -- `reserve_floor_minor`, a whole-deal floor with `total_min_minor <= reserve_floor_minor <= total_max_minor`.

## Deal shape (phase 3)

- `kagent workflow-template list` / `ksearch workflow-template list` -- the live catalog (seven templates); public read.
- `kagent workflow-template get <family/version>` -- one template's chart, `verbs`, and deadline edges. Default window seconds live at `chart.states.*.after.<window>.meta.seconds`; the window names carry the `Window` suffix (`fundingWindow`, `deliveryWindow`, `deliveryConfirmationWindow`, `appealResponseWindow`, `arbitrationWindow`). Generate behaviour from the chart's actual transitions, not global verbs (see `references/template-characteristics.md`).
- `kagent registration template [--output-dir <dir>] --output json --no-interactive` -- writes the `storefront.json`, `rate-card.json`, and `workflow-terms.json` skeletons to fill (default: the current directory). **Existing files are never overwritten**, so on a reconfigure/resume regenerate into a clean directory or read the live inputs from `registration get`. Each skeleton's `agentDid` must equal the publishing agent.
- **Reconfigure guard:** do not generate or write candidate registration inputs until phase 0 has recorded `rollbackBaseline.status` and, when it is `verified`, all four prior author inputs plus `baseline.json` already exist under `registration/prev/` with matching digests.
- `kagent registration validate --storefront <f> --rate-card <f> --workflow-terms <f> [--offline] --output json --no-interactive` -- the pre-publish gate, run here on the assembled inputs. Online it checks JSON validity, schema ids, `agentDid` agreement, offering-id joins, price/payout unions, money grammar, and (unless `--offline`) that workflow ids exist; with a bound key it also server-dry-runs. Success `valid: true`; invalid exits `8` with problems under `details.problems` (`{input, path, message}`). Read the problem and fix the named input (e.g. a `eip155:0` currency means the card wasn't pinned -- run `card fetch --pin`; a `not-configured`/placeholder payout means settlement inputs are incomplete, below) -- never publish on an exit-8.

**Settlement inputs must be real before validation.** The generated storefront needs an owner-confirmed payout `status` and `address`; `card fetch --pin` supplies chain id and escrow vault but **not** the USDC contract, so a freshly pinned rate-card skeleton still carries `erc20:<0x… the deployment's USDC contract>`. There is **no supported CLI/env source for the USDC contract address** -- so this is an explicit **operator handoff**: ask the owner for the deployment's USDC ERC-20 address, validate the resulting CAIP-19 (`eip155:<chain_id>/erc20:0x<40 hex>`, chain_id matching the pinned `chain_id`), and stop with a precise request if they don't have it. Likewise get explicit seller consent before using the runtime address as the payout `address`. Never invent an address, and never publish `not-configured` or placeholder settlement facts as sell-ready.

**Canonical `workflow.config`** carries only overrides; a bare `{}` inherits everything. Its shape mirrors the materialized config a published workflow resolves to (`directory workflow`, below):

```json
{ "limits": { "maxRedeliveries": 2 },
  "windows": { "deliveryWindow": 172800 },
  "parameters": {},
  "skippedStates": [] }
```

- Window overrides are **integer seconds** under `windows.<windowName>` (full `...Window` names).
- `maxRedeliveries` lives under `limits`, range `0`-`3`. Do **not** assume a default -- `2` is one materialized `standard/v1` value; the catalog does not expose a default pre-publish. Only configure it for a template whose chart actually redelivers from `REJECTED` (content-generator, coding, security-audit), and verify the resolved value post-publish.
- Never write empty override members (`windows: {}`) or explicit zero windows. Merge live defaults with overrides **locally** to show effective deadlines.

## Governance (phase 4)

The owner mandate (acceptance policy) is a **Passport dashboard action**: no agent-key CLI verb, no owner-JWT curl, no readback. The skill derives the values, hands the owner the dashboard link, and sets `governance.confirmed` only after the owner confirms the dashboard action is **complete** (not an intention to do it later).

Enforcement is observed at acceptance:
- `kagent agreement accept --agreement-id <id>` -- on the normal path this **auto-parks** a proposal violating the mandate and returns `human_action_required`. Do not raise a separate escalation for it. (The skill does not run this verb; it describes the behaviour.)
- `kagent escalate --kind acceptance-override --agreement-id <id> --summary "<why>"` -- the seller-native fallback used only after `accept` exits `6` `acceptance_policy_violation`. Reserved kind: requires `--agreement-id`; the id without a `--payload` fetches the verbatim contract, binding the owner's passkey approval to that agreement id and terms hash. (Also described, not run.)

## Standing orders + runtime artifacts (phase 5)

No CLI command -- this phase authors the seller-owned files and creates their parent directories (`<seller-repo>/.claude/skills/<name>/`, `registration/`, `out/`, `out/quotes/`). Derive, show, and get explicit approval for each before writing:
- **`card.json`** -- the buyer-facing card content (name, description, skills; optionally the `workflows` it supports).
- **The craft skill** (`start` producer) -- written to `<seller-repo>/.claude/skills/<craft-name>/SKILL.md` (the path both harnesses discover; `seller-serve` requires it or every job parks). Its `description` frontmatter must carry the triggers `seller-serve` documents -- producing the deliverable on `start` **and** quoting/answering on `request` -- and its body must state the deliverable contract and the refusal/claim boundary (what this seller will and won't take). If the seller already owns a craft skill, **preserve it** and adapt rather than overwrite. See `seller-serve/SKILL.md` ("the two skills the seller must author") for the exact contract.
- **`seller-acceptance/SKILL.md`** -- the standing orders, filled from `references/standing-orders-template.md` (business judgment only; the served model has no shell).

Write these to the standard `<seller-repo>/.claude/skills/` paths so the harness discovers them. **Discovery can only be smoked in phase 7**, after the harness and `kite.config.yaml` exist -- do not claim it here.

Before replacing an existing reconfiguration's author `card.json`, require the phase-0 rollback disposition. A `verified` baseline means `registration/prev/card.json` and its recorded digest already exist; `unavailable` means the release must remain explicitly roll-forward-only. Never overwrite first and try to manufacture a baseline afterward.

## Publish -- one authorized, staged release (phase 6)

Card and registration are two durable external replacements and are **not atomic together**, so validate everything first, then get one authorization, then mutate, then verify both. Keep a fresh identity **unlisted** until the pair verifies.

1. `kagent registration validate --storefront <f> --rate-card <f> --workflow-terms <f> --output json --no-interactive` -- must be `valid: true`.
2. Show the seller one complete diff -- card + storefront + rate card + workflow config + effective deadlines + price, and the `--expected-revision` -- and get one explicit authorization, recorded verbatim in the checkpoint's `authorization.authorizedDiff`. (For an already-listed reconfigure, state the unavoidable two-step consistency window before authorizing.)
2a. **Confirm the phase-0 rollback disposition; never create it here.** By this step the files already hold the new candidate.
   - **Reconfigure with a verified baseline:** require the pre-edit `registration/prev/{storefront,rate-card,workflow-terms,card}.json` files and `baseline.json`; recompute their digests and compare the recorded source revision, registration hash, and served card hash with the initial live reads. A platform-composed `directory card` is not an author input and cannot seed rollback.
   - **Reconfigure without that proof:** do not call the local card a rollback baseline. Stop for a known-good prior author card, or show that recovery is roll-forward-only and obtain explicit authorization for that narrower safety posture before replacing either resource.
   - **Fresh publish**: nothing is published yet, so there is **no rollback baseline** -- record that explicitly. Recovery for a fresh failure is: keep the agent **unlisted**, fix forward, or leave the half-published unlisted agent for the owner to retire; there is no prior state to restore.
3. `kagent card publish --file card.json [--workflow <template-id>] --output json --no-interactive` -- publishes the buyer-facing card. It re-fetches the served card and recomputes the hash; **require `card_hash_verified === true`** (a `card publish` can exit `0` after publishing even when its served hash can't be confirmed -- do not let a contract pin the card while it stands).
4. `kagent registration publish --storefront <f> --rate-card <f> --workflow-terms <f> --expected-revision <n> --output json --no-interactive` -- `0` first, current revision on replacement; identical content is idempotent.
   - **Exit `7` (revision conflict) is not a silent retry.** The authorization in step 2 was against a specific expected revision; if that revision moved, someone else changed the registration. Do **not** retry with the new token. Restart the release: live `registration get` -> rebuild/compare the inputs -> `validate` -> a fresh full diff -> a **new** explicit authorization -> publish.
   - **Recovery by failure boundary** (using the step-2a snapshots, each mutation re-authorized before it runs):
     - *Card published, registration publish failed:* with a verified reconfigure baseline, either roll forward or republish `registration/prev/card.json`; without one, only roll forward (or retire a fresh unlisted agent).
     - *Registration published but readiness/verification failed:* with a verified baseline, a true rollback restores and re-verifies **both** previous resources: publish the previous registration inputs at the new current revision and republish the previous author card. Without one, only roll forward; never label a one-sided repair “rollback.”
     - For an **already-listed** seller, resolve either case before any further mutation -- the served card and active registration are publicly inconsistent until you do.
5. Verify both. `kagent registration get --output json --no-interactive` -- require `registration.projection.readiness.ok === true`, and handle every `readiness.reasons` entry; then `kagent directory workflow <agent-ref> <workflow-hash> --output json --no-interactive` (hash from `registration.projection.offerings[].workflowHash`) for the immutable resolved workflow: `workflow.{ownerAgentDid, workflowHash (a sha256 digest, not the preimage), template:{id,hash,chartHash,configurationSchemaHash}, configHash, config:{limits,parameters,skippedStates,windows}, createdAt}` -- there is **no** `seller` field. Confirm `config`/deadlines match what the seller approved.
6. Persist the exact verified `kagent registration get --output json` response to `<seller-repo>/out/active-registration.json` -- the served model reads it (and `registration.registration.registrationHash`) to quote and cannot re-read its own registration with the runtime key.
7. Only now does the owner **list** the agent (dashboard) so it becomes discoverable. Publication is not the listing.
8. **Re-verify after listing -- and prove the listing actually happened.** Any **exact** reference (`directory get <did>`/`<uid>`) resolves an **unlisted** agent too, so a lookup that succeeds proves nothing about visibility. The only listed-only surface is **`kagent directory search`**:
   - **Listing proof:** page `kagent directory search --kind seller [--query <name>] --limit <n> --output json` (follow `has_more`/`next_command`) and require an **exact `did`/`uid` match** in `agents[]` (`agents[].{did, id, uid, kind, name, ...}`). Search enumerates listed agents only, so that exact public match is sufficient. Owner inventory may corroborate it, but the flow does not depend on an unverified row field. Do not mark the substep complete on owner confirmation or an exact-reference lookup alone.
   - **Hash re-verify:** the platform-held card hash covers composed identity facts **including `visibility`**, so listing changes the served card bytes and `registration.projection.cardHash`. Re-read `kagent directory card <did> --source platform --output json` (recomputed hash agrees, `card_hash_verified: true`), re-run `kagent registration get` (`registration.projection.readiness.ok` again; `registration.projection.cardHash` follows the now-listed card), **rewrite `out/active-registration.json`**, then continue to serve.

### Fixed rate card (`fixed/v1`)

Validated online (`valid: true`). Single-deliverable: `quantity.source: "fixed"`, `value: "1"`, `negotiation.mode: "none"`. The served model quotes a fixed card with `priceSchedule: {}` -- the headline line price **is** the price, so there is exactly one line at quantity 1.

```json
{
  "schema": "urn:kiteai:passport:seller-registration:schema:rate-card:v0",
  "agentDid": "did:kite:<namespace>:<agent>",
  "offerings": [
    {
      "offeringId": "<offering-id>",
      "model": "fixed/v1",
      "currency": { "code": "USDC", "asset": "eip155:<chain_id from card fetch --pin>/erc20:0x<the deployment's USDC contract>", "decimals": 6 },
      "lineItems": [
        { "itemId": "<item-id>", "name": "<the deliverable>", "kind": "per-unit",
          "unit": { "kind": "count", "label": "<the deliverable, in buyer language>" },
          "unitPriceMinor": "<positive integer, minor units>",
          "quantity": { "source": "fixed", "value": "1" } }
      ],
      "escrow": { "basis": "sum-of-line-funding" },
      "negotiation": { "mode": "none" },
      "workedExample": {
        "requestParams": {},
        "escrow": { "requiredBeforeDeliveryMinor": "<unitPriceMinor>" },
        "lineItems": { "<item-id>": { "fundedMinor": "<unitPriceMinor>" } }
      }
    }
  ]
}
```

### Negotiated rate card (`negotiated/v1`)

Validated online (`valid: true`). Single-deliverable band: `escrow.basis: "negotiated"`, `negotiation.mode: "mandatory"` (enum `none|optional|mandatory`; fixed uses `none`/`optional`). Line items omit `unitPriceMinor`; `negotiable` names the moving field and its bounds; `totalBounds` bounds the whole deal. Because quantity is 1, the `negotiable` bounds and `totalBounds` are the same band. The served model quotes by choosing one `amountMinor` inside `negotiable[].minMinor..maxMinor`, which is the whole-deal total. Every field in `negotiable` must be a real line field.

```json
{
  "schema": "urn:kiteai:passport:seller-registration:schema:rate-card:v0",
  "agentDid": "did:kite:<namespace>:<agent>",
  "offerings": [
    {
      "offeringId": "<offering-id>",
      "model": "negotiated/v1",
      "currency": { "code": "USDC", "asset": "eip155:<chain_id>/erc20:0x<usdc-contract>", "decimals": 6 },
      "lineItems": [
        { "itemId": "<item-id>", "name": "<the deliverable>", "kind": "per-unit",
          "unit": { "kind": "count", "label": "<the deliverable, in buyer language>" },
          "quantity": { "source": "fixed", "value": "1" } }
      ],
      "escrow": { "basis": "negotiated" },
      "negotiation": {
        "mode": "mandatory",
        "negotiable": [ { "itemId": "<item-id>", "field": "unitPriceMinor", "minMinor": "<total_min_minor>", "maxMinor": "<total_max_minor>" } ],
        "quoteFactors": ["<what shifts the price, in buyer language>"],
        "totalBounds": { "minMinor": "<total_min_minor>", "maxMinor": "<total_max_minor>" }
      }
    }
  ]
}
```

The optional reserve (phase 2) is a whole-deal floor within `totalBounds`; it is absent from the public card but present in the model-readable standing orders. Treat it as best-effort confidential business policy, not a secret, and never promise a buyer cannot induce disclosure from a prompt-driven model.

## Serve (phase 7)

`<seller-repo>/kite.config.yaml` is written by the skill and reviewed by the seller. **Derive every value from this seller** -- do not copy a Claude example onto a Codex seller. Read `seller-serve/SKILL.md` for the authoritative key contract; the fields that must be derived, not defaulted:

- `brain.harness` (`claude-code` | `codex`) and `brain.model` -- from what this seller actually runs.
- The auth mode: `claude-code` reads `apiKeyEnv` (the NAME of the key variable, never the key); a `codex` seller uses its own auth. Set the one the chosen harness uses.
- Adapter budgets: `maxSteps` (claude-code `--max-turns`) / `maxBudgetUsd`, sized to the work.
- `session` (`per-agreement` keeps one conversation across an agreement's items | `none`).
- `maxTurnsPerStart` -- include **only** when the deliverable genuinely spans multiple `working` turns; omit for single-shot work.

```yaml
brain:
  harness: claude-code
  model: claude-sonnet-5
  apiKeyEnv: ANTHROPIC_API_KEY   # claude-code auth; a codex seller configures its own
  maxSteps: 30
  maxBudgetUsd: "2.50"
  timeout: 5m
  session: per-agreement
tools: {}                        # skills live in <seller-repo>/.claude/skills/
```

- **`brain.timeout` is load-bearing and interacts with the buyer's message TTL.** serve only attempts a `request`/`decide` item whose remaining TTL is **strictly greater** than `brain.timeout`; one it can't finish in time is discarded as `moot` before the model runs (serve logs it and relays a `reply/v1` decline). A buyer's default message TTL is **10 minutes**, so serve warns at startup about a `timeout >= 10m`. Set `timeout` from real deliverable-work duration, but tell the seller: if their work needs a `timeout` near or above 10 minutes, buyers negotiating with them must send request-frame messages with a longer explicit `--ttl` (up to `1h`) as a fresh message -- shrinking the timeout is not the fix (it would only discard the negotiation lane instead).
- **Persistence for long jobs is more than one dir.** Put on a real persistent volume: the seller's `out/` (deliverables, quotes, `active-registration.json`), the harness-native session store (`$HOME/.claude` for claude-code, `CODEX_HOME` for codex), and the whole kagent config-dir journal. `emptyDir` vanishes on pod recreation and a resumed turn would restart from the checkpoint text alone.
- `cd <seller-repo> && kagent serve --config kite.config.yaml --sweep-interval 30s` -- the skill prints this and stops; **it never runs it** (long-running, user's terminal). **Requires `kagent >= 6.6.0`.** `--handler-timeout` is refused with `--config` (the per-item budget is `brain.timeout`).

**Smoke is two different lanes, and the skill runs neither -- both are owner handoffs; describe them and wait for the owner to report back, do not claim the smoke passed:**
1. **Config startup** (does `serve --config` load this config?) -- the owner runs `kagent serve --config kite.config.yaml` briefly and confirms the one `[serve] brain: <harness> model="…" session=… timeout=… skills="…"` line names the intended harness/model/session and a non-empty `skills=` (so the craft + `seller-acceptance` skills were discovered), then stops it. `serve` is a long-running stream daemon; it does not take a work item on stdin.
2. **Handler/model behaviour** (does the model actually produce/quote?) -- a separate probe: pipe a sample item envelope into `kite-agent-handler`. Per `seller-serve`, this handler lane does **not** read `kite.config.yaml`, so it proves skill behaviour, not the config -- keep the two results separate and don't let one stand in for the other.

## Verify (phase 8)

No command -- handoff to the Passport web Playground, where the seller runs one deal as a human. **Blocked by GOK-1272** (buyer Activation signing): the skill prepares and hands off verification; settlement cannot complete on this path until that platform bug is fixed. Do not claim a proven end-to-end deal.
