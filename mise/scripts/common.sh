#!/usr/bin/env bash

set -euo pipefail

log() {
  printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

warn() {
  printf '[%s] [WARN] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2
}

err() {
  printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2
}

die() {
  err "$*"
  exit 1
}

need_cmd() {
  local cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found."
}

fix_perm_0600() {
  local path=$1
  if [ -f "$path" ]; then
    local mode
    if mode=$(stat -c '%a' "$path" 2>/dev/null); then
      :
    elif mode=$(stat -f '%Lp' "$path" 2>/dev/null); then
      :
    else
      warn "Could not determine permissions for $path"
      return 1
    fi
    if [ "$mode" != "600" ]; then
      warn "Fixing permissions on $path (expected 0600, was $mode)."
      chmod 600 "$path"
    fi
  fi
}

retry() {
  local max_attempts=$1
  shift
  local attempt=1
  local delay=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      return 1
    fi
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
    warn "Retrying ($attempt/$max_attempts)..."
  done
}

hash_eq() {
  local path=$1 expected=$2
  if [ ! -f "$path" ]; then
    return 1
  fi
  local actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ "$actual" == "$expected" ]]
}

confirm_overwrite() {
  local path=$1 force=$2 backup_dir=$3
  if [ ! -e "$path" ]; then
    return 0
  fi
  if [ "$force" != "1" ]; then
    warn "File $path already exists. Use --force to overwrite."
    return 1
  fi
  mkdir -p "$backup_dir"
  local backup_file
  backup_file="$backup_dir/$(basename "$path").bak.$(date '+%Y%m%d-%H%M%S')"
  cp -a "$path" "$backup_file"
  warn "Backed up $path to $backup_file before overwriting."
  return 0
}

safe_unzip() {
  local zip_path=$1 dest_dir=$2
  local py_cmd="python3"
  if ! command -v "$py_cmd" >/dev/null 2>&1; then
    py_cmd="python"
  fi
  "$py_cmd" - "$zip_path" "$dest_dir" <<'PY'
import sys
import zipfile
from pathlib import Path

zip_path = Path(sys.argv[1]).expanduser().resolve()
dest_dir = Path(sys.argv[2]).expanduser().resolve()

if not zip_path.exists():
    raise FileNotFoundError(zip_path)

dest_dir.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(zip_path) as zf:
    for member in zf.infolist():
        target = dest_dir / member.filename
        resolved = target.resolve()
        if not str(resolved).startswith(str(dest_dir)):
            raise RuntimeError(f"Blocked path traversal attempt: {member.filename}")
    zf.extractall(dest_dir)
PY
}
