# Owner Account Bootstrap for buyer/seller-agent-setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `buyer-agent-setup` and `seller-agent-setup` carry an owner from "logged in" to "active, bound agent" in one skill invocation — claiming the controller identifier, submitting KYC/KYB, creating the agent, and binding via the new mint-then-bind fast path — without the owner leaving the terminal, using the four new `kpass` verbs (`identifier claim`, `onboarding submit`, `onboarding status`, `agent token create`) that `passport-cli`'s `feat/owner-onboarding` branch adds.

**Architecture:** A new shared reference file, `references/owner-bootstrap.md`, is created identically in both `buyer-agent-setup/` and `seller-agent-setup/` (no cross-skill include mechanism exists in this repo — "shared" means kept identical by convention). Each skill's `SKILL.md` Step 2 and Step 3 point into it instead of duplicating its prose. Running its commands from inside these skills requires widening each skill's `allowed-tools` glob beyond what `buyer-agent/README.md` / `seller-agent/README.md` currently document, so those two group READMEs are updated in the same pass to name this as a deliberate, scoped exception.

**Tech Stack:** This repo has no application code — every task here edits Markdown skill content and one JSON manifest (`skills.json`). Verification is `npm run validate` (structure/frontmatter/reference-link checks, `scripts/validate.sh` + `scripts/check-skill-content.js`) and `npm run lint` (`markdownlint-cli2`), both already wired into this repo's CI. There is no automated eval harness for skill *behavior* — end-to-end CLI verification is manual and is called out as its own task at the end.

**Spec:** `docs/superpowers/specs/2026-08-28-owner-onboarding-design.md` (this repo). Companion CLI spec: `passport-cli`'s `docs/superpowers/specs/2026-08-28-owner-onboarding-design.md` on branch `feat/owner-onboarding` (confirmed implemented as of commit `f7cec22` in that repo; not yet merged to `passport-cli` `main` or tagged as of this writing).

## Global Constraints

- **No `--handle` prompt.** `identifier claim` never asks the owner to pick a handle; omit the flag and let the CLI auto-generate one from the account's saved email.
- **Never fabricate KYC data silently.** Placeholder `--legal-name`/`--country` on the individual (`kyc`) path must be disclosed in the transcript, verbatim, every time. A business (`kyb`) path never uses placeholders — `--reg-no` in particular is only ever the owner's real number.
- **Default to individual (`ind`/`kyc`) for both lanes.** Only use `corp`/`kyb` when the owner has explicitly said this agent represents a registered business.
- **`--skip-runtime-approval` is not load-bearing.** It records an agent-level preference but has had no effect on binding activation since backend commit `d84f17c6`. Do not treat it as part of the fast path; the fast path is entirely the mint-then-bind sequence (Step 6 below).
- **The direct-path bind stays exactly as documented today** as the fallback branch — never deleted, only demoted to "if token mint ever requires step-up."
- **`allowed-tools` widening is scoped to two files only** (`buyer-agent-setup/SKILL.md`, `seller-agent-setup/SKILL.md`) and to the four new verbs plus (seller only) the pre-existing `kpass agent` tree. No other skill in either group gains any new grant.
- **`skills.json`'s `min_kpass_version` / `min_kagent_version` are top-level, not per-skill** — bumping them raises the floor for every skill in the bundle, not just these two. Confirmed by reading `scripts/setup.sh`'s `DEFAULT_MIN_KPASS_VERSION` fallback.
- Every command shown in any file this plan touches must match `passport-cli`'s actual flag names and output fields, confirmed against the `feat/owner-onboarding` branch source (`cmd/identifier/claim.go`, `cmd/onboarding/submit.go`, `cmd/onboarding/status.go`, `cmd/agent/token/create.go`, `cmd/agent/create.go`) — not invented or copied from the design doc without cross-checking.

---

## Task 1: Document the `allowed-tools` exception in both group READMEs

**Files:**
- Modify: `buyer-agent/README.md` (the "Permission glob contract" section, lines 26–40)
- Modify: `seller-agent/README.md` (the "Permission glob contract" section, lines 27–41)

**Interfaces:** None — pure documentation, no other task depends on this one's content (only on it existing before a reviewer asks "is this widening documented anywhere").

- [ ] **Step 1: Edit `buyer-agent/README.md`**

Find:

```markdown
## Permission glob contract

Skills in this group declare `allowed-tools` scoped to the agent verb tree
only, not the full `kpass` surface a human-driven skill would need:

```yaml
allowed-tools:
  - "Bash(kpass agent *)"
```

This is narrower than a `user`-group skill's glob (e.g. `Bash(kpass signup
*)`, `Bash(kpass login *)`) by design: a buyer agent should never be able to
invoke `kpass signup`, `kpass login`, or other human-account commands through
this permission, even if it's running in the same sandbox as user-facing
skills.
```

Replace with:

```markdown
## Permission glob contract

Skills in this group declare `allowed-tools` scoped to the agent verb tree
only, not the full `kpass` surface a human-driven skill would need:

```yaml
allowed-tools:
  - "Bash(kpass agent *)"
