## ADDED Requirements

### Requirement: Serialized root-run backup workflow
The project SHALL provide a non-interactive shell workflow for a root cron job. The workflow SHALL reject non-root execution, acquire a non-blocking exclusive lock before changing state, and validate that Docker, `tar`, `sha256sum`, `flock`, `runuser`, `sync`, and the host power-management command are available. It SHALL verify that the `pz-server` container and `pz-data` volume exist before attempting a backup.

#### Scenario: A second invocation overlaps an active run
- **WHEN** another invocation already holds the workflow lock
- **THEN** the new invocation SHALL exit without stopping the container, deleting backups, or powering off the host

#### Scenario: A required Docker resource is absent
- **WHEN** `pz-server` or `pz-data` does not exist
- **THEN** the workflow SHALL exit unsuccessfully without creating a backup or powering off the host

### Requirement: Safe Project Zomboid container stop
The workflow SHALL determine whether `pz-server` is running. When it is running, the workflow SHALL stop it with `docker stop --timeout 120 pz-server` and verify that the container is stopped before reading the persisted data. If that stop results in exit code `137`, the workflow SHALL exit unsuccessfully without creating a backup, pruning a prior backup, or powering off the host. When the container was already stopped before the workflow began, the workflow SHALL continue with the offline backup without evaluating its prior exit code.

#### Scenario: Running game server stops within the grace period
- **WHEN** `pz-server` is running and exits without exit code `137` after the requested stop
- **THEN** the workflow SHALL continue to the offline archive stage

#### Scenario: Docker force-kills the game server
- **WHEN** the requested container stop results in exit code `137`
- **THEN** the workflow SHALL leave the host running and preserve all prior finalized backups

#### Scenario: The game server is already stopped
- **WHEN** `pz-server` is stopped before the workflow starts
- **THEN** the workflow SHALL archive the existing `pz-data` state without interpreting the previous container exit code as the current stop result

### Requirement: Complete and finalized volume archive
The workflow SHALL create `/home/potsonhumer/pa-backup` when absent as `potsonhumer`. It SHALL archive the entire `pz-data` named volume through a temporary helper container with the volume mounted read-only and a root-owned temporary staging directory as the helper output. It SHALL write the gzip archive through a unique `.partial` filename and generate a SHA-256 checksum before renaming the archive to its finalized timestamped `.tar.gz` name. The workflow SHALL set finalized archive and checksum files to `potsonhumer:root` with mode `0640` in staging, then publish them to the backup directory as `potsonhumer`.

#### Scenario: A complete offline backup is created
- **WHEN** the container is stopped and archive and checksum commands succeed
- **THEN** the backup directory SHALL contain a finalized timestamped `.tar.gz` archive and matching checksum file for the entire `pz-data` volume

#### Scenario: Archive creation fails
- **WHEN** the helper archive command or checksum creation fails
- **THEN** the workflow SHALL not finalize the new archive, prune a prior backup, or power off the host

### Requirement: Successful backup retention
The workflow SHALL retain the three newest finalized archives that match its own backup filename format in `/home/potsonhumer/pa-backup`. It SHALL list and remove only older matching archive/checksum pairs as `potsonhumer`, and only after a new archive has been finalized and verified. It SHALL not count `.partial` files as successful backups or remove unrelated files in the backup directory.

#### Scenario: A fourth successful backup is finalized
- **WHEN** finalizing a new archive would leave four matching finalized backups
- **THEN** the workflow SHALL retain the three newest archives and their matching checksum files and remove the oldest matching archive and checksum pair

#### Scenario: A new backup fails before finalization
- **WHEN** a new archive does not reach the finalized state
- **THEN** the workflow SHALL preserve every existing finalized backup regardless of the retention limit

### Requirement: Conditional host power-off
The workflow SHALL call `sync` and power off the complete Linux host with `systemctl poweroff` only after the stop decision, archive finalization, checksum generation, permission updates, and retention stage all succeed. Any failure before that point SHALL leave the host powered on and return a nonzero result suitable for cron logging.

#### Scenario: Backup workflow completes successfully
- **WHEN** all prior workflow stages succeed
- **THEN** the workflow SHALL synchronize pending writes and initiate host power-off

#### Scenario: Any pre-power-off step fails
- **WHEN** any required workflow stage exits unsuccessfully
- **THEN** the workflow SHALL not call `systemctl poweroff`
