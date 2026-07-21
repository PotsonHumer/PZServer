## MODIFIED Requirements

### Requirement: Buildable dedicated-server image
The project SHALL provide a two-stage Dockerfile that uses Docker BuildKit's build architecture to select and checksum-verify the matching pinned official ARM64 or x64 DepotDownloader asset without invoking SteamCMD, installs Project Zomboid Dedicated Server with anonymous access to App ID `380870` from the hard-coded Steam `unstable` branch in a fixed application directory, and copies the installed server into a `linux/amd64` runtime image for native Linux/Windows x86_64 execution or Apple x86_64 container translation. The Dockerfile SHALL NOT expose a build argument, environment variable, or runtime option to select a Steam branch.

#### Scenario: Build retrieves the Build 42 dedicated server
- **WHEN** an operator builds the image with Docker while Steam is reachable
- **THEN** the build completes with the `unstable`-branch dedicated server installed in the image
