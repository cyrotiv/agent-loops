#!/bin/bash
# Phase 4 evaluation pass (PLAN.md). Code eval runs on GLM-5.2 via the
# zai/glm-5.2 provider alias. NOTE: provider is configured before Phase 2,
# not at scaffold time — this script will fail until then.
ts=$(date +%Y%m%d-%H%M%S)
kimi -m "zai/glm-5.2" -p "$(cat prompts/evaluator.md)" > "traces/${ts}-evaluator.log" 2>&1
