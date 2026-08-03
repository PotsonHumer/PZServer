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

FROM ubuntu:24.04

ENV PZ_SERVER_DIR=/home/steam/pzserver \
    PZ_DATA_DIR=/home/steam/Zomboid \
    HOME=/home/steam

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash steam \
    && mkdir -p "${PZ_DATA_DIR}" \
    && chown steam:steam "${PZ_DATA_DIR}"

COPY --from=downloader --chown=steam:steam /home/steam/pzserver ${PZ_SERVER_DIR}
COPY --from=rcon-client --chmod=755 /usr/local/bin/mcrcon /usr/local/bin/mcrcon

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

USER steam
WORKDIR ${PZ_SERVER_DIR}

VOLUME ["/home/steam/Zomboid"]

EXPOSE 16261/udp 16262/udp 8766/udp 8767/udp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/pz-entrypoint.sh"]
