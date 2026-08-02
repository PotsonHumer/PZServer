#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/pz-backup-and-poweroff.sh"
readonly REAL_TAR="$(command -v tar)"
if command -v sha256sum >/dev/null 2>&1; then
  readonly REAL_HASH_BINARY="$(command -v sha256sum)"
  readonly REAL_HASH_KIND='sha256sum'
else
  readonly REAL_HASH_BINARY="$(command -v shasum)"
  readonly REAL_HASH_KIND='shasum'
fi
readonly REAL_CHMOD="$(command -v chmod)"
readonly REAL_MV="$(command -v mv)"
readonly REAL_RM="$(command -v rm)"
readonly REAL_MKDIR="$(command -v mkdir)"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pz-backup-test.XXXXXX")"
MOCK_BIN="$TEST_DIR/mock-bin"
BACKUP_DIR="$TEST_DIR/backups"
SOURCE_DIR="$TEST_DIR/source"
STAGING_DIR="$TEST_DIR/staging"
STATE_FILE="$TEST_DIR/container-state"
MOCK_LOG="$TEST_DIR/mock.log"
CHOWN_LOG="$TEST_DIR/chown.log"

cleanup() {
  rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equals() {
  [[ "$1" == "$2" ]] || fail "expected '$1', got '$2'"
}

archive_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

create_mock() {
  mkdir -p "$MOCK_BIN" "$SOURCE_DIR/Saves/Multiplayer/420正版" "$SOURCE_DIR/Server"
  printf 'world-data\n' > "$SOURCE_DIR/Saves/Multiplayer/420正版/world.bin"
  printf 'server-config\n' > "$SOURCE_DIR/Server/420正版.ini"

  apply_mock docker '#!/usr/bin/env bash
set -Eeuo pipefail
case "$1" in
  container)
    [[ "$2" == inspect ]] && exit 0
    ;;
  volume)
    [[ "$2" == inspect ]] && exit 0
    ;;
  inspect)
    if [[ "$2" == --format ]]; then
      case "$3" in
        "{{.State.Running}}") cat "$MOCK_STATE_FILE" ;;
        "{{.State.ExitCode}}") printf "%s\\n" "$MOCK_EXIT_CODE" ;;
        *) exit 9 ;;
      esac
      exit 0
    fi
    ;;
  stop)
    printf "docker %s\\n" "$*" >> "$MOCK_LOG"
    printf "false\\n" > "$MOCK_STATE_FILE"
    exit 0
    ;;
  run)
    [[ "${MOCK_ARCHIVE_FAIL:-0}" == 0 ]] || exit 7
    backup=""
    target=""
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      if [[ "${args[i]}" == -v ]]; then
        mount="${args[i + 1]}"
        [[ "$mount" == *:/backup ]] && backup="${mount%:/backup}"
      fi
      if [[ "${args[i]}" == -czf ]]; then
        target="${args[i + 1]}"
      fi
    done
    [[ -n "$backup" && "$target" == /backup/* ]] || exit 8
    "$REAL_TAR" -C "$MOCK_SOURCE_DIR" -czf "$backup/${target#/backup/}" .
    exit 0
    ;;
esac
exit 10
'

  apply_mock id '#!/usr/bin/env bash
printf "0\\n"
'
  apply_mock getent '#!/usr/bin/env bash
exit 0
'
  apply_mock flock '#!/usr/bin/env bash
[[ "${MOCK_LOCK_FAIL:-0}" == 0 ]]
'
  apply_mock runuser '#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" == -u ]]
shift 2
[[ "$1" == -- ]]
shift
exec "$@"
'
  apply_mock sha256sum '#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" == --check ]]; then
  checksum_file="$2"
  read -r expected file_name < "$checksum_file"
  if [[ "$REAL_HASH_KIND" == sha256sum ]]; then
    actual="$($REAL_HASH_BINARY "$file_name")"
  else
    actual="$($REAL_HASH_BINARY -a 256 "$file_name")"
  fi
  actual="${actual%% *}"
  [[ "$actual" == "$expected" ]]
  exit
fi
if [[ "$REAL_HASH_KIND" == sha256sum ]]; then
  exec "$REAL_HASH_BINARY" "$1"
fi
exec "$REAL_HASH_BINARY" -a 256 "$1"
'
  apply_mock sync '#!/usr/bin/env bash
printf "sync\\n" >> "$MOCK_LOG"
'
  apply_mock systemctl '#!/usr/bin/env bash
printf "systemctl %s\\n" "$*" >> "$MOCK_LOG"
'
  apply_mock chown '#!/usr/bin/env bash
printf "chown %s\\n" "$*" >> "$CHOWN_LOG"
'

  apply_mock chmod '#!/usr/bin/env bash
set -Eeuo pipefail
args=()
for argument in "$@"; do
  [[ "$argument" == -- ]] || args+=("$argument")
done
exec "$REAL_CHMOD" "${args[@]}"
'

  apply_mock mv '#!/usr/bin/env bash
set -Eeuo pipefail
args=()
for argument in "$@"; do
  [[ "$argument" == -- ]] || args+=("$argument")
done
exec "$REAL_MV" "${args[@]}"
'

  apply_mock rm '#!/usr/bin/env bash
set -Eeuo pipefail
args=()
for argument in "$@"; do
  [[ "$argument" == -- ]] || args+=("$argument")
done
exec "$REAL_RM" "${args[@]}"
'

  apply_mock mkdir '#!/usr/bin/env bash
set -Eeuo pipefail
args=()
for argument in "$@"; do
  [[ "$argument" == -- ]] || args+=("$argument")
done
exec "$REAL_MKDIR" "${args[@]}"
'

  apply_mock mktemp '#!/usr/bin/env bash
set -Eeuo pipefail
"$REAL_RM" -rf "$MOCK_STAGING_DIR"
"$REAL_MKDIR" -p "$MOCK_STAGING_DIR"
printf "%s\\n" "$MOCK_STAGING_DIR"
'

  apply_mock find '#!/usr/bin/env bash
set -Eeuo pipefail
directory="$1"
shopt -s nullglob
for path in "$directory"/pz-data-*.tar.gz; do
  [[ -f "$path" ]] && basename "$path"
done
'
  apply_mock tar '#!/usr/bin/env bash
exit 0
'
}

apply_mock() {
  local name="$1"
  local contents="$2"
  local target="$MOCK_BIN/$name"

  printf '%s' "$contents" > "$target"
  chmod 0755 "$target"
}

run_workflow() {
  env \
    PATH="$MOCK_BIN:$PATH" \
    REAL_TAR="$REAL_TAR" \
    REAL_HASH_BINARY="$REAL_HASH_BINARY" \
    REAL_HASH_KIND="$REAL_HASH_KIND" \
    REAL_CHMOD="$REAL_CHMOD" \
    REAL_MV="$REAL_MV" \
    REAL_RM="$REAL_RM" \
    REAL_MKDIR="$REAL_MKDIR" \
    MOCK_SOURCE_DIR="$SOURCE_DIR" \
    MOCK_STATE_FILE="$STATE_FILE" \
    MOCK_STAGING_DIR="$STAGING_DIR" \
    MOCK_EXIT_CODE="$MOCK_EXIT_CODE" \
    MOCK_LOG="$MOCK_LOG" \
    CHOWN_LOG="$CHOWN_LOG" \
    MOCK_ARCHIVE_FAIL="$MOCK_ARCHIVE_FAIL" \
    MOCK_LOCK_FAIL="$MOCK_LOCK_FAIL" \
    PZ_BACKUP_DIR="$BACKUP_DIR" \
    PZ_BACKUP_LOCK_FILE="$TEST_DIR/workflow.lock" \
    bash "$SCRIPT_UNDER_TEST"
}

create_mock
printf 'true\n' > "$STATE_FILE"
: > "$MOCK_LOG"
: > "$CHOWN_LOG"
MOCK_EXIT_CODE=0
MOCK_ARCHIVE_FAIL=0
MOCK_LOCK_FAIL=0

# A running container stops, creates a valid archive, and requests power-off.
run_workflow
assert_equals 1 "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"
grep -Fqx 'docker stop --timeout 120 pz-server' "$MOCK_LOG" || fail 'expected Docker stop call'
grep -Fqx 'systemctl poweroff' "$MOCK_LOG" || fail 'expected power-off call'
grep -Fq 'chown potsonhumer:root' "$CHOWN_LOG" || fail 'expected finalized ownership request'

first_archive="$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f -print -quit)"
assert_equals 640 "$(archive_mode "$first_archive")"
if [[ "$REAL_HASH_KIND" == sha256sum ]]; then
  (cd "$BACKUP_DIR" && "$REAL_HASH_BINARY" --check "$(basename "$first_archive").sha256") >/dev/null
else
  (cd "$BACKUP_DIR" && "$REAL_HASH_BINARY" -a 256 -c "$(basename "$first_archive").sha256") >/dev/null
fi
"$REAL_TAR" -tzf "$first_archive" | grep -Fqx './Saves/Multiplayer/420正版/world.bin' || \
  fail 'archive does not contain the multiplayer world'
"$REAL_TAR" -tzf "$first_archive" | grep -Fqx './Server/420正版.ini' || \
  fail 'archive does not contain the server configuration'

# An already stopped container is still backed up, and four successes retain three.
run_workflow
run_workflow
run_workflow
assert_equals 3 "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"
assert_equals 3 "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz.sha256' -type f | wc -l | tr -d ' ')"

poweroff_count_before="$(grep -c '^systemctl poweroff$' "$MOCK_LOG")"
archive_count_before="$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"

# A lock conflict does not stop or power off the host.
MOCK_LOCK_FAIL=1
if run_workflow; then
  fail 'lock conflict unexpectedly succeeded'
fi
MOCK_LOCK_FAIL=0
assert_equals "$poweroff_count_before" "$(grep -c '^systemctl poweroff$' "$MOCK_LOG")"

# An archive failure preserves the three finalized backups and skips power-off.
MOCK_ARCHIVE_FAIL=1
if run_workflow; then
  fail 'archive failure unexpectedly succeeded'
fi
MOCK_ARCHIVE_FAIL=0
assert_equals "$archive_count_before" "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"
assert_equals "$poweroff_count_before" "$(grep -c '^systemctl poweroff$' "$MOCK_LOG")"

# Exit code 137 after a requested stop skips archive and power-off.
printf 'true\n' > "$STATE_FILE"
MOCK_EXIT_CODE=137
if run_workflow; then
  fail 'forced-stop path unexpectedly succeeded'
fi
assert_equals "$archive_count_before" "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"
assert_equals "$poweroff_count_before" "$(grep -c '^systemctl poweroff$' "$MOCK_LOG")"

printf 'PASS: pz-backup-and-poweroff mock workflow\n'
