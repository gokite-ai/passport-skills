# Buyer Agent Skills

## Purpose

This group holds skills for an autonomous agent acting as a **buyer** — an
agent that decides what to purchase and executes the purchase itself, as
opposed to a human operator driving `kpass` through a chat interface. It is
the agent-facing counterpart to the `user` group: same underlying Passport
capabilities (sessions, payments, wallet), driven by a CLI surface built for
unattended agent-to-agent use rather than a human in the loop.

## CLI surface

Skills in this group drive:

```bash
kpass agent <command> [subcommand] [flags] --output json
```

`kpass agent ...` is a distinct verb tree under the existing `kpass` binary
(see `authenticate-user/SKILL.md`, `request-session/SKILL.md` for the `user`
group's `kpass <command>` tree). Commands are space-separated
(`kpass agent agreement propose`); the colon spelling used in some `kpass`
help text is not what these skills document.

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

## JSON output / exit-code contract

Every `kpass agent ...` command follows the same conventions documented in
[`docs/reference.md`](../docs/reference.md) for the rest of the `kpass` CLI:

- `--output json` on every invocation — no human-readable fallback.
- The standard envelope: `_version`, `status`, `hint`, `next_command`, plus
  command-specific data fields spread at the top level (not nested under a
  `data` key). Envelope `status` is one of `success`,
  `human_action_required`, `pending`, `expired`, `error`.
- The shared exit-code table, including exit code 3 for auth errors and exit
  code 6 for session policy violations.

The agent lane **extends** that exit-code table with two codes the
human-facing `kpass` surface does not emit:

| Code | Name | Meaning |
|------|------|---------|
| 7 | `CONFLICT` | The agreement plane's "you signed against a state that has moved, or an id that is already taken" family. The fix is mechanical: re-read, rebuild, retry. |
| 8 | `PROTOCOL` | A **local** refusal — canonicalization, signing or verification failed on this machine and the artifact never left it. Nothing was sent; do not retry the same bytes. |

Error envelopes carry `error`, `hint`, `next_command`, plus optional
`error_code`, `details`, and `retriable`. `retriable` is three-state: `true`,
`false`, or **absent** when no server ruled on the request (every local
refusal, every transport failure) — absence is not `false`.

Skills authored into this group must reuse that envelope and exit-code table
rather than inventing agent-specific variants, so a single "Reading the JSON
Envelope" mental model (see `kite-passport/SKILL.md`) covers both the `user`
and `buyer-agent` groups.

## Skills in this group

Skills live in top-level directories named after their slug, as in the rest of
the repository — group membership is recorded by the `group` field in
`skills.json`, not by nesting under this directory. This directory holds the
group's documentation.

| Skill | Purpose |
|-------|---------|
| [`buyer-agent-setup`](../buyer-agent-setup/SKILL.md) | Runtime identity: `init`, `bind` with the owner's passkey approval, `status`. The gateway skill — the other two require an active binding. |
| [`buyer-find-seller`](../buyer-find-seller/SKILL.md) | Discovery and verification: `directory search/get/card/keys`, and `card fetch --pin` for the chain context `propose` requires. |
| [`buyer-purchase`](../buyer-purchase/SKILL.md) | The escrowed agreement lane: propose, owner-approved session, fund, watch, verify, confirm or reject, review. |
