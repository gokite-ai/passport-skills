# CLI Drift and Requirements-Doc Gap Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct confirmed CLI-behavior drift (v1.15.1 → v2.0.0) and document real-but-unwritten mechanisms (`refund-consent`, the 48h auto-confirm timeout, an existing seller starter-kit example) across five `passport-skills` skill files, and bump `skills.json`'s version floor to match.

**Architecture:** Every change is a targeted markdown edit to an existing `SKILL.md` and/or its `references/commands.md`, following each skill's established structure, plus a two-line JSON edit to `skills.json`. No new skill directories, no code.

**Tech Stack:** Markdown skill files (YAML frontmatter + prose), verified against live `kpass 2.0.0`/`kagent 2.0.0` CLI output and the `passport` backend's coordination chart (`_study/passport-main/pkg/coordination/chart_reference.json`).

**Spec:** `docs/superpowers/specs/2026-08-27-cli-drift-and-doc-gap-fixes-design.md`

## Global Constraints

- Every command example uses `--output json` (project-wide convention).
- Never document a command, flag, or field that was not verified against live `--help` output or repo source during planning — every value in this plan was captured live during planning; do not extend beyond what's written here.
- Out of scope, do NOT add: any `appeal`/arbitration-invocation command, any fix for `--base-url` persistence, any fix for the `deliverable` schema field, any feedback to the onboarding doc's author. If a task's own research surfaces a temptation to "fix" one of these, don't — flag it in the task report instead.
- Per this project's global git policy: **do not run `git add`/`git commit`** for any step below. Leave files modified for the user to review and commit manually (GPG-signed).
- **Correction from planning:** the spec's finding #1 (`kpass agent bind`'s `--device`/`--env`/`--software` flags allegedly undocumented) is a **false positive** — direct verification during plan-writing found `buyer-agent-setup/references/commands.md:104-106` already documents all three, correctly, untouched since before either gap-analysis round. **No task in this plan touches `buyer-agent-setup`.** This correction is recorded here so an executor doesn't go looking for a Task 1 that doesn't exist.

---

### Task 1: `buyer-find-seller` — fix the card-verification claim (spec finding #2)

**Files:**
- Modify: `buyer-find-seller/SKILL.md`

**Interfaces:**
- Consumes: live `kpass agent directory card --help` output, captured during planning (verbatim below).
- Produces: n/a (leaf documentation task).

- [ ] **Step 1: Rewrite the card-verification paragraph to distinguish `platform_held` from `self_hosted`**

  Edit `buyer-find-seller/SKILL.md`. Find this exact paragraph (currently at line 89, inside `### Step 2: Read the Candidate`):

  Old:
  ```
  `directory card` returns the seller's published agent card *and verifies its hash*: the envelope carries `card_hash` (as reported), `card_hash_recomputed`, and `card_hash_verified`. **A mismatch is exit code 8, not a soft warning** — the CLI refuses to hand you a card whose bytes do not match the published hash, with both hashes in `details`. Do not work around it: report to the owner that the seller's card does not verify, and do not propose against it.
  ```
  New:
  ```
  `directory card` reads whichever card the seller actually publishes — its own https origin's, when it has one, or the one its runtime published to Passport otherwise — and the two have different verification guarantees. The envelope's `source` member says which answered.

  **`source: "platform_held"`** — the hash covers the platform's served composition, and this command recomputes it locally and compares: `card_hash` (as reported), `card_hash_recomputed`, and `card_hash_verified`. **A mismatch is exit code 8, not a soft warning** — the CLI refuses to hand you a card whose bytes do not match, with both hashes in `details`. Do not work around it: report to the owner that the seller's card does not verify, and do not propose against it.

  **`source: "self_hosted"`** — the hash covers the raw bytes at the seller's own `card_url`, which this command does **not** re-fetch; it serves the last recorded observation, not a live proxy-fetch. Nothing here is verified against the origin. If the deal matters enough to need that guarantee, fetch `card_url` directly and hash the response yourself before trusting it — do not assume `directory card`'s success here means the same thing it means for a platform-held card.

  Both cards can exist for one agent (a URL seller that also published through its runtime); pass `--source platform` to read the platform-held one even then — omit it for precedence (self-hosted wins when present).
  ```

