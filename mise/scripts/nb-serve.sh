#!/usr/bin/env bash
set -euo pipefail

# ACP agent options
AGENT=""
AGENT_PORT=""
AGENT_PID=""

cleanup() {
  set +e
  if [ -n "${AGENT_PID:-}" ]; then
    if kill -0 "$AGENT_PID" >/dev/null 2>&1; then
      # Try graceful shutdown of the agent bridge
      kill -TERM "$AGENT_PID" >/dev/null 2>&1 || true
      sleep 0.5
      # Ensure any child processes also receive TERM
      pkill -TERM -P "$AGENT_PID" >/dev/null 2>&1 || true
      sleep 0.3
      # Force kill as a last resort
      kill -KILL "$AGENT_PID" >/dev/null 2>&1 || true
      pkill -KILL -P "$AGENT_PID" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT INT TERM HUP QUIT

# Help/usage
print_help() {
  cat <<'EOF'
Usage: mise run nb-serve -- [options]

Options:
  -h, --help                 Show this help and exit
  --agent {claude|gemini}    Start ACP bridge for the agent before marimo
  --agent-port PORT          Port for the agent bridge (default: 3017 for claude, 3019 for gemini)

Environment:
  MiseMarimoPort             Port for marimo editor (default: 2718)

Notes:
  - Ensure the project has pyproject.toml and notebooks/eda.py
  - Enable Agents in marimo Settings > Lab, then select the agent in the sidebar
EOF
}

# Parse CLI options: --agent [claude|gemini], --agent-port <port>
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    --agent)
      if [ $# -lt 2 ]; then
        echo "--agent requires a value (claude|gemini)" >&2
        exit 2
      fi
      AGENT="$2"
      shift 2
      ;;
    --agent-port)
      if [ $# -lt 2 ]; then
        echo "--agent-port requires a port number" >&2
        exit 2
      fi
      AGENT_PORT="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      # Unknown option: stop parsing to avoid breaking future args
      break
      ;;
  esac
done

# Simple TCP port wait (uses bash's /dev/tcp)
wait_for_port() {
  local port="$1" timeout="${2:-10}" start elapsed
  start=$(date +%s)
  while true; do
    if (echo >"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1; then
      return 0
    fi
    elapsed=$(( $(date +%s) - start ))
    if [ "$elapsed" -ge "$timeout" ]; then
      return 1
    fi
    sleep 0.5
  done
}

PROJECT_DIR=$(cd "${MISE_ORIGINAL_CWD:-$(pwd)}" && pwd)
if [ ! -f "$PROJECT_DIR/pyproject.toml" ]; then
  echo "nb-serve must be run inside a generated project directory (pyproject.toml not found)." >&2
  exit 1
fi
if [ ! -f "$PROJECT_DIR/notebooks/eda.py" ]; then
  echo "notebooks/eda.py not found in $PROJECT_DIR; did you run kaggle-init?" >&2
  exit 1
fi
# If an ACP agent was requested, start it in the background
if [ -n "${AGENT:-}" ]; then
  case "$AGENT" in
    claude)
      if [ -z "${AGENT_PORT:-}" ]; then AGENT_PORT=3017; fi
      npx stdio-to-ws "npx @zed-industries/claude-code-acp" --port "$AGENT_PORT" >/dev/null 2>&1 &
      AGENT_PID=$!
      ;;
    gemini)
      if [ -z "${AGENT_PORT:-}" ]; then AGENT_PORT=3019; fi
      npx stdio-to-ws "npx @google/gemini-cli --experimental-acp" --port "$AGENT_PORT" >/dev/null 2>&1 &
      AGENT_PID=$!
      ;;
    *)
      echo "Unsupported agent: $AGENT (supported: claude, gemini)" >&2
      exit 2
      ;;
  esac
  # Best-effort wait for the agent port to become available
  if ! wait_for_port "$AGENT_PORT" 10; then
    echo "Warning: agent '$AGENT' did not open port $AGENT_PORT within timeout; marimo may fail to connect." >&2
  fi
fi

PORT=${MiseMarimoPort:-2718}
cd "$PROJECT_DIR"
# Don't exec marimo so traps run and cleanup executes on Ctrl-C and other signals
PYTHONPATH="$PROJECT_DIR${PYTHONPATH:+:$PYTHONPATH}" uv run -- marimo edit notebooks/eda.py --port "$PORT"
