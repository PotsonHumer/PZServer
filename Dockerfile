# syntax=docker/dockerfile:1
# Download server files natively on the builder architecture; run the x86_64
# game through the host's Linux/amd64 runtime (Rosetta in OrbStack/Docker Desktop).
FROM --platform=$BUILDPLATFORM debian:trixie-slim AS downloader

ARG PZ_APP_ID=380870
ARG BUILDARCH
ARG DEPOT_DOWNLOADER_VERSION=3.4.0
ARG DEPOT_DOWNLOADER_ARM64_SHA256=d9fb612ccebc1db8eeea3b4045d2221ec70431381393ce908fb72f01d4f9c812
ARG DEPOT_DOWNLOADER_X64_SHA256=a999dec66b4850fc961bd50366696d23c2d0fad7b18790e6a5647b2f19097a53

ENV PZ_SERVER_DIR=/home/steam/pzserver

USER root

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

RUN case "${BUILDARCH}" in \
        arm64) depotdownloader_arch=arm64; depotdownloader_sha256="${DEPOT_DOWNLOADER_ARM64_SHA256}" ;; \
        amd64) depotdownloader_arch=x64; depotdownloader_sha256="${DEPOT_DOWNLOADER_X64_SHA256}" ;; \
        *) echo "Unsupported build architecture: ${BUILDARCH}" >&2; exit 1 ;; \
    esac \
    && curl --fail --location --silent --show-error \
        --output /tmp/depotdownloader.zip \
        "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-${depotdownloader_arch}.zip" \
    && echo "${depotdownloader_sha256}  /tmp/depotdownloader.zip" | sha256sum --check \
    && unzip -q /tmp/depotdownloader.zip -d /tmp/depotdownloader \
    && install --mode=755 /tmp/depotdownloader/DepotDownloader /usr/local/bin/DepotDownloader \
    && rm -rf /tmp/depotdownloader /tmp/depotdownloader.zip

RUN mkdir -p "${PZ_SERVER_DIR}" \
    && (DepotDownloader \
        -app "${PZ_APP_ID}" \
        -os linux \
        -dir "${PZ_SERVER_DIR}" \
        > /tmp/depotdownloader.log 2>&1 \
        || { tail -n 200 /tmp/depotdownloader.log; exit 1; }) \
    && test -f "${PZ_SERVER_DIR}/start-server.sh" \
    && chmod 755 \
        "${PZ_SERVER_DIR}/start-server.sh" \
        "${PZ_SERVER_DIR}/ProjectZomboid64" \
        "${PZ_SERVER_DIR}/jre64/bin/java" \
    && rm -f /tmp/depotdownloader.log

FROM --platform=$BUILDPLATFORM debian:trixie-slim AS rcon-client

# mcrcon is distributed under the zlib License.
ARG MCRCON_VERSION=0.7.2
ARG MCRCON_X64_STATIC_SHA256=790bfdd4f51245bc40f909e3a915f98cf569f57b0edf47697f5d72e0b86c2877

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --silent --show-error \
        --output /tmp/mcrcon.zip \
        "https://github.com/Tiiffi/mcrcon/releases/download/v${MCRCON_VERSION}/mcrcon-${MCRCON_VERSION}-linux-x86-64-static.zip" \
    && echo "${MCRCON_X64_STATIC_SHA256}  /tmp/mcrcon.zip" | sha256sum --check \
    && unzip -q /tmp/mcrcon.zip -d /tmp/mcrcon \
    && find /tmp/mcrcon -type f -name mcrcon -exec install --mode=755 {} /usr/local/bin/mcrcon \; \
    && test -x /usr/local/bin/mcrcon \
    && rm -rf /tmp/mcrcon /tmp/mcrcon.zip

FROM --platform=$TARGETPLATFORM docker:27.5.1-cli AS docker-client

FROM ubuntu:24.04

ENV PZ_SERVER_DIR=/home/steam/pzserver \
    PZ_DATA_DIR=/home/steam/Zomboid \
    HOME=/home/steam \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    PZ_JAVA_XMX=

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash steam \
    && mkdir -p "${PZ_DATA_DIR}" \
    && chown steam:steam "${PZ_DATA_DIR}"

COPY --from=downloader --chown=steam:steam /home/steam/pzserver ${PZ_SERVER_DIR}
COPY --from=rcon-client --chmod=755 /usr/local/bin/mcrcon /usr/local/bin/mcrcon
COPY --from=docker-client --chmod=755 /usr/local/bin/docker /usr/local/bin/docker

RUN install --mode=0444 \
        "${PZ_SERVER_DIR}/ProjectZomboid64.json" \
        "${PZ_SERVER_DIR}/ProjectZomboid64.default.json"

