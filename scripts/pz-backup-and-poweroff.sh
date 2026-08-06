#!/usr/bin/env bash
# Run the Compose backup service, then power off the Linux host on success.

set -Eeuo pipefail
IFS=$'\n\t'

readonly COMPOSE_DIR="${PZ_COMPOSE_DIR:-/var/PZServer}"
readonly LOCK_FILE="${PZ_BACKUP_LOCK_FILE:-/run/lock/pz-backup-and-poweroff.lock}"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

require_root() {
  [[ "$(id -u)" == '0' ]] || die 'this script must be run as root'
}

main() {
  local command

  require_root
  for command in docker flock sync systemctl id date; do
    require_command "$command"
  done
  docker compose version >/dev/null 2>&1 || die 'Docker Compose is unavailable'
  [[ -d "$COMPOSE_DIR" ]] || die "Compose project directory does not exist: $COMPOSE_DIR"
  [[ -f "$COMPOSE_DIR/compose.yaml" ]] || die "Compose file is unavailable: $COMPOSE_DIR/compose.yaml"
  [[ -d "$(dirname "$LOCK_FILE")" ]] || die "lock directory does not exist: $(dirname "$LOCK_FILE")"

  exec 9>"$LOCK_FILE"
  flock -n 9 || die 'another backup-and-power-off run is already active'

  log 'running the Compose backup service'
  (
    cd "$COMPOSE_DIR"
    docker compose run --rm --no-deps pz-backup
  ) || die 'Compose backup service failed'

  log 'backup succeeded; synchronizing filesystems before host power-off'
  sync || die 'filesystem synchronization failed'
  log 'powering off the host'
  systemctl poweroff || die 'systemctl poweroff failed'
}

main "$@"
