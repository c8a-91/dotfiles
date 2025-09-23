#!/usr/bin/env bash
set -euo pipefail

print_help() {
  cat <<EOF
Run marimo notebook server with optional agent integration

This starts the marimo notebook server for EDA with configurable options
and optional integration with AI coding agents like Claude or Gemini.

Usage:
  mise run nb-serve [options]

Examples:
  # Start marimo with default settings
  mise run nb-serve

  # Start on all interfaces with custom port
  mise run nb-serve --host 0.0.0.0 --port 3000

  # Start with Claude agent
  mise run nb-serve --agent claude

  # Use Claude agent on custom port
  mise run nb-serve --agent claude --agent-port 3018

  # Start with Gemini agent
  mise run nb-serve --agent gemini

Options:
  -h, --help                 Show this help message
  -p, --port PORT            Port for marimo editor (default: 2718 or MiseMarimoPort)
  -H, --host HOST            Host for marimo editor (default: localhost or MiseMarimoHost)
  --agent TYPE               Launch an AI coding agent (claude or gemini)
  --agent-port PORT          Port for the agent bridge (default: 3017 for claude, 3019 for gemini)

Environment:
  MiseMarimoPort             Port for marimo editor (default: 2718)
  MiseMarimoHost             Host for marimo editor (default: localhost, use 0.0.0.0 for all interfaces)

Notes:
  - Ensure the project has pyproject.toml and notebooks/eda.py
  - Enable Agents in marimo Settings > Lab, then select the agent in the sidebar
EOF
}

# Parse CLI options: --agent [claude|gemini], --agent-port <port>, --port <port>, --host <host>
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
    --port|-p)
      if [ $# -lt 2 ]; then
        echo "--port requires a port number" >&2
        exit 2
      fi
      CLI_PORT="$2"
      shift 2
      ;;
    --host|-H)
      if [ $# -lt 2 ]; then
        echo "--host requires a host address" >&2
        exit 2
      fi
      CLI_HOST="$2"
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

# Cleanup function for graceful shutdown
cleanup() {
  if [ -n "${AGENT_PID:-}" ]; then
    echo "Stopping agent process (PID: $AGENT_PID)..."
    kill "$AGENT_PID" 2>/dev/null || true
    wait "$AGENT_PID" 2>/dev/null || true
  fi
}

# Set up trap to cleanup on exit
trap cleanup EXIT INT TERM

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

# CLI options take precedence over environment variables
PORT=${CLI_PORT:-${MiseMarimoPort:-2718}}
HOST=${CLI_HOST:-${MiseMarimoHost:-localhost}}

cd "$PROJECT_DIR"
# Don't exec marimo so traps run and cleanup executes on Ctrl-C and other signals
PYTHONPATH="$PROJECT_DIR${PYTHONPATH:+:$PYTHONPATH}" uv run -- marimo edit notebooks/eda.py --host "$HOST" --port "$PORT"
