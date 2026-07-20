#!/usr/bin/env bash

set -Eeuo pipefail

: "${PZ_SERVER_DIR:=/home/steam/pzserver}"
: "${PZ_DATA_DIR:=${HOME}/Zomboid}"

if [[ ! -x "${PZ_SERVER_DIR}/start-server.sh" ]]; then
  echo "Project Zomboid server startup script is missing: ${PZ_SERVER_DIR}/start-server.sh" >&2
  exit 1
fi

mkdir -p "${PZ_DATA_DIR}"

# This image is linux/amd64. On Apple Silicon, OrbStack or Docker Desktop
# translates the complete x86_64 process tree, including the bundled Java.
# Replacing PID 1 preserves Docker signal delivery to the server process tree.
exec "${PZ_SERVER_DIR}/start-server.sh" "$@"
