#!/usr/bin/env bash
# Parallelisatie helper voor fleet-manager scripts

MAX_JOBS="${MAX_JOBS:-4}"

run_parallel() {
  local func="$1"
  shift
  local items=("$@")
  local pids=()
  
  for item in "${items[@]}"; do
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
      sleep 0.1
    done
    "$func" "$item" &
    pids+=($!)
  done
  
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
}

run_parallel_with_timeout() {
  local func="$1"
  local timeout="$2"
  shift 2
  local items=("$@")
  local pids=()
  
  for item in "${items[@]}"; do
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
      sleep 0.1
    done
    (
      timeout "$timeout" "$func" "$item"
    ) &
    pids+=($!)
  done
  
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
}
