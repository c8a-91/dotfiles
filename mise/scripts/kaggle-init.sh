#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${MISE_ORIGINAL_CWD:-$(pwd)}" && pwd)
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/lib/init_common.sh"


usage() {
  cat <<'USAGE'
Usage: mise run kaggle-init <competition-slug> [options]

Options:
  --name <project-name>   Directory name for the project (default: slug)
  --py <version>          Python version to use (default: 3.11)
  --theme <auto|light|dark>
                          Theme preference for generated notebooks (default: auto)
  --open                  Open marimo editor for notebooks/eda.py after setup
  --gpu                   Force GPU dependencies (auto-detect CUDA/ROCm)
  --cpu                   Force CPU dependencies
  --add <deps>            Additional comma-separated dependencies (e.g., optuna,wandb)
  --no-download           Skip Kaggle data download
  --keep-zip              Keep downloaded ZIP archives
  --force                 Overwrite conflicting files (existing copies are backed up)
  -h, --help              Show this help and exit
USAGE
}

SLUG=""
PROJECT_NAME=""
PY_VERSION="3.11"
THEME="auto"
OPEN_EDITOR=0
FORCE=0
NO_DOWNLOAD=0
KEEP_ZIP=0
DEVICE_OVERRIDE=""
EXTRA_DEPS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --py)
      PY_VERSION="$2"
      shift 2
      ;;
    --theme)
      THEME="$2"
      shift 2
      ;;
    --open)
      OPEN_EDITOR=1
      shift
      ;;
    --gpu)
      DEVICE_OVERRIDE="gpu"
      shift
      ;;
    --cpu)
      DEVICE_OVERRIDE="cpu"
      shift
      ;;
    --add)
      IFS=',' read -r -a add_list <<<"$2"
      for dep in "${add_list[@]}"; do
        dep_trimmed=$(printf '%s' "$dep" | sed 's/^ *//;s/ *$//')
        if [ -n "$dep_trimmed" ]; then
          EXTRA_DEPS+=("$dep_trimmed")
        fi
      done
      shift 2
      ;;
    --no-download)
      NO_DOWNLOAD=1
      shift
      ;;
    --keep-zip)
      KEEP_ZIP=1
      shift
      ;;
    --force)
      FORCE=1
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

if [ -z "$SLUG" ]; then
  die "Competition slug is required."
fi

if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME="$SLUG"
fi

case "$THEME" in
  auto|light|dark) ;;
  *) die "Invalid theme: $THEME" ;;
esac

PROJECT_DIR="${ROOT_DIR}/${PROJECT_NAME}"
mkdir -p "$PROJECT_DIR"

if [ "$FORCE" = "1" ]; then
  warn "Force mode enabled. Existing files may be overwritten. Backups will be stored under .backups/."
fi

prepare_backup_roots

init_logging

need_cmd uv
select_python_bin

ensure_uv_cache_dir
UV_FAILURE=0





# apply_confirm moved to lib/init_common.sh

# write_file moved to lib/init_common.sh

write_template_file "${SCRIPT_DIR}/templates/root/.env.example" "$PROJECT_DIR/.env.example" 0644 PROJECT_NAME="$PROJECT_NAME" SLUG="$SLUG"

write_template_file "${SCRIPT_DIR}/templates/root/.gitignore" "$PROJECT_DIR/.gitignore" 0644 PROJECT_NAME="$PROJECT_NAME" SLUG="$SLUG"

write_template_file "${SCRIPT_DIR}/templates/root/README.md" "$PROJECT_DIR/README.md" 0644 PROJECT_NAME="$PROJECT_NAME" SLUG="$SLUG" PY_VERSION="$PY_VERSION" THEME="$THEME"

write_template_file "${SCRIPT_DIR}/templates/configs/config.yaml" "$PROJECT_DIR/configs/config.yaml" 0644 SLUG="$SLUG"

write_template_file "${SCRIPT_DIR}/templates/configs/logging.yaml" "$PROJECT_DIR/configs/logging.yaml" 0644 SLUG="$SLUG"

mkdir -p "$PROJECT_DIR/data"/raw "$PROJECT_DIR/data/external" "$PROJECT_DIR/data/interim" "$PROJECT_DIR/data/processed"
mkdir -p "$PROJECT_DIR/notebooks" "$PROJECT_DIR/src" "$PROJECT_DIR/logs" "$PROJECT_DIR/runs"

# detect_device moved to lib/init_common.sh

device=$(detect_device)

# get_cuda_version moved to lib/init_common.sh

# cuda_tag_from_version moved to lib/init_common.sh

cuda_tag="cu121"
if [ "$device" = "cuda" ]; then
  if cuda_version=$(get_cuda_version); then
    cuda_tag=$(cuda_tag_from_version "$cuda_version")
    log "Detected CUDA version $cuda_version -> $cuda_tag"
  else
    warn "Could not determine CUDA version; defaulting to $cuda_tag"
  fi
fi

write_template_file "${SCRIPT_DIR}/templates/root/pyproject.toml" "$PROJECT_DIR/pyproject.toml" 0644 PROJECT_NAME="$PROJECT_NAME" SLUG="$SLUG" PY_VERSION="$PY_VERSION"

if ! run_uv "Pin Python ${PY_VERSION}" python pin "${PY_VERSION}"; then
  warn "Failed to pin Python ${PY_VERSION} with uv. The project will use the system interpreter unless you run 'uv python pin ${PY_VERSION}' manually."
fi

CORE_DEPS=(marimo polars numpy scikit-learn xgboost matplotlib plotly pyyaml python-dotenv rich tqdm pyarrow kaggle)
log "Adding core dependencies via uv add"
if ! run_uv "Adding core dependencies" add "${CORE_DEPS[@]}"; then
  warn "Core dependencies were not installed automatically. Run 'uv add ${CORE_DEPS[*]}' once network access is available."
