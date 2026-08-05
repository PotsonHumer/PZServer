## Why

Project Zomboid RCON can execute server-management commands but does not reliably return query results such as the current player count. Operators therefore cannot use the existing local CLI to determine whether anyone is online.

## What Changes

- Add a container-local `pz-query` command that reads the live player count through Project Zomboid's Steam A2S query endpoint instead of RCON.
- Return machine-readable current and maximum player counts from the command.
- Keep the query entirely inside the container loopback network and require no RCON password or additional published port.
- Document how to use the query and how failure differs from an empty server.

## Capabilities

### New Capabilities

- `local-player-count-query`: A container-local CLI for retrieving the live Project Zomboid player count through A2S.

### Modified Capabilities

None.

## Impact

- Affected code: Runtime image dependencies and a bundled `pz-query` executable.
- Affected tests: A2S challenge, response parsing, empty-server count, and error-path coverage.
- Affected documentation: Local operator commands and player-count semantics.
