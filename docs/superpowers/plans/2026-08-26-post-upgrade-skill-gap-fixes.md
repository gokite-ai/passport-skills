# Post-upgrade Skill Gap Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring six `passport-skills` skill files back in sync with the last 15 days of upstream changes in `passport-cli`, `passport-web`, and the `passport` backend, so buyer (`kpass`) and seller (`kagent`) flows route to the right skill and describe current CLI/dashboard behavior accurately.

**Architecture:** Every change is a targeted markdown edit to an existing `SKILL.md` and/or its `references/commands.md` / `references/examples.md`, following each skill's established structure (high-level flow + decision guidance in `SKILL.md`, full argument tables and worked examples in `references/`). No new skill directories, no code, no schema changes.

**Tech Stack:** Markdown skill files (YAML frontmatter + prose), verified against live `kpass`/`kagent` CLI output and passport-web/backend source, using the project's existing eval regression harness (`evals/`) for verification.

**Spec:** `docs/superpowers/specs/2026-08-26-post-upgrade-skill-gap-fixes-design.md`

## Global Constraints

- Every command example uses `--output json` (project-wide convention already in every touched skill).
- Never document a command, flag, or field that was not verified against live `--help` output, a commit diff, or backend source in this plan — if a task below cites a value, it was verified during planning; do not extend beyond what's written here without the same verification.
- `min_kpass_version` / `min_kagent_version` in `skills.json` are `1.15.0`; installed CLI is `1.15.1` — no version bump needed.
- Where an edit would push a `SKILL.md` past its current size, prefer moving detail into the skill's existing `references/commands.md` or `references/examples.md` rather than growing `SKILL.md` further (matches the project's established split between the two).
- Per this project's global git policy: **do not run `git add`/`git commit`** for any step below. Each task ends with the files left modified for the user to review and commit manually (with GPG signing). Do not skip this note when executing — replace any "commit" instinct with "stop and hand back for review."

---

### Task 1: `seller-fulfill` — work-plane coverage, accept pre-signing gate, Escalations pointer, routing description

**Files:**
- Modify: `seller-fulfill/SKILL.md`
- Modify: `seller-fulfill/references/commands.md`
- Modify: `seller-fulfill/references/examples.md`

**Interfaces:**
- Consumes: verified live output of `kagent work claim/submit/fail/pending --help`; commit `d0d8865` diff (`agreement_accept.go`, `agreement_price_schedule.go`) in `passport-cli`; passport-web commit `890429c` (Governance page, route `/governance`).
- Produces: n/a (leaf documentation task; Task 6 verifies all tasks together).

- [ ] **Step 1: Extend the "Choosing How to Notice Work" section in `SKILL.md` with the work plane as a third option**

  Edit `seller-fulfill/SKILL.md`. Change the section header and add a new subsection immediately after it (before `## Defaults`):

  Old:
  ```
  ## Choosing How to Notice Work: `listen` vs Polling
  ```
  New:
  ```
  ## Choosing How to Notice Work: `listen` vs Polling vs the Work Plane
  ```

  Then, after the existing paragraph ending `...cursor would advance past events nothing acted on.` (currently followed by `## Defaults`), insert:

  ```markdown

  ### A Third Option: the Work Plane

  `kagent work claim` and `kagent work pending` answer a third question: "what does Passport say I owe right now, across every agreement, regardless of whether I was ever notified?" The coordination engine states an obligation after every committed transition — for this seller, a delivery obligation appears the moment an agreement reaches `FULFILLING`. `work claim` leases a batch of due items and reads back their offered commands, deadline, and verification anchors in one call; `work pending` is the backstop sweep that finds anything a dropped `work.available` notification stranded, without leasing it.

  Use it alongside, not instead of, `listen`/polling: `listen` is the lowest-latency way to learn a proposal exists at all, but the work plane is the reliable way to find a due obligation this agent already knows about (an accepted agreement whose delivery is owed) even when the doorbell that should have said so never arrived. A worker driven by a scheduler rather than a live process should poll `work pending` periodically for exactly this reason.

  Full mechanics — the two clocks, claim-token fencing, and how `work submit` relates to `agreement deliver` — are in `references/commands.md`.
  ```

- [ ] **Step 2: Document the new pre-signing registration/price-schedule gate on `agreement accept`**

  Edit `seller-fulfill/SKILL.md`, Step 2 ("Review the Terms, Then Accept"). Replace the paragraph starting `` `--agreement-id` is the only flag. Before signing anything... `` with:

  ```markdown
  `--agreement-id` is the only flag. Before signing anything, the command verifies locally, in order: that the contract names this agent as seller; that the terms hash re-derives from the stored proposal bytes; that the buyer's terms signature recovers to a key the buyer has actually published; that the relayed EIP-712 Agreement co-signature recovers to that same buyer key and was built for this agent's key; and that the contract's `registrationBasis` and `priceSchedule` match this seller's own active registration, read fresh from Passport. Any failure is a local refusal (exit 8, or 6 when the contract names a different seller) — nothing was sent, and re-running the same bytes will fail the same way.

  That last check used to happen only after this agent had already signed: Passport re-derived the same mismatch and refused the acceptance, but by then the seller's key had already signed a contract certain to be rejected. It is now caught here, before either signature is produced — the same way `propose` already gates the buyer's price schedule before the buyer signs.
  ```

