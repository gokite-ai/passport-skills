# CLI drift and requirements-doc gap fixes — design

**Date:** 2026-08-27
**Status:** Draft, pending review

## Context

Two new requirements docs (`Buyer & Seller Portal — Onboarding Flow
Requirements for the first A2A deal.md`, `Kite A2A One-Pager — Agents That Do
Business.md`) prompted a second gap-analysis round. That round surfaced two
kinds of findings:

1. **CLI drift**: the skills were last verified against `kpass`/`kagent`
   v1.15.1. The CLI now installed in this environment is v2.0.0 (confirmed
   `kpass --version` / `kagent --version`), which is what the staging
   installer actually serves. Two targeted re-verification passes against
   live v2.0.0 found real, confirmed drift.
2. **Requirements-doc gaps**: real commands exist that are undocumented, and
   one existing skill claim is actively misleading given real behavior.

Per explicit scoping decisions: missing-CLI-command findings (an `appeal`
verb that's architecturally modeled but not exposed by either binary; no
persistence for `--base-url`; no schema field for buyer-specific purchase
instructions) are **out of scope for this round** — they need a product/CLI
decision, not a doc fix, and are being tracked separately. Two doc-author-facing
observations about the onboarding doc itself (governance/price-negotiation
being one ceremony not two; a step-ordering mismatch) are also out of scope —
they're feedback for that doc's author, not a skills fix.

## Research method

Five research passes, each grounded in live command output or repo source,
not inference:

- Three parallel forks reading the two new docs against current skills
  (buyer flow, seller flow, refund/dispute terminology), each cross-checking
  claims against live CLI `--help` output and, where needed, the `passport`
  backend's coordination chart (cloned at `_study/passport-main`).
- Two parallel forks re-verifying all buyer-side and seller-side skill
  content against live `kpass 2.0.0`/`kagent 2.0.0 --help` output,
  specifically hunting for drift introduced since the 1.15.1 baseline the
  last round verified against.
- Direct verification (not delegated) of every finding below: exact
  `--help` text for `bind`, `directory card`, `listen`, `card publish`,
  `agreement refund-consent`; the coordination chart's `DELIVERED` and
  `REJECTED` state transitions (`pkg/coordination/chart_reference.json`);
  the existing `passport-cli/examples/autonomous/` seller daemon example;
  and current `skills.json` version fields.

## Findings and fixes

### 1. `kpass agent bind` gained three undocumented flags — false positive, no-op

Live `kpass agent bind --help` now lists `--device`, `--env`, `--software`
(all optional strings, recorded on the binding — device description,
environment label like "prod"/"staging", and a software identifier
defaulting to the binary+version) alongside the previously-documented
`--agent`, `--token`, `--wait`, `--poll-interval`, `--timeout`. These exist
to let an owner disambiguate between several pending or active runtime
bindings for the same agent.

**Resolution: no-op, confirmed during plan-writing.** Direct verification of
`buyer-agent-setup/references/commands.md`'s `## kpass agent bind` flag
table found `--device`, `--env`, and `--software` already documented there,
correctly, untouched since before either gap-analysis round — this finding
was a false positive. The implementation plan for this spec touches no file
in `buyer-agent-setup/` for this reason; see that plan's Global Constraints
for the same note.

### 2. `buyer-find-seller` actively misdocuments card verification (highest severity)

`buyer-find-seller/SKILL.md:187` lists `kpass agent directory card --source
...` under "Commands That DO NOT Exist," asserting `directory card`
registers no flags — **this is now false**. `--source` is live
(`--source platform` reads the platform-held card of a seller that also
self-hosts one).

More importantly, `buyer-find-seller/SKILL.md:89` currently promises that
`directory card` *"returns the seller's published agent card and verifies
its hash... A mismatch is exit code 8, not a soft warning."* Live help text
draws a distinction this line erases: for `source=platform_held`, the CLI
does recompute and compare the hash locally, exactly as documented. For
`source=self_hosted`, the hash covers the seller's raw origin bytes, which
`directory card` **does not re-fetch** — it serves the last recorded
observation. Verifying against the origin is the caller's own
responsibility (fetch `card_url`, hash it yourself), and nothing in the
current skill says so.

**Fix:**
- Remove the false "Commands That DO NOT Exist" line for `--source`.
- Rewrite the verification paragraph to state both guarantees precisely:
  `platform_held` is locally hash-verified with exit 8 on mismatch, exactly
  as before; `self_hosted` is not re-verified by this command at read time,
  and a buyer relying on a self-hosted seller's card must independently
  fetch and hash `card_url` before trusting it.