```

This is narrower than a `user`-group skill's glob (e.g. `Bash(kpass signup
*)`, `Bash(kpass login *)`) by design: a buyer agent should never be able to
invoke `kpass signup`, `kpass login`, or other human-account commands through
this permission, even if it's running in the same sandbox as user-facing
skills.

**Named exception:** `buyer-agent-setup` additionally carries
`"Bash(kpass identifier *)"` and `"Bash(kpass onboarding *)"`, scoped to the
one-time owner identity/KYC bootstrap documented in its
`references/owner-bootstrap.md` (claiming a controller identifier and
submitting KYC before an agent can be created — see that skill's Step 2). No
other skill in this group carries this grant, and `buyer-agent-setup` still
cannot invoke `kpass signup`, `kpass login`, or any other human-account
command outside that named path.
```

- [ ] **Step 2: Edit `seller-agent/README.md`**

Find:

```markdown
## Permission glob contract

Skills in this group declare `allowed-tools` scoped to the `kagent` binary
only:

```yaml
allowed-tools:
  - "Bash(kagent *)"
```

This keeps a seller-agent skill's permissions disjoint from both the `user`
group's `kpass ...` glob and the `buyer-agent` group's `Bash(kpass agent *)`
glob: a seller-agent skill should never be able to invoke buyer-side spending
commands or human-account commands, even when installed in the same agent
sandbox.
```

Replace with:

```markdown
## Permission glob contract

Skills in this group declare `allowed-tools` scoped to the `kagent` binary
only:

```yaml
allowed-tools:
  - "Bash(kagent *)"
```

This keeps a seller-agent skill's permissions disjoint from both the `user`
group's `kpass ...` glob and the `buyer-agent` group's `Bash(kpass agent *)`
glob: a seller-agent skill should never be able to invoke buyer-side spending
commands or human-account commands, even when installed in the same agent
sandbox.

**Named exception:** `seller-agent-setup` additionally carries
`"Bash(kpass identifier *)"`, `"Bash(kpass onboarding *)"`, and
`"Bash(kpass agent *)"`, scoped to the one-time owner identity/KYC bootstrap
and agent creation/bind-token minting documented in its
`references/owner-bootstrap.md` (see that skill's Step 2 and Step 3). No
other skill in this group carries this grant, and `seller-agent-setup` still
cannot invoke `kpass signup`, `kpass login`, buyer-side spending commands, or
any other human-account command outside that named path.
```

- [ ] **Step 3: Validate**

```bash
npm run validate
```

Expected: `[OK]` on all checks — this task touches no `skills.json` entries or `SKILL.md` frontmatter, so nothing here should fail. This is a docs-only change; there is no "fails then passes" cycle to demonstrate — confirm the command still exits 0.

- [ ] **Step 4: Lint**

```bash
npx markdownlint-cli2 buyer-agent/README.md seller-agent/README.md
```

Expected: no errors.

- [ ] **Step 5: Commit — including the reviewed spec docs**

