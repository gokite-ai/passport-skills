import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  gradeResponse,
  loadEvalCases,
  runEvalCase,
  runEvalSuite,
  writeReports,
} from "../scripts/eval-runner-lib.mjs";
import { parseArgs } from "../scripts/eval-runner.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtureAdapter = path.join(here, "fixtures", "eval-adapter.mjs");
const runner = path.join(here, "..", "scripts", "eval-runner.mjs");
const execFileAsync = promisify(execFile);

function sampleCase(overrides = {}) {
  return {
    id: 1,
    prompt: "Return alpha and beta",
    expected_output: "A response containing both markers",
    assertions: ["alpha", "beta"],
    ...overrides,
  };
}

test("loadEvalCases validates and loads the repository format", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "eval-runner-load-"));
  const input = path.join(directory, "evals.json");
  await writeFile(input, JSON.stringify([sampleCase()]));

  assert.deepEqual(await loadEvalCases(input), [sampleCase()]);
});

test("loadEvalCases rejects duplicate ids and malformed assertions", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "eval-runner-invalid-"));
  const duplicateInput = path.join(directory, "duplicate.json");
  const malformedInput = path.join(directory, "malformed.json");
  await writeFile(duplicateInput, JSON.stringify([sampleCase(), sampleCase()]));
  await writeFile(
    malformedInput,
    JSON.stringify([sampleCase({ assertions: ["valid", ""] })]),
  );

  await assert.rejects(loadEvalCases(duplicateInput), /duplicate eval id 1/i);
  await assert.rejects(loadEvalCases(malformedInput), /non-empty strings/i);
});

test("loadEvalCases rejects unreadable, empty, and malformed cases", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "eval-runner-schema-"));
  const cases = [
    ["invalid-json.json", "not json", /unable to read eval file/i],
    ["empty.json", "[]", /non-empty JSON array/i],
    ["scalar.json", "{}", /non-empty JSON array/i],
    ["null-case.json", "[null]", /must be an object/i],
    ["bad-id.json", JSON.stringify([sampleCase({ id: 0 })]), /positive integer id/i],
    [
      "bad-prompt.json",
      JSON.stringify([sampleCase({ prompt: "" })]),
      /prompt must be a non-empty string/i,
    ],
    [
      "bad-expected.json",
      JSON.stringify([sampleCase({ expected_output: null })]),
      /expected_output must be a non-empty string/i,
    ],
    [
      "bad-assertions.json",
      JSON.stringify([sampleCase({ assertions: "alpha" })]),
      /assertions must contain non-empty strings/i,
    ],
  ];

  await assert.rejects(
    loadEvalCases(path.join(directory, "missing.json")),
    /unable to read eval file/i,
  );
  for (const [name, contents, expected] of cases) {
    const input = path.join(directory, name);
    await writeFile(input, contents);
    await assert.rejects(loadEvalCases(input), expected);
  }
});

test("gradeResponse reports every missing literal assertion", () => {
  assert.deepEqual(gradeResponse(sampleCase(), "alpha only"), {
    passed: false,
    assertions: [
      { text: "alpha", passed: true },
      { text: "beta", passed: false },
    ],
    missingAssertions: ["beta"],
  });
});

test("parseArgs supports repeatable adapter arguments and case filters", () => {
  assert.deepEqual(
    parseArgs([
      "--adapter",
      "agent-cli",
      "--adapter-arg",
      "--print",
      "--adapter-arg",
      "json",
      "--case",
      "4",
      "--case",
      "7",
      "--jobs",
      "2",
    ]),
    {
      adapter: "agent-cli",
      adapterArgs: ["--print", "json"],
      input: "evals/evals.json",
      outputDirectory: "eval-results",
      timeoutMs: 120_000,
      jobs: 2,
      caseIds: [4, 7],
    },
  );
  assert.deepEqual(parseArgs(["--help"]), { help: true });
  assert.throws(() => parseArgs([]), /--adapter is required/);
  assert.throws(() => parseArgs(["--jobs", "0"]), /positive integer/);
  assert.throws(() => parseArgs(["--adapter"]), /requires a value/);
  assert.throws(() => parseArgs(["--adapter", "tool", "--wat"]), /unknown option/);
  assert.deepEqual(
    parseArgs([
      "--adapter",
      "tool",
      "--input",
      "custom.json",
      "--output-dir",
      "artifacts",
      "--timeout-ms",
      "42",
    ]),
    {
      adapter: "tool",
      adapterArgs: [],
      input: "custom.json",
      outputDirectory: "artifacts",
      timeoutMs: 42,
      jobs: 1,
      caseIds: [],
    },
  );
});

test("runEvalCase sends the prompt on stdin and grades stdout", async () => {
  const result = await runEvalCase(sampleCase(), {
    adapter: process.execPath,
    adapterArgs: [fixtureAdapter, "echo"],
    timeoutMs: 2_000,
  });

  assert.equal(result.status, "passed");
  assert.equal(result.response, "Return alpha and beta");
  assert.equal(result.exitCode, 0);
  assert.deepEqual(result.missingAssertions, []);
  assert.ok(result.durationMs >= 0);
});

test("runEvalCase records adapter failures without grading partial output", async () => {
  const result = await runEvalCase(sampleCase(), {
    adapter: process.execPath,
    adapterArgs: [fixtureAdapter, "fail"],
    timeoutMs: 2_000,
  });

  assert.equal(result.status, "error");
  assert.equal(result.exitCode, 7);
  assert.match(result.stderr, /fixture failure/);
});