- Document `--source platform` in the flag list.

### 3. `kagent listen` gained `--allow-remote-forward`

Live help shows a new flag `--allow-remote-forward` (also requires
`KAGENT_ALLOW_REMOTE_FORWARD=1` in the environment — the flag alone doesn't
authorize it) that permits a non-loopback `--forward` target.
`seller-fulfill/SKILL.md:353`'s claim that `listen` "has exactly two flags of
its own: `--forward` and `--from`" is now false.

**Fix:** update that line to name three flags, and add one sentence
explaining `--allow-remote-forward`'s two-part gate (flag + env var) and
why it's deliberately awkward to enable (forwarding notifications off-box
is a real trust boundary change — "everything this stream carries then
leaves the machine," per the CLI's own help text).

### 4. `kagent card publish` gained a `--workflow` flag

Live help shows a new repeatable `--workflow <id>` flag that injects or
overrides the card's `workflows` array (the agreement workflows this seller
supports) without hand-editing the card file, checked against the platform's
workflow registry at publish time. This ties directly to the already-merged
`e0db00b` change ("the seller owns the workflow"). Completely undocumented
in `seller-agent-setup/SKILL.md` Step 5.

**Fix:** add a short paragraph to Step 5 documenting `--workflow`, its
repeatable/override semantics, and the registry-refusal behavior for an
unregistered id (pointing at `kagent workflow list`).

### 5. `kagent agreement refund-consent` exists, works, is undocumented

Confirmed live: `kagent agreement refund-consent --agreement-id <id>
--output json` signs an EIP-712 RefundConsent and ends a dispute by sending
the escrow back to the buyer — "the short way out of a rejection... not an
admission of anything, and not arbitration." It is correctly *absent* from
`seller-fulfill`'s "Commands That DO NOT Exist" list (not falsely denied),
but nothing tells a seller this is how to respond to a rejection it agrees
with. This is the actual mechanism behind the one-pager's "or refund"
promise.

