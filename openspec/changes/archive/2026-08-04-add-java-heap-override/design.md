## Context

The installed Project Zomboid 64-bit launcher configuration contains `-Xmx8g`. This is a suitable server default but can exceed Docker Desktop's local virtual-machine memory during testing. The existing image starts the launcher through a Dockerfile-generated entrypoint and persists game data separately under `/home/steam/Zomboid`.

The override must be available at `docker run` time, because local and production machines can have different memory budgets. It must not be confused with Docker memory limits: Java heap is only one component of the server's total memory use.

## Goals / Non-Goals

**Goals:**

- Let an operator set `PZ_JAVA_XMX=2g` (or another positive whole-number MiB/GiB value) for a single container configuration.
- Preserve the image's shipped launcher heap setting when the variable is unset.
- Reject malformed values before starting Project Zomboid, without accepting arbitrary JVM arguments.
- Keep the change out of persistent game data.

**Non-Goals:**

- Setting Docker's memory limit or guaranteeing that a selected heap prevents an out-of-memory failure.
- Changing other JVM options, auto-tuning memory, or changing heap while the server is running.
- Persisting a local-test heap choice into saves or server configuration.

## Decisions

### Apply the setting in the entrypoint at container start

The Dockerfile will retain an immutable copy of the launcher JSON supplied by the installed game. At every container start, the entrypoint will restore that baseline into the active launcher configuration, then apply `PZ_JAVA_XMX` when it is set.

This makes the selected value a property of the current container run and ensures an unset variable returns to the game-provided default. A Docker build argument would require rebuilding for each local test value, and editing the persisted Zomboid directory would incorrectly couple a runtime resource choice to game data.

### Limit the accepted value grammar

`PZ_JAVA_XMX` will accept a positive, whole decimal number followed by `m` or `g`, case-insensitively (for example `512m`, `2g`, or `8G`). Values such as `0g`, decimals, whitespace, unitless numbers, and strings containing additional JVM flags will cause a clear non-zero pre-start failure.

The entrypoint will replace only the launcher configuration's `-Xmx` argument, after validating that the expected argument occurs exactly once. This avoids environment-driven shell or JVM option injection. Passing the environment value directly to the launcher was rejected because it would allow unrelated JVM arguments.

### Treat launcher layout changes as a safe startup failure

The update logic will atomically produce the active configuration and verify the expected single `-Xmx` value. If a future Project Zomboid update changes the launcher layout, the entrypoint will stop before launching the server instead of starting with an unknown or partly modified configuration.

Adding `jq` was rejected: the change only needs a tightly constrained replacement and should not introduce another runtime dependency.

## Risks / Trade-offs

- [A heap value is too low for the selected world or mods] → Document that the setting is mainly for local testing and that the JVM heap is not total container memory; operators can omit it to use the supplied default.
- [The upstream launcher JSON changes] → Validate the expected single heap argument and fail before starting Project Zomboid.
- [A container is restarted with a different environment setting] → Restore the immutable baseline before each startup so the active JSON always reflects that startup's setting.

## Migration Plan

1. Build the updated image.
2. For constrained local testing, start the container with `-e PZ_JAVA_XMX=2g`; omit the variable to retain the image default.
3. To roll back, use an image from before this change or remove the environment variable and recreate/start the container with the updated image. No saved-world migration is required.

## Open Questions

None.