fi

# install_torch moved to lib/init_common.sh

install_torch

if [ ${#EXTRA_DEPS[@]} -gt 0 ]; then
  log "Adding extra dependencies: ${EXTRA_DEPS[*]}"
  if ! run_uv "Adding extra dependencies" add "${EXTRA_DEPS[@]}"; then
    warn "Extra dependencies were not installed automatically."
  fi
fi

# ensure_kaggle_auth moved to lib/init_common.sh

if [ "$NO_DOWNLOAD" != "1" ]; then
  ensure_kaggle_auth || warn "Continuing without validated Kaggle credentials (downloads may fail)."
fi

RAW_BASE="$PROJECT_DIR/data/raw"
RAW_DEST="$RAW_BASE/$SLUG"
ZIP_PATH="$RAW_BASE/${SLUG}.zip"

if [ "$NO_DOWNLOAD" = "1" ]; then
  log "Skipping data download (--no-download)."
else
  mkdir -p "$RAW_BASE"
  if [ -d "$RAW_DEST" ] && [ "$FORCE" != "1" ]; then
    log "Data directory $RAW_DEST already exists; skipping download."
  else
    if [ "$FORCE" = "1" ] && [ -d "$RAW_DEST" ]; then
      mkdir -p "$BACKUP_DIR/data_raw"
      mv "$RAW_DEST" "$BACKUP_DIR/data_raw/$(basename "$RAW_DEST")" || true
      log "Backed up existing data directory to $BACKUP_DIR/data_raw/"
    fi
    if [ -f "$ZIP_PATH" ] && [ "$FORCE" = "1" ]; then
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
      warn "Kaggle download failed after retries. Please download manually:"
      warn "  uv run --with kaggle -- kaggle competitions download -c $SLUG -p $RAW_BASE"
    fi
  fi
fi

write_template_file "${SCRIPT_DIR}/templates/python/__init__.py" "$PROJECT_DIR/src/__init__.py" 0644 PROJECT_NAME="$PROJECT_NAME" SLUG="$SLUG"

write_template_file "${SCRIPT_DIR}/templates/python/paths.py" "$PROJECT_DIR/src/paths.py" 0644

write_template_file "${SCRIPT_DIR}/templates/python/data.py" "$PROJECT_DIR/src/data.py" 0644

write_template_file "${SCRIPT_DIR}/templates/python/features.py" "$PROJECT_DIR/src/features.py" 0644

write_template_file "${SCRIPT_DIR}/templates/python/models.py" "$PROJECT_DIR/src/models.py" 0644

write_template_file "${SCRIPT_DIR}/templates/python/viz.py" "$PROJECT_DIR/src/viz.py" 0644

# Resolve marimo version to embed into notebooks' __generated_with
MARIMO_VERSION="$(
  cd "$PROJECT_DIR" && uv run --with marimo -- python - <<'PY'
import marimo, sys
sys.stdout.write(marimo.__version__)
PY
)" || MARIMO_VERSION="0.0.0"

write_template_file "${SCRIPT_DIR}/templates/notebooks/eda.py" "$PROJECT_DIR/notebooks/eda.py" 0644 THEME="$THEME" MARIMO_VERSION="$MARIMO_VERSION"

write_template_file "${SCRIPT_DIR}/templates/notebooks/train.py" "$PROJECT_DIR/notebooks/train.py" 0644 MARIMO_VERSION="$MARIMO_VERSION"

# Download CLAUDE.md for Claude Code integration with marimo
log "Downloading CLAUDE.md for Claude Code integration"
if curl -sS https://docs.marimo.io/CLAUDE.md -o "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
  # Append Kaggle-specific context to CLAUDE.md
  cat >> "$PROJECT_DIR/CLAUDE.md" <<EOF

## Additional Kaggle Competition Context

This project is set up for a Kaggle competition: ${SLUG}

Key project structure:
- Data is stored in \`data/raw/${SLUG}/\`
- Notebooks are in \`notebooks/\` (eda.py, train.py)
- Source code is in \`src/\` with modules for data, features, models, and visualization
- Use efficient data loading strategies for large datasets
- Consider memory optimization techniques when working with limited resources
- Focus on creating reproducible pipelines for model training
- Document feature engineering steps clearly
- Track experiment results and model performance metrics
EOF
  log "Successfully downloaded and customized CLAUDE.md"
else
  warn "Failed to download CLAUDE.md. You can manually download it with:"
  warn "  curl https://docs.marimo.io/CLAUDE.md > $PROJECT_DIR/CLAUDE.md"
fi

if ! run_uv "uv sync" sync; then
  warn "uv sync failed. Run 'uv sync' manually when dependencies are available."
fi

if [ "$OPEN_EDITOR" = "1" ]; then
  log "Opening marimo editor."
  (
    cd "$PROJECT_DIR"
    uv run marimo edit notebooks/eda.py
  )
fi

if [ "$UV_FAILURE" = "1" ]; then
  warn "One or more uv operations failed. Please ensure network access and rerun 'uv sync'."
fi

# Generate .envrc for direnv to auto-activate .venv and show project name in prompt
write_template_file "${SCRIPT_DIR}/templates/root/.envrc" "$PROJECT_DIR/.envrc" 0644 PROJECT_NAME="$PROJECT_NAME" SLUG="$SLUG"

log "Initialization complete."
log "Created .envrc for direnv. Inside the project directory, run 'direnv allow' once to enable auto-activation of .venv and loading of .env."
log "Created CLAUDE.md for optimal Claude Code integration with marimo notebooks."
log "Try these next commands:"
log "  cd $PROJECT_DIR"
log "  mise run nb-serve"
log "  mise run train"
