## Why

The current deployment instructions require repeating a long `docker run` command whenever the
container is created or replaced. That makes it easy to omit the persistent volume, network ports,
RCON secret mount, or the established `420正版` server selection.

## What Changes

- Add a Docker Compose definition for the local Project Zomboid server, including image build,
  persistent data, game ports, the local RCON secret, and graceful-stop settings.
- Make the existing RCON and locale settings fixed Compose defaults for the `420正版` server.
- Load `PZ_ADMIN_PASSWORD` and `PZ_JAVA_XMX` from a local `.env` file instead of committing them
  to the Compose definition.
- Ignore `.env`, provide a non-secret `.env.example`, and document concise Compose operations for
  first startup, normal restart, and rebuilding the image.

## Capabilities

### New Capabilities

- `docker-compose-operation`: Declarative local Docker Compose operation of the Project Zomboid
  server with durable data, local RCON, and non-committed runtime configuration.

### Modified Capabilities

None.

## Impact

- New `compose.yaml` and `.env.example` files.
- `.gitignore` and `README.md` updates.
- Docker Compose v2 becomes the supported local operation interface; the existing image,
  entrypoint, RCON wrapper, and persistent `pz-data` volume remain unchanged.
