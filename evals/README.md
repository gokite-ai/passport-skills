# Evals — Skills Regression Set

`evals.json` is the master list of behavioral eval scenarios for this repo's skills: 101 cases, each `{id, prompt, expected_output, assertions}`. There is currently **no automated runner in this repo**. Grading is manual: dispatch a subagent (or run the skill interactively) against each `prompt`, capture its response, and check that the response's actual behavior matches `expected_output` and that every string in `assertions` appears in it. Treat a failing assertion as a real regression, not noise — assertions are kept short and literal (command names, flag names, key output markers) specifically so they can be eyeballed against a transcript without ambiguity.

There used to be references here to a `functional-workspace/` transcript store, `grade_all.py`, `build_benchmark.py`, and a `RUNBOOK.md` describing an automated grading pipeline. None of that ever existed in this repo (checked against full git history) — it described tooling from a separate porting session that was never committed. This file now describes how grading actually happens today instead of pointing at nonexistent scripts.

## Coverage by skill

| id range | skill | group |
|---|---|---|
| 1-3 | activity | user |
| 4-6, 24-26 | authenticate-user | user |
| 7-8, 14-16, 31-32, 44-46, 51-52 | request-session | user |
| 9-11, 38-40, 49 | kite-discovery | user |
| 12-13, 29-30 | manage-agents | user |
| 17-19, 33-37, 48, 50 | shopping | user |
| 20-21, 27-28, 56 | wallet-send | user |
| 22-23, 41-43, 47 | x402-execute | user (15 moved out to request-session -- it tests session reuse, not payment execution) |
| 53-55 | attach-session | user |
| 57-60 | buyer-agent-setup | buyer-agent |
| 67-71 | buyer-find-seller | buyer-agent |
| 78-83 | buyer-purchase | buyer-agent |
| 61-64, 66 | seller-agent-setup | seller-agent |
| 65, 72-75, 77 | seller-fulfill | seller-agent |
| 84-88 | upgrade-passport | user |
| 89-92 | kite-passport (gateway routing) | user |
| 76, 93-97 | seller-serve | seller-agent |
| 98-101 | kite-seller | seller-agent |

`form-session-delegation`, `cloud-deploy`, and `report-feedback` have no evals and were explicitly out of scope for the 2026-08-28 correctness pass below.

## 2026-08-28 correctness audit

Every eval for `authenticate-user`, `request-session`, `manage-agents`, `kite-discovery`, `buyer-agent-setup`, `buyer-find-seller`, `buyer-purchase`, `seller-agent-setup`, and `seller-fulfill` was diffed against that skill's current `SKILL.md`/`references/*.md`. 19 evals had stale or wrong `expected_output`/`assertions` and were corrected in place (same ids, same structure) — the recurring bug patterns were:

- **Retired/renamed CLI syntax**: `ksearch services list`/`get --service-id` (plural, retired flag) → `ksearch service list`/`get <positional-id>` (ids 9-11, 38-39, 49); wrong health subcommand for a catalog-scoped question (id 40).
- **Default-flow drift**: `buyer-agent-setup`/`seller-agent-setup` moved their default bind path from direct `bind --wait` + passkey approval to mint-then-bind (`token create` → `bind --token`), which several evals still tested as the fallback path instead of the default (ids 58, 62).
- **Backwards polling logic**: `request-session` eval 31 asserted `--wait` on a status check the docs explicitly say should be a single check *without* `--wait` once the user has signaled approval.
- **Retired delegation field**: two evals (51, 52) asserted a `payment_policy.allowed_payment_approaches` field the skill's docs say must NOT be present — sessions are protocol-agnostic and the rail is detected automatically at execute time.
- **Missing mandatory flag**: `authenticate-user` evals 4/5/25 omitted the required `--client agent` flag on `signup init`/`login init`.
- **Skill misattribution after a new sibling skill shipped**: eval 76 tested `seller-fulfill`'s `kagent listen` as the default live-service loop, but `seller-serve` (added after this eval was written) made `kagent serve --handler` the default and demoted `listen` to an explicit-exception path — corrected in place to test `seller-serve`'s actual default.

`manage-agents` evals 13 and 30 also had inconsistent filter behavior for near-identical "active sessions" phrasing (13 omitted `--status active`, 30 included it) — aligned to match.

A follow-up review pass caught two more issues: eval 15 (moved here from x402-execute) described the pre-reuse-detection workflow -- `kpass agent:session list` first, then payment -- when `request-session/SKILL.md` now says reuse is checked automatically inside `agent:session create` and `list` is optional/diagnostic-only; and eval 76's skill-reassignment (seller-fulfill → seller-serve, see above) wasn't reflected in this table. Both are fixed now. A few new-eval assertions were also tightened from generic prose fragments (`"no permission"`, `"asks"`, a bare `"scope"`) to more literal, discriminating markers actually grounded in the skill docs.

`activity`, `attach-session`, `wallet-send`, `x402-execute`, and `shopping` were **not** audited in this pass and may carry similar drift — treat their evals with proportionally less confidence until they get the same treatment.

## Adding evals

Follow the existing objects' shape and terseness: `assertions` should be short literal substrings (command names, flag names, distinctive output markers) that would actually appear in a correct response — not full sentences. Ground every `expected_output`/`assertions` claim in the target skill's current `SKILL.md`/`references/*.md`; don't infer behavior from a prior eval version or from general plausibility.

## Routing evals

`routing-experiments/FINDINGS.md` documents a separate, harder problem: whether a skill *triggers* at all for a given natural-language prompt (as opposed to, given that it triggered, whether its behavior is correct — which is all `evals.json` tests). The external harness used for that (`~/.agents/skills/skill-creator/scripts/run_eval.py`) is structurally unable to detect triggers via `.claude/commands/` stubs against bare `claude -p` queries — see that file for the full mechanism and why the resulting 50%/0%-recall scores are an expected null result, not a skill-quality signal. No `trigger-evals/` directory exists in this repo for the same reason; `evals.json` is behavior-only.
