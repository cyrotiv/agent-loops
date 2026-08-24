# Implementation Plan: Agent Loops for Building a New Mobile App

**Models:** Kimi K3 (planner / generator / visual evaluator) + GLM-5.2 (code evaluator)
**Method:** Karpathy `loops.md` harness design + scheduled loops from the Hanako article
**Status:** Draft for review

Guiding rules, condensed from the two sources:

- Write the loop, not the prompt. The loop is: gather, reason, act, verify, repeat.
- Separate roles: planner, generator, evaluator. A model never grades its own work.
- Negotiate a testable contract before any code is written.
- State lives on disk, never in context. Three files should be enough to resume after a crash.
- Let failed runs restart from disk state instead of patching forever.
- Keep traces of everything; debug by reading transcripts, not by re-prompting by vibe.
- Start with one loop. Add loops only after the previous one earns trust.
- Human approves the risky 5% (merges to main, first runs, store submissions); agents do the boring 95%.
- Re-audit the harness on every model upgrade and delete what the model now does for free.
- The bottleneck always moves; the loop's job is to make the next one visible.

---

## Role assignment

| Role | Model | Why |
|-|-|-|
| Planner | Kimi K3 | Long-horizon reasoning, 1M context holds the whole spec + repo |
| Generator | Kimi K3 | Tuned for long-horizon coding sessions |
| Code evaluator | GLM-5.2 | Different model family (kills self-grading sycophancy), ~1/6 the cost, runs every iteration |
| Visual evaluator | Kimi K3 | Native vision for screenshot review against the taste rubric |

---

## Phase 0 — Scaffold the state layer (manual, ~30 min)

Empty git repo plus:

```
SPEC.md                 # one paragraph: what the app is, who it is for, platforms
contract.md             # negotiated checklist of testable assertions (starts empty)
feature_list.json       # machine-readable queue: id, desc, status, test
progress.md             # what is done, what is next, current blockers
log.md                  # append-only: ## [YYYY-MM-DD] op | title
rubric.md               # taste rubric: design / originality / craft / functionality, weighted,
                        # calibrated against 3 good reference apps + 3 slop examples
prompts/planner.md
prompts/generator.md
prompts/evaluator.md
research/               # Phase 1 outputs: features.md, competitors.md, user-flows.md, …
traces/                 # raw session transcripts, one file per run
loop.sh                 # the build while-loop
eval.sh                 # the evaluation pass
```

`SPEC.md` holds the raw idea as given; Phase 1 refines it. Test tooling (Maestro vs native frameworks) follows from the platform decision in Sub-loop 1.2 — default: Expo + EAS with Maestro.

Human reviews `SPEC.md` and `rubric.md` before anything runs. These two files are the boundary everything else respects.

## Phase 1 — Discover & refine (human + Kimi K3)

Rationale: a vague idea refined badly poisons the feature list and contract negotiation downstream, so requirements are built iteratively with the human before any code. Sub-loop 1.0 always runs; 1.1–1.4 are conditional — skip whatever is already decided. Keep this lightweight: short documents, one human gate each.

**Sub-loop 1.0 — Idea extraction (always runs).** Attended and conversational — this is the one phase where the agent questions the human directly, so it runs as an interactive `kimi` session, not headless. Mechanics:

- **Start:** the human writes the raw idea into `SPEC.md` (one paragraph, vague is fine) and opens an interactive planner session with `prompts/planner.md`. The planner parses the idea into explicit statements, surfaces implied features (e.g. "social app" implies auth, profiles, feed), and asks clarifying questions in batches: who are the users, what is the core action, backend needed, offline, auth, payments, platform(s), simplest version that delivers value. Expect 30–90 min of dialogue.
- **Middle:** the human answers; the planner refines, maintaining a running draft of `research/features.md` — app concept, P0 (MVP) / P1 (post-MVP) / P2 (future) features with rough complexity + dependencies, explicit non-goals.
- **End (concrete exit condition, not vibes):** no material ambiguities remain (every question answered or deliberately parked in `## Open Questions` with human acknowledgment) → planner finalizes `features.md` → human reviews, requests changes if any → human records approval mechanically (an `Approved: <date>` line in the file). Approval seeds `feature_list.json` from the P0 list and unlocks 1.1–1.4.
- **Failure modes:** ending too early (planner accepts "whatever you think" without surfacing tradeoffs — the think-before-coding agreement exists for this) or never ending (marginal questions forever; the valve is demoting uncertain items to P1/P2 or Open Questions instead of blocking the gate).