**Fix:** add a new step (or a subsection under the existing Step 8 "Watch
for Settlement") to `seller-fulfill/SKILL.md` documenting `refund-consent`:
when to use it (seller agrees the delivery didn't meet terms, or would
rather refund than spend the arbitration window), its one required flag,
and that it's a terminal, no-appeal action. Add the command reference entry
to `seller-fulfill/references/commands.md`.

### 6. The 48-hour delivery-confirmation auto-timeout is undocumented

Confirmed in the `passport` backend's coordination chart
(`chart_reference.json`): `DELIVERED` has an `after` transition keyed on
`deliveryConfirmationWindow` (`seconds: 172800` = 48h) that fires
`CONFIRMATION_EXPIRED` and moves the agreement straight to `ACCEPTED` —
releasing escrow to the seller — if the buyer takes no action. Zero mentions
of this in either `buyer-purchase` or `seller-fulfill` (`grep` for
"48"/"172800"/"CONFIRMATION_EXPIRED"/"automatically" returns nothing in
either file). A buyer who does nothing after delivery is automatically
charged.

**Fix:**
- `buyer-purchase/SKILL.md` Step 7/8 (Verify Before Confirming / Confirm or
  Reject): add a clear statement that inaction has a financial consequence —
  the `deliveryConfirmationWindow` from the signed contract (one of the
  "five windows" already surfaced during proposal) auto-releases escrow to
  the seller if neither `confirm` nor `reject` runs before it elapses.
- `seller-fulfill/SKILL.md` Step 8 (Watch for Settlement): add the seller-side
  mirror — a delivered agreement the buyer never responds to still resolves,
  in the seller's favor, once the window elapses; `agreement status --watch`
  will show `ACCEPTED` even with no buyer `confirm`.

### 7. Dispute-resolution language overstates what's CLI-reachable

`seller-fulfill/SKILL.md:278` and `buyer-purchase/SKILL.md:273` both
describe a rejection as going to "the contract's arbiter," who "decides."
Per the coordination chart, `REJECTED`'s only two live-CLI-reachable
transitions are `REFUND_CONSENT_SUBMITTED` (seller's `refund-consent`,
fix #5) and the `appealResponseWindow` timeout (also 172800s/48h) to
`CANCELLED` (refund) — `APPEAL_SUBMITTED`/`kite.contract.appeal` exists in
the chart but is not exposed by either CLI today (the out-of-scope missing
command from the earlier round). As currently worded, both skills imply an
agent can rely on arbiter adjudication as a real, reachable path — it isn't,
today.

**Fix:** without recommending or building the missing `appeal` command
(out of scope), correct the wording in both skills to state the two paths
that actually resolve a rejection today: the seller's own
`refund-consent`, or the `appealResponseWindow` timeout defaulting to a
refund (`CANCELLED`). Keep the existing "know who the arbiter is before
signing" guidance (still correct — the contract still names one, and the
schema still requires it), but stop implying an agent can invoke arbitration
today. `seller-fulfill/SKILL.md`'s existing "Commands That DO NOT Exist"
line for `agreement appeal` (line 349) already correctly states no such
verb exists — the fix is only to the narrative language elsewhere that
contradicts that line's own accuracy.

### 8. Seller starter-kit gap is resolved — reference existing example, don't write new content

A prior round flagged "no example/starter server for a seller's `listen
--forward` target" as a real gap. This round found it already exists:
`passport-cli/examples/autonomous/seller.sh` (+ `responder.py`, `lib.sh`,
and a `README.md` explaining the architecture) is a complete, working,
already-maintained example — `kagent listen --forward` piping to a ~200-line
Python A2A responder that dispatches on `agreement.proposed` /
`agreement.funding.updated` / `work.available` / `message.received` and
runs the corresponding `kagent` verbs. It documents exactly the three
platform rules a seller integrator needs (SUBMITTED isn't progress; the
stream is a latency optimization, not the correctness mechanism; `listen`
never claims work).

**Fix:** add a pointer from `seller-agent-setup/SKILL.md` (near the
"Minimum integration work" implied by Step 5/6, or in the Cross-Skill
References section) and from `seller-fulfill/SKILL.md`'s "Choosing How to
Notice Work" section to `passport-cli/examples/autonomous/README.md` as the
worked reference implementation. No new content is authored describing the
integration from scratch — the existing example is the reference, this
repo just needs to point at it. If `passport-cli`'s examples directory path
is not guaranteed stable across CLI versions, phrase the pointer in a way
that degrades gracefully (name the file, note it ships in the
`passport-cli` source tree under `examples/autonomous/`).

### 9. Version floor bump

`skills.json`'s `min_kpass_version` and `min_kagent_version` are both still
`1.15.0`. Findings #1-#4 above are all new-since-1.15.0 capabilities (not
breaking changes — content that doesn't mention them still works below
2.0.0), but since this round documents them as real, current capabilities,
the floor should reflect where they were confirmed to exist:
`min_kpass_version: "2.0.0"`, `min_kagent_version: "2.0.0"`. Neither
neither drift check found anything requiring a floor above 2.0.0.

**Fix:** bump both fields in `skills.json`. This is a one-line-each,
low-risk change; no other `skills.json` field needs touching.

## Explicitly out of scope (per user decision)

- Building or recommending a CLI `appeal`/arbitration-invocation command.
- Any fix for `--base-url`/`KITE_PASSPORT_BASE_URL` non-persistence (a real
  CLI gap, but a CLI-team decision, not a skills-doc fix).
- Any fix for the `deliverable` schema field conflating an offering's
  generic description with a specific purchase's instructions (a
  schema/product decision).
- Feedback to the onboarding doc's author about "Governance" vs. "price
  negotiation" being one ceremony, or the seller-flow step-ordering
  mismatch — not a skills change.

## Verification

Same pattern as the last round: after edits, re-run the grep-based
verification each fix specifies, self-review the full diff for markdown
correctness, and — since the automated eval-regression harness
(`evals/functional-workspace/`) was confirmed absent from this repo in the
prior round's ledger — rely on the same manual routing/content
cross-check used then, not a harness run.

## Files touched

- `buyer-find-seller/SKILL.md` (finding #2)
- `seller-fulfill/SKILL.md`, `seller-fulfill/references/commands.md`
  (findings #3, #5, #6, #7, #8)
- `seller-agent-setup/SKILL.md` (findings #4, #8)
- `buyer-purchase/SKILL.md` (findings #6, #7)
- `skills.json` (finding #9)

`buyer-agent-setup/` is deliberately absent from this list — finding #1 is a
confirmed false positive; see that finding above.
