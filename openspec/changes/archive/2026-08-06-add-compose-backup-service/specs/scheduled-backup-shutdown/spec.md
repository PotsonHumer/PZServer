## MODIFIED Requirements

### Requirement: Serialized root-run backup workflow
The project SHALL provide a non-interactive root-only shell workflow for a root cron job. The
workflow SHALL reject non-root execution, acquire a non-blocking exclusive lock before invoking the
Compose backup command, and validate that Docker Compose, `flock`, `sync`, and the host
power-management command are available. It SHALL run `docker compose run --no-deps pz-backup` from
`PZ_COMPOSE_DIR`, defaulting to `/var/PZServer`.

#### Scenario: A second invocation overlaps an active run
- **WHEN** another invocation already holds the workflow lock
- **THEN** the new invocation SHALL exit without invoking the backup service or powering off the host

#### Scenario: The Compose project directory is unavailable
- **WHEN** `PZ_COMPOSE_DIR` is missing or cannot run the backup command
- **THEN** the workflow SHALL exit unsuccessfully without powering off the host

### Requirement: Safe Project Zomboid container stop
The workflow SHALL delegate game shutdown to the Compose backup service. When `pz-server` is
running, that service SHALL issue RCON `save` followed by RCON `quit`, wait for the container to
exit without a forced-stop timeout, and verify a clean exit before archiving. The workflow SHALL
not invoke `docker stop`.

#### Scenario: Running game server shuts down through RCON
- **WHEN** the root-host workflow invokes a backup while `pz-server` is running
- **THEN** the game server receives RCON save and quit before any archive is created

#### Scenario: Game server cannot cleanly shut down
- **WHEN** the RCON shutdown or container wait fails
- **THEN** the workflow SHALL leave the host running and preserve prior finalized backups

### Requirement: Complete and finalized volume archive
The Compose backup service SHALL create a verified offline archive of the entire read-only
`pz-data` volume in the configured bind-backed backup directory. It SHALL write through a unique
`.partial` filename, generate and verify a SHA-256 checksum, then finalize the timestamped archive
and matching checksum only after verification succeeds.

#### Scenario: A complete offline backup is created
- **WHEN** the RCON shutdown and archive stages succeed
- **THEN** the backup directory SHALL contain a finalized timestamped `.tar.gz` archive and matching
checksum file for the entire `pz-data` volume

#### Scenario: Archive creation fails
- **WHEN** archive creation or checksum verification fails
- **THEN** the workflow SHALL not finalize the new archive, prune a prior backup, or power off the
host

### Requirement: Successful backup retention
The Compose backup service SHALL retain the three newest finalized archives that match its own
backup filename format in the configured backup directory. It SHALL remove only older matching
archive/checksum pairs after a new archive has been finalized and verified. It SHALL not count
`.partial` files as successful backups or remove unrelated files.

#### Scenario: A fourth successful backup is finalized
- **WHEN** finalizing a new archive would leave four matching finalized backups
- **THEN** the service SHALL retain the three newest archives and matching checksum files and remove
the oldest matching archive and checksum pair

#### Scenario: A new backup fails before finalization
- **WHEN** a new archive does not reach the finalized state
- **THEN** the workflow SHALL preserve every existing finalized backup regardless of the retention
limit

### Requirement: Conditional host power-off
The root-host workflow SHALL call `sync` and power off the complete Linux host with `systemctl
poweroff` only after the Compose backup command succeeds. Any failure before that point SHALL leave
the host powered on and return a nonzero result suitable for cron logging.

#### Scenario: Backup workflow completes successfully
- **WHEN** the Compose backup service succeeds
- **THEN** the workflow SHALL synchronize pending writes and initiate host power-off

#### Scenario: Any pre-power-off step fails
- **WHEN** the Compose backup command exits unsuccessfully
- **THEN** the workflow SHALL not call `systemctl poweroff`
