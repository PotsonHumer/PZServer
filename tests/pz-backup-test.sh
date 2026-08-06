#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DOCKERFILE="$REPO_ROOT/Dockerfile"
readonly REAL_TAR="$(command -v tar)"
readonly REAL_RM="$(command -v rm)"
readonly REAL_MV="$(command -v mv)"
readonly REAL_CHMOD="$(command -v chmod)"
if command -v sha256sum >/dev/null 2>&1; then
  readonly REAL_HASH_BINARY="$(command -v sha256sum)"
  readonly REAL_HASH_KIND='sha256sum'
else
  readonly REAL_HASH_BINARY="$(command -v shasum)"
  readonly REAL_HASH_KIND='shasum'
fi

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pz-backup-test.XXXXXX")"
MOCK_BIN="$TEST_DIR/mock-bin"
SOURCE_DIR="$TEST_DIR/source"
BACKUP_DIR="$TEST_DIR/backups"
MOCK_LOG="$TEST_DIR/mock.log"
CHOWN_LOG="$TEST_DIR/chown.log"
RUNNER="$TEST_DIR/pz-backup"

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

extract_runner() {
  awk '
    $0 == "COPY --chmod=755 <<\047EOF\047 /usr/local/bin/pz-backup" { in_block = 1; next }
    in_block && $0 == "EOF" { exit }
    in_block { print }
  ' "$DOCKERFILE" > "$RUNNER"
  [[ -s "$RUNNER" ]] || fail 'could not extract pz-backup from Dockerfile'
  chmod 0755 "$RUNNER"
}

apply_mock() {
  local name="$1"
  local contents="$2"

  printf '%s' "$contents" > "$MOCK_BIN/$name"
  chmod 0755 "$MOCK_BIN/$name"
}

create_mocks() {
  mkdir -p "$MOCK_BIN" "$SOURCE_DIR/Saves/Multiplayer/420正版" "$SOURCE_DIR/Server" "$BACKUP_DIR"
  printf 'world-data\n' > "$SOURCE_DIR/Saves/Multiplayer/420正版/world.bin"
  printf 'server-config\n' > "$SOURCE_DIR/Server/420正版.ini"

  apply_mock docker '#!/usr/bin/env bash
set -Eeuo pipefail
case "$1" in
  inspect)
    [[ "$2" == --format && "$3" == "{{.State.Running}}" && "$4" == pz-server ]] || exit 9
    printf "%s\n" "$MOCK_RUNNING"
    ;;
  wait)
    [[ "$2" == pz-server ]] || exit 9
    printf "docker wait pz-server\n" >> "$MOCK_LOG"
    printf "%s\n" "$MOCK_WAIT_EXIT"
    ;;
  *) exit 10 ;;
esac
'
  apply_mock pz-rcon '#!/usr/bin/env bash
set -Eeuo pipefail
printf "pz-rcon %s\n" "$1" >> "$MOCK_LOG"
[[ "$MOCK_RCON_FAIL" != "$1" ]]
'
  apply_mock flock '#!/usr/bin/env bash
[[ "${MOCK_LOCK_FAIL:-0}" == 0 ]]
'
  apply_mock tar '#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${MOCK_ARCHIVE_FAIL:-0}" == 0 ]] || exit 7
exec "$REAL_TAR" "$@"
'
  apply_mock sha256sum '#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" == --check ]]; then
  read -r expected file_name < "$2"
  if [[ "$REAL_HASH_KIND" == sha256sum ]]; then
    actual="$($REAL_HASH_BINARY "$file_name")"
  else
    actual="$($REAL_HASH_BINARY -a 256 "$file_name")"
  fi
  [[ "${actual%% *}" == "$expected" ]]
  exit
fi
if [[ "$REAL_HASH_KIND" == sha256sum ]]; then
  exec "$REAL_HASH_BINARY" "$1"
fi
exec "$REAL_HASH_BINARY" -a 256 "$1"
'
  apply_mock stat '#!/usr/bin/env bash
