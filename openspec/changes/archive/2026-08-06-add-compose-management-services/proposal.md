## Why

After moving the server to Docker Compose, routine management still requires naming the running
`pz-server` container. Operators should be able to invoke the existing player-count and RCON tools
as short, one-off Compose services without exposing a management port or altering their local-only
network model.

## What Changes

- Add profiled, one-off Compose services named `pz-query` and `pz-rcon`.
- Run each management tool in a separate container that shares the running `pz-server` network
  namespace and reads the persistent PZ configuration without writing it.
- Document `docker compose run pz-query` and `docker compose run pz-rcon <command>` as the normal
  local management commands.
- Preserve stopped one-off containers after execution for logs and exit-code inspection.

## Capabilities

### New Capabilities

- `compose-management-services`: One-off Docker Compose services for container-local player
  queries and RCON commands.

### Modified Capabilities

None.

## Impact

- `compose.yaml` gains two profile-gated management services.
- `README.md` documents Compose-native management commands.
- The existing image, `pz-query`, `pz-rcon`, game service, RCON port exposure, and persistent
  server data remain unchanged.
