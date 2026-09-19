import { spawn } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

function assertEvalCase(value, index) {
  const label = `eval at index ${index}`;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
  if (!Number.isInteger(value.id) || value.id < 1) {
    throw new TypeError(`${label} must have a positive integer id`);
  }
  for (const field of ["prompt", "expected_output"]) {
    if (typeof value[field] !== "string" || value[field].trim() === "") {
      throw new TypeError(`${label}.${field} must be a non-empty string`);
    }
  }
  if (
    !Array.isArray(value.assertions) ||
    value.assertions.length === 0 ||
    value.assertions.some(
      (assertion) => typeof assertion !== "string" || assertion.trim() === "",
    )
  ) {
    throw new TypeError(`${label}.assertions must contain non-empty strings`);
  }
}

export async function loadEvalCases(inputPath) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(inputPath, "utf8"));
  } catch (error) {
    throw new Error(`unable to read eval file ${inputPath}: ${error.message}`, {
      cause: error,
    });
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new TypeError("eval file must contain a non-empty JSON array");
  }

  const ids = new Set();
  parsed.forEach((evalCase, index) => {
    assertEvalCase(evalCase, index);
    if (ids.has(evalCase.id)) {
      throw new TypeError(`duplicate eval id ${evalCase.id}`);
    }
    ids.add(evalCase.id);
  });
  return parsed;
}

export function gradeResponse(evalCase, response) {
  const assertions = evalCase.assertions.map((text) => ({
    text,
    passed: response.includes(text),
  }));
  const missingAssertions = assertions
    .filter(({ passed }) => !passed)
    .map(({ text }) => text);
  return {
    passed: missingAssertions.length === 0,
    assertions,
    missingAssertions,
  };
}

function executeAdapter(evalCase, options) {
  return new Promise((resolve) => {
    const started = performance.now();
    let stdout = "";
    let stderr = "";
    let spawnError;
    let timedOut = false;
    let settled = false;
    const child = spawn(options.adapter, options.adapterArgs ?? [], {
      env: {
        ...process.env,
        EVAL_ID: String(evalCase.id),
      },
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
    });

    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, options.timeoutMs);

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      spawnError = error;
    });
    child.on("close", (exitCode, signal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve({
        stdout,
        stderr,
        exitCode,
        signal,
        spawnError,
        timedOut,
        durationMs: Math.round((performance.now() - started) * 100) / 100,
      });
    });

    child.stdin.on("error", () => {
      // The adapter may exit before consuming stdin; its exit status is authoritative.
    });
    child.stdin.end(evalCase.prompt);
  });
}

export async function runEvalCase(evalCase, options) {
  assertEvalCase(evalCase, 0);
  if (!options.adapter) throw new TypeError("adapter is required");
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 1) {
    throw new TypeError("timeoutMs must be a positive integer");
  }

  const execution = await executeAdapter(evalCase, options);
  const base = {
    id: evalCase.id,
    prompt: evalCase.prompt,
    expectedOutput: evalCase.expected_output,
    expectedAssertions: evalCase.assertions,
    response: execution.stdout,
    stderr: execution.stderr,
    exitCode: execution.exitCode,
    signal: execution.signal,
    durationMs: execution.durationMs,
    timedOut: execution.timedOut,
  };

  if (execution.timedOut) {
    return {
      ...base,
      status: "timeout",
      assertions: [],
      missingAssertions: [...evalCase.assertions],
      error: `adapter exceeded timeout of ${options.timeoutMs} ms`,
    };
  }
  if (execution.spawnError) {
    return {
      ...base,
      status: "error",
      assertions: [],
      missingAssertions: [...evalCase.assertions],
      error: execution.spawnError.message,
    };
  }
  if (execution.exitCode !== 0) {
    return {
      ...base,
      status: "error",
      assertions: [],
      missingAssertions: [...evalCase.assertions],
      error: `adapter exited with code ${execution.exitCode}`,
    };
  }

  const grade = gradeResponse(evalCase, execution.stdout);
  return {
    ...base,
    status: grade.passed ? "passed" : "failed",
    ...grade,
  };
}