- [ ] **Step 2: Remove the false "does not exist" entry and add the real `--source` flag**

  Edit `buyer-find-seller/SKILL.md`, in the "Commands That DO NOT Exist" section. Find:

  Old:
  ```
  - `kpass agent directory card --source ...` — `directory card` takes a positional reference and registers **no flags at all**. Same for `directory get` and `directory keys`; `directory registration` is the one directory read with flags (`--registration-hash`, `--inputs`), and `directory offering <ref> <offeringId>` takes two positionals.
  ```
  New:
  ```
  - `kpass agent directory get --source ...` / `directory keys --source ...` — `--source` exists only on `directory card`, to pick between a seller's self-hosted and platform-held card when both exist. `directory get` and `directory keys` still take a positional reference and register no flags of their own; `directory registration` is the other directory read with flags (`--registration-hash`, `--inputs`), and `directory offering <ref> <offeringId>` takes two positionals.
  ```

- [ ] **Step 3: Update the flag-summary sentence in Step 2**

  Edit `buyer-find-seller/SKILL.md`. Find (currently line 93):

  Old:
  ```
  These commands take a **positional reference** — `kpass agent directory get <ref>`, not `--agent`. The reference may be a DID, an `agt_` id, a uid, a wire public key, or a `jkt:` thumbprint. `directory get`, `directory card` and `directory keys` register no flags of their own; `directory registration` adds `--registration-hash <h>` (read a historical revision) and `--inputs=false` (omit the three documents), and `directory offering` takes the offering id as a **second positional argument**.
  ```
  New:
  ```
  These commands take a **positional reference** — `kpass agent directory get <ref>`, not `--agent`. The reference may be a DID, an `agt_` id, a uid, a wire public key, or a `jkt:` thumbprint. `directory get` and `directory keys` register no flags of their own; `directory card` adds `--source platform` (see above); `directory registration` adds `--registration-hash <h>` (read a historical revision) and `--inputs=false` (omit the three documents); and `directory offering` takes the offering id as a **second positional argument**.
  ```

- [ ] **Step 4: Verify**

  Run:
  ```bash
  grep -n "source.*platform_held\|source.*self_hosted\|--source platform" buyer-find-seller/SKILL.md
  grep -n "registers.*no flags at all" buyer-find-seller/SKILL.md
  ```
  Expected: the first returns matches (new content present); the second returns **no match** (false claim removed). Re-read the edited sections to confirm markdown renders cleanly.

- [ ] **Step 5: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the file for the user.

---

### Task 2: `seller-fulfill` — listen flag, refund-consent, 48h timeout, dispute language, starter-kit pointer (spec findings #3, #5, #6, #7, #8)

**Files:**
- Modify: `seller-fulfill/SKILL.md`
- Modify: `seller-fulfill/references/commands.md`

**Interfaces:**
- Consumes: live `kagent listen --help` and `kagent agreement refund-consent --help` output (verbatim below); the coordination chart's `DELIVERED`→`ACCEPTED` (`deliveryConfirmationWindow`, 172800s) and `REJECTED`→`CANCELLED` (`appealResponseWindow`, 172800s) transitions, confirmed in `_study/passport-main/pkg/coordination/chart_reference.json`; `passport-cli/examples/autonomous/README.md`'s existing seller-daemon example.
- Produces: n/a.

- [ ] **Step 1: Fix the "exactly two flags" claim on `listen`**

  Edit `seller-fulfill/SKILL.md`, in the "Commands That DO NOT Exist" section. Find (currently line 353):

  Old:
  ```
  - `kagent listen --events ...` / `--filter` / `--timeout` — `listen` has exactly two flags of its own: `--forward` and `--from`.
  ```
  New:
  ```
  - `kagent listen --events ...` / `--filter` / `--timeout` — `listen` has three flags of its own: `--forward`, `--from`, and `--allow-remote-forward`. None of `--events`/`--filter`/`--timeout` exist.
  ```

