## Why

Project Zomboid's dedicated server currently requires users to manually provision SteamCMD, install the server files, expose the correct UDP ports, and preserve generated game data. A containerized deployment makes that setup reproducible while keeping server configuration and world saves safe across image rebuilds.

## What Changes

- Add a two-stage Docker image: use Docker BuildKit's build architecture to select and verify the matching official DepotDownloader asset when downloading Project Zomboid Dedicated Server (Steam App ID `380870`), then run the complete `linux/amd64` game process tree.
- Add a startup wrapper that prepares the persistent game-data directory and forwards container shutdown signals to the server process.
- Document build, run, data-volume, configuration, and UDP port-publishing procedures.
- Support both the current default UDP port pair (`16261`, `16262`) and the legacy pre-41.77 ports (`16261`, `8766`, `8767`) in the image metadata and documentation, with runtime configuration remaining authoritative.

## Capabilities

### New Capabilities

- `dedicated-server-container`: Build and run a Project Zomboid dedicated server from a Docker image without invoking SteamCMD.
- `server-data-persistence`: Preserve server settings and multiplayer world data outside the container lifecycle.
- `server-networking-documentation`: Provide version-aware UDP port-publishing instructions for clients to connect.

### Modified Capabilities

None.

## Impact

- Adds a Dockerfile, container entrypoint/startup script, `.dockerignore`, and deployment documentation to this currently empty repository.
- Uses a multi-architecture Debian download stage and pins the checksums for official ARM64 and x64 DepotDownloader releases, then copies the installed files into a `linux/amd64` runtime image. It does not invoke SteamCMD.
- Requires Docker to build/run and a host-managed volume or bind mount for persistent Project Zomboid data.