- [ ] **Step 3: Add an Escalations dashboard pointer near the escalation flow**

  Edit `seller-fulfill/SKILL.md`, Step 3 ("When the Acceptance Policy Refuses"). After the paragraph ending `...this agent should not open a second escalation for the same deal without being told to.`, insert:

  ```markdown

  The owner can also see every open escalation for this agent in one place — **Passport web app → Governance → this agent → Escalations**, at the top of that page — rather than only from the `approval_url` this agent surfaces per deal.
  ```

- [ ] **Step 4: Update the routing description in frontmatter**

  Edit `seller-fulfill/SKILL.md` frontmatter `description`. Replace:
  ```
  description: >-
    Serve incoming agreements as an autonomous seller: notice a proposal (by
    streaming notifications with `kagent listen --forward` or by polling
    `kagent agreement list`), verify the buyer's formation signatures and accept,
    escalate to the owner when the acceptance policy refuses a deal, sign the
    Activation, deliver the artifact once the escrow is funded, register evidence,
    and answer buyer questions. Invoke whenever a buyer has proposed to this agent,
    whenever an accepted agreement needs advancing, and whenever an acceptance or
    delivery is refused (acceptance_policy_violation, revision_conflict, an unfunded
    escrow). Requires an active binding and a pinned card -- see seller-agent-setup.
  ```
  With:
  ```
  description: >-
    Serve incoming agreements as an autonomous seller: notice a proposal (by
    streaming notifications with `kagent listen --forward`, polling `kagent
    agreement list`, or draining the work plane with `kagent work claim` /
    `work pending`), verify the buyer's formation signatures and accept,
    escalate to the owner when the acceptance policy refuses a deal, sign the
    Activation, deliver the artifact once the escrow is funded, register evidence,
    and answer buyer questions. Invoke whenever a buyer has proposed to this agent,
    whenever an accepted agreement needs advancing, whenever this agent holds a
    leased work item to submit or fail, and whenever an acceptance or delivery is
    refused (acceptance_policy_violation, revision_conflict, an unfunded escrow).
    Requires an active binding and a pinned card -- see seller-agent-setup.
  ```

- [ ] **Step 5: Add the registration/price-schedule check to the local-verification table in `references/commands.md`**

  Edit `seller-fulfill/references/commands.md`. In the `### Local verification, in order` table under `## kagent agreement accept`, after row 9 (`| 9 | The co-signature recovers to the buyer's address under the escrow domain | Exit **8** |`), add:

  ```
  | 10 | The contract's `registrationBasis` and `priceSchedule` match this seller's own active registration (read fresh via `GET /v1/agents/<seller>/registration`) | Exit **8** |
  ```

  And after the paragraph `Every one of these is a local refusal: ... their identical resend is a no-op).`, insert:

  ```markdown

  Check 10 is new: it used to be enforced only server-side, after this agent had already signed. It reuses the same validation `propose` runs on the buyer's side, so a schedule one lane would refuse can no longer be signed by the other.
  ```

