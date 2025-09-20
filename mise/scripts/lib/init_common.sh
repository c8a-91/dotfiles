#!/usr/bin/env bash
# Shared helpers for kaggle-init and related setup scripts.
# This library expects that common.sh has already been sourced to provide:
# - log, warn, err, die, need_cmd, retry, confirm_overwrite, safe_unzip
#
# Conventions:
# - The caller should export PROJECT_DIR to the target project directory.
# - Functions avoid side effects unless explicitly documented.
# - Where useful, globals are set to mirror legacy behavior.

# Initialize logging to a timestamped file under $PROJECT_DIR/logs and tee stdout/stderr.
# Sets TIMESTAMP and LOG_FILE globals.
init_logging() {
  if [ -z "${PROJECT_DIR:-}" ]; then
    die "init_logging: PROJECT_DIR is not set"
  fi
  mkdir -p "$PROJECT_DIR/logs"
  if [ -z "${TIMESTAMP:-}" ]; then
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
  fi
  LOG_FILE="$PROJECT_DIR/logs/init-$TIMESTAMP.log"
  export TIMESTAMP LOG_FILE
  : >"$LOG_FILE"
  # Redirect and tee, keeping script stderr merged into the log
  exec > >(tee -a "$LOG_FILE") 2>&1
  trap 'err "Initialization failed."' ERR
  log "Logging to $LOG_FILE"
}

# Prepare backup directories under $PROJECT_DIR/.backups/$TIMESTAMP
# Sets BACKUP_ROOT and BACKUP_DIR globals.
prepare_backup_roots() {
  if [ -z "${PROJECT_DIR:-}" ]; then
    die "prepare_backup_roots: PROJECT_DIR is not set"
  fi
  if [ -z "${TIMESTAMP:-}" ]; then
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    export TIMESTAMP
  fi
  BACKUP_ROOT="$PROJECT_DIR/.backups"
  BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
  mkdir -p "$BACKUP_DIR"
  export BACKUP_ROOT BACKUP_DIR
}

# Choose python binary and ensure availability.
# Sets PYTHON_BIN global.
select_python_bin() {
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  else
    die "python or python3 is required."
  fi
  need_cmd "$PYTHON_BIN"
  export PYTHON_BIN
}

# Ensure UV cache dir under project and export UV_CACHE_DIR.
ensure_uv_cache_dir() {
  if [ -z "${PROJECT_DIR:-}" ]; then
    die "ensure_uv_cache_dir: PROJECT_DIR is not set"
  fi
  UV_CACHE_DIR="$PROJECT_DIR/.uv-cache"
  export UV_CACHE_DIR
  mkdir -p "$UV_CACHE_DIR"
}

# Run uv in the project context with a description for logging.
# Maintains UV_FAILURE=1 on first failure to signal non-fatal issues.
run_uv() {
  local desc="$1"
  shift
  if [ -z "${PROJECT_DIR:-}" ]; then
    die "run_uv: PROJECT_DIR is not set"
  fi
  if (
    cd "$PROJECT_DIR"
    uv "$@"
  ); then
    return 0
  fi
  warn "$desc failed (uv $*)."
  UV_FAILURE=1
  export UV_FAILURE
  return 1
}

# Prefer venv-local kaggle CLI; fallback to `uv run --with kaggle`.
kaggle_cli() {
  if [ -z "${PROJECT_DIR:-}" ]; then
    die "kaggle_cli: PROJECT_DIR is not set"
  fi
  if [ -x "$PROJECT_DIR/.venv/bin/kaggle" ]; then
    "$PROJECT_DIR/.venv/bin/kaggle" "$@"
  else
    (
      cd "$PROJECT_DIR"
      uv run --with kaggle -- kaggle "$@"
    )
  fi
}

# Apply a file update with confirmation/backups:
# - If dest exists and is identical to src: remove src and return (no-op)
# - If dest exists and differs: confirm_overwrite (honors FORCE) and backup to $BACKUP_DIR
# - Otherwise create parent dir and move src to dest
# Arguments:
#   $1: src temp file (will be moved/removed)
#   $2: destination path
#   $3: octal permissions (e.g., 0644)
apply_confirm() {
  local src=$1 dest=$2 perms=$3
  if [ -f "$dest" ]; then
    if cmp -s "$src" "$dest"; then
      log "Unchanged $dest"
      rm -f "$src"
      return 0
    fi
    local force="${FORCE:-0}"
    local backup_dir="${BACKUP_DIR:-}"
    if ! confirm_overwrite "$dest" "$force" "$backup_dir"; then
      rm -f "$src"
      log "Skipped existing $dest (use --force to overwrite)."
      return 0
    fi
  else
    mkdir -p "$(dirname "$dest")"
  fi
  mv "$src" "$dest"
  chmod "$perms" "$dest"
  log "Wrote $dest"
}

