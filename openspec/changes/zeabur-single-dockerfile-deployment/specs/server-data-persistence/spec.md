## MODIFIED Requirements

### Requirement: Persistent server-data mount
The project SHALL document one container data directory under the runtime user's home directory that contains the Project Zomboid `Zomboid` settings and multiplayer-save hierarchy and is intended for a Docker volume, bind mount, or managed-platform persistent volume. The documentation SHALL direct Zeabur operators to mount a persistent volume at that same directory rather than over the installed server files.

#### Scenario: First run creates server data
- **WHEN** an operator starts the server with an empty mount at the documented data directory
- **THEN** generated server settings and world data are written to that mount