- [ ] **Step 6: Add the `kagent work` command reference section**

  Edit `seller-fulfill/references/commands.md`. Insert a new section between the end of `## kagent listen` (the line `---` immediately before `## Error Envelope`) and `## Error Envelope`:

  ````markdown
  ## `kagent work claim` / `work submit` / `work fail` / `work pending`

  The work plane's queue, this agent's side: after every committed transition the coordination engine states an obligation, Passport materializes it as a work item, and these four verbs are how the obligated party drains it. It exists alongside `listen`/polling as a third, backstop-reliable way to find due work — see "A Third Option: the Work Plane" in `SKILL.md` for when to prefer it.

  An item carries two clocks that never merge: `deadline` is the agreement's (past it the vault settles without anyone's signature), `lease_expires_at` is the queue's (past it another attempt starts). Pace the work by the deadline, retries by the lease.

  | Verb | Flags | Notes |
  |---|---|---|
  | `work claim` | `--command <name>` (repeatable, narrows to items offering that act), `--max <n>` (default 25, cap 100), `--lease-seconds <n>` (30–3600, default 300), `--key-file`, `--config-dir` | Leases up to `--max` due items exclusively for `--lease-seconds`, and reads back what the `work.available` doorbell doesn't carry: the offered commands, the agreement deadline, and the verification anchors (`terms_digest`, `chart_hash`, `latest_proof_hash`). An EMPTY batch is success, not refusal — nothing is due right now, which is what makes polling this cheap. The claim token fences the whole batch; quote it back on `submit`/`fail`. |
  | `work submit` | `--item <wrk_id>`, `--claim-token <token>`, `--agreement-id` (with `--file`; read from the queue when absent), `--file` (uploads and registers the artifact — its sha256 becomes the `deliveryHash`) or `--evidence-id` + `--content-hash` (cite a record already registered), `--evidence-type` (default `delivery`), `--content-type`, `--units`, `--key-file` | Records that the deliverable's bytes exist — deliberately nothing more. SUBMITTED never moves the agreement; the receipt's `next_action` names the signed command only this party can send (for a delivery obligation, that's `agreement deliver`). A submission under a superseded token is a conflict the worker must NOT retry — the lease lapsed, a successor claimed the item, and the successor's submission is the one that counts. An identical retry under the live token is a no-op success. |
  | `work fail` | `--item`, `--claim-token`, `--reason` (closed enum: `upstream_unavailable`, `request_unpriced`, `capacity_exceeded`, `permanent_error`), `--retriable`, `--detail` (free text, never parsed), `--key-file` | An explicit, reasoned hand-back — without it a worker that cannot do the work either sits on the lease until it lapses, or submits nothing and lies. `--retriable` is this worker's own claim that another attempt could help; it requeues the item with a backoff and never touches the money plane — exhausting attempts is terminal for the ITEM only, and the agreement's deadline decides where the money goes. |
  | `work pending` | `--limit <n>` (cap 200), `--since <RFC3339>`, `--key-file`, `--config-dir` | Lists this agent's outstanding items regardless of what was notified or leased — the backstop half of "the doorbell is allowed to get lost". `lease_expires_at` present on a row means some worker still holds it, which is how a supervisor tells "not started" from "in flight, maybe crashed". |

  `work submit --file` alone does not complete a delivery obligation: the agreement moves only once this party's signed command (`agreement deliver`, for a delivery obligation) reaches the coordination engine. Treat `work claim`'s offered commands as the authority on which signed verb to run next.

  ```bash
  kagent work claim --command deliver --max 5 --output json
  kagent work submit --item wrk_9a2 --claim-token clm_7f... --file ./report.pdf --output json
  kagent agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
  ```
  ````

- [ ] **Step 7: Add a worked work-plane example**

  Edit `seller-fulfill/references/examples.md`. Append a new section at the end of the file, after the last line (`...that is a conversation with the buyer (\`message send\`) and, if they reject, a matter for the contract's arbiter.`):

  ````markdown

  ## Example 3: Draining the Work Plane as a Backstop

  A scheduled worker that runs every few minutes, rather than a long-lived `listen` process, checks for anything due:

  ```bash
  kagent work pending --output json
  ```

  ```json
  {
    "status": "success",
    "items": [
      { "item": "wrk_9a2", "agreement_id": "agr_7f2a", "commands": ["deliver"], "deadline": "2026-08-28T12:00:00Z" }
    ],
    "has_more": false
  }
  ```

  One item is due. Claim it, fencing the batch with a claim token:

  ```bash
  kagent work claim --command deliver --max 5 --lease-seconds 600 --output json
  ```

  ```json
  {
    "status": "success",
    "claim_token": "clm_7f2a91",
    "items": [
      { "item": "wrk_9a2", "agreement_id": "agr_7f2a", "commands": ["deliver"], "deadline": "2026-08-28T12:00:00Z", "terms_digest": "sha256:...", "chart_hash": "sha256:...", "latest_proof_hash": "sha256:..." }
    ]
  }
  ```

  Submit records the bytes exist, fenced by the live claim token:

  ```bash
  kagent work submit --item wrk_9a2 --claim-token clm_7f2a91 --file ./report.pdf --output json
  ```

  SUBMITTED is not progress — the agreement still needs the signed command:

  ```bash
  kagent agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
  ```

  If the worker instead cannot do this item right now (say, an upstream dependency is down), it hands the lease back explicitly rather than letting it lapse silently:

  ```bash
  kagent work fail --item wrk_9a2 --claim-token clm_7f2a91 --reason upstream_unavailable --retriable --output json
  ```
  ````

- [ ] **Step 8: Verify**

  Run:
  ```bash
  grep -n "work claim\|work pending\|work submit\|work fail" seller-fulfill/SKILL.md seller-fulfill/references/commands.md seller-fulfill/references/examples.md
  grep -n "registrationBasis.*priceSchedule.*active registration\|check 10\|Check 10" seller-fulfill/references/commands.md
  grep -n "Governance.*Escalations\|Escalations" seller-fulfill/SKILL.md
  ```
  Expected: non-empty matches for each — the work-plane content, the new accept-gate check, and the Escalations pointer are all present. Then re-read the edited `SKILL.md` sections to confirm markdown renders cleanly (no broken headers, no unclosed code fences).

- [ ] **Step 9: Stop for manual review and commit**

  Per this project's git policy, do not run `git add`/`git commit`. Leave the three modified files for the user to review and commit (with GPG signing).

---

### Task 2: `buyer-purchase` — work-plane coverage (buyer side), routing description

**Files:**
- Modify: `buyer-purchase/SKILL.md`
- Modify: `buyer-purchase/references/commands.md`
- Modify: `buyer-purchase/references/examples.md`

**Interfaces:**
- Consumes: verified live output of `kpass agent work claim/submit/fail/pending --help` (confirmed identical semantics to `kagent`'s, except the buyer surface's `work claim`/`work pending` register no `--config-dir` flag — buyer state is anchored to `.kite-passport/`, matching the existing convention documented in `buyer-agent-setup/SKILL.md`).
- Produces: n/a.

- [ ] **Step 1: Add a work-plane note after Step 5 ("Sign the Activation") in `SKILL.md`**

  Edit `buyer-purchase/SKILL.md`. After the paragraph ending `...\`have_seller_activation_sig\` in \`funding get\` tell you what is still outstanding; the seller's half is the seller's job.` (end of Step 5, immediately before `### Step 6: Wait for Delivery`), insert:

  ```markdown

  **A note on noticing this obligation.** The Activation signature this step produces is itself an obligation the coordination engine states once the agreement reaches `COMMITTED`. A buyer managing many agreements at once can find every such due obligation in one call via `kpass agent work claim` / `work pending` — the work plane's backstop sweep — instead of watching `agreement status` per agreement id. Full mechanics: `references/commands.md`.
  ```

- [ ] **Step 2: Update the routing description in frontmatter**

  Edit `buyer-purchase/SKILL.md` frontmatter `description`. Replace:
  ```
  description: >-
    Buy from another agent under a signed, escrowed agreement: propose terms to a
    seller, get the owner's passkey approval for a spending session scoped to that
    agreement, fund the escrow, wait for delivery, verify the artifact against the
    signed delivery hash, then confirm or reject and leave a review. Invoke whenever
    this agent needs to pay another agent for a deliverable rather than call a paid
    HTTP endpoint, and whenever an existing agreement needs to be advanced,
    inspected, or recovered after a refusal (session_scope_forbidden,
    funding_submission_incomplete, revision_conflict). Requires an active runtime
    binding and a pinned persona card -- see buyer-agent-setup and buyer-find-seller.
  ```
  With:
  ```
  description: >-
    Buy from another agent under a signed, escrowed agreement: propose terms to a
    seller, get the owner's passkey approval for a spending session scoped to that
    agreement, fund the escrow, wait for delivery, verify the artifact against the
    signed delivery hash, then confirm or reject and leave a review. Invoke whenever
    this agent needs to pay another agent for a deliverable rather than call a paid
    HTTP endpoint, whenever this agent holds a due obligation on the work plane
    (`kpass agent work claim` / `work pending`), and whenever an existing agreement
    needs to be advanced, inspected, or recovered after a refusal
    (session_scope_forbidden, funding_submission_incomplete, revision_conflict).
    Requires an active runtime binding and a pinned persona card -- see
    buyer-agent-setup and buyer-find-seller.
  ```

- [ ] **Step 3: Add the `kpass agent work` command reference section**

  Edit `buyer-purchase/references/commands.md`. Insert a new section between the end of `## kpass agent escalate` / `kpass agent escalation status` (the line `---` immediately before `## Error Envelope`) and `## Error Envelope`:

  ````markdown
  ## `kpass agent work claim` / `work submit` / `work fail` / `work pending`

  The work plane's queue, this agent's side: after every committed transition the coordination engine states an obligation, Passport materializes it as a work item, and these four verbs are how the obligated party drains it. On the buyer surface the obligation that most commonly shows up here is the Activation signature due once an agreement reaches `COMMITTED` (Step 5). Unlike the seller surface (`kagent`), `work claim` and `work pending` register no `--config-dir` flag here — buyer state is anchored to `.kite-passport/`, the same as everywhere else in this lane.

  An item carries two clocks that never merge: `deadline` is the agreement's (past it the vault settles without anyone's signature), `lease_expires_at` is the queue's (past it another attempt starts). Pace the work by the deadline, retries by the lease.

  | Verb | Flags | Notes |
  |---|---|---|
  | `work claim` | `--command <name>` (repeatable, narrows to items offering that act), `--max <n>` (default 25, cap 100), `--lease-seconds <n>` (30–3600, default 300), `--key-file` | Leases up to `--max` due items exclusively for `--lease-seconds`, and reads back the offered commands, the agreement deadline, and the verification anchors in one call. An EMPTY batch is success, not refusal. The claim token fences the whole batch; quote it back on `submit`/`fail`. |
  | `work submit` | `--item <wrk_id>`, `--claim-token <token>`, `--agreement-id` (with `--file`; read from the queue when absent), `--file`, `--evidence-id` + `--content-hash`, `--evidence-type`, `--content-type`, `--units`, `--key-file` | Records that bytes exist for an artifact-bearing obligation — deliberately nothing more. The agreement moves only once this party's own signed command reaches the coordination engine. On this lane, a non-artifact obligation (the Activation signature) is completed by running the offered signing verb directly (`agreement funding sign`), not by `work submit`. |
  | `work fail` | `--item`, `--claim-token`, `--reason` (closed enum: `upstream_unavailable`, `request_unpriced`, `capacity_exceeded`, `permanent_error`), `--retriable`, `--detail`, `--key-file` | An explicit, reasoned hand-back. `--retriable` requeues the item with a backoff and never touches the money plane. |
  | `work pending` | `--limit <n>` (cap 200), `--since <RFC3339>`, `--key-file` | Lists this agent's outstanding items regardless of what was notified or leased — the backstop half of "the doorbell is allowed to get lost". |

  Treat `work claim`'s offered commands as the authority on which verb to run next for a given item, rather than assuming `work submit` always applies.

  ```bash
  kpass agent work claim --command fundingSign --max 5 --output json
  kpass agent agreement funding sign --agreement-id agr_7f2a --output json
  ```
  ````

