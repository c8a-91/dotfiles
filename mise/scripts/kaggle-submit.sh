#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/lib/init_common.sh"

# Use kaggle_cli from lib/init_common.sh

usage() {
  cat <<'USAGE'
Usage: mise run kaggle-submit [options]

Options:
  --slug <slug>        Competition slug (default: infer from project metadata)
  --file <path>        Submission file (default: submission.csv)
  --message <msg>      Submission message (default: "Auto submission")
  --project <dir>      Project directory (default: current working directory)
  -h, --help           Show this help message
USAGE
}

SLUG=""
FILE="submission.csv"
MESSAGE="Auto submission"
PROJECT_DIR=$(cd "${MISE_ORIGINAL_CWD:-$(pwd)}" && pwd)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)
      SLUG="$2"
      shift 2
      ;;
    --file)
      FILE="$2"
      shift 2
      ;;
    --message)
      MESSAGE="$2"
      shift 2
      ;;
    --project)
      PROJECT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      die "Unexpected argument: $1"
      ;;
  esac
done

PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
if [ -z "$SLUG" ] && [ -f "$PROJECT_DIR/pyproject.toml" ]; then
  SLUG=$(grep -E "Kaggle project scaffold for" "$PROJECT_DIR/pyproject.toml" | sed -E 's/.*for ([^"]+).*/\1/' || true)
fi

if [ -z "$SLUG" ]; then
  die "Competition slug is required."
fi

SUB_PATH="$PROJECT_DIR/$FILE"
if [ ! -f "$SUB_PATH" ]; then
  die "Submission file not found: $SUB_PATH"
fi

need_cmd uv

mkdir -p "$PROJECT_DIR/logs"
LOG_FILE="$PROJECT_DIR/logs/submit-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
log "Logging to $LOG_FILE"

fix_perm_0600 "$HOME/.kaggle/kaggle.json"

log "Validating submission via src.data.validate_submission"
(
  cd "$PROJECT_DIR"
  uv run python -c "from pathlib import Path; from src.data import validate_submission; validate_submission(Path('$FILE'))"
)

log "Submitting to Kaggle competition $SLUG"
retry 3 kaggle_cli competitions submit -c "$SLUG" -f "$SUB_PATH" -m "$MESSAGE"

log "Submission completed."
