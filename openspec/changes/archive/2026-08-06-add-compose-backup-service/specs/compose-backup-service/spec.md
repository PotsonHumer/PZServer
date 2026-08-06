## ADDED Requirements

### Requirement: One-off Compose backup service
The Compose configuration SHALL define a profile-gated `pz-backup` service. An operator SHALL be
able to run `docker compose run --no-deps pz-backup` while `pz-server` is running. The service SHALL not
start during normal `docker compose up -d`, SHALL not publish ports, and SHALL not start a stopped
`pz-server`.

#### Scenario: Start a manual backup
- **WHEN** `pz-server` is running and an operator runs `docker compose run --no-deps pz-backup`
- **THEN** Compose starts only the one-off backup runner and does not start another game server

#### Scenario: Main server is unavailable
- **WHEN** an operator runs the backup service while `pz-server` is stopped or absent
- **THEN** the command exits nonzero without creating a backup or starting the game server

### Requirement: RCON-safe offline archive
The backup runner SHALL use the existing local RCON wrapper to send `save` followed by `quit` to
the running game server. It SHALL wait for `pz-server` to exit without a forced-stop timeout and
SHALL archive `pz-data` only after a successful clean exit. A failure in the RCON sequence, wait,
or archive stage SHALL exit nonzero without finalizing a new backup.

#### Scenario: Clean shutdown precedes backup
- **WHEN** the RCON save and quit commands succeed and `pz-server` exits cleanly
- **THEN** the runner creates an offline archive from the persistent world data

#### Scenario: RCON command fails
- **WHEN** the save or quit command fails
- **THEN** the runner does not archive the world and does not force-stop the game server

### Requirement: Configurable host backup destination
The Compose configuration SHALL declare a bind-backed volume named `pz-backup` whose host path is
`${PZ_BACKUP_DIR:-/home/potsonhumer/pz-backup}`. The backup runner SHALL mount `pz-data` read-only
and write verified timestamped archive/checksum pairs to the backup destination. It SHALL retain
only the three newest finalized matching pairs and SHALL not treat partial or unrelated files as
successful backups.

#### Scenario: Use the default backup directory
- **WHEN** `PZ_BACKUP_DIR` is unset and the default host directory exists
- **THEN** a successful backup is written under `/home/potsonhumer/pz-backup`

#### Scenario: Use a configured backup directory
- **WHEN** an operator sets `PZ_BACKUP_DIR` to an existing host directory
- **THEN** the backup service writes and retains archives in that directory

### Requirement: Local Docker control boundary
The backup runner SHALL use the local Docker socket only to inspect and wait for the named
`pz-server` container. It SHALL not publish the socket or accept a remote Docker endpoint. The
documentation SHALL identify Docker-socket access as trusted local administrator access.

#### Scenario: Inspect the backup service configuration
- **WHEN** an operator inspects the rendered Compose configuration
- **THEN** the backup service has no published ports and uses only the local Docker socket mount for
  container-state confirmation

### Requirement: Compose-backed scheduled power-off
The root-host backup-and-poweroff workflow SHALL invoke `docker compose run --no-deps pz-backup` from a
configurable Compose project directory and SHALL synchronize filesystems and call `systemctl
poweroff` only after that command succeeds. It SHALL not use `docker stop` to terminate the game
server.

#### Scenario: Scheduled backup succeeds
- **WHEN** the Compose backup command succeeds in the root-host workflow
- **THEN** the workflow synchronizes filesystems and initiates host power-off

#### Scenario: Compose backup fails
- **WHEN** the Compose backup command exits unsuccessfully
- **THEN** the root-host workflow leaves the host running and does not invoke `systemctl poweroff`
