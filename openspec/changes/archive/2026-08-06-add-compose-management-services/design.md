## Context

The Compose-managed `pz-server` container already contains `pz-query` and `pz-rcon`, but invoking
them with `docker compose exec` requires naming the main service on every command. Both tools
intentionally target `127.0.0.1`: `pz-query` sends A2S requests to loopback and `pz-rcon` connects
to the local RCON port. A normal separate Compose network would therefore make both tools talk to
their own empty container instead of the running game server.

## Goals / Non-Goals

**Goals:**

- Provide `docker compose run pz-query` and `docker compose run pz-rcon <command>` as one-off
  local management commands.
- Preserve the tools' loopback-only model without adding a management port or a remote host
  option.
- Keep normal `docker compose up -d` limited to the game server.
- Leave completed one-off containers stopped for operator inspection.

**Non-Goals:**

- Changing the `pz-query` or `pz-rcon` programs, adding host wrapper scripts, or accepting a
  remote management target.
- Automatically starting a stopped PZ server when an operator runs a management command.
- Removing exited one-off containers automatically or changing PZ world data.

## Decisions

### Define explicit profile-gated management services

`compose.yaml` will define services named `pz-query` and `pz-rcon`, each under a `management`
profile. They will override the image entrypoint with the corresponding existing executable. An
operator will explicitly invoke either service with `docker compose run`; profile-gated services
are not started by normal `docker compose up -d` but are enabled when directly targeted.

The service names deliberately match the tool names. A generic management service would require a
less clear command and would not provide distinct default entrypoints.

### Share the named main container's network namespace

Both one-off services will use `network_mode: container:pz-server`, relying on the fixed
`container_name` already provided by the main service. They will mount the `pz-data` volume
read-only and receive the selected `PZ_SERVER_NAME` so they can read the same configuration as the
game server.

Using `container:pz-server` means a stopped or absent main container causes the one-off command to
exit nonzero rather than launching PZ. `service:pz-server` was rejected because it forms a Compose
service dependency and could cause `docker compose run` to start a stopped game server. A normal
Compose bridge network was rejected because it cannot preserve the tools' current loopback-only
behavior without changing their code.

### Preserve one-off containers after completion

The management services will use the default no-restart behavior. Documentation will omit
`--rm`, so the one-off container exits after its tool finishes and remains available for logs and
exit-code inspection. Operators can remove accumulated stopped containers later with standard
Compose cleanup commands.

Automatic removal was rejected because the chosen operational model values the post-run record
more than automatic cleanup.

## Risks / Trade-offs

- [The main container is stopped] → The one-off container fails before querying or issuing RCON;
  document this as intentional and require the operator to start PZ explicitly first.
- [Stopped one-off containers accumulate] → They consume only metadata and can be inspected or
  removed with Compose; do not conceal this by adding `--rm`.
- [The fixed `pz-server` name changes] → The namespace-sharing services fail configuration or
  execution, preventing a silent query to the wrong endpoint.
- [The helper needs PZ configuration] → Mount `pz-data` read-only, so the helpers cannot alter
  the persistent world or server configuration.

## Migration Plan

1. Update the Compose configuration and rebuild the image only if it is not already available.
2. Start `pz-server` normally with `docker compose up -d`.
3. Use `docker compose run pz-query` or `docker compose run pz-rcon <command>`.
4. To roll back, remove the two helper services from Compose; existing `docker exec` management
   commands continue to work against the unchanged main container.

## Open Questions

None.
