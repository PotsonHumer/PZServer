## 1. Container image foundation

- [x] 1.1 Add a `.dockerignore` that excludes repository-local server data, Git metadata, and other non-build inputs.
- [x] 1.2 Create a two-stage Dockerfile: use a pinned `sonroyaalmerol/steamcmd-arm64` download stage without invoking SteamCMD, verify a pinned official ARM64 DepotDownloader release, install Steam App ID `380870` with anonymous access, and copy it into a `linux/amd64` runtime image.
- [x] 1.3 Create and use an unprivileged `steam` account and home directory, give it ownership of the installation and data paths required at runtime, and declare the relevant UDP ports in image metadata.

## 2. Server startup and state handling

- [x] 2.1 Add an entrypoint/startup script that prepares the runtime user's `Zomboid` data directory and invokes the installed x86_64 server runtime in the foreground under the `linux/amd64` container runtime.
- [x] 2.2 Implement and document normal termination handling, including a finite Docker stop grace period, without promising lossless saves after forced termination.
- [x] 2.3 Confirm that an empty mounted data directory is populated on first startup and that its server settings and multiplayer-save hierarchy is available after the container is recreated.

## 3. Operator documentation

- [x] 3.1 Write a README covering native ARM64 DepotDownloader and Apple x86_64 container-translation prerequisites, image build, first-run behavior, the documented persistent data mount, and intentional rebuilds for server updates.
- [x] 3.2 Add a current-version `docker run` example that publishes `16261/udp` and `16262/udp`.
- [x] 3.3 Add a separate pre-41.77 `docker run` example that publishes `16261/udp`, `8766/udp`, and `8767/udp`, and explain that the Docker mapping, host-network rules, and `SERVERNAME.ini` must agree.

## 4. Verification

- [x] 4.1 Build the `linux/amd64` Docker image and verify that the dedicated-server files and non-root default command are present in the resulting image.
- [x] 4.2 Start a smoke-test container with a disposable data mount, verify the foreground server reaches `*** SERVER STARTED ****`, then issue a Docker stop and inspect the result (the translated runtime required Docker's forced termination after the 60-second grace period).
- [x] 4.3 Recreate the smoke-test container with the same data mount and verify that previously generated configuration and saved data remain available.

## 5. Cross-architecture builder support

- [x] 5.1 Select and checksum-verify the official DepotDownloader `arm64` or `x64` asset from Docker BuildKit's `BUILDARCH`, so Apple Silicon, Linux x86_64, and Windows x86_64 Docker builders do not require ARM64 emulation for the download stage.
