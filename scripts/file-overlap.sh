#!/usr/bin/env bash
# scripts/file-overlap.sh — Detect file-level overlap between two git refs.
# Source: ClawTeam clawteam/workspace/conflicts.py:15-114
# Usage:
#   scripts/file-overlap.sh check <ref1> <ref2> [--base BASE]
#   scripts/file-overlap.sh --help
set -euo pipefail

cmd_help() {
  cat <<EOF
Usage: file-overlap.sh check <ref1> <ref2> [--base BASE]

Detects file overlap between two git refs (relative to a common base).
Output: markdown table with severity per file (high if same lines, medium if same file).

  --base BASE   Common ancestor (default: \$(git merge-base ref1 ref2))
  --help        This message
EOF
}

# Parse `git diff -U0 BASE..REF` and emit lines: "FILE\tSTART\tCOUNT"
parse_hunks() {
  local base="$1"
  local ref="$2"
  local cur_file=""
  git diff -U0 "$base..$ref" 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ ^\+\+\+\ b/(.+)$ ]]; then
      cur_file="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^@@\ -[0-9,]+\ \+([0-9]+)(,([0-9]+))?\ @@ ]]; then
      local start="${BASH_REMATCH[1]}"
      local count="${BASH_REMATCH[3]:-1}"
      [ "$count" = "0" ] && count="1"
      printf '%s\t%s\t%s\n' "$cur_file" "$start" "$count"
    fi
  done
}

# Check if two ranges (start1, count1) and (start2, count2) intersect
# Range A is [start1, start1+count1-1]; Range B is [start2, start2+count2-1]
ranges_intersect() {
  local s1="$1" c1="$2" s2="$3" c2="$4"
  local e1=$((s1 + c1 - 1))
  local e2=$((s2 + c2 - 1))
  [ "$s1" -le "$e2" ] && [ "$s2" -le "$e1" ]
}

cmd_check() {
  local ref1="$1"; shift
  local ref2="$1"; shift
  local base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) base="$2"; shift 2;;
      *) echo "unknown flag: $1" >&2; return 1;;
    esac
  done
  if [ -z "$base" ]; then
    base=$(git merge-base "$ref1" "$ref2" 2>/dev/null || echo "$ref1")
  fi

  local h1; h1=$(parse_hunks "$base" "$ref1")
  local h2; h2=$(parse_hunks "$base" "$ref2")

  if [ -z "$h1" ] || [ -z "$h2" ]; then
    echo "No overlap (one or both refs have no diff vs base $base)"
    return 0
  fi

  # Get file lists
  local files1; files1=$(printf '%s\n' "$h1" | cut -f1 | sort -u)
  local files2; files2=$(printf '%s\n' "$h2" | cut -f1 | sort -u)
  local common; common=$(comm -12 <(printf '%s\n' "$files1") <(printf '%s\n' "$files2"))

  if [ -z "$common" ]; then
    echo "No overlap (no shared files)"
    return 0
  fi

  printf '| File | Severity | %s lines | %s lines |\n' "$ref1" "$ref2"
  printf '|------|----------|------------|------------|\n'
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local hunks1; hunks1=$(printf '%s\n' "$h1" | awk -v f="$f" -F'\t' '$1==f { print $2","$3 }')
    local hunks2; hunks2=$(printf '%s\n' "$h2" | awk -v f="$f" -F'\t' '$1==f { print $2","$3 }')
    local severity="medium"
    while IFS= read -r hr1; do
      [ -z "$hr1" ] && continue
      local s1; s1=$(echo "$hr1" | cut -d, -f1)
      local c1; c1=$(echo "$hr1" | cut -d, -f2)
      while IFS= read -r hr2; do
        [ -z "$hr2" ] && continue
        local s2; s2=$(echo "$hr2" | cut -d, -f1)
        local c2; c2=$(echo "$hr2" | cut -d, -f2)
        if ranges_intersect "$s1" "$c1" "$s2" "$c2"; then
          severity="high"
        fi
      done <<< "$hunks2"
    done <<< "$hunks1"
    local lines1; lines1=$(printf '%s\n' "$hunks1" | tr '\n' ',' | sed 's/,$//')
    local lines2; lines2=$(printf '%s\n' "$hunks2" | tr '\n' ',' | sed 's/,$//')
    printf '| %s | %s | %s | %s |\n' "$f" "$severity" "$lines1" "$lines2"
  done <<< "$common"
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    check) cmd_check "$@";;
    help|-h|--help) cmd_help;;
    *) echo "unknown command: $cmd" >&2; cmd_help; exit 1;;
  esac
}

main "$@"