This is the first commit on this branch, so it also picks up the two spec files that were sitting untracked before this branch existed (`docs/superpowers/specs/2026-08-28-owner-onboarding-design.md`, updated during this plan's own review pass with the `allowed-tools` correction and the top-level-version-floor correction, plus `docs/superpowers/specs/2026-08-28-owner-onboarding-cross-team-requirements.md`) and this plan file itself:

```bash
git add buyer-agent/README.md seller-agent/README.md \
  docs/superpowers/specs/2026-08-28-owner-onboarding-design.md \
  docs/superpowers/specs/2026-08-28-owner-onboarding-cross-team-requirements.md \
  docs/superpowers/plans/2026-08-28-owner-onboarding.md
git commit -m "docs(agent-groups): document the owner-bootstrap allowed-tools exception

Also adds the reviewed owner-onboarding design/requirements specs and
implementation plan."
```

---

## Task 2: Create `seller-agent-setup/references/owner-bootstrap.md`

**Files:**
- Create: `seller-agent-setup/references/owner-bootstrap.md`

**Interfaces:**
- Produces: the file `seller-agent-setup/SKILL.md` will link to via `@references/owner-bootstrap.md` in Task 3 (required by `scripts/check-skill-content.js`'s reference-link check).

- [ ] **Step 1: Write the file**

```markdown
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
kpass agent create --uid <slug> --kind seller --output json
```

(`--kind buyer` on the buyer copy of this file.) Ask the owner for the `uid` — it becomes the tail of the DID permanently, neither can be changed afterwards, only replaced by a new agent — and any of this skill's own Step 2 options (`--url`, `--description`, etc.) it already documents. You run this command directly, on the owner's already-authenticated `kpass` session (see `authenticate-user`) — the owner does not need to open a separate terminal or type it themselves.

`--skip-runtime-approval` exists and is harmless to pass, but has had no effect on binding activation since backend commit `d84f17c6` — activation is determined entirely by bind method (Step 6 below), never by this flag. Do not rely on it, and do not describe it to the owner as controlling whether this flow is hands-off.

## Step 6: Mint and bind

```bash
kpass agent token create --agent <did-or-agt-id> --output json
```

Then consume the token immediately, on this skill's own binary:

```bash
kagent bind --agent <did-or-agt-id> --token <art_...> --output json
```

(`kpass agent bind --agent <did-or-agt-id> --token <art_...> --output json` on the buyer copy of this file.)

Token minting needs only the owner's plain JWT — no passkey step-up — so in practice this lands `active` immediately: no `--wait` needed, no `approval_url` to surface. This is the default path from here forward.

**If token mint ever comes back requiring step-up anyway** (kept as a defensive fallback, not because it's expected): fall back to exactly this skill's already-documented direct-path bind — drop `--token`, bind directly, and surface `approval_url` / passkey guidance exactly as this skill's Step 3 already does for that case.

The plaintext token (`art_...`) is shown exactly once, at mint — the server stores only its hash. Consume it immediately; there is no way to recover it later.

---

This file assumes the caller already holds a plain owner JWT (see `authenticate-user`). If any command above returns exit code 3 (`AUTH`), stop and tell the owner to run `authenticate-user` first — do not attempt to work around a missing JWT here.
```

- [ ] **Step 2: Validate the new file is picked up**

```bash
npm run validate
```

Expected: still passes — this task alone doesn't add a `@references/owner-bootstrap.md` link yet (that's Task 3), so `check-skill-content.js` doesn't check this file's existence until then. Confirm exit 0 regardless, as a baseline before Task 3 wires the link.

- [ ] **Step 3: Lint**

```bash
npx markdownlint-cli2 seller-agent-setup/references/owner-bootstrap.md
```

Expected: no errors. Fix any line-length or heading-style violations the linter flags before moving on.

- [ ] **Step 4: Commit**

```bash
git add seller-agent-setup/references/owner-bootstrap.md
git commit -m "feat(seller-agent-setup): add the owner-bootstrap reference"
```

---

## Task 3: Wire `seller-agent-setup/SKILL.md` to the new reference

**Files:**
- Modify: `seller-agent-setup/SKILL.md` (frontmatter `allowed-tools`, Step 2 at lines 133–141, Step 3 at lines 145–169, Cross-Skill References at the end of the file)

**Interfaces:**
- Consumes: `seller-agent-setup/references/owner-bootstrap.md` (Task 2).

- [ ] **Step 1: Widen `allowed-tools` in the frontmatter**

Find:

```yaml
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(bash */setup-kagent.sh*)"
  - "Bash(bash */setup-ksearch.sh*)"
  - "Bash(kagent *)"
  - "Bash(ksearch *)"
---
```

Replace with:

```yaml
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(bash */setup-kagent.sh*)"
  - "Bash(bash */setup-ksearch.sh*)"
  - "Bash(kagent *)"
  - "Bash(ksearch *)"
  - "Bash(kpass identifier *)"
  - "Bash(kpass onboarding *)"
  - "Bash(kpass agent *)"
---
```

- [ ] **Step 2: Replace Step 2's body**

Find:

```markdown
### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover this. The owner creates the seller agent record and tells you which one this runtime represents — a `did:kite:...` DID, an `agt_...` id, or a uid. A reference that does not resolve is exit 4, not something to retry with guesses.

What they run is either the Passport dashboard or, with their own login:

```bash
kpass agent create --uid <slug> --kind seller --output json
```

That is the owner's command, not yours: it authenticates with their JWT, and the `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) A seller created without a `--url` starts **unlisted**, which is correct at this point: it has no card yet for a buyer to read.
```

Replace with:

```markdown
### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover the `uid` on your own — ask the owner, and confirm `--kind seller`. Before creating the agent, work through **`references/owner-bootstrap.md`** steps 1–4: check onboarding status, claim the controller identifier, submit KYC/KYB, and poll briefly. Every account needs this before `agent create` will succeed — it refuses with `ErrRequiresIdentifier` / `ErrRequiresOnboarding` otherwise.

Once that resolves (`verified`, or already was), create the agent — either the owner does this through the Passport dashboard, or you run it directly on their already-authenticated `kpass` session (see `authenticate-user`):

```bash
kpass agent create --uid <slug> --kind seller --output json
```

The `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) A seller created without a `--url` starts **unlisted**, which is correct at this point: it has no card yet for a buyer to read. A reference that does not resolve later, in Step 3, is exit 4, not something to retry with guesses.

If `owner-bootstrap.md` Step 4 reports onboarding still `pending` past its poll budget, or Step 1/3 hit a `rejected` record, stop there and follow that file's guidance — do not attempt `agent create` early.
```

- [ ] **Step 3: Replace Step 3's opening (the bind command and the token-path bullet)**

Find:

```markdown
### Step 3: Bind, and Surface the Approval

```bash
kagent bind --agent <did-or-agt-id> --wait --output json
```

- **`status: "human_action_required"`, `binding: "pending"`** — the direct path, always. **The owner must approve it with their passkey; no CLI verb can.** How to tell them depends on what the envelope carries, and both cases happen:
```

Replace with:

```markdown
### Step 3: Bind, and Surface the Approval

**Default path — mint then bind (`references/owner-bootstrap.md` Step 6):**

```bash
kpass agent token create --agent <did-or-agt-id> --output json
kagent bind --agent <did-or-agt-id> --token <art_...> --output json
```

Token minting needs only the owner's plain JWT — no passkey step-up — so this lands `active` immediately in practice: no `--wait`, no `approval_url` to surface. Do this first.

**Fallback path — if token mint ever comes back requiring step-up** (defensive, not expected):

```bash
kagent bind --agent <did-or-agt-id> --wait --output json
```

- **`status: "human_action_required"`, `binding: "pending"`** — the direct path. **The owner must approve it with their passkey; no CLI verb can.** How to tell them depends on what the envelope carries, and both cases happen:
```

The rest of Step 3 (the `approval_url` present/absent bullets, the re-surface guidance, the `--wait` polling description, and the "any other binding value" closing line) stays exactly as it is today — it now documents the fallback branch instead of the only branch, and none of its content needs to change.

- [ ] **Step 4: Add the four new commands to the "Command Reference" pointer list**

Find:

```markdown
## Command Reference

Full argument tables, JSON envelopes, content rules, and hash semantics for `init`, `key show`, `bind`, `status`, `card fetch`, `card publish`, `registration template`, `registration validate`, `registration publish`, `registration get`, `docs publish`, and `docs unpublish`:
```

Replace with:

```markdown
## Command Reference

Full argument tables, JSON envelopes, content rules, and hash semantics for `init`, `key show`, `bind`, `status`, `card fetch`, `card publish`, `registration template`, `registration validate`, `registration publish`, `registration get`, `docs publish`, `docs unpublish`, and the owner-bootstrap commands (`kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, `kpass agent token create`):
```

- [ ] **Step 5: Add a Cross-Skill Reference to `authenticate-user`**

Find the "Cross-Skill References" section (near the end of the file) and add one bullet naming `authenticate-user` as the actual JWT prerequisite:

```markdown
- **The JWT this skill assumes throughout:** the **`authenticate-user`** skill — run it first if `owner-bootstrap.md`'s commands return exit code 3.
```

Add it as the first bullet under `## Cross-Skill References`, before the existing `seller-serve` bullet.

- [ ] **Step 6: Validate**

```bash
npm run validate
```

Expected: `[OK] All SKILL.md frontmatter parses and references/ links resolve` — this is the check that would fail if Task 2's file were missing or misnamed; confirm it now passes with the real `@references/owner-bootstrap.md` link in place.

- [ ] **Step 7: Lint**

```bash
npx markdownlint-cli2 seller-agent-setup/SKILL.md
```

Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add seller-agent-setup/SKILL.md
git commit -m "feat(seller-agent-setup): bootstrap identity/KYC before agent create, mint-then-bind by default"
```

---

## Task 4: Document the four new commands in `seller-agent-setup/references/commands.md`

**Files:**
- Modify: `seller-agent-setup/references/commands.md` (insert a new section after "Shared Flags", before `## \`kagent init\`` at line 21)

**Interfaces:** None — reference documentation only, read by whoever needs the exact flag/envelope shape.

- [ ] **Step 1: Insert the new section**

After the `Shared Flags` section's closing `---` (line 19) and before `## \`kagent init\`` (line 21), insert:

```markdown
## Owner Bootstrap: `kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, `kpass agent token create`

These four run on the **`kpass`** binary (the owner's account surface), not `kagent` — see `references/owner-bootstrap.md` for when and why this skill invokes them. All four still take `--output json`.

### `kpass identifier claim`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--handle <handle>` | string | `""` | no | The handle half, without the `ind-`/`corp-` prefix. Auto-generated from the account's saved email when omitted, with automatic retry (up to 5 attempts, numeric suffix) on collision. |
| `--type <ind\|corp>` | string | `ind` | no | Individual or business. |

```bash
kpass identifier claim --output json
```

```json
{
  "_version": "1",
  "status": "success",
  "identifier": "ind-alice",
  "claimed_at": "2026-08-28T00:00:00Z",
  "hint": "Claimed ind-alice. Next: 'kpass onboarding submit --type kyc ...' to complete account verification."
}
```

An account that already claimed an identifier gets a `usage`-class error whose message names that fact directly (`error_code: identifier_already_claimed`) and whose hint names the exact next command — this is not a bare 409 to interpret, read the message.

### `kpass onboarding submit`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--type <kyc\|kyb>` | string | `""` | **yes** | Individual or business. |
| `--legal-name <name>` | string | `""` | **yes** | Legal name on file. |
| `--country <ISO2>` | string | `""` | **yes** | Two-letter ISO 3166-1 country code. |
| `--reg-no <num>` | string | `""` | only for `kyb` | Business registration number. |

```bash
kpass onboarding submit --type kyc --legal-name alice --country US --output json
```

```json
{
  "_version": "1",
  "status": "success",
  "onboarding_status": "pending",
  "type": "kyc",
  "legal_name": "alice",
  "country": "US",
  "submitted_at": "2026-08-28T00:00:00Z",
  "hint": "Submitted. Run 'kpass onboarding status --output json' to check verification."
}
```

`onboarding_status` comes back `verified` immediately on a backend with onboarding auto-approve on — the hint changes accordingly to point at `agent create`. A verified record is immutable: resubmitting is a 409, with a hint saying so.

### `kpass onboarding status`

No flags beyond the shared ones.

```bash
kpass onboarding status --output json
```

```json
{
  "_version": "1",
  "status": "success",
  "onboarding_status": "verified",
  "type": "kyc",
  "legal_name": "alice",
  "country": "US",
  "submitted_at": "2026-08-28T00:00:00Z",
  "verified_at": "2026-08-28T00:00:05Z",
  "reason": "",
  "hint": "Verified. Next: 'kpass agent create --uid <slug> --kind <buyer|seller> --output json'."
}
```

Exit 4 (`NOT_FOUND`) until a first `onboarding submit`. No `--wait` flag — polling is the caller's job (see `owner-bootstrap.md` Step 4).

### `kpass agent token create`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agent <ref>` | string | `""` | **yes** | DID, `agt_...` id, or uid. |
| `--ttl-seconds <n>` | int | server default (1 hour) | no | Token lifetime. Mutually exclusive with `--never-expires`. |
| `--never-expires` | bool | `false` | no | Still single-use despite no expiry. |

```bash
kpass agent token create --agent did:kite:ind-alice:my-seller --output json
```

```json
{
  "_version": "1",
  "status": "success",
  "token": "art_...",
  "id": "art_01...",
  "expires_at": "2026-08-28T01:00:00Z",
  "hint": "Use this once: kpass agent bind --agent did:kite:ind-alice:my-seller --token art_... --output json (or kagent bind for a seller runtime). It will not be shown again."
}
```

The plaintext `token` is shown exactly once — the server stores only its hash. Consume it immediately with `kagent bind --token <art_...>`.

---
```

- [ ] **Step 2: Validate**

```bash
npm run validate
```

Expected: exit 0, no new failures.

- [ ] **Step 3: Lint**

```bash
npx markdownlint-cli2 seller-agent-setup/references/commands.md
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add seller-agent-setup/references/commands.md
git commit -m "docs(seller-agent-setup): document identifier/onboarding/token-create commands"
```

---

## Task 5: Create `buyer-agent-setup/references/owner-bootstrap.md`

**Files:**
- Create: `buyer-agent-setup/references/owner-bootstrap.md`

**Interfaces:**
- Produces: the file `buyer-agent-setup/SKILL.md` will link to via `@references/owner-bootstrap.md` in Task 6.

- [ ] **Step 1: Write the file**

Same content as Task 2's file (`seller-agent-setup/references/owner-bootstrap.md`), with exactly these two differences (this is the "kept identical by convention" file — copy it verbatim and make only these edits):

1. In Step 5, the shown command is `kpass agent create --uid <slug> --kind buyer --output json`, and drop the parenthetical `(--kind buyer on the buyer copy of this file)` since this *is* the buyer copy.
2. In Step 6, the shown bind command is `kpass agent bind --agent <did-or-agt-id> --token <art_...> --output json`, and drop the parenthetical `(kagent bind ... on the buyer copy of this file)` since this *is* the buyer copy — instead note `(kagent bind on the seller copy of this file)`.

Concretely, copy the full file from Task 2, then in the buyer copy:
- Step 5's code block becomes:
  ```bash
  kpass agent create --uid <slug> --kind buyer --output json
  ```
  and delete the sentence `(`--kind buyer` on the buyer copy of this file.)`.
- Step 6's second code block becomes:
  ```bash
  kpass agent bind --agent <did-or-agt-id> --token <art_...> --output json
  ```
  and the following sentence becomes: `(`kagent bind --agent <did-or-agt-id> --token <art_...> --output json` on the seller copy of this file.)`

Everything else — Steps 1–4, the intro paragraph, the closing JWT paragraph — is byte-for-byte identical to Task 2's file.

- [ ] **Step 2: Validate**

```bash
npm run validate
```

Expected: exit 0.

- [ ] **Step 3: Lint**

```bash
npx markdownlint-cli2 buyer-agent-setup/references/owner-bootstrap.md
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add buyer-agent-setup/references/owner-bootstrap.md
git commit -m "feat(buyer-agent-setup): add the owner-bootstrap reference"
```

---

## Task 6: Wire `buyer-agent-setup/SKILL.md` to the new reference

**Files:**
- Modify: `buyer-agent-setup/SKILL.md` (frontmatter `allowed-tools`, Step 2 at lines 104–115, Step 3 at lines 116–142, Cross-Skill References at the end of the file)

**Interfaces:**
- Consumes: `buyer-agent-setup/references/owner-bootstrap.md` (Task 5).

- [ ] **Step 1: Widen `allowed-tools` in the frontmatter**

Find:

```yaml
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kpass agent *)"
---
```

Replace with:

```yaml
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kpass agent *)"
  - "Bash(kpass identifier *)"
  - "Bash(kpass onboarding *)"
---
```

- [ ] **Step 2: Replace Step 2's body**

Find:

```markdown
### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover this. The owner creates the agent record and tells you which one this runtime represents. Accept any of: a `did:kite:...` DID, an `agt_...` id, or a uid.

If the owner has not created an agent record yet, stop and say so — `bind` against a nonexistent agent is exit code 4, not a retriable condition. What they run is either the Passport dashboard or, with their own login:

```bash
kpass agent create --uid <slug> --kind buyer --output json
```

That is the owner's command, not yours: it authenticates with their JWT, and the `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) Do not offer to run it against a token you happen to hold.
```

Replace with:

```markdown
### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover the `uid` on your own — ask the owner. Before creating the agent, work through **`references/owner-bootstrap.md`** steps 1–4: check onboarding status, claim the controller identifier, submit KYC/KYB, and poll briefly. Every account needs this before `agent create` will succeed — it refuses with `ErrRequiresIdentifier` / `ErrRequiresOnboarding` otherwise.

Once that resolves (`verified`, or already was), create the agent — either the owner does this through the Passport dashboard, or you run it directly on their already-authenticated `kpass` session (see `authenticate-user`):

```bash
kpass agent create --uid <slug> --kind buyer --output json
```

The `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) A reference that does not resolve later, in Step 3, is exit code 4, not a retriable condition.

If `owner-bootstrap.md` Step 4 reports onboarding still `pending` past its poll budget, or Step 1/3 hit a `rejected` record, stop there and follow that file's guidance — do not attempt `agent create` early.
```

- [ ] **Step 3: Replace Step 3's opening (the bind command and its lead-in)**

Find:

```markdown
### Step 3: Bind the Key, and Surface the Approval

```bash
kpass agent bind --agent <did-or-agt-id> --wait --output json
```

Two outcomes, and the difference is the whole ceremony:

- **`status: "human_action_required"`, `binding: "pending"`** — the normal direct path. **The owner must approve it with their passkey; no CLI verb can.** How to tell them depends on what the envelope carries, and both cases happen:
```

Replace with:

```markdown
### Step 3: Bind the Key, and Surface the Approval

**Default path — mint then bind (`references/owner-bootstrap.md` Step 6):**

```bash
kpass agent token create --agent <did-or-agt-id> --output json
kpass agent bind --agent <did-or-agt-id> --token <art_...> --output json
```

Token minting needs only the owner's plain JWT — no passkey step-up — so this lands `active` immediately in practice: no `--wait`, no `approval_url` to surface. Do this first.

**Fallback path — if token mint ever comes back requiring step-up** (defensive, not expected):

```bash
kpass agent bind --agent <did-or-agt-id> --wait --output json
```

Two outcomes, and the difference is the whole ceremony:

- **`status: "human_action_required"`, `binding: "pending"`** — the direct path. **The owner must approve it with their passkey; no CLI verb can.** How to tell them depends on what the envelope carries, and both cases happen:
```

The rest of Step 3 stays exactly as it is today — it now documents the fallback branch instead of the only branch.

- [ ] **Step 4: Add the four new commands to the "Command Reference" pointer list**

Find:

```markdown
## Command Reference

Full argument tables, JSON envelopes, and the per-command error envelopes for `init`, `key show`, `bind`, and `status` live in:
```

Replace with:

```markdown
## Command Reference

Full argument tables, JSON envelopes, and the per-command error envelopes for `init`, `key show`, `bind`, `status`, and the owner-bootstrap commands (`kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, `kpass agent token create`) live in:
```

- [ ] **Step 5: Add a Cross-Skill Reference to `authenticate-user`**

Find the "Cross-Skill References" section and add, as the first bullet, before the existing `buyer-find-seller` bullet:

```markdown
- **The JWT this skill assumes throughout:** the **`authenticate-user`** skill — run it first if `owner-bootstrap.md`'s commands return exit code 3.
```

- [ ] **Step 6: Validate**

```bash
npm run validate
```

Expected: `[OK] All SKILL.md frontmatter parses and references/ links resolve`.

- [ ] **Step 7: Lint**

```bash
npx markdownlint-cli2 buyer-agent-setup/SKILL.md
```

Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add buyer-agent-setup/SKILL.md
git commit -m "feat(buyer-agent-setup): bootstrap identity/KYC before agent create, mint-then-bind by default"
```

