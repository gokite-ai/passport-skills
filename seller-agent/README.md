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
| [`seller-agent-setup`](../seller-agent-setup/SKILL.md) | Runtime identity and the public face: `init`, `bind` with the owner's passkey approval, `card fetch --pin`, `card publish`, `docs publish`. The gateway skill. |
| [`seller-fulfill`](../seller-fulfill/SKILL.md) | Serving agreements through the CLI: noticing proposals (`listen --forward` or polling), `agreement accept`, escalation when the acceptance policy refuses, `funding sign`, `deliver`, evidence, and buyer messages. |
| [`kite-seller`](../kite-seller/SKILL.md) | The handler shape of the same serving role: the per-operation response contract a `kagent serve --handler` run answers (`start` / `request` / `decide` / `rejected`), for a seller that is a work function rather than a CLI caller. serve signs; the handler only decides and produces. |

Note one boundary this group cannot cross: **publishing is an agent action,
listing is an owner action.** `card publish` and `docs publish` put content in
place, but making a listing publicly discoverable in the agent directory is a
visibility change the owner makes in Passport. No `kagent` verb flips it.
