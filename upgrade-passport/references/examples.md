# Upgrade Passport — Worked Examples

End-to-end walkthroughs for the `upgrade-passport` skill. The Auto-Upgrade Behavior rules and Quick Decision Flow live in `SKILL.md`; per-command syntax, exit codes, and JSON shapes live in `commands.md`.

---

## Example 1 — Quick check on POSIX (current)

```bash
kpass upgrade --check --output json
```

Exit 0, output:
```json
{"_version":"1","status":"success","current_bundle":22,"latest_bundle":22,"channel":"latest","behind":false,"hint":"kpass is up to date (bundle 22, channel latest).","next_command":""}
```

Tell the user: "Your kpass is up to date (bundle 22, latest channel)."

## Example 2 — Auto-detect + auto-upgrade on POSIX

The user just asked the agent to send 5 USDC. The wallet-send response carried:

```json
{
  "transaction_hash": "0x…",
  "_version": "1",
  "status": "success",
  "hint": "Sent 5 USDC.",
  "next_command": "",
  "update_available": {
    "current_bundle": 21,
    "latest_bundle": 22,
    "channel": "latest",
    "install_command": "kpass upgrade"
  }
}
```

The transfer succeeded (the user's primary task is done). `install_command` is `"kpass upgrade"` → POSIX → Rule 1 applies → upgrade automatically.

```bash
kpass upgrade --output json
```

Exit 0, output:
```json
{"_version":"1","status":"success","from_bundle":21,"to_bundle":22,"channel":"latest","cli_version":"1.3.18","ksearch_version":"1.0.4","skills_version":"1.1.8","hint":"Upgraded to bundle 22.","next_command":""}
```

Tell the user (one combined message):

> Sent 5 USDC successfully (tx 0x…). I also upgraded kpass to bundle 22 (CLI 1.3.18) since a newer version was available.

Do not ask permission first — the upgrade is automatic, the report comes after.

### Example 2b — Manual upgrade flow (user explicitly asked)

User: "Is my kpass up to date?"

```bash
kpass upgrade --check --output json
```

Exit 10:
```json
{"_version":"1","status":"success","current_bundle":21,"latest_bundle":22,"channel":"latest","behind":true,"hint":"kpass bundle 22 available (current: 21, channel latest). Run: kpass upgrade","next_command":"kpass upgrade"}
```

User explicitly asked, so per the manual-flow branch in the decision diagram, just go ahead and apply:

```bash
kpass upgrade --output json
```

Tell the user: "You were on bundle 21, latest is 22. Upgraded — you're now on bundle 22 (CLI 1.3.18)."

## Example 3 — Behind on Windows, surface install command (no agreement needed)

The Windows path is fundamentally different from POSIX. There is no agent action that can perform the upgrade — only the user can run the install script. So whether `update_available` was detected automatically or the user explicitly asked, the response is the same: surface the command verbatim.

```bash
kpass upgrade --check --output json
```

Exit 10, output:
```json
{"_version":"1","status":"success","current_bundle":21,"latest_bundle":22,"channel":"latest","behind":true,"hint":"kpass bundle 22 available (current: 21, channel latest). Run: irm https://cli.gokite.ai/install.ps1 | iex","next_command":"irm https://cli.gokite.ai/install.ps1 | iex"}
```

Tell the user verbatim:
> Bundle 22 is available. To upgrade on Windows, run this in a PowerShell prompt:
>
> ```
> irm https://cli.gokite.ai/install.ps1 | iex
> ```
>
> I can't run it for you on Windows — please run it yourself, then re-run your original task in a fresh shell.

**Do not** invoke `kpass upgrade` on Windows (it would just emit a `human_action_required` envelope with the same install_command — no actual upgrade happens). **Do not** spawn PowerShell to execute the irm command. Both would violate Rule 2.

## Example 4 — User wants to switch to stable

```bash
kpass upgrade --channel stable --output json
```

If stable is deployed in this environment, the CLI fetches that channel pointer and applies it. The new `version.json` records `channel: "stable"` so future `kpass upgrade` calls follow stable. If stable is not deployed (exit 4), tell the user: "The stable channel isn't deployed in this environment. Try `--channel latest`."

## Example 5 — Skip auto-upgrade because the user is mid-task

The user is in the middle of a checkout flow — `kpass agent:session create` returned `human_action_required` (waiting for the user to approve a delegation via passkey). The response included:

```json
{
  "request_id": "req_…",
  "approval_url": "https://…",
  "_version": "1",
  "status": "human_action_required",
  "hint": "Visit the approval URL to authorize the session.",
  "next_command": "kpass agent:session status --request-id req_… --wait",
  "update_available": {
    "current_bundle": 21,
    "latest_bundle": 22,
    "channel": "latest",
    "install_command": "kpass upgrade"
  }
}
```

`update_available` is present, but Rule 3 applies — the user is mid-flow waiting on approval. **Do not auto-upgrade right now.** Continue with `kpass agent:session status --wait`. After the session is approved AND the user's downstream task (the actual purchase / API call) completes, then upgrade.

This is the most common reason to defer: a new CLI version mid-flow could change behavior under the user's feet, and the new bundle's skills might not match the version the agent just loaded into context.

## Example 6 — `KPASS_AUTO_UPGRADE=0` requires confirmation

The user's environment has `KPASS_AUTO_UPGRADE=0` (auto-upgrade disabled, detection still on). After a kpass call returned `update_available`, the agent surfaces the update and asks before applying:

> Bundle 22 is available (you're on 21). Want me to upgrade now? It will run `kpass upgrade`.

Only proceed after the user agrees. This is the same flow as Example 2b — manual confirmation — but triggered by the env var instead of an explicit user request.
