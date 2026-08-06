# docker-compose-operation Specification

## Purpose
TBD - created by archiving change add-docker-compose. Update Purpose after archive.
## Requirements
### Requirement: Compose-managed local server
The project SHALL provide a Compose definition that builds `pz-server:local` for `linux/amd64` and
runs one container named `pz-server`. The service SHALL use the existing Docker volume named
`pz-data` at `/home/steam/Zomboid`, set a 60-second stop grace period, and publish only
`16261/udp` and `16262/udp` for game traffic.

#### Scenario: Start against existing persistent data
- **WHEN** an operator starts the Compose service with an existing `pz-data` volume
- **THEN** the service uses that exact volume and does not create a Compose-prefixed replacement
  volume

#### Scenario: Preserve local management exposure
- **WHEN** an operator inspects the Compose service's published ports
- **THEN** no RCON port is published

### Requirement: Established server and RCON defaults
The Compose service SHALL set `PZ_RCON_PASSWORD_FILE` to `/run/secrets/pz-rcon-password`,
`PZ_RCON_PORT` to `27015`, `PZ_SERVER_NAME` to `420正版`, and both `LANG` and `LC_ALL` to
`C.UTF-8`. It SHALL mount `secrets/rcon-password` as the `pz-rcon-password` secret at the
configured RCON password path.

#### Scenario: Start the established server configuration
- **WHEN** the local RCON password file exists and an operator starts the Compose service
- **THEN** the container receives the established `420正版` and locale settings and reads the RCON
  password from `/run/secrets/pz-rcon-password`

### Requirement: Local administrator and heap configuration
The Compose service SHALL load `.env` into the server container through `env_file`. The repository
SHALL ignore `.env` and SHALL provide a tracked `.env.example` that documents
`PZ_ADMIN_PASSWORD` and `PZ_JAVA_XMX` without containing an administrator password.

#### Scenario: Keep installation-specific values out of Git
- **WHEN** an operator creates `.env` from `.env.example` and adds an administrator password and
  Java heap value
- **THEN** Compose passes those values to the server container while Git does not report `.env` as
  an untracked file

### Requirement: Documented Compose operation
The documentation SHALL describe preparing `.env` and the RCON password file, starting or
replacing the server with Compose, safely migrating the existing manual `pz-server` container
without deleting `pz-data`, and rebuilding without Docker cache for a PZ server update.

#### Scenario: Recreate the server without repeating docker run options
- **WHEN** an operator follows the Compose documentation to replace the server container
- **THEN** they can recreate it with a Compose command while retaining the existing world data and
  local-only RCON configuration

