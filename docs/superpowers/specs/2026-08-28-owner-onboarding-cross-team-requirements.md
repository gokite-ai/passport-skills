# Owner onboarding: requirements for backend, passport-web, and builder studio

**Date:** 2026-08-28
**Status:** Draft — for handoff, not an implementation plan
**Audience:** passport backend, passport-web, builder studio teams
**Related:** `passport-cli` design doc `2026-08-28-owner-onboarding-design.md`;
`passport-skills` design doc `2026-08-28-owner-onboarding-design.md` (both in
their respective repos)

## Why this exists

Today, registering an owner account with a claimed identifier and verified
KYC/KYB, then binding an active runtime to an agent, only works end-to-end
through passport-web's "New agent" flow (confirmed working — an existing
account here already has three `Verified` demo seller agents created that
way). We're adding a CLI-driven equivalent, so a buyer or seller owner can
do this conversationally through Claude Code + `passport-skills`, without
ever opening a browser, in a dev/sandbox environment. Production behavior is
explicitly out of scope for this round — see each design doc's Non-goals.

This doc is not asking any of these three teams to build the CLI-facing
feature. It's flagging what the CLI/skills work depends on, needs
confirmed, or will make more visible once it ships.

## Backend (`passport`)

### 1. Resolved: minting a bind token does not require passkey step-up

Checked directly against `passport/docs/identity-module-openapi.json` and
`pkg/identity/handler/routes.go`: `POST /v1/agents/:agent/runtimeTokens`
sits in the same `protected` route group — documented in-repo as "user JWT +
rate limit" — as `POST /v1/agents` and `POST /v1/agents/:agent/runtimes/:runtime:approve`.
No passkey/step-up check exists in the handler or middleware for any of
these routes. A plain owner JWT mints a token; the CLI/skills fast path
reaches a fully hands-off outcome in dev with no browser round trip. No ask
here — just confirming for the record, since this was the item most likely
to block the design.

**New observation, not a request:** since `runtimes:approve` is in that same
plain-JWT route group, the "passkey ceremony" that today's direct-path
binding approval requires looks like it's enforced by passport-web (the
dashboard requires a WebAuthn assertion before showing the approve button),
not by the backend. We're not asking anyone to change this — bypassing a
deliberate human checkpoint on granting runtime signing authority is a
product/security decision — but whoever owns that checkpoint should know
it's a UI-layer control today, not a backend one, in case that's a surprise.

### 2. Confirm `require_runtime_approval: false` is meant to be self-service

`POST /v1/agents` documents this field (`identity-module.md` §3.1, default
`true`). We're about to let a caller set it to `false` directly from the
CLI at agent-creation time, with no other gate. If this was intended as an
internal/admin-only knob rather than something any owner can flip for their
own agent, please say so now — the CLI/skills design in both linked docs
assumes it's a normal, owner-controlled trust trade-off.

### 3. Nice-to-have: cheaper status check

Today, knowing "has this account claimed an identifier, and what's its
onboarding status" costs at least two separate calls (there's no documented
`GET` for the identifier claim itself, only the one-time `POST`). The
CLI/skills flow needs to check both before deciding what to do, on every
invocation, including the common case where both are already done. Folding
identifier + onboarding status into one existing read (e.g. whatever backs
`kpass me`) would save round trips on every skill run, but isn't a blocker —
we can call what exists today.

### 4. Nice-to-have: distinguish 409 causes on identifier claim

A second claim attempt 409s whether it's "this account already claimed a
different identifier," "this account already claimed exactly this handle"
(a safe no-op, e.g. re-running an interrupted skill), or "someone else has
this handle" (needs a new candidate). The module already uses a
machine-readable `reason` in `details[]` elsewhere (§9) for exactly this
kind of disambiguation — extending that convention here would let the CLI
stop guessing.

### 5. FYI, not a request: KYC/KYB vendor integration becomes more visible

`identity-module.md` §2.2 already flags no real KYC/KYB vendor is wired in —
`pending → verified` only happens via a non-prod auto-approve switch. That's
an existing, acknowledged gap we're not asking anyone to close as part of
this work. Flagging it because CLI-driven signups are about to start
hitting `/v1/users/onboarding` from a lot more places than passport-web's
one form, so any account created against a non-dev backend will visibly
stall at `pending` — worth knowing this is coming, not a surprise later.

### 6. FYI: first-time non-browser callers on these two routes

`/v1/users/identifier` and `/v1/users/onboarding` have, to our knowledge,
only ever been called from passport-web. If either handler has any
browser-context assumption baked in (CSRF token, session cookie behavior,
CORS config scoped to the web origin) that a bearer-JWT CLI call wouldn't
satisfy, we'd want to know before, not after, shipping.

## passport-web

### 1. Confirm CLI-written state renders identically

Once the CLI can claim an identifier, submit onboarding, create agents, and
bind runtimes, it becomes a second writer into the same resources
passport-web's dashboard already reads (Seller Agents list/detail,
Governance, etc.). We expect this to already be true — the dashboard is
presumably backend-driven and path-agnostic — but ask for confirmation
rather than assuming, since this hasn't been a real path until now.

### 2. Pending-KYC messaging

When onboarding sits at `pending` on a non-auto-approve backend, the new CLI
flow tells the owner to check the dashboard. Please confirm the existing
`kyc-section.tsx` / `kyc-reminder-banner.tsx` surfaces a clear "under review"
state for someone arriving with that context (as opposed to a state that
only makes sense to someone who started the flow in the browser).

### 3. Conditional: step-up UI for token minting

If backend item 1 above resolves to "yes, step-up required," passport-web
may need a page or deep link the CLI can point the owner at to approve a
token mint — parallel to whatever page today's `approval_url` (direct-path
bind) already opens. Only relevant depending on that answer; not asking for
anything speculative here.

## Builder studio

We don't have this repo locally yet, so this section is necessarily
higher-level than the other two.

### 1. Don't diverge on the KYC/identifier contract

Builder studio is porting the Seller Agents and Agreements pages from
passport-web (confirmed: `seller-agents`, `seller-agents/:id`,
`agreements/selling`, `agreements/:id` all currently live on
passport-web.dev). Whatever fields and flow that port uses for identifier
claim and KYC/KYB submission should match what the CLI now also submits
(`type`, `legal_name`, `country`, `reg_no`) — same backend contract, two
UIs. If builder studio's port predates this doc, worth a pass to confirm no
drift crept in.

### 2. Same DID scheme, same verification ladder

An agent created via CLI and an agent created via builder studio's ported
"New agent" flow must be indistinguishable to a counterparty — same
`did:kite:<controller_identifier>:<uid>` scheme, same L1–L4 verification
tiers. This should already be true by construction (same backend, same
routes) — flagging so it's an explicit checklist item during the port
rather than an assumption nobody verified.

### 3. Conditional: step-up / auto-activate parity

If builder studio ever wants its own "one-click" seller-agent creation path
(skip the runtime-approval passkey ceremony, the way this CLI/skills work
does for dev), it depends on backend item 1 and 2 above the same way the
CLI does — no separate design needed, just flagging the dependency so it
isn't rediscovered independently later.

## Open questions summary (for quick reference)

1. ~~Backend: does bind-token minting need passkey step-up?~~ Resolved: no.
2. Backend: is `require_runtime_approval: false` meant to be self-service?
   Still open — the only remaining item with any chance of blocking.
3. Everything else above is a nice-to-have, a confirmation, or an FYI, not
   a blocker.
