# Post-upgrade skill gap fixes — design

**Date:** 2026-08-26
**Status:** Draft, pending review

## Context

`passport-cli`, `passport-web`, and the `passport` backend (main branch) all
shipped substantial changes in the last 15 days. `passport-skills` was
reported to have UX issues when routed through by `kpass` (buyer) and
`kagent` (seller) — including cases where a relevant skill isn't invoked at
all. This spec enumerates the confirmed gaps between current skill content
and current upstream behavior, and the fix for each.

## Research method

Three parallel research passes (one per sibling repo, git log + diff over the
last 15 days, cross-referenced against this repo's SKILL.md/references
files):

- `passport-cli`: verified live `kpass --help` / `kagent --help` output
  against skill command references. Confirmed the seller CLI binary is
  `kagent` (not "kseller" — no such binary/command exists; the buyer-agent
  install log confirms `kpass`, `kagent`, and `ksearch` as the three shipped
  binaries).
- `passport-web`: git log over dashboard-facing commits, cross-referenced
  against skill text that tells owners to use the browser/dashboard.
- `passport` backend: cloned fresh from `origin/main` to
  `_study/passport-main` (the local working copy is mid-feature-branch and
  was not used), git log over API/data-model-facing commits.

## Gaps and fixes

### 1. `agent work` plane has zero skill coverage (new coverage)

`kpass agent work` and `kagent work` (identical subcommand surface:
`claim`, `submit`, `fail`, `pending`) is a claim/lease/submit/fail queue
that materializes an obligation after every committed agreement transition
(e.g. a delivery obligation). It is a backstop-reliable alternative to the
`listen`/`agreement list` polling that `seller-fulfill` already documents —
`work pending` explicitly exists to catch work a dropped `work.available`
notification stranded. No skill mentions it.

**Fix:**
- `seller-fulfill/SKILL.md`: extend the existing "Choosing How to Notice
  Work: listen vs polling" section with a third option — the work plane —
  and when to prefer it (reliability backstop, works without a `listen`
  server).
- `seller-fulfill/references/commands.md`: add `work claim` / `work submit`
  / `work fail` / `work pending` command reference, including the two-clock
  model (`deadline` vs `lease_expires_at`), claim-token fencing, and that
  `work submit` alone does not move the agreement — `agreement deliver`
  still does.
- `seller-fulfill/references/examples.md`: one worked claim → submit →
  deliver example.
- `buyer-purchase/SKILL.md` + `references/commands.md` + `references/examples.md`:
  same treatment for the buyer-side obligations that surface as work items
  (to be confirmed exactly which buyer commands land in the work plane
  during implementation — `agent work claim --command` narrows by offered
  command name, so this is discoverable empirically).

### 2. `seller-fulfill`: stale `agreement accept` refusal behavior

Commit `d0d8865` (passport-cli, 2026-08-26) changed `agreement accept` to
locally gate and refuse *before* signing when the contract's
`registrationBasis`/`priceSchedule` doesn't match this seller's own active
registration — previously it signed first and only then got refused by the
platform. `seller-fulfill/SKILL.md` still documents only the old
post-signing/platform-refusal path.

**Fix:** update the accept section with the new local pre-signing refusal,
its exit code, and message.

### 3. `seller-agent-setup`: stale governance instructions

`seller-agent-setup/SKILL.md` Step 8 (~lines 274–327) instructs the owner
to set the acceptance policy via raw `curl -X PUT ... -H "Authorization:
Bearer <owner-jwt>"`. passport-web shipped a dedicated **Governance**
dashboard page for this (commit `890429c`) that handles USD-minor-unit
conversion and optimistic-concurrency versioning for the owner. Asking a
non-developer owner to hand-craft a bearer-JWT curl request when a form
exists is a real UX regression.

**Fix:** make the dashboard Governance page the primary instruction; keep
curl only as a documented fallback for scripted/headless use.

### 4. `seller-agent-setup` / `seller-fulfill`: missing Escalations pointer

The same Governance page surfaces pending Escalations at the top of its
index. Neither skill points the owner there when an escalation is raised.

**Fix:** add a one-line pointer to the Governance page's Escalations panel
in both skills, near where each currently says "surface the approval/
escalation URL verbatim."

### 5. `buyer-agent-setup` / `seller-agent-setup`: missing Pending Runtime Approvals panel

