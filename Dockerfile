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
COPY --chown=steam:steam --chmod=755 docker/pz-entrypoint.sh /usr/local/bin/pz-entrypoint.sh

USER steam
WORKDIR ${PZ_SERVER_DIR}

VOLUME ["/home/steam/Zomboid"]

EXPOSE 16261/udp 16262/udp 8766/udp 8767/udp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/pz-entrypoint.sh"]