# Write stdin to a temporary file, then install it at dest via apply_confirm.
# Usage: write_file DEST [PERMS] <<'EOF' ... EOF
write_file() {
  local dest=$1
  local perms=${2:-0644}
  local tmp
  tmp=$(mktemp)
  cat >"$tmp"
  apply_confirm "$tmp" "$dest" "$perms"
}

# Build envsubst variable spec string (e.g., "$VAR1 $VAR2") from KEY=VALUE pairs
_build_varspec_from_pairs() {
  if ! command -v envsubst >/dev/null 2>&1; then
    # No envsubst; variable spec is not needed
    return 0
  fi
  local pair key
  local out=""
  for pair in "$@"; do
    key="${pair%%=*}"
    if [ -n "$key" ]; then
      out="$out\$$key "
    fi
  done
  printf '%s' "$out"
}

# Render a template file using provided KEY=VALUE pairs.
# If envsubst is available, use it; otherwise, fallback to sed-based substitution
# supporting ${VAR} and $VAR placeholders.
# Prints path to a temporary rendered file.
render_to_tmp_from_file() {
  local src=$1
  shift
  local tmp
  tmp=$(mktemp)

  if command -v envsubst >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    (
      # Export variables so envsubst can see them
      for pair in "$@"; do
        key="${pair%%=*}"
        val="${pair#*=}"
        # Export as environment variable
        export "$key=$val"
      done
      vars_spec=$(_build_varspec_from_pairs "$@")
      if [ -n "$vars_spec" ]; then
        envsubst "$vars_spec" <"$src" >"$tmp"
      else
        envsubst <"$src" >"$tmp"
      fi
    )
  else
    cp "$src" "$tmp"
    local pair key val val_esc
    for pair in "$@"; do
      key="${pair%%=*}"
      val="${pair#*=}"
      # Escape for sed replacement
      val_esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
      # Replace ${KEY} and $KEY
      sed -i -e "s|\${$key}|$val_esc|g" -e "s|\$$key|$val_esc|g" "$tmp"
    done
  fi

  printf '%s\n' "$tmp"
}

# Render a template from stdin and return a temp file path.
render_to_tmp_from_stdin() {
  local tmp_src
  tmp_src=$(mktemp)
  cat >"$tmp_src"
  render_to_tmp_from_file "$tmp_src" "$@"
}

# Write a rendered template file to destination with permission handling and backups.
# Usage: write_template_file SRC DEST [PERMS] [KEY=VALUE ...]
write_template_file() {
  local src=$1 dest=$2 perms=${3:-0644}
  shift 3 || true
  local rendered
  rendered=$(render_to_tmp_from_file "$src" "$@")
  apply_confirm "$rendered" "$dest" "$perms"
}

# Write a rendered template from stdin to destination with permission handling and backups.
# Usage: write_template_stdin DEST [PERMS] [KEY=VALUE ...] <<'EOF' ... EOF
write_template_stdin() {
  local dest=$1 perms=${2:-0644}
  shift 2 || true
  local rendered
  rendered=$(render_to_tmp_from_stdin "$@")
  apply_confirm "$rendered" "$dest" "$perms"
}

