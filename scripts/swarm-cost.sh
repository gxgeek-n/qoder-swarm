#!/usr/bin/env bash
# scripts/swarm-cost.sh — Aggregate dispatch log into cost summary.
# Reads .swarm/audit/dispatches.jsonl (written by hooks/agent-dispatch-log.sh).
# Also supports --error-rate to show per-model error rates from attempts.jsonl.
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"

# ── --error-rate: per-model error breakdown ──────────────────────────
if [[ "${1:-}" == "--error-rate" ]]; then
  AUDIT_FILE="${SWARM_HOME}/.swarm/audit/attempts.jsonl"

  # Parse --since flag (default: 24h)
  SINCE="24h"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) SINCE="${2:-24h}"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Convert since duration to seconds
  case "$SINCE" in
    *h) SINCE_SECS=$(( ${SINCE%h} * 3600 )) ;;
    *d) SINCE_SECS=$(( ${SINCE%d} * 86400 )) ;;
    *)  SINCE_SECS=86400 ;;
  esac

  if [ ! -f "$AUDIT_FILE" ]; then
    echo "No audit data yet — run some swarm dispatches to accumulate data."
    exit 0
  fi

  echo "=== Error rate — last ${SINCE} ==="
  echo ""
  printf "%-30s %-5s  %-6s  %-5s    %s\n" "Model" "Total" "Errors" "Rate" "Common errors"
  printf '%s\n' '─────────────────────────────────────────────────────────────────────'

  jq -s -r --argjson since_secs "$SINCE_SECS" '
    def rate(errors; total):
      if total == 0 then "0.0%"
      else
        ((errors * 1000 / total + 0.5) | floor) as $p |
        "\($p / 10 | floor).\($p % 10)%"
      end;

    (now - $since_secs) as $cutoff |
    map(select((.ts | fromdateiso8601) > $cutoff)) |
    group_by(.model) |
    map({
      model: .[0].model,
      total: length,
      errors: (map(select(.status != "completed")) | length),
      common: (
        map(select(.status != "completed"))
        | group_by(.error_class // "unknown")
        | map({class: (.[0].error_class // "unknown"), count: length})
        | sort_by(-.count)
        | map("\(.class)(\(.count))")
        | join(", ")
      )
    }) |
    . as $rows |
    ($rows | map(.total) | add // 0) as $gt |
    ($rows | map(.errors) | add // 0) as $ge |
    ($rows[] | [.model, (.total | tostring), (.errors | tostring), rate(.errors; .total), (if (.common // "") == "" then "—" else .common end)] | @tsv),
    (["__TOTAL__", ($gt | tostring), ($ge | tostring), rate($ge; $gt), ""] | @tsv)
  ' "$AUDIT_FILE" | while IFS=$'\t' read -r model total errors rate common; do
    if [ "$model" = "__TOTAL__" ]; then
      echo ""
      echo "Total: ${total} dispatches, ${errors} errors (${rate})"
    else
      printf "%-30s %-5s  %-6s  %-5s    %s\n" "$model" "$total" "$errors" "$rate" "$common"
    fi
  done

  exit 0
fi

# ── Default: dispatch cost summary ───────────────────────────────────
LOG_FILE="${SWARM_HOME}/.swarm/audit/dispatches.jsonl"

if [ ! -f "$LOG_FILE" ]; then
  echo "No dispatch log found at $LOG_FILE"
  echo "Install hooks/agent-dispatch-log.sh to start collecting data."
  exit 0
fi

echo "=== Dispatch Cost Summary ==="
echo ""
echo "Total dispatches: $(wc -l < "$LOG_FILE" | tr -d ' ')"
echo ""
echo "By model:"
jq -r '.model' "$LOG_FILE" | sort | uniq -c | sort -rn | sed 's/^/  /'
echo ""
echo "By agent:"
jq -r '.agent' "$LOG_FILE" | sort | uniq -c | sort -rn | sed 's/^/  /'
echo ""
echo "Estimated credits (rough):"
# Credit multipliers: Qwen3.7-Max-DogFooding=0, GLM-5.2=0.6, Ultimate=1.0, DeepSeek-V4-Flash=0.1
jq -r '.model' "$LOG_FILE" | awk '
  /Qwen3.7-Max-DogFooding/ { free++ }
  /GLM-5.2/ { mid += 0.6 }
  /Ultimate/ { heavy += 1.0 }
  /DeepSeek-V4-Flash/ { cheap += 0.1 }
  /inherit/ { unknown++ }
  END {
    total = free * 0 + mid + heavy + cheap
    printf "  Free (Qwen): %d calls x 0.00x = 0\n", free
    printf "  Mid (GLM-5.2): %.0f calls x 0.60x = %.1f\n", mid/0.6, mid
    printf "  Heavy (Ultimate): %.0f calls x 1.00x = %.1f\n", heavy, heavy
    printf "  Cheap (DeepSeek): %.0f calls x 0.10x = %.1f\n", cheap/0.1, cheap
    printf "  Unknown (inherit): %d calls\n", unknown
    printf "  ---------------------------------\n"
    printf "  Estimated total: %.1f credits\n", total
  }
'
