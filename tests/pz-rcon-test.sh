#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DOCKERFILE="$REPO_ROOT/Dockerfile"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pz-rcon-test.XXXXXX")"

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

extract_heredoc() {
  local target="$1"
  local output="$2"

  awk -v target="$target" '
    $0 == "COPY --chmod=755 <<\047EOF\047 " target { in_block = 1; next }
    in_block && $0 == "EOF" { exit }
    in_block { print }
  ' "$DOCKERFILE" > "$output"
  [[ -s "$output" ]] || fail "could not extract $target from Dockerfile"
  chmod 0755 "$output"
}

ENTRYPOINT="$TEST_DIR/pz-entrypoint.sh"
PZ_RCON="$TEST_DIR/pz-rcon"
extract_heredoc /usr/local/bin/pz-entrypoint.sh "$ENTRYPOINT"
extract_heredoc /usr/local/bin/pz-rcon "$PZ_RCON"

PZ_SERVER_DIR="$TEST_DIR/pzserver"
PZ_DATA_DIR="$TEST_DIR/Zomboid"
PASSWORD_FILE="$TEST_DIR/rcon-password"
START_LOG="$TEST_DIR/start.log"
LAUNCHER_LOG="$TEST_DIR/launcher.json"
MCRCON_LOG="$TEST_DIR/mcrcon.log"
mkdir -p "$PZ_SERVER_DIR" "$PZ_DATA_DIR"

cat > "$PZ_SERVER_DIR/start-server.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$START_LOG"
cp "$PZ_SERVER_DIR/ProjectZomboid64.json" "$LAUNCHER_LOG"
EOF
chmod 0755 "$PZ_SERVER_DIR/start-server.sh"

cat > "$PZ_SERVER_DIR/ProjectZomboid64.json" <<'EOF'
{
  "vmArgs": [
    "-Djava.awt.headless=true",
    "-Xmx8g",
    "-Dtest=true"
  ]
}
EOF
cp "$PZ_SERVER_DIR/ProjectZomboid64.json" "$PZ_SERVER_DIR/ProjectZomboid64.default.json"
chmod 0444 "$PZ_SERVER_DIR/ProjectZomboid64.default.json"

cat > "$TEST_DIR/mcrcon" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
{
  printf 'host=%s\n' "$MCRCON_HOST"
  printf 'port=%s\n' "$MCRCON_PORT"
  printf 'password=%s\n' "$MCRCON_PASS"
  printf 'argc=%s\n' "$#"
  printf 'arg1=%s\n' "$1"
} > "$MCRCON_LOG"
printf 'mock response\n'
EOF
chmod 0755 "$TEST_DIR/mcrcon"
sed "s|/usr/local/bin/mcrcon|${TEST_DIR}/mcrcon|" "$PZ_RCON" > "$PZ_RCON.tmp"
mv "$PZ_RCON.tmp" "$PZ_RCON"
chmod 0755 "$PZ_RCON"

run_entrypoint() {
  env \
    HOME="$TEST_DIR/home" \
    PZ_SERVER_DIR="$PZ_SERVER_DIR" \
    PZ_DATA_DIR="$PZ_DATA_DIR" \
    PZ_JAVA_XMX= \
    START_LOG="$START_LOG" \
    LAUNCHER_LOG="$LAUNCHER_LOG" \
    "$@" \
    "$ENTRYPOINT"
}

printf 'first-secret\n' > "$PASSWORD_FILE"
entrypoint_output="$TEST_DIR/entrypoint-output"
run_entrypoint \
  PZ_RCON_PASSWORD_FILE="$PASSWORD_FILE" \
  PZ_RCON_PORT=27015 \
  PZ_SERVER_NAME=local-rcon \
  > "$entrypoint_output" 2>&1

config_path="$PZ_DATA_DIR/Server/local-rcon.ini"
[[ -f "$config_path" ]] || fail 'RCON config was not created'
grep -Fqx 'RCONPort=27015' "$config_path" || fail 'RCON port was not configured'
grep -Fqx 'RCONPassword=first-secret' "$config_path" || fail 'RCON password was not configured'
assert_equals 600 "$(stat -f '%Lp' "$config_path" 2>/dev/null || stat -c '%a' "$config_path")"
grep -Fq -- 'first-secret' "$entrypoint_output" && fail 'entrypoint exposed the password'
grep -Fqx -- '-servername' "$START_LOG" || fail 'entrypoint did not select the RCON server name'
grep -Fqx -- 'local-rcon' "$START_LOG" || fail 'entrypoint did not pass the RCON server name'
grep -Fq '"-Xmx8g"' "$LAUNCHER_LOG" || fail 'entrypoint did not preserve the default Java heap'

