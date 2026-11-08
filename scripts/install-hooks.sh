#!/usr/bin/env bash
# Install a git pre-push hook that runs the local test suite (CI is manual-only on GitHub).
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$(git -C "$ROOT" rev-parse --git-path hooks)/pre-push"
mkdir -p "$(dirname "$hook")"
cat > "$hook" <<H
#!/usr/bin/env bash
exec bash "$ROOT/tests/run.sh"
H
chmod +x "$hook"
echo "installed $hook"
