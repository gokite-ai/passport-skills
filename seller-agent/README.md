# Seller Agent Skills

## Purpose

This group holds skills for an autonomous agent acting as a **seller** — an
agent that manages a merchant's Passport-side presence (listings, incoming
sessions, settlement) rather than spending on a buyer's behalf. It targets a
second binary, `kagent`, shipped in the same release bundle as `kpass` from
`passport-cli`, distinct from both the `user` group (human operator driving
`kpass`) and the `buyer-agent` group (agent driving `kpass agent ...`).

## CLI surface

Skills in this group drive:

```bash
kagent <command> [subcommand] [flags] --output json
```

`kagent` is a separate executable from `kpass`, not a subcommand tree under
it — installed alongside `kpass` from the same passport-cli release bundle. It
holds its own runtime key in its own state directory (`~/.kagent`), so a
seller identity is not a buyer identity with different flags. Colon-separated
paths work as aliases (`kagent agreement:funding:sign`), but these skills
document the space-separated form.

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
`"Bash(kpass identifier *)"`, `"Bash(kpass onboarding *)"`,
`"Bash(kpass agent create *)"`, and `"Bash(kpass agent token create *)"`,
scoped to the one-time owner identity/KYC bootstrap and agent
creation/bind-token minting documented in its `references/owner-bootstrap.md`
(see that skill's Step 2 and Step 3). No other skill in this group carries
this grant, and `seller-agent-setup` still cannot invoke `kpass signup`,
`kpass login`, buyer-side spending commands (`kpass agent fund`, `kpass agent
agreement ...`, `kpass agent session ...`, etc. — the grant is scoped to
exactly `agent create` and `agent token create`, not the whole `kpass agent`
tree), or any other human-account command outside that named path.

**Named exception:** `seller-onboarding` additionally carries owner-plane
**reads** only — `"Bash(kpass status *)"`, `"Bash(kpass me *)"`,
`"Bash(kpass user agents --agent-type seller *)"`, and
`"Bash(kpass onboarding status *)"` (plus `"Bash(shasum *)"` and
`"Bash(sha256sum *)"` for checkpoint digests). It does **not** carry any owner-plane **mutation**: the account
bootstrap and record creation the `kpass` binary requires before a seller can
exist (`kpass identifier claim`, `kpass onboarding submit`, `kpass agent create`,
`kpass agent token create`) are **owner handoffs** the skill derives and the
owner runs in their own terminal — deliberately kept out of `allowed-tools`
because they are account-wide/immutable, `onboarding submit` carries legal PII,
and the skill reads untrusted seller-repo content (prompt-injection surface).
It carries no `kpass login`, no buyer-side spending, and no other human-account
command. (A seller/account-scoped wrapper that would let these run safely under
the skill is tracked under GOK-1305.)

## JSON output / exit-code contract

`kagent` follows the same conventions documented in
[`docs/reference.md`](../docs/reference.md) for `kpass`, verified against the
CLI implementation per `CONTRIBUTING.md`'s "verify against the CLI source"
rule:

- `--output json` on every invocation — no human-readable fallback.
- The standard envelope: `_version`, `status`, `hint`, `next_command`, plus
  command-specific data fields spread at the top level (not nested under a
  `data` key). Envelope `status` is one of `success`,
  `human_action_required`, `pending`, `expired`, `error`.
- The shared exit-code table, reused rather than redefined so an agent already
  familiar with the `kpass` envelope from the `user` or `buyer-agent` groups
  does not need a second mental model for `kagent`.

The agent lane **extends** that exit-code table with two codes the
human-facing `kpass` surface does not emit:

| Code | Name | Meaning |
|------|------|---------|
| 7 | `CONFLICT` | The agreement plane's "you signed against a state that has moved, or an id that is already taken" family. The fix is mechanical: re-read, rebuild, retry. |
| 8 | `PROTOCOL` | A **local** refusal — canonicalization, signing or verification failed on this machine and the artifact never left it. Nothing was sent; do not retry the same bytes. |

Exit code 10 (`BEHIND`) exists in the shared table but is unreachable from
`kagent`, which carries no `upgrade` verb.

Error envelopes carry `error`, `hint`, `next_command`, plus optional
`error_code`, `details`, and `retriable`. `retriable` is three-state: `true`,
`false`, or **absent** when no server ruled on the request — absence is not
`false`.

## Skills in this group

Skills live in top-level directories named after their slug, as in the rest of
the repository — group membership is recorded by the `group` field in
`skills.json`, not by nesting under this directory. This directory holds the
group's documentation.

| Skill | Purpose |
|-------|---------|
| [`seller-onboarding`](../seller-onboarding/SKILL.md) | The human entry point: interview a seller with zero Kite vocabulary about their own business and derive every platform artifact — identity, offer/rate-card, workflow template, governance mandate, standing orders, craft skill — then prepare and hand off one live verification deal (settlement blocked by GOK-1272). Drives the same commands the runbook skills below document. |
| [`seller-agent-setup`](../seller-agent-setup/SKILL.md) | Runtime identity and the public face: `init`, `bind` with the owner's passkey approval, `card fetch --pin`, `card publish`, `docs publish`. The gateway skill. |
| [`seller-fulfill`](../seller-fulfill/SKILL.md) | Serving agreements through the CLI: noticing proposals (`listen --forward` or polling), `agreement accept`, escalation when the acceptance policy refuses, `funding sign`, `deliver`, evidence, and buyer messages. |
| [`seller-agreement-history`](../seller-agreement-history/SKILL.md) | After-the-fact, read-only lookups: `agreement proofs [--verify]`, `agreement evidence list`, `escalation list`/`status` — not a workflow step. |
| [`seller-serve`](../seller-serve/SKILL.md) | **The default way to take work**: run the seller as a work function under `kagent serve --config kite.config.yaml`, so one binary holds the key and answers each item by running the seller's own model with the seller's skills — the seller writes no platform code. Covers the seller directory, the config file, the two skills the seller authors, and the card facts the model reads from disk. |
| [`kite-seller`](../kite-seller/SKILL.md) | The work-function shape of the same serving role: the per-operation response contract a `kagent serve` brain answers (`start` / `request` / `decide` / `rejected` / `settle` / `closed`), for a seller that is a work function rather than a CLI caller. serve signs; the brain only decides and produces. |

Note one boundary this group cannot cross: **publishing is an agent action,
listing is an owner action.** `card publish` and `docs publish` put content in
place, but making a listing publicly discoverable in the agent directory is a
visibility change the owner makes in Passport. No `kagent` verb flips it.
