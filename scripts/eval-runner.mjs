#!/usr/bin/env node

import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  loadEvalCases,
  runEvalSuite,
  writeReports,
} from "./eval-runner-lib.mjs";

const usage = `Usage:
  node scripts/eval-runner.mjs --adapter <executable> [options]

The adapter receives the eval prompt on stdin and writes the agent transcript to
stdout. EVAL_ID is provided for correlation; grading criteria stay private.

Options:
  --adapter <path>       Adapter executable (required)
  --adapter-arg <value>  Argument passed to the adapter; repeat as needed
  --input <path>         Eval JSON file (default: evals/evals.json)
  --output-dir <path>    Report directory (default: eval-results)
  --timeout-ms <number>  Per-case timeout (default: 120000)
  --jobs <number>        Concurrent adapter processes (default: 1)
  --case <id>            Run one eval id; repeat to select multiple
  --help                 Show this help
`;

function readValue(argv, index, option, allowOptionValue = false) {
  const value = argv[index + 1];
  if (value === undefined || (!allowOptionValue && value.startsWith("--"))) {
    throw new Error(`${option} requires a value`);
  }
  return value;
}

function parsePositiveInteger(value, option) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`${option} must be a positive integer`);
  }
  return parsed;
}

export function parseArgs(argv) {
  const options = {
    adapterArgs: [],
    input: "evals/evals.json",
    outputDirectory: "eval-results",
    timeoutMs: 120_000,
    jobs: 1,
    caseIds: [],
  };

  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option === "--help") return { help: true };
    if (option === "--adapter") {
      options.adapter = readValue(argv, index, option);
      index += 1;
    } else if (option === "--adapter-arg") {
      options.adapterArgs.push(readValue(argv, index, option, true));
      index += 1;
    } else if (option === "--input") {
      options.input = readValue(argv, index, option);
      index += 1;
    } else if (option === "--output-dir") {
      options.outputDirectory = readValue(argv, index, option);
      index += 1;
    } else if (option === "--timeout-ms") {
      options.timeoutMs = parsePositiveInteger(
        readValue(argv, index, option),
        option,
      );
      index += 1;
    } else if (option === "--jobs") {
      options.jobs = parsePositiveInteger(readValue(argv, index, option), option);
      index += 1;
    } else if (option === "--case") {
      options.caseIds.push(
        parsePositiveInteger(readValue(argv, index, option), option),
      );
      index += 1;
    } else {
      throw new Error(`unknown option: ${option}`);
    }
  }
  if (!options.adapter) throw new Error("--adapter is required");
  return options;
}

async function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n\n${usage}`);
    process.exitCode = 2;
    return;
  }
  if (options.help) {
    process.stdout.write(usage);
    return;
  }

  try {
    const allCases = await loadEvalCases(options.input);
    const selected =
      options.caseIds.length === 0
        ? allCases
        : allCases.filter(({ id }) => options.caseIds.includes(id));
    const missingIds = options.caseIds.filter(
      (id) => !selected.some((evalCase) => evalCase.id === id),
    );
    if (missingIds.length > 0) {
      throw new Error(`unknown eval id(s): ${missingIds.join(", ")}`);
    }

    const report = await runEvalSuite(selected, options);
    const reports = await writeReports(report, options.outputDirectory);
    const percentage = (report.summary.passRate * 100).toFixed(2);
    process.stdout.write(
      `Evaluated ${report.summary.total} case(s): ${report.summary.passed} passed (${percentage}%).\n` +
        `JSON: ${path.resolve(reports.json)}\n` +
        `Markdown: ${path.resolve(reports.markdown)}\n`,
    );
    if (report.summary.passed !== report.summary.total) process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`Eval runner error: ${error.message}\n`);
    process.exitCode = 2;
  }
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))
) {
  await main();
}