**Sub-loops 1.1–1.4 — conditional, run only what's needed:**

- **1.1 Competitor analysis** → `research/competitors.md`. Skip if positioning is already decided. Hallucination risk: the human verifies named competitors actually exist. Gate: pick the differentiator.
- **1.2 Platform decision** → `research/platform-decision.md`. Skip if already chosen. Default: Expo + EAS — one-command cloud builds, managed signing, `eas submit`, OTA updates, and a small config surface (fewer LLM misconfiguration errors). Override only for custom native modules or background-service limits. Gate: human locks the platform.
- **1.3 User flow mapping** → `research/user-flows.md`. Skip if flows are already mapped. Every journey (onboarding, core actions, settings) with happy paths and error/empty/loading states. A missed flow = a missing screen later. Gate: approve flows.
- **1.4 Technical feasibility** → `research/feasibility.md`. Only for niche APIs (HealthKit, BLE, CarPlay, background services); standard CRUD/auth/camera/GPS/push skips this. LLMs overclaim on niche APIs — human sanity-checks. Gate: pivot or de-scope before code if infeasible.

**Phase 1 exit criteria:** `features.md` approved; conditional sub-loops completed or explicitly skipped; research claims spot-checked. The approved P0 list becomes `feature_list.json`; `progress.md` and `log.md` are seeded. This is the last fully manual gate until merge.

## Phase 2 — Contract negotiation (2–3 rounds, K3 vs GLM-5.2)

- Generator (K3) proposes in `contract.md` what "done" looks like per feature.
- Evaluator (GLM-5.2, separate session, system prompt: *the code is broken, your job is to prove it*) pushes back: vague criteria get rejected, missing edge cases added.
- They argue via `contract.md` on disk until it holds ~20–30 testable assertions. Ten is too few (evaluator rubber-stamps); aim for assertions that are mechanical, not judgment calls.
- Human arbitrates deadlocks only.

Target contract shape for mobile:

1. App builds for target platform(s), zero warnings on lint/typecheck.
2. Unit/component tests green (Jest/Vitest or XCTest/Espresso).
3. Maestro flows pass on a clean simulator (one YAML flow per core user journey).
4. Screenshot review passes the rubric threshold.

## Phase 3 — The build loop (inner while-loop)

`loop.sh`:

```bash
#!/bin/bash
while ! grep -qx "DONE" progress.md; do
  ts=$(date +%Y%m%d-%H%M%S)
  kimi -p "$(cat prompts/generator.md)" > "traces/${ts}-generator.log" 2>&1
  sleep 10
done
```

The generator prompt enforces, every iteration:

1. Read `feature_list.json`, `progress.md`, `contract.md` first — nothing else is trusted memory.
2. Pick the single next unfinished feature.
3. Boot/reset the simulator to a clean state.
4. Implement it. Run build + unit tests + the relevant Maestro flow. Fix what broke.
5. Update `feature_list.json` and `progress.md`; append to `log.md`; commit with a clear message.
6. If every feature in `feature_list.json` passes the contract, write `DONE` as the last line of `progress.md` and stop.

Restart policy (§V): if a run goes sideways (repeated failing tests, patch-on-patch churn visible in the trace), the next iteration deletes the feature's changes and rebuilds from the state files rather than patching. Do not interrupt restarts — that is the loop working correctly. Interrupt only when the *contract itself* is wrong.

**Generator working agreements** (baked into `prompts/generator.md` verbatim at scaffold time):

- **Think before coding, adapted for unattended runs.** Reason from first principles — start from the actual problem and its constraints, not from the most familiar pattern; the obvious library or architecture is a hypothesis to check, not a default. State assumptions explicitly; present multiple interpretations instead of picking silently; push back when a simpler approach exists. In Phases 1–2 (human present): ask when uncertain, stop when confused. In the build loop (no human present): record the ambiguity, the chosen interpretation, and the rejected alternatives in `progress.md`, flag it for morning review, and continue. Exception — confusion at the *contract* level still stops the loop cold (§V: insert a human when the contract itself is wrong).
- **Simplicity first.** Minimum code that solves the problem: no unrequested features, no single-use abstractions, no speculative "configurability," no error handling for impossible scenarios. If 200 lines could be 50, rewrite it. Test: would a senior engineer call this overcomplicated?
- **Surgical changes.** Touch only what the current feature requires; don't "improve" adjacent code, refactor what isn't broken, or reformat. Match existing style. Clean up only orphans your own changes created; mention pre-existing dead code in `log.md`, don't delete it. Every changed line traces to the current feature.
- **Goal-driven execution — the definition of done.** A feature is never done on the strength of "I implemented it." Done means: a check tied to a specific `contract.md` line exists and passes (test written for the failing/invalid case first, then made to pass). Refactors require green tests before and after.