- [ ] **Step 4: Add a worked work-plane example**

  Edit `buyer-purchase/references/examples.md`. Append a new section at the end of the file, after the last line (`...which is the correct answer rather than a bug to work around.`):

  ````markdown

  ## Example 3: Draining the Work Plane for a Due Activation Signature

  A buyer running many agreements checks what it owes right now, rather than watching one agreement at a time:

  ```bash
  kpass agent work pending --output json
  ```

  ```json
  {
    "status": "success",
    "items": [
      { "item": "wrk_4b1", "agreement_id": "agr_7f2a", "commands": ["fundingSign"], "deadline": "2026-08-28T12:00:00Z" }
    ],
    "has_more": false
  }
  ```

  One Activation signature is due. Claim it to fence the batch, then run the offered command directly — there is no artifact to submit for a signature:

  ```bash
  kpass agent work claim --command fundingSign --max 5 --output json
  kpass agent agreement funding sign --agreement-id agr_7f2a --output json
  ```
  ````

- [ ] **Step 5: Verify**

  Run:
  ```bash
  grep -n "work claim\|work pending\|work submit\|work fail\|fundingSign" buyer-purchase/SKILL.md buyer-purchase/references/commands.md buyer-purchase/references/examples.md
  ```
  Expected: non-empty matches in all three files. Re-read the edited sections to confirm no broken markdown.

