# Seller Onboarding Artifacts — Runtime Key, Registration Files, Mandate

**Status: reference · 2026-08-30**  
Companion to the parent design doc: the six artifacts a seller prepares at onboarding — the runtime key, the four registration files (agent card + the commerce-registration triple), and the owner mandate — with exact formats and real examples. Examples are taken from the deployed recruiting-agent example (`public/examples/recruiting-agent`, live at recruiter.kiteai.dev) and the live dev registry (`passport.dev.gokite.ai`). The parent doc decides _how the interview derives these values_; this page pins _what the derived artifacts look like_.

> The JSON examples below are annotated with `//` comments (meaning + allowed values). The actual files must be pure JSON — strip the comments.

## 1\. The six artifacts

| Artifact | Where it lives | Who reads it | Published by | Mutable after publish? |
| --- | --- | --- | --- | --- |
| Runtime key | `~/.kagent` (or `KAGENT_CONFIG_DIR`); production: Vault → env | The seller binary (signs everything) | `kagent init` creates; owner approves the bind | Re-key = `init --force` (orphans in-flight deals) |
| Agent card `card.json` | Seller repo | Buyers (discovery); platform (advertised-workflows check) | `kagent card publish --file` | Republish replaces in place |
| `registration/storefront.json` | Seller repo | Buyers (what is sold, in buyer language) | `kagent registration publish` (all three, atomic) | New immutable revision per publish |
| `registration/rate-card.json` | Seller repo | Buyers + platform (THE executable price book) | same atomic publish | New immutable revision per publish |
| `registration/workflow-terms.json` | Seller repo | Platform + engine (workflow template + config); buyers (terms prose) | same atomic publish | Registration: new revision. Workflow move: **owner-only** (§6.3) |
| Acceptance policy (owner mandate) | **Not a repo file** — platform state | Governance module at `decide` | Owner: dashboard or `PUT /v1/agents/{id}/acceptancePolicy` | Full replace, optimistic-concurrency `version` |

Where each enters the bootstrap (order matters):  
`kagent init` (key) → `kagent bind --agent <did>` (owner passkey approval) → `kagent card fetch --pin` → `kagent card publish` (card) → `kagent registration publish` (the triple, authored as `registration template` → edit → `registration validate`). The mandate is set by the owner in the same pass — a fresh seller with no policy refuses every proposal (fail-closed) and "looks exactly like a broken agent".

## 2\. Runtime key

One durable secp256k1 key per seller identity, created by `kagent init` and bound to the agent DID by the owner's passkey approval (`kagent bind`). It signs everything the seller does — card publishes, registration publishes, quotes, acceptances, deliveries, settlement Activations.

- Locally it lives in the kagent config dir (`~/.kagent`, or `KAGENT_CONFIG_DIR` for isolated role directories).
- In deployment it is supplied as `SELLER_RUNTIME_PRIVATE_KEY` from Vault — **never generated fresh on a pod restart**: a new key orphans every agreement pinned to the old one.
- There is no rotate/export/delete verb. Re-keying is `kagent init --force`, an explicitly destructive act that needs the owner's go-ahead.

## 3\. Agent card — `card.json`

Free-shape JSON presented to buyers; the platform checks only specific members. The one member with platform-enforced meaning is the `workflows` **array**: the agreement workflows this seller advertises. It gates formation — a buyer proposal naming a workflow the card does not advertise is refused — and each id is validated against the platform's workflow registry at publish time (a typo is refused at publish, not discovered by a buyer).

Real example — the deployed recruiting agent's card:

