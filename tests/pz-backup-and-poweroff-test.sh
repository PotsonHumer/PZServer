#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/pz-backup-and-poweroff.sh"
readonly REAL_RM="$(command -v rm)"
readonly REAL_MKDIR="$(command -v mkdir)"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pz-backup-poweroff-test.XXXXXX")"
MOCK_BIN="$TEST_DIR/mock-bin"
COMPOSE_DIR="$TEST_DIR/compose"
MOCK_LOG="$TEST_DIR/mock.log"

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

apply_mock() {
  local name="$1"
  local contents="$2"

  printf '%s' "$contents" > "$MOCK_BIN/$name"
  chmod 0755 "$MOCK_BIN/$name"
}

mkdir -p "$MOCK_BIN" "$COMPOSE_DIR"
touch "$COMPOSE_DIR/compose.yaml"

apply_mock docker '#!/usr/bin/env bash
set -Eeuo pipefail
case "$1 $2" in
  "compose version")
    exit 0
    ;;
  "compose run")
    [[ "$3" == --rm && "$4" == --no-deps && "$5" == pz-backup ]] || exit 9
    printf "docker compose run --rm --no-deps pz-backup\n" >> "$MOCK_LOG"
    [[ "${MOCK_COMPOSE_FAIL:-0}" == 0 ]]
    exit
    ;;
esac
exit 10
'
apply_mock id '#!/usr/bin/env bash
printf "0\n"
'
apply_mock flock '#!/usr/bin/env bash
[[ "${MOCK_LOCK_FAIL:-0}" == 0 ]]
'
apply_mock sync '#!/usr/bin/env bash
printf "sync\n" >> "$MOCK_LOG"
'
apply_mock systemctl '#!/usr/bin/env bash
printf "systemctl %s\n" "$*" >> "$MOCK_LOG"
'

run_workflow() {
  env \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_LOG="$MOCK_LOG" \
    MOCK_COMPOSE_FAIL="$MOCK_COMPOSE_FAIL" \
    MOCK_LOCK_FAIL="$MOCK_LOCK_FAIL" \
    PZ_COMPOSE_DIR="$COMPOSE_DIR" \
    PZ_BACKUP_LOCK_FILE="$TEST_DIR/workflow.lock" \
    bash "$SCRIPT_UNDER_TEST"
}

: > "$MOCK_LOG"
MOCK_COMPOSE_FAIL=0
MOCK_LOCK_FAIL=0

run_workflow
grep -Fqx 'docker compose run --rm --no-deps pz-backup' "$MOCK_LOG" || fail 'expected Compose backup call'
grep -Fqx 'sync' "$MOCK_LOG" || fail 'expected filesystem synchronization'
grep -Fqx 'systemctl poweroff' "$MOCK_LOG" || fail 'expected power-off call'
grep -Fq 'docker stop' "$MOCK_LOG" && fail 'wrapper attempted a forced Docker stop'

poweroff_count_before="$(grep -c '^systemctl poweroff$' "$MOCK_LOG")"
MOCK_COMPOSE_FAIL=1
if run_workflow; then
  fail 'Compose backup failure unexpectedly succeeded'
fi
MOCK_COMPOSE_FAIL=0
assert_equals "$poweroff_count_before" "$(grep -c '^systemctl poweroff$' "$MOCK_LOG")"

MOCK_LOCK_FAIL=1
if run_workflow; then
  fail 'lock conflict unexpectedly succeeded'
fi
MOCK_LOCK_FAIL=0
assert_equals "$poweroff_count_before" "$(grep -c '^systemctl poweroff$' "$MOCK_LOG")"

printf 'PASS: Compose-backed backup-and-poweroff workflow\n'
