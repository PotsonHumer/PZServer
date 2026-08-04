## Why

Project Zomboid's bundled 64-bit launcher defaults to an 8 GiB Java heap. That can exceed the memory available to Docker Desktop during local testing, even when the server does not need production-scale capacity.

## What Changes

- Add an optional `PZ_JAVA_XMX` runtime environment variable for selecting the Java maximum heap size.
- Validate the value before the game server starts, and reject invalid values rather than passing arbitrary JVM options through the environment.
- Restore the image's bundled launcher configuration at each container start so an override is transient and the default remains available when the variable is unset.
- Document that this controls Java heap only, not Docker's total memory usage.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dedicated-server-container`: Container startup gains a validated, optional Java maximum-heap override.

## Impact

- Affected code: Dockerfile-generated entrypoint and launcher configuration stored in the image.
- Affected documentation: `README.md` local run instructions and memory guidance.
- Affected verification: startup tests for an unset, valid, and invalid `PZ_JAVA_XMX` value.
