#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/lib/init_common.sh"

# Use kaggle_cli from lib/init_common.sh

usage() {
  cat <<'USAGE'
Usage: mise run kaggle-download <competition-slug> [options]

Options:
  --slug <slug>        Competition slug (default: positional argument or project metadata)
  --project <dir>      Project directory (default: current working directory)
  --force              Re-download and overwrite existing data
  --keep-zip           Keep downloaded ZIP archive
  -h, --help           Show this help message
USAGE
}

SLUG=""
PROJECT_DIR=$(cd "${MISE_ORIGINAL_CWD:-$(pwd)}" && pwd)
FORCE=0
KEEP_ZIP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)
      SLUG="$2"
      shift 2
      ;;
    --project)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --keep-zip)
      KEEP_ZIP=1
      shift
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
      if [ -z "$SLUG" ]; then
        SLUG="$1"
      else
        die "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

if [ -z "$SLUG" ] && [ -f "$PROJECT_DIR/pyproject.toml" ]; then
  SLUG=$(grep -E "Kaggle project scaffold for" "$PROJECT_DIR/pyproject.toml" | sed -E 's/.*for ([^"]+).*/\1/' || true)
fi

if [ -z "$SLUG" ]; then
  die "Competition slug is required."
fi

PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
mkdir -p "$PROJECT_DIR/logs"
LOG_FILE="$PROJECT_DIR/logs/download-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
log "Logging to $LOG_FILE"

fix_perm_0600 "$HOME/.kaggle/kaggle.json"

RAW_BASE="$PROJECT_DIR/data/raw"
RAW_DEST="$RAW_BASE/$SLUG"
ZIP_PATH="$RAW_BASE/${SLUG}.zip"

mkdir -p "$RAW_BASE"
if [ -d "$RAW_DEST" ] && [ "$FORCE" != "1" ]; then
  log "Data directory $RAW_DEST already exists; use --force to overwrite."
  exit 0
fi

BACKUP_DIR=""
if [ "$FORCE" = "1" ] && [ -d "$RAW_DEST" ]; then
  BACKUP_DIR="$PROJECT_DIR/.backups/download-$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$BACKUP_DIR"
  mv "$RAW_DEST" "$BACKUP_DIR/$(basename "$RAW_DEST")"
  warn "Backed up existing data to $BACKUP_DIR"
fi

if [ "$FORCE" = "1" ] && [ -f "$ZIP_PATH" ]; then
  rm -f "$ZIP_PATH"
fi

log "Downloading Kaggle competition $SLUG"
if retry 3 kaggle_cli competitions download -c "$SLUG" -p "$RAW_BASE"; then
  log "Download succeeded"
  mkdir -p "$RAW_DEST"
  safe_unzip "$ZIP_PATH" "$RAW_DEST"
  log "Extracted archive to $RAW_DEST"
  if [ "$KEEP_ZIP" != "1" ]; then
    rm -f "$ZIP_PATH"
    log "Removed archive $ZIP_PATH"
  fi
else
  err "Download failed after retries."
  err "Run manually: uv run --with kaggle -- kaggle competitions download -c $SLUG -p $RAW_BASE"
  exit 1
fi
