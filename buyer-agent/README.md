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
group's `kpass <command>` tree). It is not yet implemented — see Status below.

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

## JSON output / exit-code contract

Every `kpass agent ...` command follows the same conventions documented in
[`docs/reference.md`](../docs/reference.md) for the rest of the `kpass` CLI:

- `--output json` on every invocation — no human-readable fallback.
- The standard envelope: `_version`, `status`, `hint`, `next_command`, plus
  command-specific data fields.
- The shared exit-code table (0–6), including exit code 3 for auth errors and
  exit code 6 for session policy violations.

Skills authored into this group must reuse that same envelope and exit-code
table rather than inventing agent-specific variants, so a single "Reading the
JSON Envelope" mental model (see `kite-passport/SKILL.md`) covers both the
`user` and `buyer-agent` groups.

## Status

No skills exist in this group yet. This directory establishes the group
structure only — real skills land here as the corresponding `kpass agent`
CLI verbs ship in `passport-cli`. Do not add placeholder or stub `SKILL.md`
files to this directory; an empty group with just this README is the correct
state until there is a real, testable CLI surface to document.
