## Context

The existing `pz-rcon` wrapper is appropriate for issuing actions such as `save` and `quit`, but Project Zomboid's RCON command handlers do not provide a dependable text result for player-list or statistics commands. Project Zomboid exposes its live server information through the Steam A2S UDP query protocol on its main server port instead.

The query must run from `docker exec` without a host-installed tool, a RCON password, or a newly published network port. The runtime image is intentionally small and currently has no general-purpose query runtime.

## Goals / Non-Goals

**Goals:**

- Provide `docker exec pz-server pz-query` as a dependable current-player-count command.
- Return explicit machine-readable zero values for an empty server.
- Clearly distinguish an unavailable server or invalid reply from a count of zero.
- Keep all query traffic on container loopback and reuse the configured PZ main port.

**Non-Goals:**

- Replacing `pz-rcon`, exposing a host or public management endpoint, or querying another server.
- Returning player names, RCON output, server administration data, or a continuous monitoring service.
- Adding a host dependency or a separately managed Python package.

## Decisions

### Bundle a focused A2S client

The image will install the distribution `python3` runtime and include a small bundled `pz-query` program using only Python's standard library. It will implement the A2S info request, including the challenge-response retry required by Steam servers, and parse only the fields necessary for the current and maximum player counts.

This avoids downloading an unpinned third-party Python package at image build time and makes the output and failure semantics part of this repository's contract. A standalone static client was considered, but would add an additional release, architecture, checksum, and maintenance surface for a small protocol operation.

### Resolve the local query target from PZ configuration

`pz-query` will target `127.0.0.1` and read `DefaultPort` from the selected persistent PZ server INI, defaulting to `16261` when that setting is absent. It will use the same `PZ_DATA_DIR` and `PZ_SERVER_NAME` selection as the other local management commands.

This keeps the command working when an operator changes PZ's main port, while preventing a caller from turning it into a generic remote network client. Hard-coding 16261 was rejected because it silently produces misleading failures for customized server ports.

### Make output and errors unambiguous

On a valid A2S response, the command will write exactly `players=<integer>` and `max_players=<integer>` on separate stdout lines. A server with no players therefore reports `players=0`. Timeouts, malformed responses, unavailable configuration, and invalid port values will write a redacted diagnostic to stderr and exit nonzero without a player-count line.

Parsing player names or the optional A2S player list was rejected because the operator requested a count and it increases privacy exposure without improving the result.

## Risks / Trade-offs

- [A2S reply format changes or sends a malformed packet] → Validate packet type, bounded fields, and count values; fail rather than printing a guessed count.
- [The PZ server is stopped or still starting] → Use a short bounded timeout and a nonzero exit status that differs from `players=0`.
- [Adding Python increases image size] → Use Ubuntu's distribution package with no pip packages and limit the bundled program to this one read-only query.

## Migration Plan

1. Build the updated image and recreate the container with the same persistent data volume.
2. While PZ is running, use `docker exec pz-server pz-query` to obtain the live count.
3. To roll back, use the previous image; this feature changes no persistent server data and requires no configuration migration.

## Open Questions

None.