test("runEvalCase records an adapter spawn error", async () => {
  const result = await runEvalCase(sampleCase(), {
    adapter: path.join(os.tmpdir(), "missing-eval-adapter"),
    adapterArgs: [],
    timeoutMs: 2_000,
  });

  assert.equal(result.status, "error");
  assert.match(result.error, /ENOENT/);
  assert.deepEqual(result.missingAssertions, ["alpha", "beta"]);
});

test("runEvalCase and runEvalSuite reject invalid execution options", async () => {
  await assert.rejects(
    runEvalCase(sampleCase(), { timeoutMs: 1 }),
    /adapter is required/,
  );
  await assert.rejects(
    runEvalCase(sampleCase(), { adapter: "tool", timeoutMs: 0 }),
    /timeoutMs must be a positive integer/,
  );
  await assert.rejects(runEvalSuite([], { jobs: 1 }), /at least one eval case/);
  await assert.rejects(
    runEvalSuite([sampleCase()], { jobs: 0 }),
    /jobs must be a positive integer/,
  );
});

test("runEvalCase terminates adapters that exceed the deadline", async () => {
  const result = await runEvalCase(sampleCase(), {
    adapter: process.execPath,
    adapterArgs: [fixtureAdapter, "hang"],
    timeoutMs: 50,
  });

  assert.equal(result.status, "timeout");
  assert.equal(result.timedOut, true);
  assert.match(result.error, /50 ms/);
});

test("runEvalSuite preserves input order while running concurrent cases", async () => {
  const cases = [
    sampleCase({ id: 2, assertions: ["eval-2"] }),
    sampleCase({ id: 1, assertions: ["eval-1"] }),
  ];
  const report = await runEvalSuite(cases, {
    adapter: process.execPath,
    adapterArgs: [fixtureAdapter, "echo-id"],
    timeoutMs: 2_000,
    jobs: 2,
  });

  assert.deepEqual(
    report.results.map(({ id }) => id),
    [2, 1],
  );
  assert.deepEqual(report.summary, {
    total: 2,
    passed: 2,
    failed: 0,
    errors: 0,
    timedOut: 0,
    passRate: 1,
  });
  assert.equal(report.environment.node, process.version);
});

test("writeReports emits machine-readable JSON and reviewable Markdown", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "eval-runner-report-"));
  const report = await runEvalSuite([sampleCase()], {
    adapter: process.execPath,
    adapterArgs: [fixtureAdapter, "echo"],
    timeoutMs: 2_000,
    jobs: 1,
  });

  const paths = await writeReports(report, directory);
  const json = JSON.parse(await readFile(paths.json, "utf8"));
  const markdown = await readFile(paths.markdown, "utf8");

  assert.equal(json.summary.passed, 1);
  assert.match(markdown, /# Passport Skills Eval Report/);
  assert.match(markdown, /1\/1 \(100\.00%\)/);
  assert.match(markdown, /PASS/);
});

test("CLI returns failure and writes evidence for a reproducible assertion miss", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "eval-runner-cli-"));
  const input = path.join(directory, "evals.json");
  const output = path.join(directory, "reports");
  await writeFile(input, JSON.stringify([sampleCase()]));

  await assert.rejects(
    execFileAsync(process.execPath, [
      runner,
      "--adapter",
      process.execPath,
      "--adapter-arg",
      fixtureAdapter,
      "--adapter-arg",
      "miss-last",
      "--input",
      input,
      "--output-dir",
      output,
    ]),
    (error) => error.code === 1 && /0 passed/.test(error.stdout),
  );
  const report = JSON.parse(
    await readFile(path.join(output, "report.json"), "utf8"),
  );
  const markdown = await readFile(path.join(output, "report.md"), "utf8");
  assert.equal(report.results[0].status, "failed");
  assert.deepEqual(report.results[0].missingAssertions, ["beta"]);
  assert.match(markdown, /## Failure details/);
  assert.match(markdown, /Assertion mismatch/);
  assert.match(markdown, /beta/);
});

test("CLI executes all repository evals and reports a complete pass", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "eval-runner-all-"));
  const output = path.join(directory, "reports");
  const { stdout } = await execFileAsync(process.execPath, [
    runner,
    "--adapter",
    process.execPath,
    "--adapter-arg",
    fixtureAdapter,
    "--adapter-arg",
    "assertions-file",
    "--adapter-arg",
    path.join(here, "..", "evals", "evals.json"),
    "--input",
    path.join(here, "..", "evals", "evals.json"),
    "--output-dir",
    output,
    "--jobs",
    "12",
  ]);

  assert.match(stdout, /Evaluated 138 case\(s\): 138 passed \(100\.00%\)/);
  const report = JSON.parse(
    await readFile(path.join(output, "report.json"), "utf8"),
  );
  assert.equal(report.summary.total, 138);
  assert.equal(report.summary.passRate, 1);
});

test("CLI help and invalid case selection use distinct exit paths", async () => {
  const { stdout } = await execFileAsync(process.execPath, [runner, "--help"]);
  assert.match(stdout, /Usage:/);

  await assert.rejects(
    execFileAsync(process.execPath, [
      runner,
      "--adapter",
      process.execPath,
      "--case",
      "9999",
    ]),
    (error) => error.code === 2 && /unknown eval id/.test(error.stderr),
  );
});
