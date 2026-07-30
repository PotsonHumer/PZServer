## Why

Project Zomboid 42.20 is now the public stable release, while the image is still
hard-coded to Steam's `unstable` branch for 42.19. The server is intentionally
starting a new world, so it should follow the stable branch and document a
zero-setup persistent data volume that Docker creates automatically.

## What Changes

- Replace the hard-coded `unstable` Steam branch selection with the public
  stable branch used by Project Zomboid 42.20.
- Update the Chinese README to describe the image and player requirements as
  Build 42 Stable rather than Build 42 Unstable.
- Change the primary Docker run guidance to use a named `pz-data` volume so
  Docker creates persistent server storage when it does not already exist.
- Export documented local Buildx builds to the local Docker image store so the
  resulting image tag is immediately usable by `docker run`.
- Explain that the image creates its container-side data directory, while a
  Dockerfile cannot create a host bind-mount directory.
- **BREAKING** Existing Build 42.19 Unstable worlds are not migrated; this
  release targets a fresh 42.20 Stable world.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dedicated-server-container`: The installed dedicated-server payload must
  come from Steam's public stable branch rather than `unstable`.
- `server-data-persistence`: The documented primary local deployment must use
  an automatically created named Docker volume for Project Zomboid data.

## Impact

- `Dockerfile` changes its DepotDownloader branch selection while retaining
  the current architecture-aware build and unprivileged runtime.
- `README.md` changes build export, player-branch, first-run, and persistence
  instructions.
- Operators rebuild the image and start a new 42.20 world using `pz-data`;
  UDP publication and GCP firewall requirements remain unchanged.