- [ ] **Step 2: Document `--allow-remote-forward` where `listen` is first introduced**

  Edit `seller-fulfill/SKILL.md`. In the "Choosing How to Notice Work" section, find the sentence:

  Old:
  ```
  `--forward` is **required** on `listen`. Without a target the process would read the stream and discard it, which is worse than not running: the cursor would advance past events nothing acted on.
  ```
  New:
  ```
  `--forward` is **required** on `listen`. Without a target the process would read the stream and discard it, which is worse than not running: the cursor would advance past events nothing acted on.

  `--forward` must be a loopback target unless `--allow-remote-forward` is also passed — and even then, the flag alone does not authorize it: `KAGENT_ALLOW_REMOTE_FORWARD=1` must also be set in the environment. Both gates exist because forwarding notifications off-box is a real trust-boundary change — the stream can carry proposal and message content, and enabling this means "everything this stream carries then leaves the machine." Leave both unset unless the forward target is genuinely remote by design.
  ```

- [ ] **Step 3: Add `--allow-remote-forward` to the `references/commands.md` flag table for `listen`**

  Edit `seller-fulfill/references/commands.md`. Find the `## kagent listen` flag table:

  Old:
  ```
  | Flag | Type | Default | Required | Notes |
  |---|---|---|---|---|
  | `--forward <url>` | string | `""` | **yes** | The local A2A JSON-RPC endpoint each notification is POSTed to. |
  | `--from <event-id>` | uint64 | `0` | no | Resume after this event id instead of the persisted cursor. |

  Exactly two flags of its own. **No filters, no `--events`, no `--timeout`.**
  ```
  New:
  ```
  | Flag | Type | Default | Required | Notes |
  |---|---|---|---|---|
  | `--forward <url>` | string | `""` | **yes** | The local A2A JSON-RPC endpoint each notification is POSTed to. Loopback only unless `--allow-remote-forward` is also set. |
  | `--from <event-id>` | uint64 | `0` | no | Resume after this event id instead of the persisted cursor. |
  | `--allow-remote-forward` | bool | `false` | no | Permits a non-loopback `--forward` target. Also requires `KAGENT_ALLOW_REMOTE_FORWARD=1` in the environment — the flag alone cannot authorize it. |

  Three flags of its own. **No filters, no `--events`, no `--timeout`.**
  ```

- [ ] **Step 4: Add a `refund-consent` step to the fulfilment flow**

  Edit `seller-fulfill/SKILL.md`. Find Step 8 ("Watch for Settlement") and its content:

  Old:
  ````
  ### Step 8: Watch for Settlement

  ```bash
  kagent agreement status --agreement-id <id> --watch --output json
  ```

  `ACCEPTED` means the buyer confirmed and the escrow released. `REJECTED` means the buyer rejected — the envelope carries their `reason_code`, whose keccak256 is the on-chain `reasonHash` the rejection commits to, and the contract's arbiter decides from there. There is no CLI verb to appeal; the dispute is handled by the named arbiter.
  ````
  New:
  ````
  ### Step 8: Watch for Settlement

  ```bash
  kagent agreement status --agreement-id <id> --watch --output json
  ```

  `ACCEPTED` means the buyer confirmed and the escrow released. **A `DELIVERED` agreement the buyer never responds to still resolves in this agent's favor**: the contract's `deliveryConfirmationWindow` (one of the five windows checked before accepting, in Step 2) auto-releases the escrow if neither `confirm` nor `reject` runs before it elapses — `agreement status --watch` will show `ACCEPTED` with no buyer action in the history. Do not treat buyer silence after delivery as a problem to chase.

  `REJECTED` means the buyer rejected — the envelope carries their `reason_code`, whose keccak256 is the on-chain `reasonHash` the rejection commits to. Two things can happen next, and today only one of them is a CLI verb:

  - **This agent agrees the delivery didn't meet terms, or would rather refund than argue:**

    ```bash
    kagent agreement refund-consent --agreement-id <id> --output json
    ```

    `--agreement-id` is the only flag. It signs an EIP-712 RefundConsent and sends the escrow back to the buyer, ending the dispute in one signed command — it is not an admission of anything, and it is not arbitration. This is the short way out of a rejection, and it's a terminal action: once submitted, there is nothing to undo.

  - **This agent disagrees, and the deal names an arbiter:** the contract still requires and names one (`arbiter_agent_id` in `agreement status`, checked in Step 2), but there is **no CLI verb to invoke arbitration today** — `agreement appeal` does not exist, on either binary. In practice, a `REJECTED` agreement neither party acts on resolves on its own: the contract's `appealResponseWindow` elapsing without a `refund-consent` also ends in a refund to the buyer. Know who the arbiter is before signing (Step 2) because the contract still names one, but do not tell a buyer or an owner that this agent can escalate a disputed rejection to arbitration right now — it cannot.
  ````

