## Why

The current image is runnable with Docker, but a fully managed platform cannot pass
interactive first-run arguments and requires its own persistent-volume and UDP
forwarding configuration. Consolidating startup into the Dockerfile and defining a
managed-platform operating path makes the Project Zomboid server deployable from a
Git repository without a host shell or Docker Compose.

## What Changes

- Move the runtime startup wrapper behaviour into the Dockerfile so the repository's
  container runtime definition has no separate executable script.
- Add a non-interactive, environment-variable-based first-run administrator-password
  path suitable for a managed deployment.
- Document Zeabur deployment: Dockerfile build detection, a persistent data volume,
  and UDP forwarding for the current Project Zomboid ports.
- Clarify that persistent storage and public UDP forwarding are platform resources;
  they are configured in Zeabur rather than created by the Dockerfile.

## Capabilities

### New Capabilities

- `managed-platform-bootstrap`: Initialize a server non-interactively from managed
  platform environment variables while keeping credentials out of the image.

### Modified Capabilities

- `dedicated-server-container`: The default startup implementation moves fully into
  the Dockerfile while retaining foreground, non-root server execution.
- `server-data-persistence`: Documentation adds managed-platform volume mounting at
  the existing Project Zomboid data path.
- `server-networking-documentation`: Documentation adds Zeabur UDP-forwarding
  instructions for the current server port pair.

## Impact

- Affects `Dockerfile`, removes the standalone entrypoint script, and updates
  `README.md`.
- Adds one managed-platform bootstrap specification and delta specifications for the
  existing container, persistence, and networking contracts.
- Does not add Docker Compose, a platform template, or infrastructure credentials to
  the repository.