passport-web added a cross-agent **Pending Runtime Approvals** panel on the
dashboard Overview page (commit `1074d64`), listing every pending runtime
binding across all of the owner's agents with thumbprint/bind-method/
key-verified state and direct Approve/Reject. Both skills currently only
point to the per-agent Runtimes tab, which is slower when disambiguating
multiple pending runtimes — the exact problem the panel solves.

**Fix:** mention the Overview panel as the faster path in both skills;
keep the per-agent tab as a fallback.

### 6. `seller-agent-setup`: missing validation error

Commit `d0d8865` also made `registration validate`/`publish` refuse a rate
card whose `negotiation.negotiable` array has a duplicate `(itemId,
field)` entry (previously the later entry silently won).

**Fix:** add this error to the local validation error catalog in
`seller-agent-setup/references/commands.md` (~line 426).

### 7. `seller-agent-setup` / `buyer-agent-setup`: missing risky-action warning mention

passport-web added impact warnings on the agent detail page for risky
runtime actions (e.g. revoking a runtime that's actively in use) — commits
`eaf03b2`, `f57cb4f`, `0015157`.

**Fix:** one line each in `seller-agent-setup/SKILL.md` and
`buyer-agent-setup/SKILL.md`, attached to each file's existing
runtime-revocation scenario text, noting the dashboard now warns on
revocation impact. **Not `manage-agents`**, despite that being this gap's
original placement below: `manage-agents/SKILL.md` is explicitly read-only
and has no revocation workflow of its own to attach the note to — the
relocation to the setup skills (which do walk an owner through revocation)
was decided during planning and `manage-agents` was correctly left
untouched.

### 8. `buyer-find-seller`: missing reviews in vetting checklist

The backend added a public read surface for agent reviews
(`aedfc2d6`, `63133159`, `6f733a77`), and passport-web added a per-agent
Reviews section (commit `370a4de`). `buyer-find-seller` currently vets a
candidate seller via card/terms/rate-card/keys only, not review history.

**Fix:** add a review-history check to the vetting steps. During
implementation, confirm whether rating data rides along on `kpass agent
directory get`'s public profile response or needs a separate verb, and
document whichever is actually true — do not guess a flag that doesn't
exist.

### 9. Routing: description frontmatter pass

Update the `description` field in `seller-fulfill/SKILL.md`,
`seller-agent-setup/SKILL.md`, and `buyer-purchase/SKILL.md` frontmatter so
new terminology introduced by the above fixes (work plane, governance
documents, price-schedule pre-signing refusal) is present for skill
routing/triggering.

## Explicitly out of scope

- **MCP-based agent discovery tools** (`agents:search`, `agents:lookup` via
  the `passport-mcp` binary): unclear whether this is meant to be a
  skill-facing surface at all, or an internal/alternate integration path.
  Flagged for a future decision, not fixed here.
- **Review-interaction depth beyond gap #8**: `buyer-purchase`'s existing
  `agreement review` (leave-a-review) coverage was verified accurate and
  complete; only the *reading* side (vetting a seller's history) had a gap.
- **Broader restructuring** of `seller-agent-setup` (449 lines) or
  `buyer-purchase` (383 lines) beyond what the above edits require. If an
  edit itself pushes a `SKILL.md` past the project's existing ~350-line
  convention, move that specific new content into `references/`
  (consistent with how every touched skill already organizes detail today)
  rather than proactively re-splitting unrelated existing content.

## Verification

After edits, run the existing eval regression workflow described in
`evals/README.md` (`functional-workspace/iteration-3/RUNBOOK.md`) against
the touched skills, to confirm no regression vs. the `main` baseline
(currently avg 0.971). The automated harness cannot verify routing/
triggering itself (see `evals/routing-experiments/FINDINGS.md` — the
harness's trigger-detection path is structurally broken), so the
description-frontmatter pass (#9) is verified by manual review against the
gap list above, not by the harness.

## Files touched

- `seller-fulfill/SKILL.md`, `seller-fulfill/references/commands.md`,
  `seller-fulfill/references/examples.md`
- `buyer-purchase/SKILL.md`, `buyer-purchase/references/commands.md`,
  `buyer-purchase/references/examples.md`
- `seller-agent-setup/SKILL.md`, `seller-agent-setup/references/commands.md`
- `buyer-agent-setup/SKILL.md`
- `buyer-find-seller/SKILL.md`

`manage-agents/SKILL.md` is deliberately **not** in this list — see gap #7
above for why.