- [ ] **Step 6: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the three modified files for the user.

---

### Task 3: `seller-agent-setup` — Governance dashboard pointer, Escalations, Pending Runtime Approvals, duplicate-negotiable validation, revocation-warning note, routing description

**Files:**
- Modify: `seller-agent-setup/SKILL.md`
- Modify: `seller-agent-setup/references/commands.md`

**Interfaces:**
- Consumes: passport-web routes `/governance` (nav label "Governance", under Sell) and `/overview` (nav label "Overview", top-level) confirmed from `src/components/layout/dashboard-sidebar.tsx`; passport-cli commit `d0d8865` exact validator message `"itemId %s field %s is already declared negotiable at index %d"` from `registration_validate.go`.
- Produces: n/a.

- [ ] **Step 1: Replace the curl-first Governance instructions in Step 8 with a dashboard-first flow**

  Edit `seller-agent-setup/SKILL.md`, Step 8. After the paragraph:
  ```
  > Your agent will refuse every proposal until you set its acceptance policy.
  > It is an owner action — your JWT is the whole authorization, and there is no
  > passkey ceremony on this route.
  ```
  and before `Read what is there now:`, insert:

  ```markdown

  The fastest way to do this is the dashboard: **Passport web app → Governance → this agent** opens a form for exactly this. It converts USD amounts to minor units, carries the optimistic-concurrency version for the owner automatically, and fails closed with a clear message instead of a silent overwrite. Point the owner there first.

  A scripted or headless alternative exists for automation:
  ```

  Then, after the existing PUT curl block and its field table (ending ``...the engine converts the contract rather than the policy, so a floor of `"1"` means one minor unit and not one dollar.``), before `Deals outside the mandate are not lost:`, insert:

  ```markdown

  The same Governance page also surfaces this agent's open Escalations, at the top, ahead of the acceptance-policy form — the owner can act on an `acceptance-override` request from there instead of only from the URL this agent surfaces in **`seller-fulfill`**'s Step 3.
  ```

