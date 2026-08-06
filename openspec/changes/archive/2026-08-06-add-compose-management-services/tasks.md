## 1. Compose one-off services

- [x] 1.1 Add a profile-gated `pz-query` service that runs the existing `pz-query` executable, shares the `pz-server` network namespace, and mounts `pz-data` read-only.
- [x] 1.2 Add a profile-gated `pz-rcon` service that runs the existing `pz-rcon` executable with the same namespace and read-only configuration access, without publishing ports, restarting, or starting the main server.

## 2. Documentation

- [x] 2.1 Replace routine `docker exec` management examples with `docker compose run pz-query` and `docker compose run pz-rcon <command>`, including the requirement that `pz-server` is already running.
- [x] 2.2 Document that the one-off containers remain exited for inspection and how to inspect or remove the accumulated stopped helper containers.

## 3. Verification

- [x] 3.1 Verify the rendered Compose configuration has profile-gated helper services, `container:pz-server` network sharing, read-only `pz-data`, no helper ports, and no dependency that starts `pz-server`.
- [x] 3.2 With a running PZ server, verify `docker compose run pz-query` reports the player count and `docker compose run pz-rcon save` sends the command; verify each helper exits and is retained afterward.
- [x] 3.3 Verify either helper exits nonzero while `pz-server` is stopped or absent and does not start it.
