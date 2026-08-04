## Why

The Docker-hosted Project Zomboid server can be started, stopped, and observed with Docker, but an operator cannot invoke its in-game administrative commands from the Linux command line. Project Zomboid has RCON support, yet the current image has neither a RCON client nor a safe, local-only invocation path.

## What Changes

- Enable Project Zomboid RCON with a configurable port and password stored in the persisted server configuration.
- Include a container-local RCON client and a `pz-rcon` command wrapper for sending PZ server commands through `docker exec`.
- Make the wrapper connect only to `127.0.0.1` inside the game container; do not expose or publish an RCON port from the image.
- Keep RCON credentials out of command arguments, standard output, and Docker image metadata.
- Document local operational commands for status, save, player listing, announcements, and graceful shutdown.

## Capabilities

### New Capabilities

- `local-rcon-cli`: Run authenticated Project Zomboid RCON commands from the Linux host through `docker exec`, without exposing a network management endpoint.

### Modified Capabilities

- None.

## Impact

- Updates the Docker image build and its operator documentation.
- Adds a bundled RCON-client dependency and a container-local command wrapper.
- Reads and writes the existing persistent `Server/<server-name>.ini` configuration under `/home/steam/Zomboid` during initial configuration.
