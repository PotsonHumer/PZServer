## 1. Bundle the local RCON client

- [x] 1.1 Select a pinned Source-RCON client release, record its license and SHA-256, and add a checksum-verified build/download stage for the linux/amd64 runtime image.
- [x] 1.2 Copy only the required client executable into the final image and verify that no RCON port is added to Dockerfile `EXPOSE` metadata.

## 2. Configure and invoke RCON

- [x] 2.1 Extend the entrypoint to validate `PZ_RCON_PASSWORD_FILE`, `PZ_RCON_PORT`, and `PZ_SERVER_NAME`, then idempotently create or update the matching persistent PZ server INI without logging the password.
- [x] 2.2 Preserve the existing startup behavior when RCON opt-in is absent and fail before PZ starts when supplied RCON configuration is invalid.
- [x] 2.3 Add the `pz-rcon` wrapper that reads the persisted RCON configuration, connects only to `127.0.0.1`, passes credentials to the bundled client without a password command argument, relays responses, and returns failures to `docker exec`.

## 3. Test the local-only workflow

- [x] 3.1 Add automated coverage for valid first-boot and repeated RCON configuration, including password redaction and invalid secret-file handling.
- [x] 3.2 Build the image and run an isolated configured server to verify `docker exec pz-server pz-rcon players` and `save`, including a quoted command with spaces.
- [x] 3.3 Inspect the final image and runtime launch configuration to verify that the RCON port is neither exposed nor published.

## 4. Document operation

- [x] 4.1 Document creation and read-only mounting of the password file, opt-in environment variables, and the `docker exec pz-server pz-rcon` command interface.
- [x] 4.2 Document the planned-maintenance sequence (`servermsg`, `save`, `quit`) and the fact that Docker-daemon access grants unrestricted PZ command access.