- [ ] **Step 2: Add the Pending Runtime Approvals pointer to Step 3**

  Edit `seller-agent-setup/SKILL.md`, Step 3 ("Bind, and Surface the Approval"). After the paragraph:
  ```
      All four values are in the bind envelope. Name the thumbprint every time: duplicate pending rows for one key are possible — a redeploy that re-files a request produces one per boot — and the owner has no other way to tell which row is the one you filed.
  ```
  and before ``Re-surface the same message rather than re-running `bind`:``, insert:

  ```markdown

    When the owner has several agents, or several pending runtimes to sort through, **Passport web app → Overview → Pending Runtime Approvals** lists every pending runtime across every agent in one place — thumbprint, bind method, and key-verified state, with Approve/Reject inline — which is faster than opening this agent's own Runtimes tab.
  ```

- [ ] **Step 3: Note the dashboard's revocation impact warning**

  Edit `seller-agent-setup/SKILL.md`, Step 9 ("Confirm, Then Tell the Owner to List"), in the status table row ``| `binding.status: "revoked"` | `pending` | The owner revoked this runtime. Ask before `init --force`. |``. After the table (before `Then say this to the owner...`), insert:

  ```markdown

  Before an owner revokes a runtime with active or pending obligations, the dashboard now shows an impact warning at the point of the click — this agent has no visibility into that ceremony and should not try to talk the owner through it.
  ```

- [ ] **Step 4: Add the duplicate-negotiable-field validation error to the local pre-flight description**

  Edit `seller-agent-setup/references/commands.md`, under `## kagent registration validate`. In the paragraph describing what local pre-flight checks (the one ending `...Workflow ids are resolved against the public \`GET /v1/workflows\` list unless \`--offline\`.`), insert before that final sentence:

  Old:
  ```
  ...negotiable entries (each present bound held to the money grammar on its own, the `field` matched to the line's actual price field, min ≤ max), the money grammar (integer strings in minor units, at most 30 digits), and the **worked-example identity** — funding recomputed line by line must equal the example exactly, the same proof the platform enforces. A storefront still carrying `price`/`settlement` is told those members moved to the rate card. Workflow ids are resolved against the public `GET /v1/workflows` list unless `--offline`.
  ```
  New:
  ```
  ...negotiable entries (each present bound held to the money grammar on its own, the `field` matched to the line's actual price field, min ≤ max, and **no `(itemId, field)` pair repeated** — a repeat is refused naming the earlier index: `itemId <id> field <field> is already declared negotiable at index <n>`, because the formation reader keys these into a map and a repeat would leave the enforced bound decided by array order rather than by the published document), the money grammar (integer strings in minor units, at most 30 digits), and the **worked-example identity** — funding recomputed line by line must equal the example exactly, the same proof the platform enforces. A storefront still carrying `price`/`settlement` is told those members moved to the rate card. Workflow ids are resolved against the public `GET /v1/workflows` list unless `--offline`.
  ```

- [ ] **Step 5: Update the routing description in frontmatter**

  Edit `seller-agent-setup/SKILL.md` frontmatter `description`. Replace:
  ```
  description: >-
    Stand up an autonomous seller on Kite Passport: generate the `kagent` runtime
    key, bind it to the agent record with the owner's passkey approval, pin the
    coordination persona card, publish the agent card, and publish the commerce
    registration (storefront, rate card, workflow/terms) buyers read before
    proposing. Invoke before any other
    `kagent` command, whenever `kagent status` reports anything other than an
    active binding, and whenever the card or a published document needs updating.
    This is the gateway skill for the seller-agent group -- serving agreements
    (seller-fulfill) requires an active binding and a pinned card first.
  ```
  With:
  ```
  description: >-
    Stand up an autonomous seller on Kite Passport: generate the `kagent` runtime
    key, bind it to the agent record with the owner's passkey approval, pin the
    coordination persona card, publish the agent card, and publish the commerce
    registration (storefront, rate card, workflow/terms) buyers read before
    proposing. Also covers pointing the owner at the Passport web dashboard for
    governance (acceptance policy, escalations) and pending runtime approvals.
    Invoke before any other `kagent` command, whenever `kagent status` reports
    anything other than an active binding, and whenever the card or a published
    document needs updating. This is the gateway skill for the seller-agent group
    -- serving agreements (seller-fulfill) requires an active binding and a pinned
    card first.
  ```

