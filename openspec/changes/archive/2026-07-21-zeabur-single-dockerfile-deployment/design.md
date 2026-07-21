## Context

The existing Project Zomboid image is a two-stage Docker build whose runtime entrypoint is supplied by `docker/pz-entrypoint.sh`. Local operators can bind a data directory, publish UDP ports, and pass `-adminpassword` interactively with `docker run`. Zeabur can build a repository Dockerfile and provides persistent volumes plus UDP forwarding, but its service configuration cannot be expressed by a Dockerfile and it has no interactive first-run terminal.

## Goals / Non-Goals

**Goals:**

- Keep the image's existing amd64 runtime, unprivileged `steam` account, data location, and graceful foreground process handling.
- Make `Dockerfile` the only repository file that defines runtime startup.
- Allow a managed service to provide the Project Zomboid admin password through an environment variable without baking that value into the image.
- Give operators an exact Zeabur setup path for the persistent volume and the current pair of UDP ports.

**Non-Goals:**

- Create a Zeabur Template, provision a Zeabur project, or automate dashboard resources from this repository.
- Add automated updates, backups, mod management, RCON, multi-instance support, or a web administration UI.
- Change the Project Zomboid network-port defaults or support legacy ports in the managed-platform walkthrough.

## Decisions

### Generate the entrypoint in Dockerfile

The final image will use an entrypoint script generated directly by a Dockerfile heredoc, so no startup script is retained in the repository. It creates the data directory and `exec`s `start-server.sh` when no managed password is set. When `PZ_ADMIN_PASSWORD` is set, it supervises the server in a separate process group, forwards Docker termination to that group, and relays server output while waiting for the two first-run password prompts.

A Dockerfile-generated entrypoint is chosen because it satisfies the requested one-file repository definition while allowing prompt-aware password delivery. Keeping the script in the repository would leave an extra deployment artifact; using a bare `ENTRYPOINT` would lose the data-directory preparation and managed-password handling.

### Use a dedicated environment variable for non-interactive administration

`PZ_ADMIN_PASSWORD`, when non-empty, will be written through a private FIFO only after the entrypoint observes each of Project Zomboid's first administrator-password and confirmation prompts. This avoids the game's `-adminpassword` command-line logging and prevents a value from being interpreted as a console command after initialization. When it is unset, startup will remain the game's normal command path. The Dockerfile must not contain a password default or print the value. Operators will store it in Zeabur's secret environment-variable setting and remove it after initialization.

Passing a raw Zeabur Start Command was rejected: it replaces the image's entrypoint, thereby bypassing its startup guarantees. Passing `-adminpassword` was rejected after verification showed that the bundled launcher logs command-line arguments. Requiring an interactive terminal was rejected because it is unavailable in the intended deployment.

### Treat Zeabur resources as operator configuration

The Dockerfile will continue to declare the data volume and UDP port metadata, but the README will direct the operator to mount a Zeabur Volume at `/home/steam/Zomboid` and create UDP forwarding to container ports `16261` and `16262`. `SERVERNAME.ini` retains matching `DefaultPort` and `UDPPort` values.

Dockerfile instructions cannot create a provider volume or public forwarding rule. A Zeabur Template could declare these resources as code, but is explicitly outside the requested single-Dockerfile repository scope.

## Risks / Trade-offs

- [A quoted inline shell entrypoint mishandles an argument or signal] → Verify image metadata and run a container smoke test that confirms the server is PID 1 after `exec`.
- [A password is visible in platform configuration or process inspection] → Do not log it or commit it; use Zeabur's secret environment-variable facility and document the residual runtime-secret exposure.
- [A Zeabur volume is omitted or mounted over the application directory] → Document only `/home/steam/Zomboid` as the mount point and explain that it contains both server settings and multiplayer saves.
- [UDP forwarding differs from the server configuration] → Document both current UDP target ports and require an end-to-end client connectivity check.

## Migration Plan

1. Build the revised image and verify its entrypoint and non-root runtime user.
2. On Zeabur, create a service from the repository, mount a new volume at `/home/steam/Zomboid`, set `PZ_ADMIN_PASSWORD`, and configure UDP forwarding to `16261` and `16262`.
3. Confirm first-start configuration, direct client connectivity, and data survival after a redeploy.
4. Roll back by redeploying the previous image or commit; retain the same volume so server settings and world saves are untouched.

## Open Questions

- None for implementation. The operator must choose the actual Zeabur project, volume ID, public forwarding addresses, and administrator secret at deploy time.
