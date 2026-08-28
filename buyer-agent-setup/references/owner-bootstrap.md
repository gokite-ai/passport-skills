# Owner Bootstrap: Identifier, KYC/KYB, and the Fast-Path Bind

Before this skill's Step 2 can create an agent, the *account* — not the
agent — needs two things Passport requires of every owner: a claimed
controller identifier and verified KYC/KYB. This file is read by both
`buyer-agent-setup` and `seller-agent-setup`; its content is kept identical
across both copies by convention (there is no cross-skill include mechanism
in this repo), the same way both skills' `references/commands.md` already
independently document overlapping `kpass` verbs. Command lines below that
name a specific binary (`kagent bind` vs. `kpass agent bind`) are the one
place the two copies differ in which line applies — use the one matching
this skill's own binary.

## Step 1: Check current state before writing anything

```bash
kpass onboarding status --output json
```

- **Exit 4 (`NOT_FOUND`)** — nothing submitted yet. Continue to Step 2.
- **`onboarding_status: "pending"`** — resume: skip straight to Step 4's poll.
- **`onboarding_status: "rejected"`** — do not silently resubmit with different placeholder data. Tell the owner the record was rejected and that a resubmission needs real information, then stop; do not continue this flow on your own guess at corrected details.
- **`onboarding_status: "verified"`** — identity is already in place. Skip straight to Step 5.

There is no equivalent cheap check for identifier claim — Step 2 below is attempted directly, and the CLI's own response tells you whether that was redundant (see Step 2's handling of `identifier_already_claimed`).

## Step 2: Claim the identifier

```bash
kpass identifier claim --output json
```

Do not pass `--handle`. Omitting it lets the CLI auto-generate a candidate from the account's saved email and retry automatically (up to 5 attempts, with a numeric suffix) if that candidate is taken — this is one-time, largely-invisible plumbing, not a decision worth interrupting the conversation for. Only pass `--handle` yourself if the owner explicitly asked to choose one.

Also omit `--type` (default `ind`) unless the owner has explicitly said this agent represents a registered business — in that case pass `--type corp`, and use the business path in Step 3 below, not the individual one.

Two outcomes the CLI itself distinguishes for you — read the error text rather than assuming a bare 409:

- **A `usage`-class error whose message starts "This account has already claimed a controller identifier"** (`error_code: identifier_already_claimed`) — this account is done with this step. Its hint names the exact next command (`kpass onboarding submit` or `kpass agent create`); follow it and continue this flow from there. This is not a failure — treat it as "already satisfied."
- **"Could not claim ... after 5 attempts — every candidate was taken"** — a different problem (every generated candidate collided with someone else's identifier, not this account's own). Report this to the owner rather than retrying further; they can supply an explicit `--handle`.

Success reports `identifier` and `claimed_at` — record `identifier` so you can name it if you need to reference it later.

## Step 3: Submit KYC/KYB

**Individual path (default):**

```bash
kpass onboarding submit --type kyc --legal-name <best available> --country <best available> --output json
```

In the common case — a Claude Code session with no real legal identity to submit — fill `--legal-name` from the account's email local part and `--country` with a placeholder (e.g. `US`), and say so plainly in the transcript, every time:

> Submitting placeholder KYC details (`<legal_name>`, `<country>`) — this only works in a dev/sandbox environment that auto-approves onboarding. A production account needs real details submitted here or through the Passport dashboard.

Never fabricate KYC data silently.

**Business path** (only when Step 2 used `--type corp` because the owner explicitly said so):

```bash
kpass onboarding submit --type kyb --legal-name <owner-provided legal name> --country <owner-provided ISO2> --reg-no <owner-provided registration number> --output json
```

Ask the owner for all three values directly. Never placeholder a registration number — unlike the individual path, this one has no dev-sandbox shortcut.

A 409 here means the record is already `verified` and immutable — the CLI's own hint says exactly that ("Already verified; nothing to do"). Treat it as success and move on; do not resubmit.

## Step 4: Poll briefly

```bash
kpass onboarding status --output json
```

A handful of times over a short window — 5 attempts, 3 seconds apart (15 seconds total) is a reasonable budget, stopping early the moment `onboarding_status` reports something other than `pending`. This mirrors `agent bind --wait`'s poll shape, but this skill owns the loop itself: `onboarding status` has no `--wait` flag, deliberately (`passport-cli`'s design keeps polling out of that CLI's scope).

- **`verified`** — continue to Step 5.
- **Still `pending` after the budget** — **stop here.** Tell the owner: identity verification is under real review, this isn't a dev/sandbox backend, check the Passport dashboard, and come back once it clears. Do not attempt `agent create` — it will just fail with `ErrRequiresOnboarding`, spending a request to learn what you already know.
- **`rejected`** — same handling as Step 1: report it, do not resubmit with guessed corrections.

## Step 5: Create the agent

```bash
kpass agent create --uid <slug> --kind buyer --output json
```

Ask the owner for the `uid` — it becomes the tail of the DID permanently, neither can be changed afterwards, only replaced by a new agent — and any of this skill's own Step 2 options (`--url`, `--description`, etc.) it already documents. You run this command directly, on the owner's already-authenticated `kpass` session (see `authenticate-user`) — the owner does not need to open a separate terminal or type it themselves.

`--skip-runtime-approval` exists and is harmless to pass, but has had no effect on binding activation since backend commit `d84f17c6` — activation is determined entirely by bind method (Step 6 below), never by this flag. Do not rely on it, and do not describe it to the owner as controlling whether this flow is hands-off.

## Step 6: Mint and bind

```bash
kpass agent token create --agent <did-or-agt-id> --output json
```

Then consume the token immediately, on this skill's own binary:

```bash
kpass agent bind --agent <did-or-agt-id> --token <art_...> --output json
```

(`kagent bind --agent <did-or-agt-id> --token <art_...> --output json` on the seller copy of this file.)

Token minting needs only the owner's plain JWT — no passkey step-up — so in practice this lands `active` immediately: no `--wait` needed, no `approval_url` to surface. This is the default path from here forward.

**If token mint ever comes back requiring step-up anyway** (kept as a defensive fallback, not because it's expected): fall back to exactly this skill's already-documented direct-path bind — drop `--token`, bind directly, and surface `approval_url` / passkey guidance exactly as this skill's Step 3 already does for that case.

The plaintext token (`art_...`) is shown exactly once, at mint — the server stores only its hash. Consume it immediately; there is no way to recover it later.

---

This file assumes the caller already holds a plain owner JWT (see `authenticate-user`). If any command above returns exit code 3 (`AUTH`), stop and tell the owner to run `authenticate-user` first — do not attempt to work around a missing JWT here.