- [ ] **Step 6: Verify**

  Run:
  ```bash
  grep -n "Governance\|Escalations\|Pending Runtime Approvals\|already declared negotiable\|impact warning" seller-agent-setup/SKILL.md seller-agent-setup/references/commands.md
  ```
  Expected: matches for each phrase. Re-read the edited sections to confirm the curl blocks are now framed as the scripted alternative, not the primary instruction, and that no existing content was accidentally duplicated or removed.

- [ ] **Step 7: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the two modified files for the user.

---

### Task 4: `buyer-agent-setup` — Pending Runtime Approvals pointer, revocation-warning note

**Files:**
- Modify: `buyer-agent-setup/SKILL.md`

**Interfaces:**
- Consumes: same passport-web route/nav facts as Task 3, Step 2.
- Produces: n/a.

- [ ] **Step 1: Add the Pending Runtime Approvals pointer to Step 3**

  Edit `buyer-agent-setup/SKILL.md`, Step 3 ("Bind the Key, and Surface the Approval"). After the paragraph:
  ```
      All four values are in the bind envelope. Name the thumbprint every time: duplicate pending rows for one key are possible — a redeploy that re-files a request produces one per boot — and the owner has no other way to tell which row is the one you filed.
  ```
  and before ``Re-surface the same message rather than re-running `bind`:``, insert:

  ```markdown

    When the owner has several agents, or several pending runtimes to sort through, **Passport web app → Overview → Pending Runtime Approvals** lists every pending runtime across every agent in one place — thumbprint, bind method, and key-verified state, with Approve/Reject inline — which is faster than opening this agent's own Runtimes tab.
  ```

- [ ] **Step 2: Note the dashboard's revocation impact warning**

  Edit `buyer-agent-setup/SKILL.md`, "Specific Scenarios" section. Replace:
  ```
  **`runtime_revoked` (exit 3):** The owner revoked this runtime in Passport, deliberately. The key is dead for signing. Ask before running `init --force`: a new key orphans agreements pinned to the old one.
  ```
  With:
  ```
  **`runtime_revoked` (exit 3):** The owner revoked this runtime in Passport, deliberately. The key is dead for signing. Ask before running `init --force`: a new key orphans agreements pinned to the old one. (The dashboard now shows an impact warning at the point of the revoke click when the runtime has active or pending obligations — this agent has no visibility into that ceremony.)
  ```

- [ ] **Step 3: Verify**

  Run:
  ```bash
  grep -n "Pending Runtime Approvals\|impact warning" buyer-agent-setup/SKILL.md
  ```
  Expected: two matches.

- [ ] **Step 4: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the modified file for the user.

---

### Task 5: `buyer-find-seller` — reviews in the vetting checklist

**Files:**
- Modify: `buyer-find-seller/SKILL.md`

**Interfaces:**
- Consumes: backend route `GET /v1/agents/:agent/reviews` (public, no auth), confirmed in `pkg/identity/handler/routes.go` and `pkg/identity/handler/public.go` in the `passport` `main` clone; response shape `IdentityAgentReviewsPage{reviews: []IdentityReviewView{reviewer_did, score, comment, contract_id, deal_outcome, recorded_at, envelope}, has_more}` from `pkg/identity/model/model.go`. No `kpass` CLI verb wraps this endpoint yet — do not invent one.
- Produces: n/a.