export async function runEvalSuite(evalCases, options) {
  if (!Array.isArray(evalCases) || evalCases.length === 0) {
    throw new TypeError("at least one eval case is required");
  }
  if (!Number.isInteger(options.jobs) || options.jobs < 1) {
    throw new TypeError("jobs must be a positive integer");
  }

  const startedAt = new Date();
  const results = new Array(evalCases.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < evalCases.length) {
      const index = nextIndex++;
      results[index] = await runEvalCase(evalCases[index], options);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(options.jobs, evalCases.length) }, worker),
  );

  const passed = results.filter(({ status }) => status === "passed").length;
  const failed = results.filter(({ status }) => status === "failed").length;
  const errors = results.filter(({ status }) => status === "error").length;
  const timedOut = results.filter(({ status }) => status === "timeout").length;
  const finishedAt = new Date();
  return {
    schemaVersion: 1,
    startedAt: startedAt.toISOString(),
    finishedAt: finishedAt.toISOString(),
    durationMs: finishedAt.getTime() - startedAt.getTime(),
    environment: {
      node: process.version,
      platform: process.platform,
      architecture: process.arch,
      ci: process.env.CI === "true",
    },
    configuration: {
      adapter: options.adapter,
      adapterArgs: options.adapterArgs ?? [],
      timeoutMs: options.timeoutMs,
      jobs: options.jobs,
    },
    summary: {
      total: results.length,
      passed,
      failed,
      errors,
      timedOut,
      passRate: passed / results.length,
    },
    results,
  };
}

function escapeTable(value) {
  return String(value).replaceAll("|", "\\|").replaceAll("\n", " ");
}

function renderMarkdown(report) {
  const percentage = (report.summary.passRate * 100).toFixed(2);
  const lines = [
    "# Passport Skills Eval Report",
    "",
    `- Started: ${report.startedAt}`,
    `- Finished: ${report.finishedAt}`,
    `- Adapter: \`${report.configuration.adapter}\``,
    `- Result: ${report.summary.passed}/${report.summary.total} (${percentage}%)`,
    "",
    "| ID | Status | Duration | Missing assertions |",
    "|---:|:---:|---:|---|",
  ];
  for (const result of report.results) {
    const missing = result.missingAssertions.map(escapeTable).join(", ") || "—";
    lines.push(
      `| ${result.id} | ${result.status === "passed" ? "PASS" : result.status.toUpperCase()} | ${result.durationMs} ms | ${missing} |`,
    );
  }

  const unsuccessful = report.results.filter(({ status }) => status !== "passed");
  if (unsuccessful.length > 0) {
    lines.push("", "## Failure details", "");
    for (const result of unsuccessful) {
      lines.push(
        `<details><summary>Eval ${result.id}: ${result.status}</summary>`,
        "",
        `**Prompt:** ${result.prompt}`,
        "",
        `**Error:** ${result.error ?? "Assertion mismatch"}`,
        "",
        "**Response:**",
        "",
        "```text",
        result.response.replaceAll("```", "` ` `"),
        "```",
        "",
        "**stderr:**",
        "",
        "```text",
        result.stderr.replaceAll("```", "` ` `"),
        "```",
        "",
        "</details>",
        "",
      );
    }
  }
  return `${lines.join("\n")}\n`;
}

export async function writeReports(report, outputDirectory) {
  await mkdir(outputDirectory, { recursive: true });
  const json = path.join(outputDirectory, "report.json");
  const markdown = path.join(outputDirectory, "report.md");
  await Promise.all([
    writeFile(json, `${JSON.stringify(report, null, 2)}\n`),
    writeFile(markdown, renderMarkdown(report)),
  ]);
  return { json, markdown };
}
