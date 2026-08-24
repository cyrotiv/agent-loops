# Versions & Changes

This repo is a collection of notes and plans on long-running agent loops. This file tracks the versions of the working documents.

## Contents of this repo

| File | What it is |
|-|-|
| `loops.md` | Andrej Karpathy's field notes on agent harness design (source material) |
| `loops.md.karpathy.png` | Karpathy's original `loops.md` post as an image (source material) |
| `claude-loops-while-you-sleep.md` | Hanako's step-by-step article on scheduled Claude loops (source material) |
| `PLAN.md` | Current implementation plan (v1) — agent loops for building a mobile app |
| `PLAN_v0.md` | First draft of the implementation plan, kept for history |

## Plan versions

### v1 — `PLAN.md` (2026-08-01)

Current version. Builds on the same skeleton as v0 (Phases 0–6, role split between Kimi K3 and GLM-5.2, contract negotiation, disk state) with four substantive changes:

- **Phase 1 rewritten: one-shot planning → iterative discovery.** v0 ran the planner once to turn `SPEC.md` into a feature list. v1 replaces this with attended sub-loops run with the human: 1.0 idea extraction (interactive, with a concrete exit condition), plus conditional 1.1 competitor analysis, 1.2 platform decision, 1.3 user flow mapping, 1.4 technical feasibility — each with its own human gate. Rationale: a vague idea refined badly poisons the feature list and contract negotiation downstream.
- **Working agreements added for both agents.** Phase 3 gains explicit generator rules (think before coding, simplicity first, surgical changes, goal-driven definition of done). Phase 4 gains evaluator rules (verdicts must cite a contract line, never an impression; report over-engineering, don't fix it).
- **Platform decision deferred and defaulted.** v0 locked the stack choice at Phase 0 (default React Native + Maestro). v1 moves it into Sub-loop 1.2 with a default of Expo + EAS (cloud builds, managed signing, OTA) and adds `research/` to the Phase 0 scaffold to hold discovery outputs.
- **Open questions resolved.** v0 listed five open questions; v1 records its answers in `Decisions locked (2026-07-31)`: Expo + EAS confirmed; GLM-5.2 invoked as an OpenAI-compatible custom provider in Kimi Code (`zai/glm-5.2`); runs on this Mac until Phase 6; explicit human-gate list. One question remains: rubric calibration (reference apps + threshold score), now with a defined procedure for setting the threshold.

### v0 — `PLAN_v0.md` (2026-08-01, superseded)

First draft. Same guiding rules and six-phase structure, but Phase 1 was a single unattended planner run, the agents had no written working agreements, and the stack / evaluator-invocation / run-location questions were still open. Kept for comparison with v1.
