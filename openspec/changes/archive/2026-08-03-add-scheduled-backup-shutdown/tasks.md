## 1. Backup workflow script

- [x] 1.1 Add a root-run shell script at `scripts/pz-backup-and-poweroff.sh` with strict error handling, dependency/user/resource preflight checks, and a non-blocking `flock` lock.
- [x] 1.2 Implement the `pz-server` running-state check and `docker stop --timeout 120 pz-server` path, including stopped-state verification and the exit-code-137 safety abort.
- [x] 1.3 Implement creation of `/home/potsonhumer/pa-backup` as `potsonhumer`, followed by a read-only helper-container archive of the complete `pz-data` volume into root-owned staging.
- [x] 1.4 Implement `.partial` archive handling, SHA-256 checksum generation, finalized archive ownership/modes, and safe retention of only the three newest matching archive/checksum pairs.
- [x] 1.5 Call `sync` and `systemctl poweroff` only on the all-success path; ensure every earlier failure skips retention changes where required and skips host power-off.

## 2. Operator documentation

- [x] 2.1 Document prerequisites, script installation, required root crontab usage, archive location, retention behavior, failure behavior, and restore/extraction guidance in the README.
- [x] 2.2 Document that the schedule and Docker restart policy are chosen separately by the operator, and that forced-stop protection leaves the host running for manual investigation.

## 3. Verification

- [x] 3.1 Run shell syntax and available shell lint checks against the new script.
- [x] 3.2 Exercise the workflow with mocked Docker and power-management commands to verify success, already-stopped, lock-conflict, archive-failure, and exit-code-137 paths without powering off a host.
- [x] 3.3 Inspect a generated test archive to confirm it contains the complete volume layout, has a valid SHA-256 checksum, correct `potsonhumer:root` ownership/mode, and retention leaves three finalized backups.
