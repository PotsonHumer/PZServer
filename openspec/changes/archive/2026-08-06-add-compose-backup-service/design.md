## Context

The existing root-cron script stops the server with `docker stop --timeout 120`, archives its
volume through a temporary Docker container, and powers off the host. The Compose project now has
local one-off management services, and the safe game shutdown contract is RCON `save`, then RCON
`quit`, followed by confirmation that the game container has actually exited. A backup service
needs the same local-only RCON path and read-only persistent data, while its destination must be a
real host directory rather than Docker-managed storage.

## Goals / Non-Goals

**Goals:**

- Provide `docker compose run --no-deps pz-backup` as a profile-gated, one-off local backup command.
- Send RCON `save`, then `quit`; wait indefinitely for `pz-server` to exit before reading the world.
- Archive the read-only `pz-data` volume to a bind-backed destination whose default host path is
  `/home/potsonhumer/pz-backup`.
- Retain verified archive/checksum pairs and the existing three-backup retention behavior.
- Keep final Linux host power-off in a root-host wrapper that runs the Compose command first.

**Non-Goals:**

- Publishing RCON, Docker, or backup ports; allowing a remote backup target; or auto-starting PZ.
- Giving a container direct systemd, host-root-filesystem, or privileged access to power off Linux.
- Backing up a stopped server through this command; the command requires a running server so it can
  establish the RCON safe-stop sequence.

## Decisions

### Add a profile-gated backup runner with local Docker access

`compose.yaml` will define `pz-backup` under the existing `management` profile. It will use the
local PZ image with a backup-specific entrypoint, join `container:pz-server` network mode, mount
`pz-data` at a read-only source path, mount the Docker socket, and mount a `pz-backup` bind-backed
volume as its archive destination. The runner will execute as root only because Docker socket access
requires it; it will create final archive files with the destination directory's owner and group.

The image will contain the existing `pz-rcon` tool plus the Docker CLI, `tar`, checksum, and locking
utilities needed by the runner. A separate generic Docker CLI image was rejected because it would
duplicate the local RCON tooling and configuration contract.

The Docker socket is a deliberate trusted-local boundary: even if the runner invokes only inspect
and wait operations, possession of the socket grants Docker-daemon control. It is mounted only in
this profile-gated service and documented as local-administrator-only.

### Make RCON the only normal shutdown mechanism

The runner will fail without archiving if `pz-server` is not running or either RCON command fails.
It will run `pz-rcon save`, then `pz-rcon quit`, then `docker wait pz-server` with no timeout. It
will reject an abnormal result before archive creation. This avoids `docker stop` and its possible
forced termination after a grace period.

Polling an A2S endpoint was rejected because it cannot conclusively establish completed process
exit. A fixed sleep was rejected because completion time is variable. Docker `wait` is the exact
state confirmation and does not force a stop.

### Declare the destination as a configurable bind-backed volume

The top-level `pz-backup` volume will use the local driver's bind options, with its `device` set to
`${PZ_BACKUP_DIR:-/home/potsonhumer/pz-backup}`. The host directory must exist before Compose runs,
so Docker never silently creates a root-owned directory in a user's home. The runner locks inside
that directory, writes a unique `.partial` archive and checksum, verifies it, and retains only the
three newest finalized matching pairs.

A normal Docker named volume was rejected because it stores archives under Docker-managed storage
instead of the requested host path. A direct short-syntax bind mount was rejected because the
top-level volume makes the operator-configurable backup location visible in the Compose volume
configuration.

### Retain a thin root-host power-off wrapper

`scripts/pz-backup-and-poweroff.sh` will remain a root-only host script, but will acquire its lock,
run `docker compose run --no-deps pz-backup` from `PZ_COMPOSE_DIR` (default `/var/PZServer`), and call `sync`
and `systemctl poweroff` only after that command succeeds. It will not call `docker stop` or create
archives itself.

Moving `systemctl poweroff` into the Compose container was rejected: it would require privileged
host-system access beyond the Docker socket and make the command substantially more dangerous.

## Risks / Trade-offs

- [Docker socket grants broad daemon control] → Restrict the service to the management profile,
  publish no ports, and document that only a trusted local Docker administrator may invoke it.
- [RCON quit never completes] → `docker wait` remains pending rather than archive an active world or
  force-stop it; the host wrapper therefore never powers off.
- [Backup directory is missing or inaccessible] → Compose fails before the runner starts; document
  that operators create and own the directory first.
- [A previous backup command is still active] → Use a non-blocking lock in the backup destination
  and fail before sending RCON commands.
- [The PZ server is already stopped] → Fail without backup or power-off rather than bypassing the
  required RCON safe-stop sequence.

## Migration Plan

1. Create the backup destination directory on the Linux host, or set `PZ_BACKUP_DIR` in `.env`.
2. Rebuild the local image and use `docker compose run --no-deps pz-backup` for manual backup.
3. Reinstall the root wrapper and point `PZ_COMPOSE_DIR` at the Compose project for scheduled
   backup-and-power-off.
4. To roll back, use the prior host script revision; existing backup archives remain in the same
   host directory.

## Open Questions

None.
