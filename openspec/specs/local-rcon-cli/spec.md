## Purpose

Define opt-in, container-local RCON configuration and the `pz-rcon` command interface for the Project Zomboid dedicated-server image.

## Requirements

### Requirement: Opt-in persistent RCON configuration
The image SHALL enable Project Zomboid RCON only when `PZ_RCON_PASSWORD_FILE` identifies a non-empty readable password file. Before starting the PZ server, the entrypoint SHALL validate the configured server name and port and SHALL create or update the matching persistent `Server/<server-name>.ini` with `RCONPort` and `RCONPassword`. The entrypoint SHALL not print the password or its contents.

#### Scenario: Configuring RCON from a secret file
- **WHEN** an operator supplies a readable non-empty password file and valid RCON port and server name settings
- **THEN** the server starts with matching RCON settings in its persisted server INI

#### Scenario: Password file is unavailable
- **WHEN** `PZ_RCON_PASSWORD_FILE` is missing, unreadable, or empty
- **THEN** the entrypoint exits before starting Project Zomboid and reports a redacted configuration error

#### Scenario: RCON is not requested
- **WHEN** `PZ_RCON_PASSWORD_FILE` is unset
- **THEN** the image preserves its existing server startup behavior without creating or enabling RCON settings

### Requirement: Container-local RCON command interface
The image SHALL provide an executable `pz-rcon` command that authenticates with the configured PZ RCON listener at `127.0.0.1` and forwards supplied command arguments to that listener. The wrapper SHALL obtain credentials without requiring callers to provide a password as a command argument, SHALL relay the RCON response, and SHALL return a nonzero status when configuration, connection, authentication, or command execution fails.

#### Scenario: Send a save command through Docker exec
- **WHEN** a running configured server receives `docker exec pz-server pz-rcon save`
- **THEN** the wrapper sends `save` to the PZ RCON listener and returns its response to the invoking Linux shell

#### Scenario: Run a command that contains spaces
- **WHEN** an operator passes a single quoted PZ command with arguments to `pz-rcon`
- **THEN** the wrapper forwards it as one RCON command without changing its content

#### Scenario: RCON has not been configured
- **WHEN** an operator invokes `pz-rcon` in a container without valid RCON configuration
- **THEN** the wrapper fails without printing a password

### Requirement: No host or public RCON endpoint
The image SHALL include the RCON client and wrapper without adding an RCON port to Dockerfile `EXPOSE` metadata. The documented container launch commands SHALL NOT publish an RCON port, and the wrapper SHALL use the container loopback address rather than a caller-controlled remote address.

#### Scenario: Inspecting the image network metadata
- **WHEN** an operator inspects the built image
- **THEN** no RCON TCP port appears in its exposed-port metadata

#### Scenario: Normal local operation
- **WHEN** the operator uses `docker exec pz-server pz-rcon players`
- **THEN** the command operates without any Docker RCON port publication

### Requirement: Local operator documentation
The repository documentation SHALL describe password-file mounting, RCON opt-in settings, the `docker exec pz-server pz-rcon` interface, and an orderly maintenance sequence using server announcement, save, and quit commands. It SHALL state that Docker-daemon access grants the ability to issue unrestricted PZ RCON commands.

#### Scenario: Operator follows the documented startup path
- **WHEN** an operator follows the documented local RCON setup
- **THEN** they can configure and invoke RCON without exposing a host or public RCON port