# Detect compute device: cpu | cuda | rocm
# Honors DEVICE_OVERRIDE=cpu|gpu:
#   - gpu selects cuda if NVIDIA is present, otherwise rocm
# Uses:
#   - nvidia-smi for CUDA presence/version
#   - torch import to refine availability (best-effort)
#   - rocminfo or torch.version.hip for ROCm
# Prints the detected device to stdout and logs reasoning.
detect_device() {
  local override="${DEVICE_OVERRIDE:-}"
  local detected="cpu"
  local reason=""
  if [ "$override" = "cpu" ]; then
    echo "cpu"
    return 0
  fi
  if [ "$override" = "gpu" ]; then
    if command -v nvidia-smi >/dev/null 2>&1; then
      detected="cuda"
      reason="Forced GPU with NVIDIA detected"
    else
      detected="rocm"
      reason="Forced GPU fallback to ROCm"
    fi
    log "$reason"
    echo "$detected"
    return 0
  fi

  # NVIDIA CUDA path
  if command -v nvidia-smi >/dev/null 2>&1; then
    local header
    header=$(nvidia-smi | head -n 1 || true)
    if printf '%s' "$header" | grep -q 'CUDA Version'; then
      detected="cuda"
      reason="nvidia-smi found"
    fi
  fi

  # Validate with torch if present
  if [ "$detected" = "cuda" ]; then
    local torch_check
    if ! torch_check=$(${PYTHON_BIN:-python3} - <<'PY'
import sys
try:
    import torch  # type: ignore
except Exception:
    sys.exit(2)
print('1' if torch.cuda.is_available() else '0')
PY
); then
      torch_check=2
    fi
    if [ "$torch_check" = "1" ]; then
      reason+="; torch CUDA available"
    elif [ "$torch_check" = "0" ]; then
      warn "Torch reports CUDA unavailable; will attempt GPU install."
    else
      warn "Torch not present; assuming CUDA GPU based on nvidia-smi."
    fi
  fi

  # ROCm path
  if [ "$detected" = "cpu" ]; then
    local rocm_check
    if ! rocm_check=$(${PYTHON_BIN:-python3} - <<'PY'
try:
    import torch  # type: ignore
except Exception:
    raise SystemExit(2)
import sys
hip = getattr(torch.version, 'hip', None)
print('1' if hip else '0')
PY
); then
      rocm_check=2
    fi
    if [ "$rocm_check" = "1" ]; then
      detected="rocm"
      reason="Torch HIP detected"
    elif command -v rocminfo >/dev/null 2>&1; then
      detected="rocm"
      reason="rocminfo command detected"
    fi
  fi

  if [ "$detected" = "cpu" ]; then
    reason=${reason:-"defaulting to CPU"}
  fi

  log "Device detection: $detected ($reason)"
  echo "$detected"
}

# Extract CUDA version with nvidia-smi (prints X.Y on success).
get_cuda_version() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    return 1
  fi
  local header
  header=$(nvidia-smi | head -n 1 || true)
  if [[ $header =~ CUDA\ Version:\ ([0-9]+\.[0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Map CUDA version to torch wheel tag (defaults to cu121).
cuda_tag_from_version() {
  local version=$1
  case "$version" in
    12.4*) echo "cu124" ;;
    12.3*) echo "cu123" ;;
    12.2*) echo "cu122" ;;
    12.1*) echo "cu121" ;;
    12.0*) echo "cu120" ;;
    11.8*) echo "cu118" ;;
    11.7*) echo "cu117" ;;
    11.6*) echo "cu116" ;;
    *) echo "cu121" ;;
  esac
}

# Install torch based on global 'device' and 'cuda_tag' variables.
# Falls back to CPU wheel on failure and updates global 'device' to "cpu".
# Uses run_uv to add dependency into the project environment.
install_torch() {
  if [ -z "${PROJECT_DIR:-}" ]; then
    die "install_torch: PROJECT_DIR is not set"
  fi
  if [ -z "${device:-}" ]; then
    die "install_torch: global 'device' is not set"
  fi

  if [ "$device" = "cuda" ]; then
    local index="https://download.pytorch.org/whl/${cuda_tag:-cu121}"
    log "Attempting to install torch from $index"
    if run_uv "Installing CUDA torch" add --index-url "$index" torch; then
      log "Installed CUDA torch from $index"
      return 0
    fi
    warn "CUDA torch install failed. Falling back to CPU wheel."
  elif [ "$device" = "rocm" ]; then
    local index="https://download.pytorch.org/whl/rocm6.1"
    log "Attempting to install torch from $index"
    if run_uv "Installing ROCm torch" add --index-url "$index" torch; then
      log "Installed ROCm torch from $index"
      return 0
    fi
    warn "ROCm torch install failed. Falling back to CPU wheel."
  fi

  if run_uv "Installing CPU torch" add torch; then
    log "Installed CPU torch wheel"
  else
    warn "Falling back to CPU torch failed; please install manually."
  fi
  device="cpu"
  export device
}

# Ensure Kaggle credentials are available:
# - If KAGGLE_USERNAME and KAGGLE_KEY are set, prefer them.
# - Otherwise fix perms and use ~/.kaggle/kaggle.json if present.
# Returns 0 if credentials appear usable, non-zero otherwise.
ensure_kaggle_auth() {
  if [ -n "${KAGGLE_USERNAME:-}" ] && [ -n "${KAGGLE_KEY:-}" ]; then
    log "Using Kaggle credentials from environment variables."
    return 0
  fi
  local kaggle_json="$HOME/.kaggle/kaggle.json"
  if [ ! -f "$kaggle_json" ]; then
    warn "Kaggle credentials not found at $kaggle_json"
    warn "Set KAGGLE_USERNAME and KAGGLE_KEY or place kaggle.json with permission 0600."
    return 1
  fi
  fix_perm_0600 "$kaggle_json"
  log "Using Kaggle credentials from $kaggle_json"
  return 0
}
