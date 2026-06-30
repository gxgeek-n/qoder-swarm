#!/usr/bin/env bash
# scripts/swarm-cost.sh — Aggregate dispatch log into cost summary.
# Reads .swarm/audit/dispatches.jsonl (written by hooks/agent-dispatch-log.sh).
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"
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
