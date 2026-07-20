## Context

The repository has no deployment implementation. Project Zomboid Dedicated Server is distributed through Steam as App ID `380870` and is started on Linux with `start-server.sh`. SteamCMD is a 32-bit program and cannot run reliably through Apple container translation. A Box64 attempt successfully downloaded and began the server but its translated JVM aborted during world loading. Pinned current official ARM64 and x64 DepotDownloader releases support anonymous dedicated-server downloads. The final image therefore runs the complete x86_64 process tree as `linux/amd64`, which is native on Linux/Windows x86_64 and translated on Apple Silicon. Project Zomboid writes server configuration and multiplayer saves below `~/Zomboid`, so an image-only solution would discard state whenever its container is replaced.

The target is a single server instance started with Docker. It must accommodate the port convention documented for current builds (`16261`/`16262` UDP) as well as the legacy pre-41.77 convention (`16261`, `8766`, `8767` UDP).

## Goals / Non-Goals

**Goals:**

- Provide a Docker build that retrieves the anonymous Project Zomboid dedicated-server application and starts it as a foreground container process.
- Keep generated server settings and world data in one documented persistent mount point.
- Run the server as an unprivileged runtime user.
- Provide precise, version-aware commands for publishing the required UDP ports.
- Make normal container stop behaviour explicit and verify it manually during implementation.

**Non-Goals:**

- Managing Steam Workshop mods, automatic scheduled updates, server administration, backups, or multiple server instances.
- Publishing a pre-built image to a registry.
- Providing host firewall, router port-forwarding, or cloud-security-group automation.
- Supporting Windows containers or non-Linux game-server binaries.

## Decisions

### Download natively on the builder architecture and run as linux/amd64

The Dockerfile uses a multi-architecture Debian download stage and does not invoke SteamCMD. It declares BuildKit's `BUILDARCH`, chooses the official `arm64` or `x64` DepotDownloader asset, and verifies the corresponding pinned checksum before invoking the downloader with anonymous access, an explicit installation directory, and `-os linux`. The documented build command targets `linux/amd64` and uses Docker host networking for a reliable Steam connection. It verifies that `start-server.sh` was installed so a Steam download error cannot produce a seemingly successful image. A second, Ubuntu-based `linux/amd64` stage copies the game files and includes root certificates; the host's Apple x86_64 translation runs Java and every game child process consistently.

Building the server files into the image makes the image immutable after a successful build and makes an update an intentional `docker build` action. Running SteamCMD on every container start was considered, but rejected because it couples availability to Steam at runtime, lengthens restarts, and makes the running version less predictable. A tested base-image digest is recorded to limit upstream drift.

### Separate application files from mutable game data

The installed game files will live in `/home/steam/pzserver`. The base image's unprivileged `steam` account supplies `HOME=/home/steam`, and `/home/steam/Zomboid` will be the sole documented data mount. This matches the server's Linux data layout and preserves `Server/` settings and `Saves/Multiplayer/` world data.

Mounting the complete installation directory was considered, but rejected because an empty host mount hides the installed server files and makes upgrades ambiguous. Users can bind-mount individual configuration files later, but the documented default is one data directory.

### Treat port configuration and host publication as separate concerns

The image will declare all relevant UDP ports for discoverability: current defaults `16261` and `16262`, plus legacy `8766` and `8767`. Documentation will state that `EXPOSE` does not publish ports and will give separate `docker run -p` commands for current and pre-41.77 deployments. The active `SERVERNAME.ini` port settings and published host ports MUST match.

Publishing only current ports was rejected because the requested legacy-build reference explicitly uses the older ports. Publishing all ports unconditionally was rejected because it exposes unnecessary host ports for a given version.

### Make shutdown observable before promising graceful saves

The entrypoint will use `exec` so Docker tracks the server process and will forward termination signals where the startup script permits. Documentation will prescribe a nonzero stop timeout. The implementation will manually stop a running test container and check that the process exits and persisted files remain. It will not claim that a forced stop guarantees a final save; operators remain responsible for backups.

## Risks / Trade-offs

- [DepotDownloader or Steam download is unavailable during image build] → Fail the build clearly; retain the last successful image and rebuild only when an update is desired.
- [The multi-architecture download-stage image or either official downloader release changes or is unavailable] → Pin the release version and architecture-specific checksums; rebuild only after deliberately reviewing a newer version.
- [PZ's bundled runtime has platform/architecture constraints] → Build for `linux/amd64`; use native execution on Linux/Windows x86_64 and require OrbStack or Docker Desktop Apple x86_64 translation on Apple Silicon; validate server startup and client connectivity on the target host.
- [Binary translation reduces server performance or causes instability] → Treat the deployment as Apple-Silicon compatible rather than native ARM64, begin with a small player count, and retain a physical x86_64 host as the supported fallback.
- [A mismatched game configuration and published UDP ports prevents players from connecting] → Document current and legacy mappings separately and include a configuration-verification step.
- [Abrupt container termination can lose unsaved progress] → Use foreground execution, a stop grace period, and a documented backup/maintenance procedure.
