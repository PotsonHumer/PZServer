## Context

The Dockerfile obtains the Project Zomboid Dedicated Server payload during its build
stage with DepotDownloader and App ID `380870`. Without a branch selector,
DepotDownloader resolves Steam's public branch, which remains Build 41. The requested
deployment target is Build 42, currently distributed through the public `unstable`
branch. The existing documented persistent mount uses `data` on the host and remains
the desired storage location for this deployment.

## Goals / Non-Goals

**Goals:**

- Build an image containing the current Build 42 `unstable` dedicated-server payload.
- Keep the branch choice internal to the Dockerfile, with no build argument,
  environment variable, or runtime setting for selecting a version.
- Keep the Chinese operating instructions on the existing `data` mount convention.

**Non-Goals:**

- Pinning an individual Build 42 patch or Steam manifest.
- Providing a Build 41 image, world conversion, or automatic data migration.
- Changing server networking, the runtime architecture, or administrator-password
  initialization.

## Decisions

### Hard-code the `unstable` branch in the build-stage downloader

The DepotDownloader invocation will pass `-branch unstable` alongside App ID `380870`
and the existing Linux platform selection. No `ARG`, `ENV`, or entrypoint option will
represent the branch.

This directly expresses the requested Build 42 target while retaining the existing
anonymous download, checksum verification, architecture-aware downloader selection,
and immutable runtime image.

An optional `PZ_BRANCH` build argument was considered, but rejected because it exposes
Build 41 selection and adds an interface the operator explicitly does not need.
Pinning a manifest was also rejected: the server is composed from several platform
depots, and a fixed manifest would prevent normal Build 42 security and compatibility
updates.

### Describe the image as Build 42 Unstable

Build and update guidance will state that every rebuild follows the latest available
Build 42 `unstable` patch. The existing `data:/home/steam/Zomboid` mount remains the
documented first-run and replacement-container path.

## Risks / Trade-offs

- [Players on Build 41 cannot join the Build 42 server] → State that all clients must
  select Steam's `Unstable` branch.
- [Steam could rename or remove the `unstable` branch] → The image build fails rather
  than silently downloading the public Build 41 branch, preserving a clear failure
  signal.

## Deployment Plan

1. Build the updated image.
2. Start it with the existing documented mount,
   `./data:/home/steam/Zomboid`.
3. Initialize the Build 42 server, then have every player select the Steam
   `Unstable` branch before connecting.

## Open Questions

None. The requested branch is explicitly `unstable`, and the host data directory
remains `data`; selecting a future stable Build 42 release is outside this change.
