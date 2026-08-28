# Owner account bootstrap for buyer/seller-agent-setup — design

**Date:** 2026-08-28
**Status:** Reviewed against `passport-skills` `main` (up to date as of
commit `433e8eb`) and the `passport-cli` `feat/owner-onboarding` branch
implementation — wire contract confirmed to match. One conflict found and
resolved during review (see the Design section's 2026-08-28 correction on the
`allowed-tools` permission-glob boundary). Ready for implementation.

**Correction (2026-08-28, from the passport backend's own design doc
`passport/docs/superpowers/specs/2026-08-28-owner-onboarding-backend-design.md`):**
`require_runtime_approval` (and therefore `--skip-runtime-approval`) has had
no effect on binding activation since backend commit `d84f17c6` — activation
is determined entirely by *bind method* (token path always active, direct
path always pending), never by this field. This design has been updated in
place (step 5 and its surrounding text below) to stop treating the flag as
load-bearing for the fast path — only step 6's mint-then-bind matters. Not
yet implemented, so corrected directly rather than left as an erratum.

## Context

`buyer-agent-setup` and `seller-agent-setup` both assume an owner already
holds a JWT (from `authenticate-user`, never wired as a formal dependency —
`skills.json` declares `"dependencies": []` for both) *and* already has an
enrolled Passport passkey, before either skill's Step 2 ("Ask the Owner
Which Agent to Bind To") tells the owner to run `kpass agent create`
themselves, outside the skill. Neither skill, nor `authenticate-user`, ever
mentions identifier claim or KYC/KYB — `agent create` will in fact refuse
with `ErrRequiresIdentifier` / `ErrRequiresOnboarding` for any account that
hasn't done both, which today means a human doing it through passport-web's
"New agent" flow before ever touching either skill.

Per PM direction (relayed 2026-08-28): seller owner registration should be a
single request from the human's point of view — no separate steps to claim
an identity, request KYC, and approve a runtime bind. This is achievable
today in an environment where the backend's onboarding auto-approve is on
(dev/local only — see the `passport-cli` design doc,
`2026-08-28-owner-onboarding-design.md`, for the new CLI verbs this depends
on) using the backend's already-existing `require_runtime_approval: false` +
bind-token path, once `passport-cli` exposes it. Buyer registration gets the
same treatment (confirmed decision) — the requirements doc never lists KYC
as a buyer-specific gate, so a buyer owner only needs identifier + a
(cheap, `ind`) KYC record to satisfy `agent create`'s gate, same mechanism.

## Goals

- Both skills complete end-to-end — logged-in owner to an active, bound
  agent — without a human leaving the terminal, when the backend allows it.
- The same skill, unmodified, degrades correctly to today's
  human-in-the-loop behavior (real KYC review, real passkey approval) when
  the backend doesn't allow it. No environment-sniffing; the skill reacts to
  what the API actually says.
- Shared logic lives in one file both skills read, not duplicated prose.

## Non-goals

- No new user-facing skill. Approach A over the alternatives considered
  (new standalone `owner-onboarding` skill; folding into
  `authenticate-user`) — see the brainstorm history for trade-offs. The
  chosen shape keeps one skill invocation as the whole experience and
  avoids forcing identifier/KYC overhead onto every login, including flows
  that never register an agent.
- No change to `authenticate-user` itself.
- No change to the passkey-approval UX for a caller whose flow uses the
  tokenless direct-path bind (the fallback branch in step 6, or anyone
  invoking `agent bind` without a token directly) — that path stays exactly
  as documented today, unconditionally pending until owner approval.

## Design