## Phase 4 — The evaluation loop (GLM-5.2 + K3 vision)

Runs after each build iteration, or on a cron interval (e.g. every 30 min during overnight runs):

- **Code evaluation (GLM-5.2):** reads `contract.md`, runs the build, unit tests, and every Maestro flow on a clean simulator. Appends pass/fail per assertion to `log.md`, writes failures to `progress.md` as blockers for the generator.
- **Visual evaluation (Kimi K3):** captures a screenshot per screen, reviews against `rubric.md`, outputs a 0–1 score plus a paragraph explaining the gap. Appends to `log.md`.
- Loop until all contract assertions pass and the rubric score crosses the threshold set in Phase 0.

Evaluation tooling note: Maestro flows are YAML and agent-writable — the evaluator may add flows for new features, but additions to `contract.md` assertions still require the negotiation in Phase 2, not unilateral edits.

Evaluator working agreements: pass/fail verdicts must cite a specific contract line or test run — never an impression ("looks fine" is not a verdict). When writing or repairing Maestro flows, the evaluator follows the same simplicity-first and surgical-change rules as the generator. Suspected generator over-engineering is reported as a finding in `log.md`, not fixed by the evaluator — roles stay separated.

## Phase 5 — Outer loops (only after Phases 3–4 are trusted)

Add one at a time, each boring, bounded, and verifiable at a glance:

1. **CI watcher** (every few minutes): fix failing CI on open branches.
2. **Flaky-test patcher** (nightly): quarantine and repair flaky Maestro flows/unit tests.
3. **Digest** (nightly): summarize `log.md` into a morning report.
4. Later: feedback clusterer once the app has users.

Each loop gets a narrow written job in its own prompt file. "Improve the codebase" is a wish, not a loop.

## Phase 6 — Move off the laptop

Once the build/eval loops run unattended locally, move them to a server (cron or CI schedules, webhook triggers) so they survive the laptop closing. Human gates that remain regardless of where loops run:

- Merge to `main`.
- First run of any new loop.
- Anything touching signing keys, store submissions, or production data.

---

## Standing operational rules

**Traces (§VII).** Every run writes its raw transcript to `traces/`. When output diverges from expectation, grep the trace for the exact moment judgment went wrong, fix the prompt at that point, rerun. `log.md` is the agent's memory; traces are yours. Never tune by vibe.

**Harness audits (§VIII).** Every piece of scaffolding is tagged with the model limitation it compensates for. On each model upgrade (K3.x, GLM-5.3, …), re-test each assumption by removing the workaround and watching traces; delete what the model now does for free. Known candidate already: aggressive context chunking/summarization, given both models' 1M-token windows. A harness that only grows is a harness nobody is reading.

**Bottleneck checks (§IX).** After every improvement, ask: what is the slowest or most failure-prone stage now? Instrument it, fix it, ship a smaller harness, repeat. Coding → planning → verification → taste is the expected progression. If everything feels smooth, the bottleneck is somewhere you are not measuring.

## Decisions locked (2026-07-31)

- **Platform:** Expo + EAS confirmed (Sub-loop 1.2 default; no native-module/background-service overrides).
- **Evaluator invocation:** GLM-5.2 as an OpenAI-compatible custom provider in Kimi Code `config.toml` (`[providers.zai]` + `[models."zai/glm-5.2"]` alias). `eval.sh` calls `kimi -m "zai/glm-5.2" -p "$(cat prompts/evaluator.md)"`; generator runs on the default model (K3). Headless `-p` mode confirmed: streams to stdout, auto permission policy, full tool use. Prerequisite: a Z.ai API key.
- **Run location:** this Mac first; server move happens in Phase 6 once loops earn trust. Keep the Mac awake during overnight runs.
- **Human gates (the risky 5%):** merges to `main`; first run of any new loop; signing/store submissions; new dependency installs; any `contract.md` edit; anything touching real user data, payments, or secrets.

## Open questions remaining

- [ ] Rubric calibration: name the 3 good + 3 slop reference apps. Threshold score is *not* fixed upfront — run the visual evaluator against the six references first; if it can't rank the calibration set correctly, fix the rubric text, then set the threshold at the worst "good" reference's score minus a small margin.