[[ "$1" == --format && "$2" == %u:%g ]] || exit 9
printf "501:20\n"
'
  apply_mock chown '#!/usr/bin/env bash
printf "chown %s\n" "$*" >> "$CHOWN_LOG"
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
  apply_mock find '#!/usr/bin/env bash
set -Eeuo pipefail
directory="$1"
shopt -s nullglob
for path in "$directory"/pz-data-*.tar.gz; do
  [[ -f "$path" ]] && basename "$path"
done
'
}

run_runner() {
  env \
    PATH="$MOCK_BIN:$PATH" \
    REAL_TAR="$REAL_TAR" \
    REAL_HASH_BINARY="$REAL_HASH_BINARY" \
    REAL_HASH_KIND="$REAL_HASH_KIND" \
    REAL_RM="$REAL_RM" \
    REAL_MV="$REAL_MV" \
    REAL_CHMOD="$REAL_CHMOD" \
    MOCK_LOG="$MOCK_LOG" \
    CHOWN_LOG="$CHOWN_LOG" \
    MOCK_RUNNING="$MOCK_RUNNING" \
    MOCK_WAIT_EXIT="$MOCK_WAIT_EXIT" \
    MOCK_RCON_FAIL="$MOCK_RCON_FAIL" \
    MOCK_LOCK_FAIL="$MOCK_LOCK_FAIL" \
    MOCK_ARCHIVE_FAIL="$MOCK_ARCHIVE_FAIL" \
    PZ_CONTAINER_NAME=pz-server \
    PZ_DATA_DIR="$SOURCE_DIR" \
    PZ_BACKUP_SOURCE_DIR="$SOURCE_DIR" \
    PZ_BACKUP_DIR="$BACKUP_DIR" \
    bash "$RUNNER"
}

extract_runner
create_mocks
: > "$MOCK_LOG"
: > "$CHOWN_LOG"
MOCK_RUNNING=true
MOCK_WAIT_EXIT=0
MOCK_RCON_FAIL=''
MOCK_LOCK_FAIL=0
MOCK_ARCHIVE_FAIL=0

run_runner
first_archive="$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f -print -quit)"
[[ -n "$first_archive" ]] || fail 'backup archive was not created'
assert_equals 640 "$(archive_mode "$first_archive")"
grep -Fqx 'pz-rcon save' "$MOCK_LOG" || fail 'expected RCON save'
grep -Fqx 'pz-rcon quit' "$MOCK_LOG" || fail 'expected RCON quit'
grep -Fqx 'docker wait pz-server' "$MOCK_LOG" || fail 'expected Docker wait'
grep -Fq 'chown 501:20' "$CHOWN_LOG" || fail 'expected destination ownership request'
"$REAL_TAR" -tzf "$first_archive" | grep -Fqx './Saves/Multiplayer/420正版/world.bin' || \
  fail 'archive does not contain the multiplayer world'

run_runner
run_runner
run_runner
assert_equals 3 "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"

archive_count_before="$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"
MOCK_RCON_FAIL=save
if run_runner; then
  fail 'RCON save failure unexpectedly succeeded'
fi
MOCK_RCON_FAIL=''
assert_equals "$archive_count_before" "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"

MOCK_WAIT_EXIT=137
if run_runner; then
  fail 'unclean container exit unexpectedly succeeded'
fi
MOCK_WAIT_EXIT=0
assert_equals "$archive_count_before" "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"

MOCK_ARCHIVE_FAIL=1
if run_runner; then
  fail 'archive failure unexpectedly succeeded'
fi
MOCK_ARCHIVE_FAIL=0
assert_equals "$archive_count_before" "$(find "$BACKUP_DIR" -name 'pz-data-*.tar.gz' -type f | wc -l | tr -d ' ')"

MOCK_RUNNING=false
if run_runner; then
  fail 'stopped server unexpectedly started a backup'
fi
grep -Fq 'docker stop' "$MOCK_LOG" && fail 'runner attempted a forced Docker stop'

printf 'PASS: RCON-safe Compose backup runner\n'
