#!/usr/bin/env bash
# Stop Project Zomboid, archive its persisted Docker volume, then power off.
# This script is intended for root's crontab and deliberately has no dry-run
# mode: test it with mocked commands before installing it on a server.

set -Eeuo pipefail
IFS=$'\n\t'

readonly CONTAINER_NAME="${PZ_CONTAINER_NAME:-pz-server}"
readonly VOLUME_NAME="${PZ_VOLUME_NAME:-pz-data}"
readonly IMAGE_NAME="${PZ_IMAGE_NAME:-pz-server:local}"
readonly BACKUP_USER="${PZ_BACKUP_USER:-potsonhumer}"
readonly BACKUP_DIR="${PZ_BACKUP_DIR:-/home/potsonhumer/pa-backup}"
readonly LOCK_FILE="${PZ_BACKUP_LOCK_FILE:-/run/lock/pz-backup-and-poweroff.lock}"
readonly STOP_TIMEOUT=120
readonly RETAIN_COUNT=3

STAGING_DIR=''

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

cleanup() {
  local status=$?

  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf -- "$STAGING_DIR"
  fi

  exit "$status"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

require_root() {
  [[ "$(id -u)" == '0' ]] || die 'this script must be run as root'
}

require_resources() {
  docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1 || \
    die "container does not exist: $CONTAINER_NAME"
  docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1 || \
    die "Docker volume does not exist: $VOLUME_NAME"
}

container_is_running() {
  local state
  state="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" || \
    die "could not inspect container state: $CONTAINER_NAME"

  case "$state" in
    true) return 0 ;;
    false) return 1 ;;
    *) die "unexpected container running state: $state" ;;
  esac
}

stop_running_container() {
  if ! container_is_running; then
    log "container is already stopped: $CONTAINER_NAME"
    return 0
  fi

  log "stopping $CONTAINER_NAME with a ${STOP_TIMEOUT}-second timeout"
  docker stop --timeout "$STOP_TIMEOUT" "$CONTAINER_NAME" >/dev/null || \
    die "Docker could not stop container: $CONTAINER_NAME"

  if container_is_running; then
    die "container is still running after docker stop: $CONTAINER_NAME"
  fi

  local exit_code
  exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$CONTAINER_NAME")" || \
    die "could not inspect container exit code: $CONTAINER_NAME"

  [[ "$exit_code" != '137' ]] || \
    die 'container exit code 137 indicates a forced stop; refusing to archive or power off'
}

prepare_backup_directory() {
  # All operations in this user-controlled home-directory path are performed
  # as the backup user. Root-only archive work stays in STAGING_DIR.
  runuser -u "$BACKUP_USER" -- mkdir -p -- "$BACKUP_DIR" || \
    die "could not create backup directory as $BACKUP_USER: $BACKUP_DIR"
  runuser -u "$BACKUP_USER" -- test -d "$BACKUP_DIR" || \
    die "backup path is not a directory: $BACKUP_DIR"
  runuser -u "$BACKUP_USER" -- chmod 0750 -- "$BACKUP_DIR" || \
    die "could not set backup directory mode: $BACKUP_DIR"
}

create_staging_directory() {
  STAGING_DIR="$(mktemp -d /var/tmp/pz-backup-and-poweroff.XXXXXX)" || \
    die 'could not create root-owned staging directory'
  chmod 0700 -- "$STAGING_DIR"
}

