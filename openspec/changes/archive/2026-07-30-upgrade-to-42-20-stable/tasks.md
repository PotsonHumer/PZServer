## 1. Stable server payload

- [x] 1.1 Remove the DepotDownloader `unstable` branch selector so the Dockerfile downloads Steam's default public branch without adding version-selection configuration.
- [x] 1.2 Verify the Dockerfile retains the existing architecture-aware DepotDownloader download, checksum verification, and `linux/amd64` runtime behavior.
- [x] 1.3 Add `--load` to documented local Docker build commands so a `docker-container` Buildx driver exports the tagged image for `docker run`.

## 2. Automatic persistent data storage

- [x] 2.1 Verify the Dockerfile-generated entrypoint creates `/home/steam/Zomboid` for the unprivileged `steam` account when the directory is absent; make only the changes necessary to satisfy that behavior.
- [x] 2.2 Update the Chinese README's primary local run and replacement-container examples to mount `pz-data:/home/steam/Zomboid` without a preceding host-directory creation command.
- [x] 2.3 Document that Docker automatically creates the named `pz-data` volume, distinguish it from a host `./data` bind mount, and retain the managed-platform mount-path guidance.

## 3. Build 42 Stable operating guidance

- [x] 3.1 Update the Chinese README to identify the image as Build 42 Stable, require players to use Steam's normal public branch, and describe rebuilds as following the current stable payload.
- [x] 3.2 State that the upgrade starts a fresh 42.20 world and does not migrate Build 42.19 Unstable data.

## 4. Verification

- [x] 4.1 Inspect Dockerfile and README changes to confirm no `unstable` branch selector or branch-selection interface remains and that the named-volume command publishes UDP ports `16261` and `16262`.
- [x] 4.2 Build the documented `linux/amd64` image and confirm the installed dedicated server reports a public-stable Build 42 version.
