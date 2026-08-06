## Why

The current backup-and-poweroff script is a root-host operation, so routine backups cannot use the
same short Compose command interface as local player queries and RCON commands. Operators need a
one-off Compose backup command that preserves the world only after a clean RCON shutdown and writes
archives to a configurable host directory.

## What Changes

- Add a profile-gated one-off `pz-backup` Compose service.
- Shut down the game with local RCON `save` then `quit`, wait for `pz-server` to exit, and only then
  archive the persistent `pz-data` volume.
- Declare the backup destination as a Compose bind-backed volume, defaulting to
  `/home/potsonhumer/pz-backup` and configurable through `PZ_BACKUP_DIR`.
- Document the Compose backup command and its local Docker-socket trust boundary.
- Refactor the existing root-host power-off script into a thin wrapper that runs the Compose backup
  command and invokes `systemctl poweroff` only after it succeeds.

## Capabilities

### New Capabilities

- `compose-backup-service`: One-off Compose service for an RCON-safe, volume-backed local backup.

### Modified Capabilities

- `scheduled-backup-shutdown`: Delegate backup work to the Compose service while retaining the
  root-host-only final power-off step.

## Impact

- `compose.yaml` gains a management-profile backup service and host-directory-backed volume.
- The backup runner and image build gain only the tools needed for local RCON, Docker wait, and
  archive creation.
- `README.md` gains Compose-native backup operation documentation.
- `scripts/pz-backup-and-poweroff.sh` becomes a root-host wrapper for the Compose backup command
  and final host shutdown.
