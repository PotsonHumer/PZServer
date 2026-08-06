## ADDED Requirements

### Requirement: One-off Compose player query
The Compose configuration SHALL define a profile-gated service named `pz-query` whose default
entrypoint runs the existing `pz-query` executable. An operator SHALL be able to run
`docker compose run pz-query` while `pz-server` is running and receive the tool's existing stdout,
stderr, and exit status. The service SHALL not start during normal `docker compose up -d`.

#### Scenario: Query the running game server
- **WHEN** `pz-server` is running and an operator runs `docker compose run pz-query`
- **THEN** the one-off container reports the current player count using the existing `pz-query`
  output contract

#### Scenario: Keep ordinary startup limited to PZ
- **WHEN** an operator runs `docker compose up -d` without enabling a management profile
- **THEN** Compose starts `pz-server` without starting either one-off management service

### Requirement: One-off Compose RCON command
The Compose configuration SHALL define a profile-gated service named `pz-rcon` whose default
entrypoint runs the existing `pz-rcon` executable. An operator SHALL be able to run
`docker compose run pz-rcon <command>` while `pz-server` is running and receive the RCON command's
stdout, stderr, and exit status.

#### Scenario: Save through a one-off service
- **WHEN** `pz-server` is running and an operator runs `docker compose run pz-rcon save`
- **THEN** the one-off container sends the `save` command through the existing local RCON wrapper

### Requirement: Isolated management connection
The one-off services SHALL share the running `pz-server` container's network namespace and SHALL
mount the existing `pz-data` volume read-only. They SHALL not publish ports, accept a caller host,
or start a stopped `pz-server` container.

#### Scenario: Main server is unavailable
- **WHEN** an operator runs either one-off service while `pz-server` is stopped or absent
- **THEN** the command exits nonzero and does not start the game server

### Requirement: Retained execution records
The one-off management services SHALL not restart after completion. Documentation SHALL use
`docker compose run` without `--rm` and SHALL explain that completed helper containers remain in
the exited state for inspection.

#### Scenario: Inspect a completed query
- **WHEN** an operator runs `docker compose run pz-query` successfully
- **THEN** its one-off container exits and remains available for Compose log and exit-status
  inspection

### Requirement: Documented Compose management
The documentation SHALL present the one-off Compose commands as the routine player-query and RCON
management interface, including the requirement that the game server is already running and a
method to clean up retained stopped helper containers.

#### Scenario: Operator follows management documentation
- **WHEN** an operator consults the local management instructions
- **THEN** they can query players and issue a save command without naming `pz-server` in either
  command
