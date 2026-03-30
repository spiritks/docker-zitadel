#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
DATA_VOLUME="${DATA_VOLUME:-${PROJECT_NAME}_data}"
LETSENCRYPT_VOLUME="${LETSENCRYPT_VOLUME:-${PROJECT_NAME}_letsencrypt}"
TIMESTAMP="$(date +%F-%H%M%S)"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backup-$TIMESTAMP}"

REQUIRED_FILES=("docker-compose.yaml" ".env")
OPTIONAL_PATHS=("postfix" "login-client.pat")

log() {
  printf '[backup] %s\n' "$*"
}

fail() {
  printf '[backup] ERROR: %s\n' "$*" >&2
  exit 1
}

require_path() {
  local path="$1"
  [[ -e "$path" ]] || fail "Required path not found: $path"
}

volume_exists() {
  docker volume inspect "$1" >/dev/null 2>&1
}

stack_running() {
  docker compose ps -q | grep -q .
}

archive_volume() {
  local volume_name="$1"
  local archive_name="$2"

  log "Archiving volume $volume_name -> $archive_name"
  docker run --rm \
    -v "$volume_name:/source:ro" \
    -v "$BACKUP_DIR:/backup" \
    alpine:3.22 sh -c "cd /source && tar czf /backup/$archive_name ."
}

main() {
  command -v docker >/dev/null 2>&1 || fail "docker is not installed"

  for path in "${REQUIRED_FILES[@]}"; do
    require_path "$path"
  done

  volume_exists "$DATA_VOLUME" || fail "Docker volume not found: $DATA_VOLUME"
  volume_exists "$LETSENCRYPT_VOLUME" || fail "Docker volume not found: $LETSENCRYPT_VOLUME"

  if stack_running; then
    log "Stopping compose stack"
    docker compose down
  else
    log "Compose stack is already stopped"
  fi

  mkdir -p "$BACKUP_DIR"
  log "Using backup directory: $BACKUP_DIR"

  local include_paths=("docker-compose.yaml" ".env")
  for path in "${OPTIONAL_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
      include_paths+=("$path")
    fi
  done

  log "Archiving project files"
  tar czf "$BACKUP_DIR/stack-files.tar.gz" "${include_paths[@]}"

  archive_volume "$DATA_VOLUME" "${DATA_VOLUME}.tar.gz"
  archive_volume "$LETSENCRYPT_VOLUME" "${LETSENCRYPT_VOLUME}.tar.gz"

  cat > "$BACKUP_DIR/manifest.txt" <<EOF
PROJECT_DIR=$PROJECT_DIR
PROJECT_NAME=$PROJECT_NAME
DATA_VOLUME=$DATA_VOLUME
LETSENCRYPT_VOLUME=$LETSENCRYPT_VOLUME
CREATED_AT=$(date --iso-8601=seconds)
EOF

  log "Backup completed successfully"
  log "Created files:"
  ls -lh "$BACKUP_DIR"
}

main "$@"
