## ADDED Requirements

### Requirement: Container-local player-count command
The image SHALL provide an executable `pz-query` command. Without arguments, the command SHALL query the running Project Zomboid server through Steam A2S at `127.0.0.1` and the selected server's configured `DefaultPort`, using `16261` when that setting is absent. On success it SHALL write exactly `players=<integer>` and `max_players=<integer>` on separate stdout lines.

#### Scenario: Query a server with players online
- **WHEN** a running Project Zomboid server reports three current players and a maximum of 32 players through A2S
- **THEN** `docker exec pz-server pz-query` writes `players=3` and `max_players=32`

#### Scenario: Query an empty server
- **WHEN** a running Project Zomboid server reports no current players through A2S
- **THEN** `docker exec pz-server pz-query` writes `players=0` rather than an empty response

#### Scenario: Use a customized main server port
- **WHEN** the selected PZ server INI sets `DefaultPort` to a valid non-default value
- **THEN** `pz-query` sends its loopback A2S request to that value

### Requirement: A2S challenge and response handling
The `pz-query` command SHALL complete the A2S challenge-response exchange when the server requires it and SHALL parse player-count fields only from a valid A2S information response.

#### Scenario: Server requests an A2S challenge
- **WHEN** the first A2S information request receives a challenge response
- **THEN** `pz-query` retries the request with that challenge and reports the counts from the resulting valid information response

### Requirement: Unambiguous query failure
When the selected server is not running, does not respond before the documented timeout, has an invalid configured port, or returns an invalid A2S response, `pz-query` SHALL write a diagnostic to stderr, SHALL not write a `players=` result, and SHALL exit nonzero.

#### Scenario: Query a stopped server
- **WHEN** an operator runs `pz-query` while Project Zomboid is not accepting A2S requests
- **THEN** the command exits nonzero with a diagnostic instead of reporting `players=0`

### Requirement: No additional management exposure
The player-count command SHALL not require RCON configuration or a RCON password, SHALL not add Docker `EXPOSE` metadata, and SHALL not accept a caller-controlled remote host.

#### Scenario: Query without RCON opt-in
- **WHEN** an operator runs `pz-query` in a running server container that has no RCON configuration
- **THEN** the command can query the container-local A2S endpoint without publishing an additional port

### Requirement: Documented player-count operation
The project documentation SHALL describe `docker exec pz-server pz-query`, its two success output lines, and the difference between `players=0` and a nonzero query failure.

#### Scenario: Operator reads player-count documentation
- **WHEN** an operator consults the local management documentation
- **THEN** they can determine how to query the count and interpret an empty server separately from a query failure
