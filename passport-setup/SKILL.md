---
name: Passport Setup
description: Install and verify the kpass CLI on this computer before running any other Passport skill. Invoke automatically when kpass is missing or when a Passport skill fails with a command-not-found error.
---

# Passport Setup

## Purpose

Install the kpass CLI on this computer so other Passport skills can run. Grok Bot installs skills but not external dependencies; this skill bridges the gap by installing the CLI itself.

## When to Use

Invoke this skill automatically when:
- `command -v kpass` returns nothing (kpass is not installed)
- Any other Passport skill fails with "command not found: kpass"
- The user asks to "install kpass", "set up Passport", or "prepare my environment for Kite"

## Installation

### Check First

Before installing, check if kpass is already present:

```bash
command -v kpass
```

If this returns a path, kpass is installed. Skip to verification.

### Install on This Computer

If kpass is missing, install it now with the official installer:

> **Note**: This installer is the vendor's official method (documented at cli.gokite.ai). For Grok Bot and similar autonomous agents, this step runs automatically. For other agents, the user should confirm before proceeding.

```bash
curl -fsSL https://cli.gokite.ai/install.sh | bash
```

This installer:
- Downloads the latest kpass CLI binary for your platform
- Installs it to `~/.local/bin/kpass` (or another standard location)
- Updates your shell's PATH if needed

After the installer completes, reload your shell environment:

```bash
export PATH="$HOME/.local/bin:$PATH"
hash -r
```

### Verification

After installation, verify kpass works:

```bash
kpass --version
```

Expected output: a version string like `kpass 1.5.0` or higher.

If `kpass --version` fails, the installation did not succeed. Report the error to the user and stop. Do not proceed to other Passport skills until verification passes.

## Next Steps

Once kpass is installed and verified:
- Other Passport skills can now run
- The user may need to authenticate with `authenticate-user` before using paid features
- Check `kpass --help` for available commands

## Notes

- This skill runs on the bot's own computer, not the user's machine
- The installer is idempotent — safe to run multiple times
- For production use only; the installer URL serves the live kpass release
- No authentication is required to install kpass; authentication happens separately via `authenticate-user`

## Dependencies

None. This is the bootstrap skill that makes other Passport skills possible.
