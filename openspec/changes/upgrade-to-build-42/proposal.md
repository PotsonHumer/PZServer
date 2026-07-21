## Why

The image currently downloads the public Project Zomboid Dedicated Server branch, which
is Build 41. The server needs to target Build 42 directly, without exposing a build
argument or runtime configuration for choosing a different Steam branch.

## What Changes

- Change the DepotDownloader invocation to download App ID `380870` from Steam's
  `unstable` branch, which supplies Build 42.
- Remove the implicit Build 41/public-branch behavior from the image build.
- Update the Chinese README build, first-run, and update instructions to identify the
  image as Build 42 Unstable while retaining the existing `data` mount convention.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dedicated-server-container`: The installed server payload must be the Build 42
  `unstable` branch rather than Steam's public branch.

## Impact

- `Dockerfile` will hard-code the DepotDownloader branch selection for App ID `380870`.
- `README.md` will change its version, build, and update guidance without changing the
  documented `data:/home/steam/Zomboid` mount.