```jsonc
{
  "name": "Kite Recruiting Agent (Claude SDK)",   // display name buyers see in discovery
  "description": "Outcome-based talent recruiting: describe a role and get a sourced candidate with buyer-confirmed interest. ...",
                                                  // free prose; what the agent does, in buyer language
  "did": "did:kite:ind-lyon:recruiting-agent-sdk",// the bound agent DID — must match the identity from `kagent bind`
  "kind": "seller",                               // role convention: seller | buyer
  "version": "0.1.0",                             // seller's own versioning; opaque to the platform
  "workflows": ["standard/v1"],                   // PLATFORM-ENFORCED: advertised workflow templates, registry-checked
                                                  // at publish; proposals naming an unlisted id are refused.
                                                  // Must cover the ids used in workflow-terms (§4.3) and the mandate (§7)
  "runtime": "Claude Agent SDK (headless), per-task sessions with follow-up resume",
                                                  // informational, free-shape
  "skills": [                                     // informational capability descriptions, free-shape
    {
      "id": "recruiting-intake",
      "name": "Recruiting intake",
      "description": "Interprets the buyer's request into search criteria and an outreach draft."
    },
    {
      "id": "candidate-sourcing",
      "name": "Candidate sourcing",
      "description": "Sources a candidate matching the agreed criteria; buyer-confirmed interest is the paid outcome."
    }
  ],
  "notes": {                                      // free-shape; honest-disclosure slots by convention
    "pricing": "See the commerce registration (rate card) — the registration, not this card, carries the executable price.",
    "disclosedRisk": "Sourcing quality depends on upstream services; payment releases only on buyer-confirmed interest evidence."
  }
}
```

```bash
kagent card publish --file ./card.json --output json
```

Notes:

- `card publish` also accepts a repeatable `--workflow <id>` flag that injects/overrides the `workflows` member without editing the file — a scripting convenience, not a separate mechanism.
- A seller serving its card from its own https origin adds `kagent card set-url --url https://seller.example`, which flips precedence to that origin.

## 4\. The commerce registration — three files, one atomic publish

The registration is how a seller declares what it sells. Three JSON inputs, submitted **together** — the platform validates the complete set against itself, activates one immutable revision, and derives the registry rows buyers search. Money is spelled in exactly one input (the rate card); there is no per-input upload.

```bash
kagent registration template --output-dir ./registration --output json   # skeletons
# edit the three files
kagent registration validate --storefront ./registration/storefront.json \
  --rate-card ./registration/rate-card.json \
  --workflow-terms ./registration/workflow-terms.json --output json
kagent registration publish  --storefront ./registration/storefront.json \
  --rate-card ./registration/rate-card.json \
  --workflow-terms ./registration/workflow-terms.json --output json
kagent registration get --output json                                    # read back the active revision
```

The three files share two spine members: `schema` (a versioned URN, pinned below) and `agentDid` (the real DID from the bind — a placeholder DID makes the file meaningless). Offerings join across files by `offeringId`.

### 4.1 `storefront.json` — identity, no money

What each offering IS, in buyer language, plus the payout configuration.

Real example (recruiting agent, complete file):

```jsonc
{
  "schema": "urn:kiteai:passport:seller-registration:schema:storefront:v0",
                                            // pinned format URN; exactly this string
  "agentDid": "did:kite:ind-lyon:recruiting-agent-sdk",
                                            // the real bound DID — a placeholder makes the file meaningless
  "offerings": [                            // one entry per thing sold; joined to the other files by offeringId
    {
      "offeringId": "candidate-sourcing",   // stable id: lowercase [a-z0-9._-], max 64 chars; an identifier, not a storage slot
      "kind": "service",                    // closed set: dataset | api | media | compute | service
                                            // ("service" = work performed, no catalogable artifact needed)
      "title": "One sourced candidate with buyer-confirmed interest for a described role",
                                            // one-line offering identity, buyer language
      "describesMarkdown": "Describe a role (free text, or role/location/requirements). ... The deliverable is the candidate profile plus the interest evidence.",
                                            // what the buyer gets — the "what do you want to advertise?" answer
      "limitationsMarkdown": "One candidate per agreement. ... the deliverable ends at buyer-confirmed interest.",
                                            // honest scope limits, shown to buyers
      "payout": {
        "status": "self-declared",          // closed set: self-declared | not-configured
                                            // (self-declared requires address; not-configured = cannot settle;
                                            //  a "verified" tier does not exist yet)
        "address": "0x8D0bFEb94FbBFB57b885B9920ffC1081f024d5C7"
                                            // where escrow releases settle: 0x + 20-byte EVM address;
                                            // the zero address is refused (money sent there is burned)
      }
    }
  ]
}
```

### 4.2 `rate-card.json` — THE executable price book

One pricing model per offering; the platform machine-checks the `workedExample` against the model — a rate card whose worked example does not reproduce under its own rules is refused at validate.

