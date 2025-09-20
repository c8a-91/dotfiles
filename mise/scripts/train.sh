#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "${MISE_ORIGINAL_CWD:-$(pwd)}" && pwd)
if [ ! -f "$PROJECT_DIR/pyproject.toml" ]; then
  echo "train task must be run inside a generated project directory (pyproject.toml not found)." >&2
  exit 1
fi
cd "$PROJECT_DIR"
exec uv run -- python -m src.models "$@"
