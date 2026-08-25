#!/bin/bash
# Phase 3 build loop (PLAN.md). Runs the generator until progress.md says DONE.
while ! grep -qx "DONE" progress.md; do
  ts=$(date +%Y%m%d-%H%M%S)
  kimi -p "$(cat prompts/generator.md)" > "traces/${ts}-generator.log" 2>&1
  sleep 10
done