---

## Task 7: Document the four new commands in `buyer-agent-setup/references/commands.md`

**Files:**
- Modify: `buyer-agent-setup/references/commands.md` (insert a new section after "Shared Flags", before `## \`kpass agent init\`` at line 20)

**Interfaces:** None.

- [ ] **Step 1: Insert the new section**

Insert the same "Owner Bootstrap" section written in Task 4, Step 1, with one change: retitle its heading from `## Owner Bootstrap: ...` to note this is the buyer copy's own account surface (the content and flag tables are identical — `kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, and `kpass agent token create` are the same binary, same flags, same envelopes regardless of which skill drives them):

```markdown
## Owner Bootstrap: `kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, `kpass agent token create`

See `references/owner-bootstrap.md` for when and why this skill invokes these four. All take `--output json`.
```

then paste the four `###` subsections (`kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, `kpass agent token create`) from Task 4, Step 1 verbatim — same flag tables, same example commands and JSON envelopes, since these are the same CLI commands regardless of which skill documents them.

- [ ] **Step 2: Validate**

```bash
npm run validate
```

Expected: exit 0.

- [ ] **Step 3: Lint**

```bash
npx markdownlint-cli2 buyer-agent-setup/references/commands.md
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add buyer-agent-setup/references/commands.md
git commit -m "docs(buyer-agent-setup): document identifier/onboarding/token-create commands"
```

