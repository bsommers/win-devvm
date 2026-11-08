#!/usr/bin/env bash
# Syntax check: `bash -n` on every *.sh in the repo; shellcheck if installed.
# Plain bash (3.2 compatible). Exit status: 0 if all checks pass, 1 otherwise.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0
files=()
while IFS= read -r f; do
  files+=("$f")
done <<EOF
$(find "$ROOT" \( -name .git -o -name .claude \) -prune -o -name '*.sh' -type f -print | sort)
EOF

if [ "${#files[@]}" -eq 0 ]; then
  echo "FAIL  no *.sh files found under $ROOT"
  exit 1
fi

errf="$(mktemp "${TMPDIR:-/tmp}/syntax.XXXXXX")"
for f in "${files[@]}"; do
  rel="${f#"$ROOT"/}"
  if bash -n "$f" 2>"$errf"; then
    echo "PASS  bash -n $rel"
  else
    echo "FAIL  bash -n $rel"
    sed 's/^/      /' "$errf"
    rc=1
  fi
done
rm -f "$errf"

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "${files[@]}"; then
    echo "PASS  shellcheck (${#files[@]} files)"
  else
    echo "FAIL  shellcheck"
    rc=1
  fi
else
  echo "SKIP  shellcheck: not installed"
fi

exit $rc
