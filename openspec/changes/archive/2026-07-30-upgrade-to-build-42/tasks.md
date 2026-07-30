## 1. Build 42 image selection

- [x] 1.1 Update the Dockerfile DepotDownloader command to hard-code Steam's `unstable` branch for App ID `380870` without adding version-selection configuration.
- [x] 1.2 Verify the Dockerfile retains the existing anonymous download, Linux depot selection, checksum verification, and `linux/amd64` runtime behavior.

## 2. Build 42 operating guidance

- [x] 2.1 Update the Chinese README to identify the image as Build 42 Unstable and state that clients must use Steam's Unstable branch.
- [x] 2.2 Retain `data:/home/steam/Zomboid` in the Chinese README's first-run, replacement-container, and managed-platform instructions.
- [x] 2.3 Update the image-update instructions to state that a rebuild retrieves the latest Build 42 Unstable server payload.

## 3. Verification

- [x] 3.1 Inspect the staged Dockerfile and README to confirm no branch-selection build argument, environment variable, or runtime option was introduced.
- [x] 3.2 Build the image with the documented `linux/amd64` command and confirm the installed server reports a Build 42 version.