Real example (recruiting agent, complete file — a flat fixed-price offering):

```jsonc
{
  "schema": "urn:kiteai:passport:seller-registration:schema:rate-card:v0",
                                            // pinned format URN
  "agentDid": "did:kite:ind-lyon:recruiting-agent-sdk",
  "offerings": [
    {
      "offeringId": "candidate-sourcing",   // must match the storefront entry
      "model": "fixed/v1",                  // closed set: fixed/v1 | negotiated/v1
                                            // (fixed publishes every amount; negotiated publishes the price's
                                            //  structure without amounts — numbers come from the quote lane)
      "currency": {
        "code": "USDC",                     // display code; NOT sufficient alone
        "asset": "eip155:5042002/erc20:0x3600000000000000000000000000000000000000",
                                            // fully-qualified CAIP asset id: chain + token contract
                                            // (this one is dev-chain USDC)
        "decimals": 6                       // minor-unit scale: 10^6 minor units = 1 USDC
      },
      "lineItems": [                        // the price's structure; every amount in minor units
        {
          "itemId": "sourced-candidate",    // stable line id, referenced by the worked example
          "name": "one candidate with buyer-confirmed interest",
          "kind": "flat",                   // closed set: flat | per-unit | graded
                                            // (flat = one amount per agreement; per-unit = unit-priced quantity,
                                            //  a subscription is a per-unit line with unit kind "time";
                                            //  graded = payout curve over an outcome measure)
          "amountMinor": "2000000"          // money grammar: non-negative integer STRING, no sign/decimal/leading zero
                                            // "2000000" at decimals:6 = 2.00 USDC
        }
      ],
      "escrow": {
        "basis": "sum-of-line-funding"      // closed set: sum-of-line-funding (fixed) | negotiated (negotiated)
                                            // — exactly one basis per model in v0
      },
      "negotiation": {
        "mode": "none"                      // closed set: none | optional | mandatory
                                            // (none = both sides use the card as-is; optional/mandatory open the quote lane)
      },
      "workedExample": {                    // machine-checked proof: funding recomputed from requestParams
                                            // must reproduce these numbers EXACTLY, or validate refuses
        "requestParams": {},                // the example buyer request (empty: flat price needs no parameters)
        "escrow": { "requiredBeforeDeliveryMinor": "2000000" },
                                            // total escrow the buyer must fund before delivery
        "lineItems": {
          "sourced-candidate": { "fundedMinor": "2000000" }
                                            // per-line funding, keyed by itemId
        }
      },
      "pricingMarkdown": "Flat 2.00 USDC per agreement, escrowed before delivery and released on the buyer-confirmed interest outcome."
                                            // buyer-facing prose restatement of the price
    }
  ]
}
```

### 4.3 `workflow-terms.json` — the workflow binding + terms prose

Per offering: which workflow template the deal runs under, an optional `config` object (§6), and four **optional** terms-prose slots (all four are `omitempty` in the platform schema — still fully supported, recorded and projected to buyers; they are independent of the workflow descriptor, which governs only `config` validation).

Real example (recruiting agent, complete file — template defaults, nothing overridden):

```jsonc
{
  "schema": "urn:kiteai:passport:seller-registration:schema:workflow-terms:v1",
                                            // pinned format URN (v1 adds workflow.config; v0 spelled workflow.id)
  "agentDid": "did:kite:ind-lyon:recruiting-agent-sdk",
  "offerings": [
    {
      "offeringId": "candidate-sourcing",   // must match the storefront + rate-card entries
      "workflow": {
        "templateId": "standard/v1",        // must name a registry template (§5); prod carries standard/v1 only
        "config": {                         // per-offering workflow configuration — full reference in §6;
                                            // all four members required, empty = template defaults
          "windows": {},                    // deadline overrides in seconds (§6.1)
          "limits": {},                     // e.g. maxRedeliveries — the seller's rework budget (§6.1)
          "skippedStates": [],              // chart states this offering skips (template declares which are skippable)
          "parameters": {}                  // template-specific knobs
        }
      },
      "deliveryMarkdown": "The deliverable is one JSON artifact per agreement: the sourced candidate's profile ... Delivered after escrow is funded.",
                                            // OPTIONAL: what delivery consists of, buyer-facing
      "acceptanceMarkdown": "Acceptance is the buyer's confirmation of the interest evidence. ... anything less does not release payment.",
                                            // OPTIONAL but load-bearing: the criterion the buyer's review judges
                                            // the delivery against — write it checkable, not marketing
      "refundMarkdown": "If no candidate reply arrives before the agreement's reply deadline, or sourcing fails upstream, the escrow refunds to the buyer.",
                                            // OPTIONAL: when the buyer gets the money back
      "licenseMarkdown": "The buyer may use the candidate profile and interest evidence for their own recruiting of the named candidate. No resale or redistribution."
                                            // OPTIONAL: what the buyer may do with the deliverable
    }
  ]
}
```

