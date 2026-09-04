#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

while IFS= read -r file; do
  if ! awk '
    function is_public(line) {
      return line ~ /^[[:space:]]*public[[:space:]]+(module|class|interface|enum|declare|const|function|method|var)([[:space:]]|$)/
    }

    function is_module(line) {
      return line ~ /^[[:space:]]*(public[[:space:]]+)?module[[:space:]]+/
    }

    {
      if ($0 ~ /^[[:space:]]*\/\// && prior_line ~ /^[[:space:]]*\/\//) {
        printf "%s:%d: multi-line comment must use block syntax\n", FILENAME, NR
        failed = 1
      }
      if (is_module($0) && prior_line !~ /^[[:space:]]*\*\/[[:space:]]*$/) {
        printf "%s:%d: module needs an adjacent block comment\n", FILENAME, NR
        failed = 1
      }
      if (is_public($0) && previous !~ /^[[:space:]]*(\/\/|\*\/)/) {
        printf "%s:%d: public declaration needs a preceding comment\n", FILENAME, NR
        failed = 1
      }
      if ($0 !~ /^[[:space:]]*$/) {
        previous = $0
      }
      prior_line = $0
    }

    END { exit failed }
  ' "$file"; then
    status=1
  fi
done < <(find "$root" -type f -name '*.sun' -not -path '*/.git/*' | sort)

if ((status != 0)); then
  echo "Sun public declarations must have concise, plain-English comments." >&2
  exit "$status"
fi

echo "Sun comment policy check passed."
