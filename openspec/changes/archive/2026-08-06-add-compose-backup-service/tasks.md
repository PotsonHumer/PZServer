## 1. Backup runner image and workflow

- [x] 1.1 Add the Docker CLI and a dedicated backup-runner entrypoint to the local PZ image without changing the existing game or management-tool entrypoints.
- [x] 1.2 Implement the runner's non-blocking destination lock, running-server validation, RCON `save` then `quit`, indefinite `docker wait`, clean-exit validation, and failure handling without `docker stop`.
- [x] 1.3 Implement read-only `pz-data` archiving with partial files, SHA-256 verification, destination-owner finalization, and three-pair retention.

## 2. Compose backup command

- [x] 2.1 Add a `management`-profile `pz-backup` service with the backup entrypoint, `container:pz-server` networking, a read-only `pz-data` mount, local Docker socket, and no published ports or restart policy.
- [x] 2.2 Declare the `pz-backup` bind-backed volume using `PZ_BACKUP_DIR` with `/home/potsonhumer/pz-backup` as its default, and document any required pre-existing host directory setup.

## 3. Scheduled power-off wrapper

- [x] 3.1 Refactor `scripts/pz-backup-and-poweroff.sh` into a root-only, locked wrapper that runs `docker compose run --no-deps pz-backup` from configurable `PZ_COMPOSE_DIR` (default `/var/PZServer`).
- [x] 3.2 Ensure the wrapper runs `sync` and `systemctl poweroff` only after the Compose command succeeds, and removes its former direct stop/archive implementation.

## 4. Documentation

- [x] 4.1 Update README with the manual `docker compose run --no-deps pz-backup` workflow, expected server shutdown, backup location configuration, retention, and Docker-socket trust boundary.
- [x] 4.2 Update scheduled backup documentation for the thin root-host wrapper, `PZ_COMPOSE_DIR`, and the guarantee that a failed backup does not power off Linux.

## 5. Verification

- [x] 5.1 Verify rendered Compose configuration: profile gating, local-only socket access, RCON-compatible namespace, read-only world data, and the default/configured bind-backed backup volume.
- [x] 5.2 Add and run focused runner/wrapper tests with mocked Docker, RCON, archive, and power-management commands to cover success, RCON failure, uncompleted shutdown, archive failure, and no-power-off behavior.
- [x] 5.3 Run syntax and diff checks, and validate the OpenSpec change strictly.
