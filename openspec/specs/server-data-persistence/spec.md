## Purpose

Define durable Project Zomboid server data and controlled shutdown behavior for container deployments.

## Requirements

### Requirement: Persistent server-data mount
The project SHALL document one container data directory under the runtime user's home directory that contains the Project Zomboid `Zomboid` settings and multiplayer-save hierarchy and is intended for a Docker volume, bind mount, or managed-platform persistent volume. The image SHALL create that container data directory for the unprivileged runtime account when it is absent. The primary local Docker run procedure SHALL mount the named Docker volume `pz-data` at that directory and state that Docker creates the named volume when it does not already exist. The documentation SHALL direct Zeabur operators to mount a persistent volume at that same directory rather than over the installed server files.

#### Scenario: First local run creates persistent server data
- **WHEN** an operator starts the documented local Docker command and `pz-data` does not already exist
- **THEN** Docker creates `pz-data` and generated server settings and world data are written to it

#### Scenario: First run creates server data in a managed mount
- **WHEN** an operator starts the server with an empty managed-platform mount at the documented data directory
- **THEN** generated server settings and world data are written to that mount

### Requirement: State survives container replacement
The documented run procedure SHALL allow a container to be removed and recreated from the same image while retaining the mounted server settings and multiplayer world data.

#### Scenario: Recreate a server container
- **WHEN** an operator removes a stopped container and starts a new one with the same persistent mount
- **THEN** the new container can access the prior server configuration and saved world data

### Requirement: Controlled container stop
The image entrypoint and documentation SHALL support normal Docker termination and specify a finite stop grace period for the server process.

#### Scenario: Stop a running server
- **WHEN** an operator issues a normal Docker stop command using the documented timeout
- **THEN** Docker sends termination to the server container and waits for the configured grace period before forceful termination