## 5\. Workflows — how to view and choose

Three read surfaces, all against the same per-environment registry (dev carries the full catalog; **prod carries** `standard/v1` **only**):

**a)** `ksearch workflow-template list` — the discovery binary, public read, no runtime key needed:

```bash
ksearch workflow-template list --output json
```

```json
{
  "count": 6,
  "workflows": [
    { "id": "coding/v1",      "name": "coding",      "schema_uri": "urn:kiteai:coordination:schema:deal-contract:v1",
      "summary": "Agreement workflow executed by the fulfill-engine coding chart." },
    { "id": "recruiting/v1",  "name": "recruiting",  "schema_uri": "urn:kiteai:coordination:schema:deal-contract:v1",
      "summary": "Agreement workflow executed by the fulfill-engine recruiting chart." },
    { "id": "standard/v1",    "name": "standard",    "schema_uri": "urn:kiteai:coordination:schema:deal-contract:v1",
      "summary": "Agreement workflow executed by the fulfill-engine standard chart." }
  ]
}
```

(Real dev output, trimmed to three of the six current templates: `coding/v1`, `content-generator/v1`, `data-seller/v1`, `recruiting/v1`, `security-audit/v1`, `standard/v1`.)

**b)** `ksearch workflow-template get <family/version>` — the full definition, including the executable state chart. Real dev output for `standard/v1` (excerpt):

```jsonc
{
  "chart": {
    "id": "kite-agreement-standard-v1",     // the executable chart identity
    "initial": "PROPOSED",                  // every deal starts here
    "states": {
      "PROPOSED":  { "on": { "CONTRACT_SIGNED": { "target": "COMMITTED" } } },
      "COMMITTED": {
        "after": { "fundingWindow": {       // deadline driven by the config window of the same name (§6.1)
                     "target": "EXPIRED",
                     "meta": { "event": "FUNDING_EXPIRED", "seconds": 1800 } } },
                                            // seconds = the template default, shown inline
        "on":    { "FUND_CONFIRMED": { "target": "FULFILLING" } }
      }
    }
  }
}
```

Every deadline in the chart names the config window that drives it plus the template-default seconds — this is where "what happens if nobody acts" is answered precisely.

**c) REST, for web/dashboard surfaces**: `GET /v1/workflows` (list projection) and `GET /v1/workflows/{family}/{version}` (full descriptor + chart projection).

Choosing: per parent-doc decision #4, the template name is an _output_ of a characteristics interview, never a question. The dimensions that differ between templates — payment trigger, escrow behavior, time windows, evidence demanded per step, skippable states — are all readable from the `get` output above. `standard/v1` is the default choice, the only prod template, and the full lifecycle (delivery review, appeal, third-party arbitration); the domain templates run domain-tuned charts with the same config surface.

## 6\. Workflows — how to configure

### 6.1 The `config` object — format

Configuration lives inside `workflow-terms.json` (§4.3), under `workflow.config`. The config surface is declared by the template itself: each descriptor carries a JSON Schema and a defaults object. All four members are required (empty means "template defaults"); unknown members are refused (`additionalProperties: false`). The real `standard/v1` contract:

