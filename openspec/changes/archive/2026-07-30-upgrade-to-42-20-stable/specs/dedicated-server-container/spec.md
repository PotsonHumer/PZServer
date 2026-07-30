## MODIFIED Requirements

### Requirement: Buildable dedicated-server image
The project SHALL provide a two-stage Dockerfile that uses Docker BuildKit's build architecture to select and checksum-verify the matching pinned official ARM64 or x64 DepotDownloader asset without invoking SteamCMD, installs Project Zomboid Dedicated Server with anonymous access to App ID `380870` from Steam's default public branch in a fixed application directory, and copies the installed server into a `linux/amd64` runtime image for native Linux/Windows x86_64 execution or Apple x86_64 container translation. The Dockerfile SHALL NOT select Steam's `unstable` branch or expose a build argument, environment variable, or runtime option to select a Steam branch. The documented local build command SHALL export its tagged result to the local Docker image store when using a `docker-container` Buildx driver.

#### Scenario: Build retrieves the stable dedicated server
- **WHEN** an operator builds the image with Docker while Steam is reachable
- **THEN** the build completes with the default-public-branch dedicated server installed in a locally runnable tagged image
