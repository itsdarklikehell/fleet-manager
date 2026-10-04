#!/usr/bin/env bash
# Structured logging helper voor fleet-manager scripts

LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FORMAT="${LOG_FORMAT:-json}"  # json, text

log_structured() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date -Iseconds)
  
  case "$LOG_FORMAT" in
    json)
      echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}" >> "$LOG_FILE"
      ;;
    text)
      echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
      ;;
  esac
}

log_debug() { [ "$LOG_LEVEL" = "DEBUG" ] && log_structured "DEBUG" "$1" || true; }
log_info() { log_structured "INFO" "$1"; }
log_warn() { log_structured "WARN" "$1"; }
log_error() { log_structured "ERROR" "$1"; }