---

## Task 8: Update `skills.json` — dependency edges and version floor

**Files:**
- Modify: `skills.json` (the `buyer-agent-setup` and `seller-agent-setup` entries' `dependencies` arrays; the top-level `min_kpass_version` and `min_kagent_version` fields)
- Modify: `scripts/setup.sh:28`, `scripts/setup-kagent.sh:37`, `attach-session/scripts/setup.sh:28`, `authenticate-user/scripts/setup.sh:28`, `buyer-agent-setup/scripts/setup.sh:28`, `request-session/scripts/setup.sh:28`, `seller-agent-setup/scripts/setup.sh:28`, `seller-agent-setup/scripts/setup-kagent.sh:37` (the `DEFAULT_MIN_KPASS_VERSION` / `DEFAULT_MIN_KAGENT_VERSION` fallback pins)

**Interfaces:** None — this is the install-graph metadata `scripts/validate.sh` and `scripts/setup.sh` read.

**Important:** `scripts/validate.sh` (its "SKILL-local setup.sh copies embed DEFAULT_MIN_KPASS_VERSION as the fallback" check, confirmed by running `npm run validate` against the unmodified repo before starting this task) fails loudly if any skill-local `setup.sh`'s `DEFAULT_MIN_KPASS_VERSION` — or any `setup-kagent.sh`'s `DEFAULT_MIN_KAGENT_VERSION` — drifts from `skills.json`'s top-level value. Bumping `skills.json` alone, without Step 2 below, breaks CI immediately.

- [ ] **Step 1: Add the dependency edges**

In the `buyer-agent-setup` entry, change:

```json
  "dependencies": []
```

to:

```json
  "dependencies": ["authenticate-user"]
```

Do the same in the `seller-agent-setup` entry. (This is metadata for the install graph, not an auto-invoke mechanism in this repo — it does not by itself change runtime behavior. Task 3/6's Cross-Skill-References prose edit is what actually tells Claude to run `authenticate-user` first when no JWT exists.)

- [ ] **Step 2: Bump the top-level version floor**

Current values (as of `main` commit `433e8eb`):

```json
  "min_kpass_version": "3.0.0",
  "min_kagent_version": "3.0.0",
```

Bump both to `"3.1.0"` as a placeholder floor:

```json
  "min_kpass_version": "3.1.0",
  "min_kagent_version": "3.1.0",
```

**This is a placeholder, not a confirmed value** — `passport-cli`'s `feat/owner-onboarding` branch (commit `f7cec22` as of this writing) is not yet merged to that repo's `main` or tagged, so the actual release version that will first carry these four verbs is not yet knowable. Before this branch merges to `passport-skills` `main`, re-check `passport-cli`'s released version and update this value to match exactly — do not ship a guessed floor. Leave a note in the PR description flagging this as pending confirmation.

This bump raises the floor for every skill in this bundle (`min_kpass_version`/`min_kagent_version` are top-level fields with no per-skill override in this schema — confirmed by reading `scripts/setup.sh`), not just `buyer-agent-setup`/`seller-agent-setup`. That is expected and matches this repo's existing versioning model; it is not a mistake to double check.

- [ ] **Step 3: Update every `DEFAULT_MIN_KPASS_VERSION` fallback pin**

In each of these six files, change the line `DEFAULT_MIN_KPASS_VERSION="3.0.0"  # floor = skills.json min_kpass_version (pre-release tag dropped)` to `DEFAULT_MIN_KPASS_VERSION="3.1.0"  # floor = skills.json min_kpass_version (pre-release tag dropped)` (same comment, only the version string changes):

- `scripts/setup.sh:28`
- `attach-session/scripts/setup.sh:28`
- `authenticate-user/scripts/setup.sh:28`
- `buyer-agent-setup/scripts/setup.sh:28`
- `request-session/scripts/setup.sh:28`
- `seller-agent-setup/scripts/setup.sh:28`

```bash
for f in scripts/setup.sh attach-session/scripts/setup.sh authenticate-user/scripts/setup.sh \
         buyer-agent-setup/scripts/setup.sh request-session/scripts/setup.sh seller-agent-setup/scripts/setup.sh; do
  sed -i.bak 's/DEFAULT_MIN_KPASS_VERSION="3.0.0"/DEFAULT_MIN_KPASS_VERSION="3.1.0"/' "$f"
  rm -f "$f.bak"
done
```

- [ ] **Step 4: Update every `DEFAULT_MIN_KAGENT_VERSION` fallback pin**

In each of these two files, change `DEFAULT_MIN_KAGENT_VERSION="3.0.0"  # floor = skills.json min_kagent_version` to `DEFAULT_MIN_KAGENT_VERSION="3.1.0"  # floor = skills.json min_kagent_version`:

- `scripts/setup-kagent.sh:37`
- `seller-agent-setup/scripts/setup-kagent.sh:37`

```bash
for f in scripts/setup-kagent.sh seller-agent-setup/scripts/setup-kagent.sh; do
  sed -i.bak 's/DEFAULT_MIN_KAGENT_VERSION="3.0.0"/DEFAULT_MIN_KAGENT_VERSION="3.1.0"/' "$f"
  rm -f "$f.bak"
done
```

If Step 2's placeholder version is later corrected to a real released version, these eight fallback lines must be updated to match — re-run these two loops with the corrected version instead of `3.1.0`.

- [ ] **Step 5: Validate**

```bash
npm run validate
```

Expected: `[OK]` on every check, including the JSON-parses check, the group-consistency check (`dependencies` naming `authenticate-user`, an existing skill, does not break anything `validate.sh` checks — it does not validate that dependency slugs exist, only that groups do, so this step is a smoke test, not a dependency-graph check), and — critically — the eight "fallback floor matches skills.json" checks Step 3/4 above exist to satisfy.

- [ ] **Step 6: Shellcheck the eight edited scripts**

```bash
shellcheck scripts/setup.sh scripts/setup-kagent.sh attach-session/scripts/setup.sh \
  authenticate-user/scripts/setup.sh buyer-agent-setup/scripts/setup.sh \
  request-session/scripts/setup.sh seller-agent-setup/scripts/setup.sh \
  seller-agent-setup/scripts/setup-kagent.sh
```

Expected: exit 0 — these are one-line string edits inside otherwise-unchanged files, so no new shellcheck findings are expected.

- [ ] **Step 7: Commit**

```bash
git add skills.json scripts/setup.sh scripts/setup-kagent.sh attach-session/scripts/setup.sh \
  authenticate-user/scripts/setup.sh buyer-agent-setup/scripts/setup.sh \
  request-session/scripts/setup.sh seller-agent-setup/scripts/setup.sh \
  seller-agent-setup/scripts/setup-kagent.sh
git commit -m "chore(skills): wire authenticate-user dependency, bump version floor for owner-bootstrap"
```

---

## Task 9: Full validation pass, and the manual end-to-end verification checklist

**Files:** None modified — this task runs the full suite this repo's CI runs, plus documents (does not itself execute, since it needs infrastructure this session doesn't have) the manual CLI verification from the design doc's own "Testing / verification" section.

**Interfaces:** None.

- [ ] **Step 1: Run the full validate + lint suite**

```bash
npm run validate
npm run lint
```

Expected: both exit 0. If `markdownlint-cli2` flags anything in files this plan touched, fix it in place before continuing — do not suppress rules.

- [ ] **Step 2: Shellcheck everything (full repo-wide sweep, matching CI)**

```bash
shellcheck scripts/*.sh */scripts/*.sh
```

Expected: exit 0. Task 8 touched eight `.sh` files (one-line version-string edits) — this is the check that confirms those edits didn't break anything CI's own `shellcheck` job would catch.

- [ ] **Step 3: Diff review against the design doc's "Files touched" list**

```bash
git diff --stat main...HEAD
```

Confirm the changed-file set matches exactly: `buyer-agent-setup/SKILL.md`, `buyer-agent-setup/references/commands.md`, `buyer-agent-setup/references/owner-bootstrap.md`, `seller-agent-setup/SKILL.md`, `seller-agent-setup/references/commands.md`, `seller-agent-setup/references/owner-bootstrap.md`, `seller-agent/README.md`, `buyer-agent/README.md`, `skills.json`, plus the eight `setup.sh`/`setup-kagent.sh` version-floor pins from Task 8 — plus the two spec files and this plan file already committed to `main`/this branch from this planning round. Nothing else should appear.

- [ ] **Step 4: Document the manual E2E checklist as a follow-up, not a blocker**

This step produces no file change — it is a checklist to hand to whoever runs the real verification once a `kpass`/`kagent` build from `passport-cli`'s `feat/owner-onboarding` branch (version `2.0.0`, the version installed in this session, predates all four verbs) is installed and pointed at a dev backend with onboarding auto-approve on:

1. Fresh account (never claimed identifier, never submitted onboarding) → invoke `seller-agent-setup` → confirm it reaches an active binding with zero pauses, and that the placeholder-KYC disclosure line actually appears in the transcript.
2. Same, for `buyer-agent-setup`.
3. An account that already has a `verified` onboarding record → confirm Step 1 of `owner-bootstrap.md` skips straight to `agent create` (no redundant `identifier claim` retry noise, no resubmission attempt).
4. Point the same skill at a backend with auto-approve off (or simulate by holding onboarding at `pending`) → confirm the skill stops cleanly with the dashboard-pointer message, and does not attempt `agent create`.
5. If `passport-cli`'s token-mint step-up branch is ever forced (e.g. by a test double), confirm the skill falls back to the direct-path bind exactly as before this change.

This cannot run inside this session — there is no dev backend or updated CLI build reachable here. Hand this checklist to the PR, and do not claim end-to-end verification happened until someone has actually run it.

- [ ] **Step 5: Final commit (if Step 1 produced any lint fixes)**

```bash
git add -A
git commit -m "chore: markdownlint fixes"
```

Skip this commit entirely if Step 1 required no fixes.
