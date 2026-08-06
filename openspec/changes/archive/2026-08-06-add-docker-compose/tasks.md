## 1. Compose configuration

- [x] 1.1 Add `compose.yaml` with the `pz-server` service, `linux/amd64` image build, fixed
  `pz-server` container name, existing `pz-data` volume, game UDP ports, and 60-second graceful
  stop setting.
- [x] 1.2 Configure the Compose RCON secret, `420正版` server and locale defaults, without
  publishing an RCON port.
- [x] 1.3 Add `.env.example` for `PZ_ADMIN_PASSWORD` and `PZ_JAVA_XMX`, and ignore the local
  `.env` file.

## 2. Documentation

- [x] 2.1 Replace routine local `docker run` instructions with Compose preparation, start,
  restart, and image-rebuild commands.
- [x] 2.2 Document migration from the existing manual `pz-server` container while preserving
  `pz-data`, and document the no-cache Compose build path for PZ updates.

## 3. Verification

- [x] 3.1 Validate the Compose configuration resolves the exact service name, persistent volume,
  game-only published ports, secret target, and required environment defaults.
