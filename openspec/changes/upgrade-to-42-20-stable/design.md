## Context

The current image downloads App ID `380870` from Steam's hard-coded `unstable`
branch, which supplied Build 42.19. Project Zomboid 42.20 is now the public
stable release. The prior 42.19 world has deliberately been removed, so this
change does not need a save migration path.

The image already prepares `/home/steam/Zomboid` with ownership for the
unprivileged `steam` account and the entrypoint creates it at startup. The
current local README instead asks operators to create a host `./data`
directory before using a bind mount. A Dockerfile cannot create a directory on
the deployment host; a named volume is the portable way for Docker to create
persistent storage automatically.

## Goals / Non-Goals

**Goals:**

- Build the Project Zomboid dedicated server from Steam's current public
  stable branch, which is 42.20 at the time of this change.
- Make the primary local deployment use an automatically created, persistent
  named Docker volume.
- Keep the existing unprivileged runtime, password initialization, data path,
  architecture handling, and UDP port guidance.

**Non-Goals:**

- Migrate, preserve, or make compatible a 42.19 world.
- Pin a Steam manifest or promise that later rebuilds remain exactly 42.20.
- Create a host `./data` directory from the Dockerfile.
- Change GCP firewall configuration, server ports, or managed-platform volume
  instructions.

## Decisions

### Download the default Steam branch

Remove DepotDownloader's `-branch unstable` option. DepotDownloader's default
branch is Steam's public branch, which is the desired stable release channel.
This avoids retaining the unstable channel after 42.20's stable promotion and
continues the project's existing model of retrieving the current release when
the immutable image is rebuilt.

Specifying a build argument was rejected because version selection is outside
the requested scope. Pinning a manifest was rejected because it would block
normal stable hotfix updates and require managing multiple Steam depot
manifests.

### Use `pz-data` as the documented primary local mount

The primary `docker run` examples will mount
`pz-data:/home/steam/Zomboid`. Docker creates this named volume if absent and
retains it after container replacement. The image's existing data-directory
creation remains responsible for the path inside the container.

A `./data` bind mount remains technically supported by Docker and is useful
when operators deliberately need host-visible files, but it is not the primary
example because directory creation and ownership are host concerns. An
anonymous volume was rejected because it is difficult to identify and reuse
when recreating a container.

### Load the documented local image tag

The local Docker build commands will include `--load`. This exports the
finished image from a `docker-container` Buildx driver into the local Docker
image store, so the documented `pz-server:local` tag can immediately be used
by `docker run`.

Leaving out `--load` was rejected because Buildx otherwise retains the result
only in its cache on this driver, despite accepting the image tag argument.
Registry publishing is outside this local-deployment workflow.

## Risks / Trade-offs

- [A player remains on the `42.19` beta or another old branch] → The README
  explicitly requires the normal public/stable game branch.
- [An operator expects files in `./data`] → The README explains that `pz-data`
  is Docker-managed and provides a clear command to inspect it if needed.
- [Future stable patches change the server version] → The README states that
  rebuilding follows the current Steam public stable payload rather than
  pinning exactly 42.20.
- [Existing 42.19 data is mounted accidentally] → The README marks this as a
  fresh-world upgrade and directs operators to use the new `pz-data` volume.

## Migration Plan

1. Rebuild the image after removing the unstable branch selector.
2. Start a new container with the named `pz-data` volume and the existing UDP
   publications.
3. Initialise a fresh 42.20 Stable world and have players leave Steam beta
   branches before joining.
4. Roll back by stopping the 42.20 container and restarting the prior image
   with a separately retained 42.19 volume; no in-place world rollback or
   migration is provided.

## Open Questions

None.
