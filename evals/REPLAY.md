# Replaying captured Passport eval answers

`scripts/replay-evals.mjs` checks the existing `evals.json` literal assertions against saved agent responses. It is a dependency-free Node.js 20+ tool for offline review and CI reporting, not an agent execution adapter. It never calls `kpass`, signs transactions, or invokes a model. An execution runner can produce its input without giving the agent the grading answer key.

## Capture protocol

First export the prompts and the grading-suite fingerprint:

```bash
node scripts/replay-evals.mjs --request capture-request.json
```

The output contains `schemaVersion`, `suiteSha256`, and `cases: [{id, prompt}]`. It intentionally excludes `expected_output` and `assertions`. Give the agent only the prompt and appropriate skills/environment. The producer should retain the fingerprint from the request that actually generated the answers; do not replace an old capture's hash with a current one just to bypass a mismatch.

After recording answers, write a separate JSON document:

```json
{
  "schemaVersion": 1,
  "suiteSha256": "COPY_FROM_THE_CAPTURE_REQUEST",
  "kind": "recorded",
  "producer": "agent/model version; skill commit; environment; capture date",
  "records": [
    {"id": 1, "response": "The actual captured agent response, unmodified"},
    {"id": 2, "error": "Agent execution failed before a response was captured"}
  ]
}
```

Include one record per executed case, with exactly one of `response` or `error`. A response can be empty; it will fail its literal checks. Omit cases that were not executed: the replayer will report them as missing instead of quietly reducing the denominator. IDs must be unique and exist in the current suite. `kind` is required: use `synthetic` for fixtures and `recorded` only for actual captured output. These labels and fingerprints track provenance but do not authenticate a producer or prove that a model ran.

Record the model, skill revision, operating system, account/test state, and tool versions in `producer` or your private capture notes. A suite hash binds prompts, expected outputs and assertions, not the skill files or remote environment. Captures may contain sensitive account details; keep them private and redact before external sharing. The generated reports omit response/error bodies and include their SHA-256 fingerprints instead. Assertion text and producer metadata still appear in reports, so inspect these fields before publishing artifacts.

## Replay and CI

```bash
node scripts/replay-evals.mjs --capture captures.json --out replay-report
# Optional custom suite:
node scripts/replay-evals.mjs --suite custom-evals.json --capture captures.json --out custom-report
```

The output directory must be new, with an existing parent directory. Refusing to reuse a report directory prevents a failed invocation from leaving a stale green report that CI mistakes for the current result. Request export also refuses to overwrite an existing file.

Outputs:

- `report.json`: every eval and every literal assertion, including match offsets and capture status; hashes identify the suite and capture.
- `report.md`: full case table, missing markers, counts and explicit semantic-review limitations.
- `junit.xml`: one testcase per assertion. Unmatched literals are failures; missing captures and execution errors are JUnit errors. XML attributes are escaped and invalid XML 1.0 control characters are replaced.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Every case was captured and every literal matched; semantic review is still required |
| 1 | At least one missing/error capture or unmatched literal; reports are written |
| 2 | Invalid arguments, malformed/stale input, or I/O error; do not use output as a successful report |

Matching is case-sensitive substring matching, following the existing suite format. Offsets are zero-based JavaScript UTF-16 string offsets. A response that merely quotes a command (or says not to run it) may match it. Every case therefore retains `semanticReview: "required"`; this tool never claims the expected behavior was satisfied. Read `expected_output` alongside the original response when reviewing semantics.

For CI, replay private or appropriately sanitized captures in a job, then publish reports in an `if: always()` artifact step. Let the replay exit code fail the job; do not hide it with `continue-on-error`. The included `Eval transcript replay` workflow tests the tool on Node 20/22 and Ubuntu/Windows. Its uploaded fixtures are **synthetic runner-contract evidence, not live Passport eval results**.

## Reproduce the full-suite contract and known failure

```bash
npm run test:replay
node test/fixtures/replay-evidence.mjs
```

Use a fresh checkout or remove only your previous generated `tmp/replay-evidence` output before repeating the evidence command. It generates two explicitly synthetic captures and three reports for each:

1. `all-markers`: tests that all assertions for every suite case can be scored and reported.
2. `missing-json-flag`: removes `--output json` from case 1. The harness verifies exit code 1 and exactly one failed case. This is a deliberately injected fixture regression, not a discovered live skill failure.

The tests also cover prompt-only exports, suite changes, duplicate/unknown IDs, empty responses, missing captures, execution errors, answer-key echo limitations, markup escaping, out-of-directory invocation, report overwrite prevention and malformed CLI inputs. New behavior scenarios continue to use the existing `evals.json` shape; no migration is required.
