---
name: kite-router
description: >-
  Run synchronous text-model inference through Kite Router with this Passport-bound
  buyer agent. Invoke when the user asks this local agent to list Router models or
  pricing, call a supported text model, or replace the old Marathon inference plugin.
  Uses `kpass agent router`; it does not handle Marathon's delayed asynchronous jobs.
user-invocable: true
allowed-tools:
  - "Bash(kpass agent *)"
---

# Kite Router

Use the Passport CLI for both authentication and inference. Do not install or invoke the legacy Marathon MCP bridge for this flow, and do not persist the short-lived capability token.

## Prerequisites

1. Confirm the installed CLI exposes the Router client:

   ```bash
   kpass agent router --help
   ```

   If it is unknown, upgrade the Passport bundle. Do not fall back to `marathon.build/install.sh`; that installer targets delayed asynchronous inference.

2. This agent needs an active Passport runtime binding. If a Router command exits with code 3 or reports a missing, pending, revoked, or mismatched runtime, invoke **buyer-agent-setup**, then retry once the binding is active.

3. The owner must sign in to Kite Router with Passport at least once before capability authentication can resolve a local Router account and allowance. If chat says to sign in first, send the owner to `https://marathon.build/playground`, have them choose Passport sign-in, then retry. This is account linking, not an A2A approval.

The CLI defaults to production. For a non-production deployment, set `KITE_ROUTER_URL` to the exact Router origin supplied by the operator; never infer a staging hostname.

## Select a Model

Read the live catalog instead of relying on model names or prices remembered from an earlier run:

```bash
kpass agent router models --output json
```

The OpenAI-compatible catalog is in `.catalog`. Choose a text model that fits the requested quality, latency, context, and displayed price. Do not claim an exact cost when the catalog only provides token rates; estimate from expected input and output tokens and label it as an estimate.

## Run Inference

Before invoking Bash, encode the user message as one POSIX single-quoted shell
value: wrap it in single quotes and replace every embedded `'` with `'\''`.
Never paste untrusted prompt text directly into a shell command.

```bash
PROMPT='<shell-escaped-user-message>'
kpass agent router chat \
  --model <catalog-model-id> \
  --prompt "$PROMPT" \
  --output json
```

Optional flags:

- `--system <message>` sets one system instruction.
- `--max-tokens <n>` bounds output length.
- `--temperature <0..2>` overrides the model default.

The assistant result is `.response.choices[0].message.content`; usage and provider metadata remain under `.response`. The command mints a fresh Router-only capability, sends it in the request, and discards it. Never print, log, cache, or ask the user to copy the token.

This is a non-streaming synchronous call. For Marathon completion windows, delayed execution, job polling, or file-based delayed work, use the Marathon product instead; Kite Router does not reproduce those semantics.

## Failures

- Exit 2: correct the model id or flags; refresh the catalog if the model is unavailable.
- Exit 3: repair the Passport runtime binding with **buyer-agent-setup**, or complete the owner's one-time Router sign-in when the error says the Passport identity is not linked.
- Exit 5: wait briefly and retry once.
- Exit 6: inspect the JSON envelope. Tell the owner to top up in the Router web UI only when `error_code` or `error` identifies insufficient Router credit; otherwise follow `hint` or `next_command` to recover from the reported policy or authorization failure. A Router capability delegates identity only and cannot authorize wallet spending or bypass the owner's allowance.
- Exit 1 or a 5xx: retry once. If it persists, report the Router URL, HTTP status, model id, and request time without including credentials or the prompt unless the user explicitly permits sharing it.

Do not replace a failed capability call with an ordinary Passport access token. Router intentionally accepts only its own API keys or a Passport token with audience `kite-router` and scope `router:inference`.