printf 'second-secret\n' > "$PASSWORD_FILE"
run_entrypoint \
  PZ_RCON_PASSWORD_FILE="$PASSWORD_FILE" \
  PZ_RCON_PORT=27016 \
  PZ_SERVER_NAME=local-rcon \
  > "$entrypoint_output" 2>&1
assert_equals 1 "$(grep -c '^RCONPort=' "$config_path")"
assert_equals 1 "$(grep -c '^RCONPassword=' "$config_path")"
grep -Fqx 'RCONPort=27016' "$config_path" || fail 'RCON port was not updated'
grep -Fqx 'RCONPassword=second-secret' "$config_path" || fail 'RCON password was not updated'

if run_entrypoint \
  PZ_RCON_PASSWORD_FILE="$TEST_DIR/missing-password" \
  PZ_SERVER_NAME=local-rcon \
  > "$entrypoint_output" 2>&1; then
  fail 'missing password file unexpectedly started the server'
fi
grep -Fq 'password file is unavailable' "$entrypoint_output" || fail 'missing password error was not reported'
grep -Fq -- 'second-secret' "$entrypoint_output" && fail 'missing password error exposed a secret'

rm -rf -- "$PZ_DATA_DIR"
run_entrypoint > "$entrypoint_output" 2>&1
[[ ! -e "$PZ_DATA_DIR/Server/servertest.ini" ]] || fail 'RCON config was created without opt-in'

run_entrypoint PZ_JAVA_XMX=2g > "$entrypoint_output" 2>&1
assert_equals 1 "$(grep -c '"-Xmx2g"' "$LAUNCHER_LOG")"
grep -R -F -- '-Xmx2g' "$PZ_DATA_DIR" >/dev/null 2>&1 && fail 'Java heap override was written to persistent data'

run_entrypoint > "$entrypoint_output" 2>&1
assert_equals 1 "$(grep -c '"-Xmx8g"' "$LAUNCHER_LOG")"

rm -f "$START_LOG" "$LAUNCHER_LOG"
if run_entrypoint PZ_JAVA_XMX='2g -XX:+UseSerialGC' > "$entrypoint_output" 2>&1; then
  fail 'invalid Java heap override unexpectedly started the server'
fi
grep -Fq 'PZ_JAVA_XMX must be a positive whole number followed by m or g' "$entrypoint_output" || \
  fail 'invalid Java heap error was not reported'
[[ ! -e "$START_LOG" ]] || fail 'invalid Java heap override started the server command'

mkdir -p "$PZ_DATA_DIR/Server"
printf 'RCONPort=27016\nRCONPassword=second-secret\n' > "$config_path"
env \
  HOME="$TEST_DIR/home" \
  PZ_DATA_DIR="$PZ_DATA_DIR" \
  PZ_SERVER_NAME=local-rcon \
  MCRCON_LOG="$MCRCON_LOG" \
  PATH="$TEST_DIR:$PATH" \
  "$PZ_RCON" 'servermsg "maintenance soon"' > "$TEST_DIR/rcon-output" 2>&1

grep -Fqx 'host=127.0.0.1' "$MCRCON_LOG" || fail 'wrapper did not use loopback'
grep -Fqx 'port=27016' "$MCRCON_LOG" || fail 'wrapper used the wrong port'
grep -Fqx 'password=second-secret' "$MCRCON_LOG" || fail 'wrapper did not authenticate'
grep -Fqx 'argc=1' "$MCRCON_LOG" || fail 'wrapper split the supplied command'
grep -Fqx 'arg1=servermsg "maintenance soon"' "$MCRCON_LOG" || fail 'wrapper changed the supplied command'
grep -Fqx 'mock response' "$TEST_DIR/rcon-output" || fail 'wrapper did not relay the client response'

grep -Eq '^EXPOSE .*tcp' "$DOCKERFILE" && fail 'Dockerfile exposes a TCP port'
grep -Fq 'MCRCON_X64_STATIC_SHA256=790bfdd4f51245bc40f909e3a915f98cf569f57b0edf47697f5d72e0b86c2877' "$DOCKERFILE" || \
  fail 'Dockerfile does not pin the mcrcon archive checksum'

printf 'PASS: pz-rcon configuration and local-wrapper workflow\n'