- [ ] **Step 1: Add a review-history check after Step 2 ("Read the Candidate")**

  Edit `buyer-find-seller/SKILL.md`. After the paragraph ending `...\`directory offering <ref> <offeringId>\` returns one offering's derived row... Registration data is discovery material: only the bilateral agreement is binding.` and before `### Step 3: Read the Terms and the Rate Card`, insert:

  ````markdown

  **Optional: check review history.** `directory search`'s optional `stats` field already carries this seller's rating/review-count aggregate. For the detail behind that aggregate — read it when the aggregate alone isn't enough to decide — Passport also serves a public, unauthenticated review list at `GET /v1/agents/<ref>/reviews`. There is no `kpass` verb for it yet, and the same permission caveat as the document URLs below applies: fetching that URL is outside this skill's permission glob. Surface it to the owner (or to whatever fetch capability the host has already authorized) rather than reaching for it here.

  Each row carries `reviewer_did`, `score` (1–10), `comment`, `contract_id`, `deal_outcome`, `recorded_at`, and a verifiable signature `envelope` (`key_id`, `sig`, `canonical`, `hash`) — so the row can be checked without trusting the API. Same-controller reviews (the seller reviewing its own other agents) are excluded; this list is independent-counterparty reputation only.
  ````

  (Note, recorded during a later documentation-accuracy pass: this step's original text instructed the agent to call the reviews endpoint directly with `curl` — a violation of this skill's `Bash(kpass agent *)`-only permission glob, mirroring the fallback-fetch pattern already documented one section later, in "Read the Terms and the Rate Card." The text above reflects the corrected instruction that actually shipped; see `buyer-find-seller/SKILL.md`'s review-history paragraph for the live version.)

- [ ] **Step 2: Verify**

  Run:
  ```bash
  grep -n "reviews?limit\|reviewer_did\|review history" buyer-find-seller/SKILL.md
  ```
  Expected: matches. Confirm the insertion sits between Step 2 and Step 3 without disturbing either heading.

- [ ] **Step 3: Stop for manual review and commit**

  Do not run `git add`/`git commit` — leave the modified file for the user.

---

### Task 6: Eval regression verification across all touched skills

**Files:**
- Read only: `evals/evals.json`, `evals/README.md`, `evals/functional-workspace/iteration-3/RUNBOOK.md`, `evals/functional-workspace/iteration-3/grade_all.py`, `evals/functional-workspace/iteration-3/build_benchmark.py`
- No files modified in this task.

**Interfaces:**
- Consumes: the six modified skill files from Tasks 1–5.
- Produces: a pass/fail regression verdict vs. the existing baseline (main avg 0.971).

- [ ] **Step 1: Read the runbook**

  Read `evals/functional-workspace/iteration-3/RUNBOOK.md` in full before proceeding — it defines the exact subagent-dispatch procedure this task must follow (per `evals/README.md`, no automated runner script exists; transcripts are produced by dispatching subagents against each eval scenario).

- [ ] **Step 2: Identify the relevant eval scenarios**

  Filter `evals/evals.json` (55 scenarios) to the ones whose `prompt`/`expected_output` exercise any of the six touched skills (`seller-fulfill`, `buyer-purchase`, `seller-agent-setup`, `buyer-agent-setup`, `buyer-find-seller`) — grep for skill-relevant keywords (`kagent`, `kpass agent`, `seller`, `buyer`, `agreement`, `registration`, `runtime`) to build the candidate list, then read each candidate's full entry to confirm relevance.

- [ ] **Step 3: Dispatch subagents per the runbook and save transcripts**

  For each relevant scenario, dispatch a subagent against the current (post-edit) skill set exactly as the runbook describes, saving each transcript to the runbook's expected `iteration-3/eval-*/<version>/outputs/response.md` path structure. This mirrors how prior comparisons (`main` vs `spring-test`) were captured — the goal here is a single new version directory representing this plan's edits (e.g. `post-upgrade-fixes`), not a new baseline.

- [ ] **Step 4: Grade and compare against baseline**

  Run:
  ```bash
  python3 evals/functional-workspace/iteration-3/grade_all.py
  python3 evals/functional-workspace/iteration-3/build_benchmark.py
  ```
  Read `grading_summary.json`. Expected: the new version's average is at or above the `main` baseline (0.971), and `losses[]` for the new version is empty. Any loss found is a regression this plan introduced — fix the specific skill content before proceeding, and re-run this step.

- [ ] **Step 5: Manually cross-check the routing/description changes**

  The harness cannot verify routing/triggering itself (`evals/routing-experiments/FINDINGS.md` — the trigger-detection path is structurally broken). Manually re-read the five frontmatter `description` changes from Tasks 1–4 against the gap list in the spec (`docs/superpowers/specs/2026-08-26-post-upgrade-skill-gap-fixes-design.md`) and confirm each new phrase (work plane, governance, price-schedule gate) is present and accurate — not by running the harness, by reading the files.

- [ ] **Step 6: Report results to the user**

  Summarize: which scenarios were run, the grading comparison, and the manual routing cross-check outcome. Do not commit anything — this task produces a verdict, not file changes.

---

## Plan Self-Review Notes

- **Spec coverage:** every numbered gap in the design doc (§1–§9) maps to a task above: work plane → Tasks 1 & 2; accept pre-signing gate → Task 1; Governance pointer → Task 3; Escalations → Tasks 1 & 3; Pending Runtime Approvals → Tasks 3 & 4; duplicate-negotiable validation → Task 3; risky-runtime-action warning → Tasks 3 & 4 (relocated from the spec's tentative "manage-agents" placement to seller-agent-setup/buyer-agent-setup's existing revocation-scenario text, since manage-agents is explicitly read-only and has no revocation content to attach this to — `manage-agents` is intentionally untouched by this plan); reviews vetting → Task 5; routing description pass → Tasks 1–3; eval verification → Task 6.
- **Placeholder scan:** no TBD/TODO; every code/markdown block above is the literal content to insert, not a description of it.
- **Type/name consistency:** command names (`work claim`/`work submit`/`work fail`/`work pending`, `agreement accept`, `agreement deliver`, `agreement funding sign`) and field names (`registrationBasis`, `priceSchedule`, `reviewer_did`, `deal_outcome`) are used identically across every task that references them, matching the verified CLI/backend ground truth gathered during brainstorming.
