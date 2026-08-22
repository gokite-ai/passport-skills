# Seller Agent Skills

## Purpose

This group holds skills for an autonomous agent acting as a **seller** — an
agent that manages a merchant's Passport-side presence (listings, incoming
sessions, settlement) rather than spending on a buyer's behalf. It targets a
second binary, `kseller`, shipped in the same release bundle as `kpass` from
`passport-cli`, distinct from both the `user` group (human operator driving
`kpass`) and the `buyer-agent` group (agent driving `kpass agent ...`).

## CLI surface

Skills in this group drive:

```bash
kseller <command> [subcommand] [flags] --output json
```

`kseller` is a separate executable from `kpass`, not a subcommand tree under
it — installed alongside `kpass` from the same passport-cli release bundle.
It is not yet implemented — see Status below.

## Permission glob contract

Skills in this group declare `allowed-tools` scoped to the `kseller` binary
only:

```yaml
allowed-tools:
  - "Bash(kseller *)"
```

This keeps a seller-agent skill's permissions disjoint from both the `user`
group's `kpass ...` glob and the `buyer-agent` group's `Bash(kpass agent *)`
glob: a seller-agent skill should never be able to invoke buyer-side spending
commands or human-account commands, even when installed in the same agent
sandbox.

## JSON output / exit-code contract

`kseller` is expected to follow the same conventions documented in
[`docs/reference.md`](../docs/reference.md) for `kpass`:

- `--output json` on every invocation — no human-readable fallback.
- The standard envelope: `_version`, `status`, `hint`, `next_command`, plus
  command-specific data fields.
- The shared exit-code table (0–6), reused rather than redefined so an agent
  already familiar with the `kpass` envelope from the `user` or `buyer-agent`
  groups does not need a second mental model for `kseller`.

Once `kseller` ships, skills authored into this group must verify the actual
envelope and exit codes against the CLI implementation (per
`CONTRIBUTING.md`'s "verify against the CLI source" rule) rather than assume
parity with `kpass` — this section states the intended contract, not a
guarantee of the shipped behavior.

## Status

No skills exist in this group yet. This directory establishes the group
structure only — real skills land here as the corresponding `kseller` CLI
verbs ship in `passport-cli`. Do not add placeholder or stub `SKILL.md`
files to this directory; an empty group with just this README is the correct
state until there is a real, testable CLI surface to document.