| Member | Constraints (from the real schema) | standard/v1 default |
| --- | --- | --- |
| `windows.fundingWindow` | integer seconds, 45 … 315360000 | 1800 (30 min) |
| `windows.deliveryWindow` | same bounds | 86400 (24 h) |
| `windows.deliveryConfirmationWindow` | same bounds | 172800 (48 h) |
| `windows.appealResponseWindow` | same bounds | 172800 (48 h) |
| `windows.arbitrationWindow` | same bounds | 604800 (7 d) |
| `limits.maxRedeliveries` | integer 0 … 3 | 2   |
| `skippedStates` | unique array over the chart's skippable state enum | `[]` |
| `parameters` | free object for template-specific knobs | `{}` |

### 6.2 A configured example

A seller that wants same-day turnaround pressure and a single rework attempt:

```jsonc
"workflow": {
  "templateId": "standard/v1",
  "config": {
    "windows": {
      "deliveryWindow": 14400,              // 4 h to deliver after funding (default 24 h); deadlines the SELLER
      "deliveryConfirmationWindow": 86400   // 24 h for the buyer's review (default 48 h); deadlines the BUYER
    },
    "limits": {
      "maxRedeliveries": 1                  // one rework attempt (default 2, max 3); the seller's own budget
    },
    "skippedStates": [],                    // run the full chart, skip nothing
    "parameters": {}                        // no template-specific knobs on standard/v1
  }
}
```

### 6.3 Config semantics — who reads it, when it binds, how it changes

- **Passport records the config verbatim**, content-addressed, without interpreting it. Validation at publish is provenance + schema shape only.
- **At deal formation the config is embedded into the signed terms.** The fulfill-engine parses it from the terms itself and enforces it; a proposal that tries to restate any of it on the wire is refused outright.
- **Windows govern both directions.** `deliveryWindow` deadlines the seller; `deliveryConfirmationWindow` deadlines the buyer's review. The seller signs what it configures and the buyer sees it in the terms before funding — the reviewed template schema (bounds above) is the protection. Only `fundingWindow` additionally keeps a platform floor.
- `limits.maxRedeliveries` **is the seller's rework budget** — buyers do not send one.
- **Existing agreements never move.** Terms pin the chart by hash; a template's chart being repinned later affects only new formations.
- **Later changes are the owner's act, not the agent's.** `kagent` authors the initial configuration and reads; moving an offering to a different configuration is done in the Passport dashboard or its owner API — preview with `POST /v1/agents/{agent}/workflows:validate`, apply with `PUT /v1/agents/{agent}/offerings/{offeringId}/workflow`. There is no `kagent` mutation verb, by design. To read what an offering runs under today: `kagent workflow list` / `kagent workflow get <workflow-hash>` (the seller's own recorded, immutable configurations — a different verb group from the `workflow-template` catalog).

## 7\. The acceptance policy (owner mandate) — platform state, not a file

Set by the owner, unreadable and unwritable by the agent (the guardrail property). `configured: false` means every acceptance is refused — a _position_, not a gap. Format, via the owner API (the dashboard offers the same form):

```bash
curl -fsS -X PUT -H "Authorization: Bearer <owner-jwt>" -H 'Content-Type: application/json' \
  "$KITE_PASSPORT_BASE_URL/v1/agents/<agt_id-or-did>/acceptancePolicy" \
  --data @policy.json
```

```jsonc
{
  "version": 0,                             // optimistic concurrency: echo what GET returned (0 when none exists);
                                            // a stale version is refused with 409
  "templates": ["standard/v1"],             // allowlist of pinned workflow templates; EMPTY MEANS NONE —
                                            // there is no spelling that means "any", deliberately
  "price_floors": {
    "standard/v1": "2000000"                // per-template minimum in MINOR UNITS ("2000000" = 2.00 USDC at 6 decimals);
                                            // a template with no floor has no minimum (the allowlist is the gate)
  },
  "price_ceilings": {},                     // OPTIONAL: per-template maximum, minor units — for sellers that would
                                            // rather escalate than silently commit to an unusually large obligation
  "max_open_obligations": 10                // OPTIONAL: cap on concurrent non-terminal deals; omitted = uncapped
}
```

Consistency rule (parent doc §11): `templates` must name exactly the workflow ids in the registration (§4.3) and the floor must sit at or below the rate-card price — otherwise the agent refuses the very deal it advertises. Deals outside the mandate are not lost; they park as escalations for a per-contract owner ruling.