- [ ] **Step 5: Add `refund-consent` to `references/commands.md`**

  Edit `seller-fulfill/references/commands.md`. Insert a new section right after the end of `## kagent agreement deliver` and its subsections, before `## kagent agreement evidence add` (find the `---` separator between them, or insert immediately before the `## kagent agreement evidence add` header if no separator exists — check the file's own convention for section breaks and match it):

  ````markdown
  ## `kagent agreement refund-consent`

  | Flag | Type | Default | Required |
  |---|---|---|---|
  | `--agreement-id <id>` | string | `""` | **yes** |

  Nothing else. Signs the EIP-712 RefundConsent the EscrowVault recovers, wraps it in a signed `kite.contract.refund_consented` command, and submits it. The anchors it commits to — the revision, the vault's current nonce, and the newest transition proof as `receiptHash` — are read back immediately before signing.

  This is the short way out of a rejection: consenting sends the escrow back to the buyer and moves the agreement to a terminal state. It is not an admission of anything, and it is not arbitration — it ends the dispute without one. The alternative is appealing to the contract-named arbiter, which costs both parties the arbitration window; there is currently no CLI verb to do that. A seller that would rather refund than argue ends it here on its own authority.

  ```bash
  kagent agreement refund-consent --agreement-id agr_7f2a --output json
  ```

  Only valid from `REJECTED`. Running it on an agreement in any other state is refused.
  ````

- [ ] **Step 6: Add a starter-kit pointer to Cross-Skill References**

  Edit `seller-fulfill/SKILL.md`. Find the `## Cross-Skill References` section:

  Old:
  ```
  ## Cross-Skill References

  - **Prerequisite:** the **`seller-agent-setup`** skill (active binding, pinned card, published card and documents).
  - **Reading a counterparty:** the directory verbs above are the same ones **`buyer-find-seller`** documents from the other side; that skill also covers reference forms and the card-hash verification semantics.
  - **The buyer's side of this flow:** the **`buyer-purchase`** skill — what the buyer does between the proposal and the confirmation.
  - **What buyers read before proposing to this agent:** published by the **`seller-agent-setup`** skill, consumed by **`buyer-find-seller`**.
  - **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
  ```
  New:
  ```
  ## Cross-Skill References

  - **Prerequisite:** the **`seller-agent-setup`** skill (active binding, pinned card, published card and documents).
  - **Reading a counterparty:** the directory verbs above are the same ones **`buyer-find-seller`** documents from the other side; that skill also covers reference forms and the card-hash verification semantics.
  - **The buyer's side of this flow:** the **`buyer-purchase`** skill — what the buyer does between the proposal and the confirmation.
  - **What buyers read before proposing to this agent:** published by the **`seller-agent-setup`** skill, consumed by **`buyer-find-seller`**.
  - **A working reference implementation of this whole flow:** `passport-cli`'s source tree ships `examples/autonomous/seller.sh` (+ `responder.py`, `README.md`) — a complete, runnable seller daemon: `kagent listen --forward` piped to a ~200-line Python A2A responder that dispatches `agreement.proposed` / `agreement.funding.updated` / `work.available` / `message.received` to the corresponding `kagent` verbs. Read its `README.md` before writing a forward target from scratch.
  - **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
  ```

- [ ] **Step 7: Verify**

  Run:
  ```bash
  grep -n "allow-remote-forward\|refund-consent\|deliveryConfirmationWindow\|examples/autonomous" seller-fulfill/SKILL.md seller-fulfill/references/commands.md
  grep -n "exactly two flags" seller-fulfill/SKILL.md
  ```
  Expected: the first returns matches across both files; the second returns **no match** (the stale "exactly two flags" phrase is gone — the corrected line says "three flags"). Re-read every edited section to confirm coherent, well-formed markdown (headers, tables, fences).

- [ ] **Step 8: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the two modified files for the user.

---

### Task 3: `seller-agent-setup` — `card publish --workflow`, starter-kit pointer (spec findings #4, #8)

**Files:**
- Modify: `seller-agent-setup/SKILL.md`

**Interfaces:**
- Consumes: live `kagent card publish --help` output (verbatim below).
- Produces: n/a.

- [ ] **Step 1: Document `--workflow` in Step 5 (Publish the Card)**

  Edit `seller-agent-setup/SKILL.md`. Find the paragraph:

  Old:
  ```
  Nothing else is validated or reshaped — the rest of the content is this agent's own claim about itself. Write it for the buyer who has to decide whether to propose: a name, a description, the skills offered, and pointers to the terms and rate-card documents published in Step 6, since there is no buyer-side document-listing verb and the card is how a buyer finds those URLs.
  ```
  New:
  ````
  Nothing else is validated or reshaped — the rest of the content is this agent's own claim about itself. Write it for the buyer who has to decide whether to propose: a name, a description, the skills offered, and pointers to the terms and rate-card documents published in Step 6, since there is no buyer-side document-listing verb and the card is how a buyer finds those URLs.

  **Declaring supported workflows.** The card may carry a `workflows` array — the agreement workflows this seller supports (design §5.12). Either write it into the file directly, or use `--workflow <id>` (repeatable) to inject or override that member without hand-editing the file:

  ```bash
  kagent card publish --file ./card.json --workflow fixed_outcome/v1 --output json
  ```

  Each id is checked against the platform's workflow registry at publish time — naming one the registry doesn't carry is refused. Run `kagent workflow list` to see the ids it does. This is discovery material for a buyer deciding whether to propose, not the source of truth for what workflow an actual contract runs under — that's still the offering's own registration (Step 7), which is what `propose` reads from on the buyer's side.
  ````

- [ ] **Step 2: Add a starter-kit pointer to Cross-Skill References**

  Edit `seller-agent-setup/SKILL.md`. Find the `## Cross-Skill References` section:

  Old:
  ```
  ## Cross-Skill References

  - **Next, to serve incoming agreements:** the **`seller-fulfill`** skill.
  - **The buyer's side of what this skill publishes:** the **`buyer-find-seller`** skill reads the card, keys, and documents published here.
  - **The buyer identity, a separate binary and key:** the **`buyer-agent-setup`** skill (`kpass agent`).
  - **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
  ```
  New:
  ```
  ## Cross-Skill References

  - **Next, to serve incoming agreements:** the **`seller-fulfill`** skill.
  - **The buyer's side of what this skill publishes:** the **`buyer-find-seller`** skill reads the card, keys, and documents published here.
  - **The buyer identity, a separate binary and key:** the **`buyer-agent-setup`** skill (`kpass agent`).
  - **Building the forward target `seller-fulfill`'s `listen` step needs:** `passport-cli`'s source tree ships a complete, runnable example at `examples/autonomous/seller.sh` (+ `responder.py`, `README.md`) — read that before writing an A2A responder from scratch.
  - **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
  ```

- [ ] **Step 3: Verify**

  Run:
  ```bash
  grep -n "workflows array\|--workflow fixed_outcome\|examples/autonomous" seller-agent-setup/SKILL.md
  ```
  Expected: matches for each. Re-read the edited sections for coherent markdown.

- [ ] **Step 4: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the modified file for the user.

---

### Task 4: `buyer-purchase` — 48h timeout, dispute language (spec findings #6, #7)

**Files:**
- Modify: `buyer-purchase/SKILL.md`

**Interfaces:**
- Consumes: the same coordination-chart evidence as Task 2, Step 4 (`deliveryConfirmationWindow`/172800s, `appealResponseWindow`/172800s).
- Produces: n/a.

- [ ] **Step 1: Add the auto-confirm timeout warning to Step 7 (Verify Before Confirming)**

  Edit `buyer-purchase/SKILL.md`. Find the paragraph at the end of Step 7:

  Old:
  ```
  Then check the artifact itself: the signed delivery command commits to a `deliveryHash` (`sha256:<hex>`), and the evidence record carries the same digest in its `hash` member along with a `url`. **Download the artifact, recompute its sha256, and compare.** A mismatch means the bytes are not what the seller signed for. Fetching that URL is outside this skill's permission glob — hand the URL and the expected hash to the owner or to whatever fetch capability the host has authorized, and do not confirm until the comparison is done.
  ```
  New:
  ```
  Then check the artifact itself: the signed delivery command commits to a `deliveryHash` (`sha256:<hex>`), and the evidence record carries the same digest in its `hash` member along with a `url`. **Download the artifact, recompute its sha256, and compare.** A mismatch means the bytes are not what the seller signed for. Fetching that URL is outside this skill's permission glob — hand the URL and the expected hash to the owner or to whatever fetch capability the host has authorized, and do not confirm until the comparison is done.

  **This step is time-bound, not just procedural.** The contract's `deliveryConfirmationWindow` (one of the five windows checked before proposing) auto-releases the escrow to the seller if neither `confirm` nor `reject` runs before it elapses — a `DELIVERED` agreement left unattended does not stay pending indefinitely, it becomes `ACCEPTED` on its own. Verify and decide promptly once delivery lands; do not treat this step as something that can wait.
  ```

- [ ] **Step 2: Correct the dispute-resolution claim in Step 8 (Confirm or Reject)**

  Edit `buyer-purchase/SKILL.md`. Find:

  Old:
  ```
  `--reason-code` is required and is **any non-empty string** — there is no enumerated list, and inventing one would be wrong. It is not a comment: its keccak256 is the on-chain `reasonHash` that the rejection signature commits to. Write something specific and stable ("delivery-hash-mismatch", "scope-not-met"), record exactly what you sent, and expect the arbiter to read it.

  Rejecting opens the dispute branch. The arbiter named in the contract decides — not Passport, and not this agent.
  ```
  New:
  ```
  `--reason-code` is required and is **any non-empty string** — there is no enumerated list, and inventing one would be wrong. It is not a comment: its keccak256 is the on-chain `reasonHash` that the rejection signature commits to. Write something specific and stable ("delivery-hash-mismatch", "scope-not-met"), and record exactly what you sent.

  Rejecting opens the dispute branch, and today it resolves one of two ways — both end in a refund to this agent, neither is "the arbiter decides":

  - **The seller agrees and consents to a refund** (`agreement refund-consent`, on their side) — the escrow returns immediately and the agreement reaches a terminal state.
  - **Neither party acts.** The contract's `appealResponseWindow` elapsing with no seller `refund-consent` also ends in a refund. There is currently no CLI verb on either binary to invoke the named arbiter — `agreement appeal` does not exist. The contract still requires and names an arbiter (Step 1), and knowing who it is still matters for judging the deal before signing, but do not expect this agent to be able to escalate a disputed rejection to arbitration right now.
  ```

- [ ] **Step 3: Verify**

  Run:
  ```bash
  grep -n "deliveryConfirmationWindow\|refund-consent\|appealResponseWindow" buyer-purchase/SKILL.md
  grep -n "The arbiter named in the contract decides" buyer-purchase/SKILL.md
  ```
  Expected: the first returns matches; the second returns **no match** (the corrected, more precise language replaced it). Re-read the edited sections for coherent markdown.

- [ ] **Step 4: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the modified file for the user.

---

### Task 5: `skills.json` — version floor bump (spec finding #9)

**Files:**
- Modify: `skills.json`

**Interfaces:**
- Consumes: confirmed installed CLI versions (`kpass 2.0.0`, `kagent 2.0.0`).
- Produces: n/a.

- [ ] **Step 1: Bump `min_kpass_version` and `min_kagent_version`**

  Edit `skills.json`. Find:

  Old:
  ```json
    "min_kpass_version": "1.15.0",
    "min_kagent_version": "1.15.0",
  ```
  New:
  ```json
    "min_kpass_version": "2.0.0",
    "min_kagent_version": "2.0.0",
  ```

  Do not touch `min_ksearch_version` — not flagged by planning, not in scope. (`version` itself is a separate matter: this plan's own drafting left it untouched, but the final whole-branch review later found that stale and bumped it to `1.10.0` in the same round, matching this repo's precedent of bumping `version` alongside a floor change — see the verify step below.)

- [ ] **Step 2: Verify**

  Run:
  ```bash
  python3 -c "import json; d = json.load(open('skills.json')); print(d['min_kpass_version'], d['min_kagent_version'], d['min_ksearch_version'], d['version'])"
  ```
  Expected output: `2.0.0 2.0.0 1.0.2 1.10.0` — confirms both target fields changed, `version` was bumped alongside them (per the final review's correction), and `min_ksearch_version` moved not at all. Also run `python3 -m json.tool skills.json > /dev/null` to confirm the file is still valid JSON after the edit.

- [ ] **Step 3: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the modified file for the user.

---

### Task 6: Cross-file consistency verification

**Files:**
- Read only: all six files touched by Tasks 1-5 — `buyer-find-seller/SKILL.md`,
  `seller-fulfill/SKILL.md`, `seller-fulfill/references/commands.md`,
  `seller-agent-setup/SKILL.md`, `buyer-purchase/SKILL.md`, `skills.json`.
- No files modified in this task.

**Interfaces:**
- Consumes: the output of Tasks 1-5.
- Produces: a pass/fail verdict on whether the touched skill files' cross-references and shared claims stay mutually consistent.

- [ ] **Step 1: Confirm the seller-fulfill/buyer-purchase dispute-language rewrite says the same thing on both sides**

  Read the rewritten dispute-resolution paragraphs in `seller-fulfill/SKILL.md` (Task 2, Step 4) and `buyer-purchase/SKILL.md` (Task 4, Step 2). Confirm both describe the same two outcomes (seller `refund-consent`, or `appealResponseWindow` timeout) and neither implies arbitration is CLI-invocable. They don't need identical wording — they're read by different audiences (seller vs. buyer) — but the underlying mechanism claim must not contradict.

- [ ] **Step 2: Confirm the two starter-kit pointers (Task 2 Step 6, Task 3 Step 2) name the same path**

  Both `seller-fulfill/SKILL.md` and `seller-agent-setup/SKILL.md` now point at `passport-cli`'s `examples/autonomous/`. Confirm both cite the same relative description (`seller.sh` + `responder.py` + `README.md`) so a reader who reads one skill first isn't confused when the other names it slightly differently.

- [ ] **Step 3: Confirm `buyer-find-seller`'s corrected verification language doesn't contradict `seller-fulfill`'s cross-reference to it**

  `seller-fulfill/SKILL.md`'s Cross-Skill References says *"that skill also covers reference forms and the card-hash verification semantics"* (unchanged by this plan). Confirm this still reads as true after Task 1's rewrite — it does, since Task 1 makes the semantics more precise, not different in kind — and doesn't need its own edit.

- [ ] **Step 4: Run a final full-repo grep for the specific stale claims this plan corrects**

  ```bash
  grep -rn "exactly two flags\|registers.*no flags at all\|The arbiter named in the contract decides" --include="*.md" .
  ```
  Expected: **no matches** anywhere in the repo (both stale claims fully removed, not just in the files this plan targeted — confirms no third file independently repeated either claim).

- [ ] **Step 5: Report results**

  Summarize: the three consistency checks (pass/fail each) and the final grep's result. This task produces a verdict only — no files change here.

---

## Plan Self-Review Notes

- **Spec coverage:** finding #1 is a confirmed false positive (documented in Global Constraints, no task needed). Findings #2 → Task 1; #3 → Task 2 Steps 1-3; #4 → Task 3 Step 1; #5 → Task 2 Steps 4-5; #6 → Task 2 Step 4 (seller side) + Task 4 Step 1 (buyer side); #7 → Task 2 Step 4 (seller side) + Task 4 Step 2 (buyer side); #8 → Task 2 Step 6 + Task 3 Step 2; #9 → Task 5. Task 6 covers the spec's implicit cross-file-consistency expectation (not a numbered finding, but the natural follow-up to two findings each touching two files). Every finding maps to a task.
- **Placeholder scan:** no TBD/TODO; every Old/New block is the literal content to find and insert, not a description of it.
- **Type/name consistency:** command names (`agreement refund-consent`, `card publish --workflow`, `listen --allow-remote-forward`) and field names (`deliveryConfirmationWindow`, `appealResponseWindow`, `source`/`platform_held`/`self_hosted`) are used identically everywhere they appear across tasks, matching the live CLI output and coordination-chart evidence gathered during planning.
