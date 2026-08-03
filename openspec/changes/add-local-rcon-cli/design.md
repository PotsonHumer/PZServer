## Context

The image currently launches `ProjectZomboid64` through `pz-entrypoint.sh` and persists its generated configuration at `/home/steam/Zomboid`. Docker can control the process lifecycle, but `docker exec` cannot send text to the server's standard input. Project Zomboid supplies an authenticated RCON listener, while the image contains no RCON client and exposes no operator command.

The operator wants management commands from the Linux host only. No RCON port is to be published from Docker and no host package installation is required.

## Goals / Non-Goals

**Goals:**

- Configure PZ RCON from a mounted secret file without putting its password in `docker run` arguments, image metadata, or command output.
- Provide `docker exec pz-server pz-rcon <command...>` as the only documented RCON invocation path.
- Have that wrapper authenticate to the RCON listener at `127.0.0.1` in the same container network namespace.
- Preserve the current no-RCON behavior when RCON configuration is not supplied.

**Non-Goals:**

- Publishing RCON to the host, LAN, or Internet.
- Providing a web panel, remote management service, interactive Docker-console bridge, or command scheduler.
- Removing the existing Docker lifecycle and backup workflow.
- Encrypting the PZ server configuration at rest; PZ requires its RCON password in its own persisted INI configuration.

## Decisions

### Use a container-local `pz-rcon` wrapper around a bundled Source-RCON client

The runtime image will contain a pinned, checksum-verified RCON client compatible with PZ's Source-RCON protocol, plus `/usr/local/bin/pz-rcon`. The wrapper will connect to `127.0.0.1`, obtain the configured port and password from the server configuration, pass those values to the client through its environment, and forward its positional arguments as one or more PZ commands.

This keeps the public interface small and makes the host command independent of client-specific flags. `docker exec` runs the wrapper in the server container's network namespace, so no Docker port publication is necessary.

Alternative considered: tell operators to install and invoke `mcrcon` on every Linux host. Rejected because it introduces unmanaged host dependencies and needs a host-visible RCON port. Alternative considered: use `docker exec` to write directly to the PZ process stdin. Rejected because `exec` creates a separate process and the existing password-aware entrypoint deliberately owns the server input FIFO.

### Opt in through a readable password-file path and a server-name/port configuration

RCON will be enabled only when `PZ_RCON_PASSWORD_FILE` names a non-empty readable file. A non-secret `PZ_RCON_PORT` and `PZ_SERVER_NAME`, defaulting to the normal PZ server name, identify the listener and the matching `Server/<name>.ini` file. The entrypoint will validate the supplied values, create or update the RCON INI settings before launching PZ, and fail closed rather than start a partially configured RCON service.

The password-file path rather than a password environment variable avoids Docker configuration metadata and shell history carrying the secret. The file is supplied as a read-only mount, normally under `/run/secrets`, and must be readable by the image's unprivileged `steam` account; the entrypoint does not copy it into the image or print it. PZ's own persisted INI still necessarily stores its configured RCON password.

Alternative considered: use `PZ_RCON_PASSWORD` directly. Rejected because `docker inspect` reveals environment values. Alternative considered: require manual INI editing. Rejected because it is error-prone on first boot and does not create a repeatable local CLI workflow.

### Keep the RCON listener unreachable outside the container

The Dockerfile will not add an RCON `EXPOSE` declaration and the documented `docker run` commands will not publish an RCON port. `pz-rcon` always targets loopback; Docker lifecycle commands remain the only host-facing control surface.

This is deliberately stronger operational guidance than binding a host port to `127.0.0.1`: no host socket is created at all. Docker users with sufficient privileges can still run `docker exec` or attach additional containers, which is accepted because Docker-daemon access is already equivalent to administrative access to the game container.

Alternative considered: publish an RCON port on `127.0.0.1`. Rejected because it is unnecessary for `docker exec` and expands the host's listening surface.

## Risks / Trade-offs

- [The secret file is absent, unreadable, or empty] → The entrypoint fails before starting PZ with a redacted diagnostic.
- [PZ rejects a generated INI or RCON listener setup] → Integration tests will start a fresh volume, run `pz-rcon`, and verify that the wrapper reports the server error without exposing the password.
- [A user with Docker-daemon access invokes destructive PZ commands] → This is inherent in Docker administrative access; document that `pz-rcon` has no command allowlist.
- [A RCON password remains in the persistent PZ INI] → Document the persistence boundary and restrict access to the Docker volume and its backups.
- [The bundled client has a security or protocol issue] → Pin its version and checksum, record its license, and update it independently from PZ.

## Migration Plan

1. Rebuild the image with the bundled client and wrapper.
2. Create a root-owned, non-user-traversable password-file directory on the Linux host, make the read-only mounted file readable by the container's `steam` account, and configure `PZ_RCON_PASSWORD_FILE` and the non-secret port/server-name variables.
3. Start a new or existing server, then verify `docker exec pz-server pz-rcon players` and `save`.
4. Use `servermsg`, `save`, and `quit` for planned maintenance before the existing Docker backup/stop workflow.
5. To roll back, recreate the container without the password-file mount and RCON environment variables, and remove the RCON keys from the persisted server INI if RCON must be disabled.

## Open Questions

None. The implementation will select and pin the client release and checksum as part of its dependency update.
