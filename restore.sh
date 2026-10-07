#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

BACKUP_DIR="${1:-${BACKUP_DIR:-}}"
FORCE="${FORCE:-0}"
MANIFEST_PROJECT_NAME=""
MANIFEST_DATA_VOLUME=""
MANIFEST_LETSENCRYPT_VOLUME=""

load_backup_manifest() {
  local manifest_path

  [[ -n "$BACKUP_DIR" ]] || return 0
  manifest_path="$BACKUP_DIR/manifest.txt"
  [[ -f "$manifest_path" ]] || return 0

  while IFS='=' read -r key value; do
    case "$key" in
      PROJECT_NAME) MANIFEST_PROJECT_NAME="$value" ;;
      DATA_VOLUME) MANIFEST_DATA_VOLUME="$value" ;;
      LETSENCRYPT_VOLUME) MANIFEST_LETSENCRYPT_VOLUME="$value" ;;
    esac
  done < "$manifest_path"
}

load_backup_manifest

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${MANIFEST_PROJECT_NAME:-$(basename "$PROJECT_DIR")}}"
DATA_VOLUME="${DATA_VOLUME:-${MANIFEST_DATA_VOLUME:-${PROJECT_NAME}_data}}"
LETSENCRYPT_VOLUME="${LETSENCRYPT_VOLUME:-${MANIFEST_LETSENCRYPT_VOLUME:-${PROJECT_NAME}_letsencrypt}}"

log() {
  printf '[restore] %s\n' "$*"
}

fail() {
  printf '[restore] ERROR: %s\n' "$*" >&2
  exit 1
}

volume_exists() {
  docker volume inspect "$1" >/dev/null 2>&1
}

stack_running() {
  docker compose ps -q | grep -q .
}

ensure_backup_dir() {
  [[ -n "$BACKUP_DIR" ]] || fail "Usage: ./restore.sh <backup-directory>"
  [[ -d "$BACKUP_DIR" ]] || fail "Backup directory not found: $BACKUP_DIR"
  BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"
  [[ -f "$BACKUP_DIR/stack-files.tar.gz" ]] || fail "Missing file: $BACKUP_DIR/stack-files.tar.gz"
  [[ -f "$BACKUP_DIR/${DATA_VOLUME}.tar.gz" ]] || fail "Missing file: $BACKUP_DIR/${DATA_VOLUME}.tar.gz"
  [[ -f "$BACKUP_DIR/${LETSENCRYPT_VOLUME}.tar.gz" ]] || fail "Missing file: $BACKUP_DIR/${LETSENCRYPT_VOLUME}.tar.gz"
}

create_or_reset_volume() {
  local volume_name="$1"

  if volume_exists "$volume_name"; then
    if [[ "$FORCE" != "1" ]]; then
      fail "Volume already exists: $volume_name (set FORCE=1 to recreate it)"
    fi
    log "Removing existing volume: $volume_name"
    docker volume rm -f "$volume_name" >/dev/null
  fi

  log "Creating volume: $volume_name"
  docker volume create "$volume_name" >/dev/null
}

extract_volume() {
  local volume_name="$1"
  local archive_name="$2"

  log "Restoring $archive_name -> $volume_name"
  docker run --rm \
    -v "$volume_name:/target" \
    -v "$BACKUP_DIR:/backup:ro" \
    alpine:3.22 sh -c "cd /target && tar xzf /backup/$archive_name"
}

main() {
  command -v docker >/dev/null 2>&1 || fail "docker is not installed"
  ensure_backup_dir

  if stack_running; then
    fail "Compose stack is running. Stop it first with: docker compose down"
  fi

  if [[ "$FORCE" != "1" ]]; then
    for path in docker-compose.yaml .env login-client.pat; do
      if [[ -e "$PROJECT_DIR/$path" ]]; then
        fail "Path already exists: $path (set FORCE=1 to overwrite local files and recreate volumes)"
      fi
    done
  fi

  log "Restoring project files"
  tar xzf "$BACKUP_DIR/stack-files.tar.gz"

  create_or_reset_volume "$DATA_VOLUME"
  create_or_reset_volume "$LETSENCRYPT_VOLUME"

  extract_volume "$DATA_VOLUME" "${DATA_VOLUME}.tar.gz"
  extract_volume "$LETSENCRYPT_VOLUME" "${LETSENCRYPT_VOLUME}.tar.gz"

  log "Restore completed successfully"
  log "Start the stack with: docker compose up -d"
}

main "$@"
