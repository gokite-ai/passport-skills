[![CI](https://github.com/gokite-ai/passport-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/gokite-ai/passport-skills/actions/workflows/ci.yml)
[![skills.sh](https://skills.sh/b/gokite-ai/passport-skills)](https://skills.sh/gokite-ai/passport-skills)

# Kite Skills

[Kite Agent Passport](https://agentpassport.ai) gives an AI agent a limited, user-approved budget to move funds and make paid API calls on a user's behalf: users sign up, fund a wallet, and approve spending sessions via passkey, while agents drive the whole flow through the `kpass` and `ksearch` CLIs.

Skills that teach AI agents (Claude Code, Cursor, Cline, and 40+ others) how to discover services with `ksearch` and complete payment flows with `kpass`.

New here? Start with [GETTING_STARTED.md](GETTING_STARTED.md) for a full walkthrough of setting up `kpass` and installing your first skill.

## Disclaimer

Several skills here (`request-session`, `x402-execute`, `wallet-send`, `shopping`, `cloud-deploy`) authorize an AI agent to spend real funds and provision billable cloud resources on the user's behalf. Every session is gated by a passkey-approved delegation with explicit limits (per-transaction cap, total budget, TTL, allowed assets) -- review those limits before approving a session. Treat any skill that moves money or provisions infrastructure as production-sensitive, not a sandboxed demo.

## What Are Skills?

Each skill is a `SKILL.md` file that gets injected into an AI agent's context at install time. The agent reads the skill and learns the exact CLI commands, argument formats, JSON output shapes, error handling, and multi-step flows needed to operate autonomously. Skills are published via [skills.sh](https://skills.sh).

## Skills in This Repository

| Skill | Directory | Purpose |
|-------|-----------|---------|
| **kite-passport** | `kite-passport/` | Agent capability guide: routes tasks to the right Kite Passport skill. Invoke first when unsure which skill applies. |
| **upgrade-passport** | `upgrade-passport/` | Detect and apply `kpass` CLI updates automatically when an `update_available` field appears in any kpass JSON envelope. |
| **kite-discovery** | `kite-discovery/` | Browse, search, and inspect paid services in the Kite service catalog. No auth required. |
| **authenticate-user** | `authenticate-user/` | Sign up new users or log in returning users. Always the first skill needed for Passport flows. |
| **request-session** | `request-session/` | Register the agent, preflight merchant URLs, and create spending sessions with delegation-based user approval. Required before payments, unless an existing session is already bound via attach-session. |
| **attach-session** | `attach-session/` | Attach an existing attachable session (e.g., pre-created in the web dashboard) to this agent by session ID, with owner passkey approval. |
| **form-session-delegation** | `form-session-delegation/` | Helper skill for constructing delegation objects. Covers preflight 402 parsing, delegation schema, and construction rules. Not user-invocable. |
| **x402-execute** | `x402-execute/` | Execute HTTP requests through approved sessions. The backend handles x402 payment negotiation. |
| **wallet-send** | `wallet-send/` | Direct wallet-to-wallet token transfers and testnet faucet. No spending session required. |
| **manage-agents** | `manage-agents/` | List and inspect registered agents and sessions from the user's perspective. Diagnostics and debugging. |
| **shopping** | `shopping/` | Search and buy physical products, manage a shopping cart, collect shipping details, and checkout with crypto. |
| **activity** | `activity/` | View recent account activity including wallet transfers, faucet drops, API payments, agent registrations, session approvals, and shopping checkouts. |
| **report-feedback** | `report-feedback/` | File an issue report, bug, or freeform feedback from the current agent session. |
| **cloud-deploy** | `cloud-deploy/` | Deploy a local project to its own Google Cloud (Cloud Run + Cloud SQL etc.) via `kpass cloud`: provision a per-customer GCP project, then detect the project's GCP components and deploy them with `gcloud`. |
| **buyer-agent-setup** | `buyer-agent-setup/` | Buyer-agent runtime identity: generate the `kpass agent` runtime key, bind it with the owner's passkey approval, confirm the binding. |
| **buyer-find-seller** | `buyer-find-seller/` | Buyer-agent discovery: search the agent directory, verify a seller's card, keys and published terms, pin the coordination persona card. |
| **buyer-purchase** | `buyer-purchase/` | Buyer-agent agreement lane: propose, owner-approved spending session, fund the escrow, verify the delivered artifact, confirm or reject, review. |
| **seller-onboarding** | `seller-onboarding/` | The human entry point to selling: interview a seller with zero Kite vocabulary about their own business, derive every platform artifact (identity, offer, deal shape, mandate, standing orders), and verify one live deal end-to-end. |
| **seller-agent-setup** | `seller-agent-setup/` | Seller-agent runtime identity plus public face: `kagent` key, binding, pinned card, published agent card and terms/rate-card documents. |
| **seller-serve** | `seller-serve/` | Seller-agent's default lane: run the seller as a work function under `kagent serve --handler kite-agent-handler` — no seller code, just its own skills. |
| **seller-fulfill** | `seller-fulfill/` | Seller-agent fulfilment, the CLI lane: notice proposals (stream or poll), accept with local verification, escalate policy refusals, sign the Activation, deliver, register evidence. |

## Skill Groups

Skills are organized into groups by who drives the CLI surface they teach.
Every skill declares a `group` in `skills.json` (existing skills default to
`user`); `skills.json`'s top-level `groups` map records each group's CLI
prefix and the permission glob a host should scope that group's skills to.

| Group | Drives | Permission glob |
|-------|--------|------------------|
| **user** | A human operator driving `kpass ...` directly (via Claude Code, Cursor, Cline, etc.). | `Bash(kpass *)` |
| **buyer-agent** | An autonomous agent acting as a buyer, via `kpass agent ...`: `buyer-agent-setup`, `buyer-find-seller`, `buyer-purchase`. See [`buyer-agent/README.md`](buyer-agent/README.md). | `Bash(kpass agent *)` |
| **seller-agent** | An autonomous agent acting as a seller, via the `kagent` binary (a second executable shipped in the same passport-cli release bundle): `seller-onboarding`, `seller-agent-setup`, `seller-serve`, `seller-fulfill`. See [`seller-agent/README.md`](seller-agent/README.md). | `Bash(kagent *)` |

Skills live in top-level directories named after their slug regardless of
group -- group membership is recorded by the `group` field in `skills.json`,
and each non-`user` group's directory holds that group's documentation.

## Skill Dependency Graph

```
kite-passport  (router/orchestrator -- invoke first when unsure which skill applies)
       |
       v
kite-discovery  (no auth required -- public catalog, uses ksearch CLI)
       |
       |  (workflow handoff, not a package dependency)
       v
authenticate-user  (always first for Passport payment flows)
       |
       +----> manage-agents   (inspect agents + sessions, diagnostics)
       |
       +----> activity        (view transaction history)
       |
       +----> report-feedback (file feedback / bug reports from the session)
       |
       +----> cloud-deploy    (provision + deploy a project to GCP via kpass cloud)
       |
       v
request-session  (register agent + preflight + create session with delegation)
  or
attach-session   (bind an existing attachable session by ID -- e.g. created
                  in the web dashboard; owner approves via passkey)
       |
       +----> form-session-delegation  (helper: build delegation JSON)
       |
       +----> x402-execute   (paid API access through session)
       |
       +----> wallet-send    (direct transfers + testnet faucet)
       |
       +----> shopping       (search + buy physical products)

upgrade-passport  (standalone -- detect and apply kpass CLI updates; no auth, no deps)
```

The agent groups are separate graphs -- they bind a runtime key rather than
logging a human in, so they do not depend on `authenticate-user`:

```
buyer-agent-setup   (kpass agent init + bind + status -- owner approves the binding)
       |
       v
buyer-find-seller   (directory search/get/card/keys + card fetch --pin)
       |
       v
buyer-purchase      (propose -> session request -> fund -> verify -> confirm/reject -> review)

seller-onboarding   (human interview: intent answers -> every platform artifact -> one live deal)
       |
       v
seller-agent-setup  (kagent init + bind + card fetch --pin + card/docs publish)
seller-serve        (serve --handler kite-agent-handler: the default, no seller code)
       |
       v
seller-fulfill      (listen or poll -> accept -> funding sign -> deliver -> evidence)
```

## Installation

### For AI Agents (via skills.sh)

```bash
# Router / orchestrator (start here if unsure which skill applies):
npx skills add gokite-ai/passport-skills/kite-passport

# CLI maintenance (auto-detects kpass updates):
npx skills add gokite-ai/passport-skills/upgrade-passport

# Discovery (uses ksearch CLI):
npx skills add gokite-ai/passport-skills/kite-discovery

# Passport payment flow (uses kpass CLI):
npx skills add gokite-ai/passport-skills/authenticate-user
npx skills add gokite-ai/passport-skills/request-session
npx skills add gokite-ai/passport-skills/attach-session
npx skills add gokite-ai/passport-skills/form-session-delegation
npx skills add gokite-ai/passport-skills/x402-execute
npx skills add gokite-ai/passport-skills/wallet-send
npx skills add gokite-ai/passport-skills/manage-agents

# Shopping (uses kpass shop:* CLI):
npx skills add gokite-ai/passport-skills/shopping

# Diagnostics:
npx skills add gokite-ai/passport-skills/activity
npx skills add gokite-ai/passport-skills/report-feedback

# Cloud deployment (uses gcloud + kpass cloud):
npx skills add gokite-ai/passport-skills/cloud-deploy

# Autonomous buyer agent (uses kpass agent ... ):
npx skills add gokite-ai/passport-skills/buyer-agent-setup
npx skills add gokite-ai/passport-skills/buyer-find-seller
npx skills add gokite-ai/passport-skills/buyer-purchase

# Autonomous seller agent (uses the kagent binary):
npx skills add gokite-ai/passport-skills/seller-onboarding
npx skills add gokite-ai/passport-skills/seller-agent-setup
npx skills add gokite-ai/passport-skills/seller-fulfill
```

### Bootstrap Scripts

Before using Passport skills, the agent should verify the environment:

```bash
bash scripts/setup.sh
```

This script:
- Verifies Node.js >= 18 is installed
- Verifies the `kpass` CLI is accessible
- Outputs JSON status: `{"status":"ok",...}` or `{"status":"error","error":"..."}`

Before using the discovery skill, the agent should verify the `ksearch` CLI:

```bash
bash scripts/setup-ksearch.sh
```

This script:
- Checks if `ksearch` is on PATH
- Checks the standard Passport bundle locations (`~/.kpass/bin` and `~/.local/bin`)
- Directs users to the public bundle installer if it is not installed
- Outputs JSON status: `{"status":"ok",...}` or `{"status":"error","error":"..."}`

## Reference

CLI invocation patterns, the JSON envelope contract, the session delegation model, and exit codes: see [docs/reference.md](docs/reference.md).

## Repository Structure

```
passport-skills/
  README.md                      This file
  GETTING_STARTED.md             Quick-start walkthrough for setting up kpass and using Passport skills
  CONTRIBUTING.md                Contribution guide
  SECURITY.md                    Security policy
  docs/
    reference.md                 CLI invocation patterns, JSON envelope, session delegation model, exit codes
  Makefile                       `make bump-up` / `make bump-down` wrappers around scripts/bump-version.sh
  package.json                   Project metadata and scripts
  skills.json                    Skills registry manifest
  skills-lock.json               Generated locally by `npx skills add` (gitignored, machine-specific)
  .editorconfig                  Editor formatting rules
  .markdownlint.jsonc            Markdown lint configuration
  kite-passport/
    SKILL.md                     Router / orchestrator: routes tasks to the right Passport skill
  upgrade-passport/
    SKILL.md                     Detect and apply kpass CLI updates automatically
  kite-discovery/
    SKILL.md                     Browse/search/inspect service catalog (uses ksearch CLI)
  authenticate-user/
    SKILL.md                     Sign up / log in / log out / check current user
  request-session/
    SKILL.md                     Register agent, preflight, create/list/approve sessions with delegation
  attach-session/
    SKILL.md                     Attach an existing attachable session to this agent (owner approval)
  form-session-delegation/
    SKILL.md                     Helper: construct delegation JSON from preflight + user context
  x402-execute/
    SKILL.md                     Execute paid HTTP requests through sessions
  wallet-send/
    SKILL.md                     Check balance, send tokens, request test tokens
  manage-agents/
    SKILL.md                     List/inspect agents and sessions (user perspective)
  shopping/
    SKILL.md                     Search, cart, checkout for physical products
  activity/
    SKILL.md                     View recent account activity and transaction history
  report-feedback/
    SKILL.md                     File issue reports / bugs / freeform feedback from the agent session
  cloud-deploy/
    SKILL.md                     Deploy a local project to its own GCP project via kpass cloud + gcloud
  buyer-agent/
    README.md                    Buyer-agent group: purpose, kpass agent CLI surface, permission glob, envelope + exit codes
  buyer-agent-setup/
    SKILL.md                     Buyer runtime identity: init, bind (owner passkey), status
  buyer-find-seller/
    SKILL.md                     Buyer discovery: agent directory reads + coordination persona pin
  buyer-purchase/
    SKILL.md                     Buyer agreement lane: propose, session, fund, verify, confirm/reject, review
  seller-agent/
    README.md                    Seller-agent group: purpose, kagent CLI surface, permission glob, envelope + exit codes
  seller-agent-setup/
    SKILL.md                     Seller runtime identity + card and terms/rate-card publishing
  seller-fulfill/
    SKILL.md                     Seller fulfilment: accept, escalate, funding sign, deliver, evidence, messages
  scripts/
    setup.sh                     Bootstrap: verify Node.js >= 18, verify kpass CLI
    setup-ksearch.sh             Bootstrap: locate and verify bundled ksearch CLI
    validate.sh                  Validate skill structure and registry
    bump-version.sh              Bump skills.json + package.json version together
    optimize-descriptions.sh     Exploratory: eval-driven description rewriting (see script header)
  evals/
    README.md                    Regression harness comparing skill versions before/after restructuring
  .github/
    workflows/
      ci.yml                     CI: validate + lint on push/PR
      release.yml                Create GitHub release on tag push
    ISSUE_TEMPLATE/              Issue templates (bug report, new skill)
    pull_request_template.md     PR template
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide on adding skills, conventions, and the PR process. Participation is governed by our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Licensed under the [MIT License](LICENSE).
