---
name: kite-router
description: >-
  Run synchronous text-model inference through Kite Router with this Passport-bound
  agent. Invoke when the user asks this local agent to list Router models or
  pricing, call a supported text model, or replace the old Marathon inference plugin.
  Uses `kpass agent router`; it does not handle Marathon's delayed asynchronous jobs.
user-invocable: true
allowed-tools:
  - "Bash(kpass agent *)"
---

# Kite Router

Use the Passport CLI for both authentication and inference. Do not install or invoke the legacy Marathon MCP bridge for this flow, and do not persist the short-lived capability token.

## Prerequisites

0. If there is no agent record yet, create one:

   First, authenticate the user if not logged in. Use the authenticate-user skill (`kpass login init --email <email> --output json`, then `kpass login verify`).

   Then create the agent:
   ```bash
   kpass agent create --uid <slug> --kind buyer --output json
   ```

   Use the returned DID for the binding steps below.

1. Confirm the installed CLI exposes the Router client:

   ```bash
   kpass agent router --help
   ```

   If it is unknown, upgrade the Passport bundle. Do not fall back to `marathon.build/install.sh`; that installer targets delayed asynchronous inference.

2. This agent needs an active Passport runtime binding. Set up the runtime identity if needed:

   **Check binding status:**
   ```bash
   kpass agent status --output json
   ```

   If the runtime key is missing or the binding is not active, complete these setup steps:

   **a) Generate the runtime key (if needed):**
   ```bash
   kpass agent init --output json
   ```

   Reports the agent's secp256k1 public key address and thumbprint. The key is stored locally.

   **b) Bind the runtime key to an agent record:**

   First, try the streamlined mint-then-bind path. `kpass agent token create` mints a one-time token, and `kpass agent bind` consumes it:
   ```bash
   kpass agent token create --agent <did:kite:agent-id> --output json
   ```

   Then bind with the returned token:
   ```bash
   kpass agent bind --agent <did:kite:agent-id> --token <art_...> --output json
   ```

   If token creation requires step-up or you need the direct path, use:
   ```bash
   kpass agent bind --agent <did:kite:agent-id> --wait --output json
   ```

   This returns an `approval_url`. Surface it to the owner, who must approve with their passkey. The command waits for completion.

   **c) Confirm the binding is active:**
   ```bash
   kpass agent status --output json
   ```

   Verify `binding.status` is `"active"`.

3. The owner must sign in to Kite Router with Passport at least once before capability authentication can resolve a local Router account and allowance. If chat says to sign in first, send the owner to `https://marathon.build/playground`, have them choose Passport sign-in, then retry. This is account linking, not a separate approval flow.

The CLI pairs the Router with the selected Passport environment: Passport dev uses Router dev, and Passport production uses Router production. For staging, local development, or another custom Passport backend, set `--router-url` or `KITE_ROUTER_URL` to the exact Router origin supplied by the operator; never infer a staging hostname.

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
- Exit 3: repair the Passport runtime binding following the setup steps above, or complete the owner's one-time Router sign-in when the error says the Passport identity is not linked.
- Exit 5: wait briefly and retry once.
- Exit 6: inspect the JSON envelope. Tell the owner to top up in the Router web UI only when `error_code` or `error` identifies insufficient Router credit; otherwise follow `hint` or `next_command` to recover from the reported policy or authorization failure. A Router capability delegates identity only and cannot authorize wallet spending or bypass the owner's allowance.
- Exit 1 or a 5xx: retry once. If it persists, report the Router URL, HTTP status, model id, and request time without including credentials or the prompt unless the user explicitly permits sharing it.

Do not replace a failed capability call with an ordinary Passport access token. Router intentionally accepts only its own API keys or a Passport token with audience `kite-router` and scope `router:inference`.