archive_volume() {
  local stamp archive_name partial_name checksum_name checksum_partial_name
  local archive_path partial_path checksum_path checksum_partial_path checksum

  stamp="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
  archive_name="pz-data-${stamp}.tar.gz"
  partial_name="${archive_name}.partial"
  checksum_name="${archive_name}.sha256"
  checksum_partial_name="${checksum_name}.partial"
  archive_path="$STAGING_DIR/$archive_name"
  partial_path="$STAGING_DIR/$partial_name"
  checksum_path="$STAGING_DIR/$checksum_name"
  checksum_partial_path="$STAGING_DIR/$checksum_partial_name"

  log "creating offline archive: $archive_name"
  docker run --rm --user 0:0 --entrypoint tar \
    -v "${VOLUME_NAME}:/source:ro" \
    -v "${STAGING_DIR}:/backup" \
    "$IMAGE_NAME" \
    -C /source -czf "/backup/$partial_name" . || \
    die 'volume archive command failed'

  [[ -s "$partial_path" ]] || die 'archive command produced no archive data'

  IFS=' ' read -r checksum _ < <(sha256sum "$partial_path")
  [[ "$checksum" =~ ^[0-9a-fA-F]{64}$ ]] || die 'could not calculate a SHA-256 checksum'
  printf '%s  %s\n' "$checksum" "$archive_name" > "$checksum_partial_path"

  mv -- "$partial_path" "$archive_path"
  mv -- "$checksum_partial_path" "$checksum_path"
  (
    cd "$STAGING_DIR"
    sha256sum --check "$checksum_name" >/dev/null
  ) || die 'new archive failed SHA-256 verification'

  chown "${BACKUP_USER}:root" -- "$archive_path" "$checksum_path" || \
    die 'could not set finalized backup ownership'
  chmod 0640 -- "$archive_path" "$checksum_path" || \
    die 'could not set finalized backup permissions'

  # Allow the backup user to move only the already finalized, non-root-owned
  # artifacts out of staging. Retention below also runs as the backup user.
  chmod 0733 -- "$STAGING_DIR" || die 'could not prepare staging for publication'
  runuser -u "$BACKUP_USER" -- mv -- "$archive_path" "$BACKUP_DIR/$archive_name" || \
    die 'could not publish finalized archive'
  runuser -u "$BACKUP_USER" -- mv -- "$checksum_path" "$BACKUP_DIR/$checksum_name" || \
    die 'could not publish finalized archive checksum'
}

is_our_archive_name() {
  [[ "$1" =~ ^pz-data-[0-9]{8}T[0-9]{6}Z-[0-9]+\.tar\.gz$ ]]
}

prune_backups() {
  local candidate index
  local -a archives=()

  while IFS= read -r candidate; do
    is_our_archive_name "$candidate" || continue
    if runuser -u "$BACKUP_USER" -- test -f "$BACKUP_DIR/$candidate.sha256"; then
      archives+=("$candidate")
    fi
  done < <(
    runuser -u "$BACKUP_USER" -- find "$BACKUP_DIR" -maxdepth 1 -type f \
      -name 'pz-data-*.tar.gz' -printf '%f\n' | LC_ALL=C sort -r
  )

  for ((index = RETAIN_COUNT; index < ${#archives[@]}; index++)); do
    log "removing expired backup: ${archives[index]}"
    runuser -u "$BACKUP_USER" -- rm -f -- \
      "$BACKUP_DIR/${archives[index]}" \
      "$BACKUP_DIR/${archives[index]}.sha256" || \
      die "could not remove expired backup: ${archives[index]}"
  done
}

main() {
  local command

  require_root
  for command in docker tar sha256sum flock runuser sync systemctl id getent mkdir chmod chown \
    date find sort rm mv mktemp; do
    require_command "$command"
  done
  getent passwd "$BACKUP_USER" >/dev/null || die "backup user does not exist: $BACKUP_USER"
  getent group root >/dev/null || die 'required group does not exist: root'
  [[ -d "$(dirname "$LOCK_FILE")" ]] || die "lock directory does not exist: $(dirname "$LOCK_FILE")"

  exec 9>"$LOCK_FILE"
  flock -n 9 || die 'another backup-and-power-off run is already active'

  require_resources
  stop_running_container
  prepare_backup_directory
  create_staging_directory
  archive_volume
  prune_backups

  log 'backup succeeded; synchronizing filesystems before host power-off'
  sync || die 'filesystem synchronization failed'
  log 'powering off the host'
  systemctl poweroff || die 'systemctl poweroff failed'
}

trap cleanup EXIT
main "$@"
