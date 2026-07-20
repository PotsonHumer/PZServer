## ADDED Requirements

### Requirement: Buildable dedicated-server image
The project SHALL provide a two-stage Dockerfile that uses Docker BuildKit's build architecture to select and checksum-verify the matching pinned official ARM64 or x64 DepotDownloader asset without invoking SteamCMD, installs Project Zomboid Dedicated Server with anonymous access to App ID `380870` in a fixed application directory, and copies the installed server into a `linux/amd64` runtime image for native Linux/Windows x86_64 execution or Apple x86_64 container translation.

#### Scenario: Build retrieves the dedicated server
- **WHEN** an operator builds the image with Docker while Steam is reachable
- **THEN** the build completes with the dedicated server installed in the image

### Requirement: Foreground server startup
The built image SHALL start the installed Linux dedicated-server startup script as its default container command and SHALL keep the container running while the game server process is running.

#### Scenario: Start a newly built image
- **WHEN** an operator starts a container without overriding its command
- **THEN** the Project Zomboid server startup process runs in the container foreground

### Requirement: Unprivileged runtime
The container SHALL execute the game server under the base image's non-root `steam` runtime account with home directory `/home/steam`.

#### Scenario: Inspect a running server process
- **WHEN** an operator inspects the user that owns the game-server process
- **THEN** the process is not owned by root
