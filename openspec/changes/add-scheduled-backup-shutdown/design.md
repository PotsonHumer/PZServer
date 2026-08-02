## Context

The Docker image persists Project Zomboid configuration and multiplayer world data in the named `pz-data` volume mounted at `/home/steam/Zomboid`. A root cron job must be able to take a filesystem-level backup of that data before powering off the Linux host. The operator has selected a 120-second Docker stop timeout, `/home/potsonhumer/pa-backup` as the archive location, `potsonhumer:root` ownership for finalized artifacts, three retained successful backups, and a fail-safe policy that does not power off after an unsafe stop.

## Goals / Non-Goals

**Goals:**

- Provide one non-interactive, root-run shell entry point suitable for cron.
- Create an offline archive of the complete persisted Docker volume only after the game container is stopped.
- Make successful archives verifiable, recoverable, and owned by `potsonhumer:root`.
- Avoid deleting a known-good archive or powering off the host after any failed prerequisite.

**Non-Goals:**

- Sending Project Zomboid console/RCON commands or taking an in-game save.
- Configuring the cron schedule, Docker restart policy, remote/off-site replication, or automatic restore.
- Backing up the installed game image, containers, or unrelated Docker volumes.

## Decisions

### Stop the container through Docker with its configured signal and a 120-second grace period

The script will call `docker stop --timeout 120 pz-server` only when the container is running, then verify that it is stopped. It will not choose a custom signal, allowing the image `STOPSIGNAL` and the server's normal termination handling to apply.

It will inspect the resulting container exit code when it initiated the stop. Exit code `137` is treated as evidence that Docker exhausted the grace period and killed the process. In that case the script exits unsuccessfully without an archive, retention deletion, or host power-off. This preserves the running host for investigation rather than treating a forced stop as a clean save.

Alternative considered: always proceed after Docker reports the container stopped. This is rejected because `docker stop` can succeed after sending a forced kill.

### Archive the complete named volume through a read-only helper container

The script will start a short-lived helper from `pz-server:local`, mount `pz-data` read-only at a neutral source path, and run `tar` inside it to write a gzip archive into a root-owned temporary staging directory. Backing up the complete volume includes `Server/`, `Saves/Multiplayer/`, account data, mods, and related persisted state.

The archive will first use a unique `.partial` filename. It becomes a successful backup only after the archive command and a SHA-256 checksum both succeed, followed by an atomic rename to the timestamped `.tar.gz` filename. The finalized archive and checksum are changed to `potsonhumer:root` with mode `0640` in staging, then published to the requested backup directory.

Alternative considered: copy only the world directory from the Docker volume mountpoint on the host. This is rejected because Docker's internal volume location is implementation-specific and because a world-only backup omits configuration and account state.

### Retain exactly the three most recent successful archives

After a new archive has been finalized, the script will identify only its own timestamped archive names under `/home/potsonhumer/pa-backup`, keep the three newest, and remove older matching archive/checksum pairs. Incomplete `.partial` files never count as successful backups. Retention never runs before a new archive and checksum are complete.

Alternative considered: rely on a broad wildcard deletion or delete old backups before archiving. This is rejected because it can delete unrelated files or leave no usable backup after a failure.

### Isolate root work from the user-writable backup directory

The script will require root, validate the `potsonhumer` account and required executables, and take a non-blocking `flock` lock before changing container or backup state. Root performs archive creation, checksumming, and ownership changes only in a root-owned temporary staging directory. It creates the requested `/home/potsonhumer/pa-backup` directory and publishes, lists, and prunes final artifacts as `potsonhumer`, so a user-controlled home-directory path is never used for root-owned archive files or root-side deletion. Finalized archives and checksum files use `potsonhumer:root` with mode `0640`.

Alternative considered: make the backup directory root-owned while keeping it below `/home/potsonhumer`. This is rejected because `potsonhumer` can still replace a child path from its writable home directory. A root-owned staging directory plus unprivileged publication avoids that path-substitution risk while retaining the requested destination and artifact ownership.

### Power off only after the backup workflow succeeds

After the archive, checksum, ownership/mode updates, and retention are successful, the script calls `sync` and then `systemctl poweroff`. Every pre-power-off error is fatal and leaves the host powered on.

Alternative considered: put `systemctl poweroff` in cron after the script regardless of its result. This is rejected because it disconnects power-off from backup success.

## Risks / Trade-offs

- [The PZ process needs longer than two minutes to stop] → The script refuses to archive or power off after exit code `137`; an operator can inspect logs and retry manually.
- [The host loses power during archive creation] → The temporary `.partial` archive is never retained as a successful backup, and previous finalized archives remain untouched.
- [The backup filesystem fills up] → Archive or checksum creation fails before retention and power-off; the script exits with an error while preserving existing archives.
- [A cron job overlaps a manual run] → A non-blocking `flock` causes the second invocation to fail without touching data.
- [A corrupt archive is produced but tar exits successfully] → The SHA-256 file detects later transfer or storage corruption, but it is not a full restore test; operators should periodically test extraction.

## Migration Plan

1. Add the script to the repository and document its required root installation path and cron invocation.
2. Run it manually as root on a non-production window and verify the archive contents, checksum, permissions, retention count, and host power-off behavior.
3. Install the chosen root crontab schedule only after the manual verification succeeds.
4. To roll back, remove the crontab entry and the installed script; existing `.tar.gz` archives remain independent restore inputs.

## Open Questions

None for the backup-and-power-off script. The time of day for the root crontab entry and whether Docker should restart `pz-server` after the next host boot are operational choices outside this change.