**Correction (2026-08-28, from a passport-skills readiness review, before
implementation started):** `buyer-agent/README.md` and `seller-agent/README.md`
document a deliberate permission-glob boundary — `buyer-agent` group skills get
`allowed-tools: Bash(kpass agent *)` only, `seller-agent` group skills get
`Bash(kagent *)` only, explicitly so neither group "should never be able to
invoke... human-account commands... even when installed in the same agent
sandbox." `identifier claim` and `onboarding submit`/`status` are account-level
`kpass` commands outside the `kpass agent` tree entirely, and `agent create` /
`agent token create` are commands `seller-agent-setup` has never had access to
(Step 2 has always documented `agent create` as "the owner's command, not
yours"). Running `owner-bootstrap.md` from inside either setup skill therefore
requires widening both skills' `allowed-tools`, and revising both group READMEs
to document this as a deliberate, scoped exception — bootstrap-only, confined
to the two setup skills, not extended to any other skill in either group. This
design now includes that permission and documentation change explicitly (see
"Changes to `allowed-tools` and group contracts" below) rather than leaving it
an unstated side effect discovered during implementation.

### New shared reference: `references/owner-bootstrap.md`

A new file under both `buyer-agent-setup/references/` and
`seller-agent-setup/references/` (identical content, kept in sync the same
way both skills' `references/commands.md` already independently document
overlapping `kpass` verbs — there's no cross-skill include mechanism in this
repo, so "shared" means "copy kept identical by convention and by whichever
plan implements this," not a symlink). Content:

1. **Check before writing.** Before claiming anything, check current state:
   `kpass onboarding status` (404/empty → nothing submitted yet;
   `pending`/`rejected` → resume; `verified` → skip straight to agent
   create). There's no equivalent cheap check for identifier claim yet (see
   backend requirements doc item 3), so identifier claim is attempted
   directly and a 409 is treated as "already claimed, continue" — see error
   table below.
2. **Claim the identifier.** `kpass identifier claim` with no `--handle` —
   let the CLI auto-generate from the account's email. Do not ask the owner
   to pick a handle; this is a one-time, largely-invisible plumbing step,
   not a decision worth interrupting a conversation for. (If a future
   caller wants a chosen handle, they can run `identifier claim --handle`
   themselves before invoking this skill — the skill only auto-generates
   when nothing was claimed yet.)
3. **Submit KYC/KYB.** `kpass onboarding submit --type kyc --legal-name
   <best available> --country <best available>`. In the common case (a
   Claude Code session with no real legal identity to submit), fill
   `--legal-name` from the account's email local part and `--country` with
   a placeholder, and say so plainly in the transcript: *"Submitting
   placeholder KYC details ({legal_name}, {country}) — this only works in a
   dev/sandbox environment that auto-approves onboarding. A production
   account needs real details submitted here or through the Passport
   dashboard."* Never fabricate KYC data silently.
4. **Poll briefly.** `kpass onboarding status`, a handful of times over a
   short window (mirrors `agent bind --wait`'s poll shape, but this skill
   owns the loop itself since `onboarding status` doesn't have a `--wait`
   flag — see passport-cli design doc, which deliberately keeps polling out
   of that CLI's scope). If `verified`, continue. If still `pending` after
   the budget, **stop here** and tell the owner: identity verification is
   under real review, this isn't a dev/sandbox backend, check the Passport
   dashboard, come back once it clears. Do not attempt `agent create` — it
   will just fail with `ErrRequiresOnboarding`, spending a request to learn
   what's already known.
5. **Create the agent.** `kpass agent create --uid <slug> --kind buyer|seller`
   — no flag needed. **Correction (2026-08-28, from the passport backend's
   design doc):** `--skip-runtime-approval` has had no effect on binding
   activation since backend commit `d84f17c6` — activation is determined
   entirely by bind method (step 6), never by any agent-level setting. The
   flag still exists and is harmless to pass, but this design no longer
   treats it as load-bearing for the fast path; step 6 alone is what lands
   the binding active.
6. **Mint and bind.** `kpass agent token create --agent <did>` →
   `kagent bind --token <art_...>` / `kpass agent bind --token <art_...>`.
   Confirmed against the backend's own route table (`pkg/identity/handler/routes.go`):
   token minting needs only the owner's plain JWT, no passkey step-up — so
   in practice this path always lands active immediately, no `--wait`
   needed, no approval URL to surface. The direct-path fallback below is
   defensive, not expected to trigger.
   **If token mint ever comes back requiring step-up anyway** (kept as a
   defensive fallback, not because it's expected): fall back to exactly
   today's direct-path flow — drop `--token`, bind directly, and surface
   `approval_url` / passkey guidance precisely as Step 3 already does. This
   is the one environment-adaptive branch in this design, driven by the
   mint response, not a guess.

### Changes to `seller-agent-setup/SKILL.md`

- **Step 2 ("Ask the Owner Which Agent to Bind To")**: before the existing
  "the owner runs `kpass agent create ...`" instruction, insert a pointer to
  `references/owner-bootstrap.md` steps 1–4. The existing `agent create`
  call itself is unchanged — no flag needed (see the correction in step 5
  above).
- **Step 3 ("Bind, and Surface the Approval")**: after runtime key creation
  (Step 1, unchanged) and the now-fast-path agent create, replace the
  unconditional direct-path bind with `owner-bootstrap.md` step 6's
  mint-then-bind, keeping the existing direct-path text as the documented
  fallback branch rather than deleting it.
- **Command Reference** and **references/commands.md**: add
  `identifier claim`, `onboarding submit`, `onboarding status`, and
  `agent token create`. `agent create --skip-runtime-approval` exists and can
  be documented as an available flag, but this skill's own flow does not
  need to pass it (see the correction in step 5 above).
- **Commands That DO NOT Exist**: remove nothing (these commands are newly
  real, not previously falsely denied — grep confirmed no prior claim about
  them).
- **Cross-Skill References**: add a line naming `authenticate-user` as the
  actual prerequisite for the JWT this skill has always assumed (closing the
  `skills.json` `dependencies: []` gap noted in Context) — a documentation
  fix that was already true regardless of this design, worth doing while
  editing nearby.

### Changes to `buyer-agent-setup/SKILL.md`

Same shape, mapped onto its own step numbers (Step 2 "Ask the Owner Which
Agent to Bind To", Step 3 "Bind the Key, and Surface the Approval"). Buyer
KYC type is always `kyc` (`ind`), never `kyb` — the requirements doc's buyer
table has no KYB-relevant "business" concept for a buyer owner, so this
skill's copy of `owner-bootstrap.md` step 3 doesn't need the `kyb` branch at
all; keeping one shared file with an unused branch for buyers is simpler
than forking the file, and costs nothing since the branch is never reached
from this skill's instructions.

### Changes to `allowed-tools` and group contracts

- **`buyer-agent-setup/SKILL.md` frontmatter:** add `"Bash(kpass identifier *)"`
  and `"Bash(kpass onboarding *)"` to `allowed-tools`. `kpass agent create` and
  `kpass agent token create` are already covered by the existing
  `"Bash(kpass agent *)"` entry — no change needed there.
- **`seller-agent-setup/SKILL.md` frontmatter:** add `"Bash(kpass identifier
  *)"`, `"Bash(kpass onboarding *)"`, `"Bash(kpass agent create *)"`, and
  `"Bash(kpass agent token create *)"` to `allowed-tools` (seller currently
  has no `kpass` access of any kind — only `kagent` and `ksearch`).
  **Correction (2026-08-28, from final-review):** narrowed from a blanket
  `Bash(kpass agent *)` to exactly the two subcommands `owner-bootstrap.md`
  actually uses — the seller side never runs any other `kpass agent` verb,
  and the narrower grant makes the group README's "cannot invoke buyer-side
  spending commands" claim literally true instead of overstated.
- **`buyer-agent/README.md`** and **`seller-agent/README.md`** ("Permission
  glob contract" section in each): document the widened glob as a named,
  bootstrap-only exception — e.g. "`buyer-agent-setup` and `seller-agent-setup`
  additionally carry `Bash(kpass identifier *)` / `Bash(kpass onboarding *)`
  [and, for seller, `Bash(kpass agent create *)` / `Bash(kpass agent token
  create *)`], scoped to the one-time owner
  identity/KYC bootstrap in `references/owner-bootstrap.md`. No other skill in
  either group carries this grant, and neither setup skill gains access to
  `kpass signup`, `kpass login`, or any other human-account command outside
  that named path." This keeps the boundary's intent (no *arbitrary*
  human-account access) precise about the one, deliberate exception rather than
  silently widening the stated rule.

### `skills.json`

- Add `"dependencies": ["authenticate-user"]` to both `buyer-agent-setup` and
  `seller-agent-setup` entries — wires the previously-unused dependency edge
  identified during research. This is metadata (install-graph), not an
  auto-invoke mechanism in this repo, so it does not by itself change
  runtime behavior; the Cross-Skill References prose edit above is what
  actually tells Claude to run `authenticate-user` first when no JWT exists.
- **Correction (2026-08-28):** `skills.json` has no per-skill version-floor
  field — `min_kpass_version` / `min_kagent_version` are top-level only, and
  every skill's bundled `setup.sh` / `setup-kagent.sh` reads that one shared
  floor (see `DEFAULT_MIN_KPASS_VERSION` in `scripts/setup.sh`). So this is a
  single repo-wide bump, not a per-entry one — raising it protects
  `owner-bootstrap.md` but also raises the floor every other skill's Step 0
  enforces. Bump the top-level `min_kpass_version` / `min_kagent_version` to
  whichever `passport-cli` release first ships the four new verbs — same
  precedent as the `2026-08-27-cli-drift-and-doc-gap-fixes` round. As of this
  writing that CLI work lives on an unmerged branch
  (`passport-cli`'s `feat/owner-onboarding`, not yet in `main` or tagged), so
  the exact version string is not yet knowable; the plan tracks this as an
  explicit placeholder to confirm before merge, not a blocker to starting
  implementation. This is what makes the requirements doc's "Automatic
  upgrade: for both CLIs... and skills" item actually protective here: Step
  0's existing `scripts/setup.sh` check enforces this floor before
  `owner-bootstrap.md` ever runs, so an out-of-date bundle is caught and
  upgraded before a caller hits a missing verb instead of a confusing runtime
  failure.

## Error handling (skill-level, on top of what the CLI already reports)

| Situation | Skill behavior |
|---|---|
| `onboarding status` never reachable (network/5xx) | Surface the CLI's own error; do not fall back to skipping onboarding. |
| Identifier already claimed (409 on step 2) | Treat as success, continue — the CLI can't yet distinguish "you" from "someone else" (backend requirements doc item 4), and in practice a 409 immediately after a fresh account almost always means an earlier partial run of this same flow. |
| Onboarding `rejected` | Do not silently resubmit with different placeholder data. Tell the owner the record was rejected and that a resubmission needs real information (`onboarding submit` again with corrected fields) or dashboard follow-up. |
| Onboarding `pending` past the poll budget | Stop; report clearly; do not attempt `agent create`. |
| Token mint requires step-up | Fall back to direct-path bind, unchanged from today's behavior. |
| `agent create` still refuses with `ErrRequiresIdentifier`/`ErrRequiresOnboarding` despite the above (race, or a step above was skipped) | Re-surface the CLI's specific error, naming the missing step by name — never a generic "agent create failed." |

## Testing / verification

No automated eval harness exists for this repo currently (confirmed in the
prior `2026-08-27-cli-drift-and-doc-gap-fixes` round). Verification is
manual, against a dev backend where onboarding auto-approve is on:

1. Fresh account (never claimed identifier, never submitted onboarding) →
   invoke `seller-agent-setup` → confirm it reaches an active binding with
   zero pauses, and that the placeholder-KYC disclosure line actually
   appears in the transcript.
2. Same, for `buyer-agent-setup`.
3. An account that already has a `verified` onboarding record → confirm
   step 1's status check skips straight to agent create (no redundant
   `identifier claim` 409 noise, no resubmission attempt).
4. Point the same skill at a backend with auto-approve off (or simulate by
   holding onboarding at `pending`) → confirm the skill stops cleanly with
   the dashboard-pointer message, and does not attempt `agent create`.
5. If `passport-cli`'s open question resolves to "token mint needs
   step-up": force that response and confirm the skill falls back to the
   direct-path bind exactly as before this change.

## Files touched

- `seller-agent-setup/SKILL.md` (steps, Command Reference, allowed-tools,
  Cross-Skill References), `seller-agent-setup/references/commands.md`,
  `seller-agent-setup/references/owner-bootstrap.md` (new)
- `buyer-agent-setup/SKILL.md` (steps, Command Reference, allowed-tools,
  Cross-Skill References), `buyer-agent-setup/references/commands.md`,
  `buyer-agent-setup/references/owner-bootstrap.md` (new)
- `seller-agent/README.md`, `buyer-agent/README.md` (permission glob contract
  — document the bootstrap-only exception)
- `skills.json` (dependency edges for both skills)

## Depends on

- `passport-cli` design doc `2026-08-28-owner-onboarding-design.md` — this
  design assumes all four new `kpass` verbs it specifies exist. Cannot ship
  ahead of that CLI work landing (at minimum in a pre-release build both
  skills' version floor can point at).
