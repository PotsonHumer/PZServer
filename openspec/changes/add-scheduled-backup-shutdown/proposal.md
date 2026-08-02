## Why

The Project Zomboid world lives in a Docker volume and needs an offline, restorable backup before the Linux host is powered down by a scheduled job. Operators currently have no repeatable workflow that both protects the complete persisted state and refuses to power off after an unsafe server stop or a failed archive.

## What Changes

- Add an operator-run shell script that gracefully stops the `pz-server` container with a 120-second timeout before taking an offline archive of the `pz-data` volume.
- Store verified compressed archives and their SHA-256 checksum files in `/home/potsonhumer/pa-backup`, with finalized artifacts owned by `potsonhumer:root`.
- Retain only the three newest successful archives, without deleting older archives until a replacement has been completely created and verified.
- Abort without powering off the host when preflight checks, graceful container shutdown, archive creation, or checksum generation fails; treat an exit code of `137` as an unsafe stop.
- Power off the whole Linux host only after a successful backup sequence, so a root crontab entry can schedule the operation.

## Capabilities

### New Capabilities

- `scheduled-backup-shutdown`: Safely stop, archive, retain, verify, and then power off a Docker-hosted Project Zomboid server.

### Modified Capabilities

- None.

## Impact

- Adds a shell script and operator documentation for a root-run cron job.
- Uses the local Docker CLI, `tar`, `sha256sum`, `flock`, and the host power-management command.
- Reads the existing `pz-server` container and `pz-data` Docker volume; it creates and deletes only explicitly named backup artifacts under `/home/potsonhumer/pa-backup`.