COPY --chmod=755 <<'EOF' /usr/local/bin/pz-entrypoint.sh
#!/usr/bin/env bash

set -Eeuo pipefail

: "${PZ_SERVER_DIR:=/home/steam/pzserver}"
: "${PZ_DATA_DIR:=${HOME}/Zomboid}"
: "${PZ_SERVER_NAME:=servertest}"
: "${PZ_RCON_PORT:=27015}"

if [[ ! -x "${PZ_SERVER_DIR}/start-server.sh" ]]; then
  echo "Project Zomboid server startup script is missing: ${PZ_SERVER_DIR}/start-server.sh" >&2
  exit 1
fi

mkdir -p "${PZ_DATA_DIR}"

fail_rcon_configuration() {
  echo "Project Zomboid RCON configuration error: $1" >&2
  exit 1
}

fail_java_heap_configuration() {
  echo "Project Zomboid Java heap configuration error: $1" >&2
  exit 1
}

configure_java_heap() {
  local launcher_config="${PZ_SERVER_DIR}/ProjectZomboid64.json"
  local launcher_baseline="${PZ_SERVER_DIR}/ProjectZomboid64.default.json"
  local temporary_path match_count

  [[ -r "${launcher_baseline}" ]] || \
    fail_java_heap_configuration 'launcher baseline is unavailable'

  temporary_path="$(mktemp "${PZ_SERVER_DIR}/.ProjectZomboid64.json.tmp.XXXXXX")"
  cp -- "${launcher_baseline}" "${temporary_path}"
  chmod 0644 "${temporary_path}"
  mv -- "${temporary_path}" "${launcher_config}"

  [[ -n "${PZ_JAVA_XMX}" ]] || return 0
  [[ "${PZ_JAVA_XMX}" =~ ^[1-9][0-9]*[mMgG]$ ]] || \
    fail_java_heap_configuration 'PZ_JAVA_XMX must be a positive whole number followed by m or g'

  match_count="$(grep -oE '"-Xmx[^"]*"' "${launcher_config}" | wc -l || true)"
  [[ "${match_count}" -eq 1 ]] || \
    fail_java_heap_configuration 'launcher configuration must contain exactly one -Xmx argument'

  temporary_path="$(mktemp "${PZ_SERVER_DIR}/.ProjectZomboid64.json.tmp.XXXXXX")"
  sed "s/\"-Xmx[^\"]*\"/\"-Xmx${PZ_JAVA_XMX}\"/" "${launcher_config}" > "${temporary_path}"
  grep -Fqx "    \"-Xmx${PZ_JAVA_XMX}\"," "${temporary_path}" || \
    grep -Fq "\"-Xmx${PZ_JAVA_XMX}\"" "${temporary_path}" || \
    fail_java_heap_configuration 'could not update the launcher heap argument'
  chmod 0644 "${temporary_path}"
  mv -- "${temporary_path}" "${launcher_config}"
}

update_ini_setting() {
  local config_path="$1"
  local key="$2"
  local value="$3"
  local temporary_path line written='false'

  umask 077
  temporary_path="$(mktemp "${config_path}.tmp.XXXXXX")"

  if [[ -f "${config_path}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" == "${key}="* ]]; then
        if [[ "${written}" == 'false' ]]; then
          printf '%s=%s\n' "${key}" "${value}" >> "${temporary_path}"
          written='true'
        fi
      else
        printf '%s\n' "${line}" >> "${temporary_path}"
      fi
    done < "${config_path}"
  fi

  if [[ "${written}" == 'false' ]]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${temporary_path}"
  fi

  chmod 600 "${temporary_path}"
  mv -- "${temporary_path}" "${config_path}"
}

configure_rcon() {
  local password_file password server_config argument

  [[ -n "${PZ_RCON_PASSWORD_FILE:-}" ]] || return 0
  [[ -f "${PZ_RCON_PASSWORD_FILE}" && -r "${PZ_RCON_PASSWORD_FILE}" ]] || \
    fail_rcon_configuration 'password file is unavailable'
  [[ -n "${PZ_SERVER_NAME}" && "${PZ_SERVER_NAME}" != */* && "${PZ_SERVER_NAME}" != *$'\n'* ]] || \
    fail_rcon_configuration 'server name is invalid'
  [[ "${PZ_RCON_PORT}" =~ ^[1-9][0-9]{0,4}$ ]] && (( PZ_RCON_PORT <= 65535 )) || \
    fail_rcon_configuration 'port is invalid'

  IFS= read -r password < "${PZ_RCON_PASSWORD_FILE}" || true
  password="${password%$'\r'}"
  [[ -n "${password}" ]] || fail_rcon_configuration 'password file is empty'

  for argument in "$@"; do
    [[ "${argument}" != '-servername' ]] || \
      fail_rcon_configuration 'use PZ_SERVER_NAME instead of a -servername argument when RCON is enabled'
  done

  mkdir -p "${PZ_DATA_DIR}/Server"
  server_config="${PZ_DATA_DIR}/Server/${PZ_SERVER_NAME}.ini"
  update_ini_setting "${server_config}" 'RCONPort' "${PZ_RCON_PORT}"
  update_ini_setting "${server_config}" 'RCONPassword' "${password}"
}

configure_rcon "$@"
configure_java_heap

server_command=("${PZ_SERVER_DIR}/start-server.sh" "$@")
if [[ -n "${PZ_RCON_PASSWORD_FILE:-}" ]]; then
  server_command+=('-servername' "${PZ_SERVER_NAME}")
fi

if [[ -z "${PZ_ADMIN_PASSWORD:-}" ]]; then
  exec "${server_command[@]}"
fi

runtime_dir="$(mktemp -d)"
input_fifo="${runtime_dir}/input"
output_fifo="${runtime_dir}/output"
server_pid=""

cleanup() {
  rm -f "${input_fifo}" "${output_fifo}"
  rmdir "${runtime_dir}" 2>/dev/null || true
}

shutdown() {
  if [[ -n "${server_pid}" ]]; then
    kill -TERM -- "-${server_pid}" 2>/dev/null || kill -TERM "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" || true
  fi
  exit 0
}

trap cleanup EXIT
trap shutdown INT TERM

mkfifo --mode=600 "${input_fifo}" "${output_fifo}"
setsid "${server_command[@]}" <"${input_fifo}" >"${output_fifo}" 2>&1 &
server_pid="$!"
exec 3>"${input_fifo}"

while IFS= read -r line || [[ -n "${line}" ]]; do
  printf '%s\n' "${line}"
  if [[ "${line}" == *"Enter new administrator password:"* || "${line}" == *"Confirm the password:"* ]]; then
    printf '%s\n' "${PZ_ADMIN_PASSWORD}" >&3
  fi
done <"${output_fifo}"

wait "${server_pid}"
EOF

COPY --chmod=755 <<'EOF' /usr/local/bin/pz-rcon
#!/usr/bin/env bash

set -Eeuo pipefail

: "${PZ_DATA_DIR:=${HOME}/Zomboid}"
: "${PZ_SERVER_NAME:=servertest}"

fail() {
  echo "pz-rcon: $1" >&2
  exit 1
}

read_ini_value() {
  local config_path="$1"
  local key="$2"
  local line

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "${key}="* ]]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  done < "${config_path}"

  return 1
}

(( $# > 0 )) || fail 'provide at least one Project Zomboid command'
[[ -n "${PZ_SERVER_NAME}" && "${PZ_SERVER_NAME}" != */* && "${PZ_SERVER_NAME}" != *$'\n'* ]] || \
  fail 'server name is invalid'

server_config="${PZ_DATA_DIR}/Server/${PZ_SERVER_NAME}.ini"
[[ -r "${server_config}" ]] || fail 'RCON is not configured for this server'
rcon_port="$(read_ini_value "${server_config}" 'RCONPort')" || fail 'RCON port is not configured'
rcon_password="$(read_ini_value "${server_config}" 'RCONPassword')" || fail 'RCON password is not configured'
rcon_password="${rcon_password%$'\r'}"

[[ "${rcon_port}" =~ ^[1-9][0-9]{0,4}$ ]] && (( rcon_port <= 65535 )) || fail 'RCON port is invalid'
[[ -n "${rcon_password}" ]] || fail 'RCON password is empty'

MCRCON_HOST=127.0.0.1 \
MCRCON_PORT="${rcon_port}" \
MCRCON_PASS="${rcon_password}" \
  exec /usr/local/bin/mcrcon "$@"
EOF

COPY --chmod=755 <<'EOF' /usr/local/bin/pz-query
#!/usr/bin/env python3

import os
import socket
import struct
import sys


DEFAULT_PORT = 16261
QUERY_TIMEOUT_SECONDS = 3
PACKET_HEADER = b"\xff\xff\xff\xff"
INFO_REQUEST = PACKET_HEADER + b"TSource Engine Query\x00"


class QueryError(Exception):
    pass


class PacketReader:
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def read(self, length):
        end = self.offset + length
        if end > len(self.data):
            raise QueryError("A2S information reply is truncated")
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def byte(self):
        return self.read(1)[0]

    def uint16(self):
        return struct.unpack("<H", self.read(2))[0]

    def string(self):
        end = self.data.find(b"\x00", self.offset)
        if end < 0:
            raise QueryError("A2S information reply has an unterminated string")
        self.offset = end + 1


def fail(message):
    print("pz-query: " + message, file=sys.stderr)
    return 1


def server_config_path():
    data_dir = os.environ.get("PZ_DATA_DIR")
    if not data_dir:
        data_dir = os.path.join(os.environ.get("HOME", "/home/steam"), "Zomboid")

    server_name = os.environ.get("PZ_SERVER_NAME", "servertest")
    if not server_name or "/" in server_name or "\n" in server_name:
        raise QueryError("server name is invalid")

    return os.path.join(data_dir, "Server", server_name + ".ini")


def configured_port():
    config_path = server_config_path()
    try:
        with open(config_path, encoding="utf-8") as config_file:
            for line in config_file:
                if line.startswith("DefaultPort="):
                    port_value = line[len("DefaultPort="):].rstrip("\r\n")
                    if not port_value.isdecimal():
                        raise QueryError("DefaultPort is invalid")
                    port = int(port_value)
                    if not 1 <= port <= 65535:
                        raise QueryError("DefaultPort is invalid")
                    return port
    except FileNotFoundError:
        return DEFAULT_PORT
    except OSError as error:
        raise QueryError("could not read server configuration: " + str(error)) from error

    return DEFAULT_PORT


def receive_info_reply(sock):
    sock.send(INFO_REQUEST)
    response = sock.recv(1400)

    if response.startswith(PACKET_HEADER + b"A"):
        if len(response) != len(PACKET_HEADER) + 1 + 4:
            raise QueryError("A2S challenge reply is invalid")
        sock.send(INFO_REQUEST + response[-4:])
        response = sock.recv(1400)

    return response


def parse_player_counts(response):
    if not response.startswith(PACKET_HEADER + b"I"):
        raise QueryError("A2S information reply is invalid")

    reader = PacketReader(response[len(PACKET_HEADER) + 1:])
    reader.byte()  # protocol version
    for _ in range(4):
        reader.string()
    reader.uint16()  # application ID
    players = reader.byte()
    max_players = reader.byte()

    if players > max_players:
        raise QueryError("A2S player count exceeds the reported maximum")

    return players, max_players


def query_player_counts(port):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(QUERY_TIMEOUT_SECONDS)
            sock.connect(("127.0.0.1", port))
            return parse_player_counts(receive_info_reply(sock))
    except socket.timeout as error:
        raise QueryError("A2S query timed out") from error
    except OSError as error:
        raise QueryError("A2S query failed: " + str(error)) from error


def main():
    if len(sys.argv) != 1:
        return fail("this command does not accept arguments")

    try:
        players, max_players = query_player_counts(configured_port())
    except QueryError as error:
        return fail(str(error))

    print("players=" + str(players))
    print("max_players=" + str(max_players))
    return 0


if __name__ == "__main__":
    sys.exit(main())
EOF

COPY --chmod=755 <<'EOF' /usr/local/bin/pz-backup
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly PZ_CONTAINER_NAME="${PZ_CONTAINER_NAME:-pz-server}"
readonly PZ_BACKUP_SOURCE_DIR="${PZ_BACKUP_SOURCE_DIR:-/source}"
readonly PZ_BACKUP_DIR="${PZ_BACKUP_DIR:-/backup}"
readonly RETAIN_COUNT=3

PARTIAL_PATH=''
CHECKSUM_PARTIAL_PATH=''

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

cleanup() {
  local status=$?

  [[ -z "$PARTIAL_PATH" || ! -e "$PARTIAL_PATH" ]] || rm -f -- "$PARTIAL_PATH"
  [[ -z "$CHECKSUM_PARTIAL_PATH" || ! -e "$CHECKSUM_PARTIAL_PATH" ]] || \
    rm -f -- "$CHECKSUM_PARTIAL_PATH"
  exit "$status"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

container_is_running() {
  local state

  state="$(docker inspect --format '{{.State.Running}}' "$PZ_CONTAINER_NAME")" || \
    fail "could not inspect container state: $PZ_CONTAINER_NAME"
  [[ "$state" == 'true' ]] || fail "container is not running: $PZ_CONTAINER_NAME"
}

acquire_lock() {
  [[ -d "$PZ_BACKUP_DIR" ]] || fail "backup path is not a directory: $PZ_BACKUP_DIR"
  exec 9>"$PZ_BACKUP_DIR/.pz-backup.lock"
  flock -n 9 || fail 'another backup is already active'
}

wait_for_clean_exit() {
  local exit_code

  log "waiting for $PZ_CONTAINER_NAME to exit"
  exit_code="$(docker wait "$PZ_CONTAINER_NAME")" || \
    fail "could not wait for container: $PZ_CONTAINER_NAME"
  [[ "$exit_code" =~ ^[0-9]+$ ]] || \
    fail "container exit code is invalid: $exit_code"
  [[ "$exit_code" == '0' ]] || \
    fail "container exited unsuccessfully: $exit_code"
}

is_our_archive_name() {
  [[ "$1" =~ ^pz-data-[0-9]{8}T[0-9]{6}Z-[0-9]+\.tar\.gz$ ]]
}

prune_backups() {
  local candidate index
  local -a archives=()

  while IFS= read -r candidate; do
    is_our_archive_name "$candidate" || continue
    [[ -f "$PZ_BACKUP_DIR/$candidate.sha256" ]] && archives+=("$candidate")
  done < <(
    find "$PZ_BACKUP_DIR" -maxdepth 1 -type f -name 'pz-data-*.tar.gz' -printf '%f\n' | \
      LC_ALL=C sort -r
  )

  for ((index = RETAIN_COUNT; index < ${#archives[@]}; index++)); do
    log "removing expired backup: ${archives[index]}"
    rm -f -- "$PZ_BACKUP_DIR/${archives[index]}" "$PZ_BACKUP_DIR/${archives[index]}.sha256"
  done
}

archive_volume() {
  local stamp archive_name checksum_name owner checksum
  local archive_path checksum_path

  [[ -d "$PZ_BACKUP_SOURCE_DIR" ]] || \
    fail "backup source is not a directory: $PZ_BACKUP_SOURCE_DIR"
  owner="$(stat --format '%u:%g' "$PZ_BACKUP_DIR")" || \
    fail 'could not determine backup directory ownership'
  [[ "$owner" =~ ^[0-9]+:[0-9]+$ ]] || fail 'backup directory ownership is invalid'

  stamp="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
  archive_name="pz-data-${stamp}.tar.gz"
  checksum_name="${archive_name}.sha256"
  archive_path="$PZ_BACKUP_DIR/$archive_name"
  PARTIAL_PATH="${archive_path}.partial"
  checksum_path="$PZ_BACKUP_DIR/$checksum_name"
  CHECKSUM_PARTIAL_PATH="${checksum_path}.partial"

  log "creating offline archive: $archive_name"
  tar -C "$PZ_BACKUP_SOURCE_DIR" -czf "$PARTIAL_PATH" . || \
    fail 'volume archive command failed'
  [[ -s "$PARTIAL_PATH" ]] || fail 'archive command produced no archive data'

  checksum="$(sha256sum "$PARTIAL_PATH")"
  checksum="${checksum%% *}"
  [[ "$checksum" =~ ^[0-9a-fA-F]{64}$ ]] || fail 'could not calculate a SHA-256 checksum'
  printf '%s  %s\n' "$checksum" "$archive_name" > "$CHECKSUM_PARTIAL_PATH"

  mv -- "$PARTIAL_PATH" "$archive_path"
  PARTIAL_PATH=''
  mv -- "$CHECKSUM_PARTIAL_PATH" "$checksum_path"
  CHECKSUM_PARTIAL_PATH=''
  (
    cd "$PZ_BACKUP_DIR"
    sha256sum --check "$checksum_name" >/dev/null
  ) || fail 'new archive failed SHA-256 verification'

  chown "$owner" -- "$archive_path" "$checksum_path" || \
    fail 'could not set finalized backup ownership'
  chmod 0640 -- "$archive_path" "$checksum_path" || \
    fail 'could not set finalized backup permissions'
  prune_backups
}

main() {
  local command

  for command in docker pz-rcon tar sha256sum flock find sort stat chown chmod rm mv date; do
    require_command "$command"
  done
  acquire_lock
  container_is_running

  log 'saving the Project Zomboid world through RCON'
  pz-rcon save || fail 'RCON save command failed'
  log 'requesting Project Zomboid shutdown through RCON'
  pz-rcon quit || fail 'RCON quit command failed'
  wait_for_clean_exit
  archive_volume
  log 'backup succeeded'
}

trap cleanup EXIT
main "$@"
EOF

USER steam
WORKDIR ${PZ_SERVER_DIR}

VOLUME ["/home/steam/Zomboid"]

EXPOSE 16261/udp 16262/udp 8766/udp 8767/udp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/pz-entrypoint.sh"]
