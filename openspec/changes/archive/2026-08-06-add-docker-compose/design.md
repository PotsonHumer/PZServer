## Context

Local operation currently relies on repeated `docker run` commands. The established production
server is named `420正版`, its persistent Docker volume is `pz-data`, and its RCON password already
resides in the ignored `secrets/rcon-password` file. The image provides the local RCON and player
query commands; Compose only needs to consistently create the same container configuration.

`PZ_ADMIN_PASSWORD` and `PZ_JAVA_XMX` vary by installation. The former is secret material and the
latter is host-memory dependent, so neither belongs in version-controlled Compose defaults.

## Goals / Non-Goals

**Goals:**

- Provide one declarative Compose service that replaces the routine local `docker run` command.
- Preserve the existing `pz-data` volume and `420正版` server selection during migration.
- Keep RCON container-local while mounting the existing password file as a Compose secret.
- Load the administrator password and Java heap override from an ignored local `.env` file.

**Non-Goals:**

- Changing PZ server behavior, its world, its default published game ports, or the image entrypoint.
- Publishing RCON, adding an administrator-password-file feature, or committing real secrets.
- Replacing the existing host backup workflow or supporting multiple Compose server instances.

## Decisions

### Use one explicitly named Compose service and existing named volume

The Compose file will build and tag `pz-server:local`, run it as `linux/amd64`, and set
`container_name: pz-server`. Its named volume will be declared with `name: pz-data`, rather than
letting Compose prepend a project name. This preserves the deployed data and existing
`docker exec pz-server ...` commands.

The alternative is relying on Compose-generated names. That would create a different volume such
as `pzserver_pz-data` and change the management command target, risking an accidental new server.

### Encode established non-secret configuration in Compose

The service will publish only the current game UDP ports and set a 60-second stop grace period. It
will set `PZ_RCON_PASSWORD_FILE=/run/secrets/pz-rcon-password`, `PZ_RCON_PORT=27015`,
`PZ_SERVER_NAME=420正版`, `LANG=C.UTF-8`, and `LC_ALL=C.UTF-8`. The existing RCON password file
will be declared as a Compose secret and mounted at the path used by the image; no RCON port will
be published.

Keeping these settings in a shell command was rejected because it is exactly the configuration
that needs to be reproducible on every container replacement.

### Use `env_file` for local administrator and memory settings

The service will declare `env_file: .env`. The tracked `.env.example` will show only
`PZ_ADMIN_PASSWORD` and `PZ_JAVA_XMX` with non-secret example values. `.env` will be ignored by
Git and documented as the installation-specific source for those two container environment
variables.

Compose interpolation alone was rejected because it does not automatically inject variables into
the container unless the Compose service references them. A version-controlled administrator
password was rejected because it would expose a secret in Git.

### Document Compose as the routine local interface

Documentation will make `docker compose up -d --build` the normal create-or-replace command and
will include a cache-bypassing image build command for PZ server updates. It will explain the
one-time migration from a manual `pz-server` container: preserve `pz-data`, stop the old container
normally, remove only that container to free the fixed name, then start Compose.

## Risks / Trade-offs

- [A manual `pz-server` container still exists] → Document that it must be stopped and removed
  without removing `pz-data` before the Compose service can claim the fixed container name.
- [The `.env` file is committed] → Add it to `.gitignore`, provide only `.env.example`, and keep
  the real administrator password out of documentation and tracked files.
- [The secret file is absent] → Compose startup fails rather than launching a server without the
  requested local RCON configuration; document the prerequisite.
- [A PZ update remains in Docker build cache] → Document the explicit no-cache Compose build path
  for server updates.

## Migration Plan

1. Back up the existing `pz-data` volume and create `secrets/rcon-password` plus `.env` locally.
2. Gracefully stop the existing manual `pz-server` container, then remove that container only;
   do not remove `pz-data`.
3. Start the Compose service, which reuses the same volume and `420正版` server configuration.
4. To roll back, stop the Compose service without its `-v` option and recreate the previous
   manual container against the unchanged `pz-data` volume.

## Open Questions

None.
