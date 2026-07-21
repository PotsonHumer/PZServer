## 1. Single-file container startup

- [x] 1.1 Replace the copied entrypoint script with a Dockerfile-defined entrypoint that prepares `PZ_DATA_DIR`, preserves runtime arguments, and `exec`s the installed server startup script.
- [x] 1.2 Add conditional `PZ_ADMIN_PASSWORD` handling that supplies a non-empty value through prompt-aware private standard input without logging, command-line exposure, console-command exposure, or image embedding.
- [x] 1.3 Remove the obsolete `docker/pz-entrypoint.sh` file and ensure no Dockerfile instruction references it.

## 2. Managed-platform documentation

- [x] 2.1 Add a Zeabur deployment section explaining Dockerfile detection, the secret `PZ_ADMIN_PASSWORD` environment variable, and why the Zeabur Start Command must remain unset.
- [x] 2.2 Document mounting a Zeabur persistent volume only at `/home/steam/Zomboid`, including the persistence and replacement behaviour.
- [x] 2.3 Document UDP forwarding to container ports `16261` and `16262`, the matching `SERVERNAME.ini` settings, and the player connection information to retain after deployment.

## 3. Verification

- [x] 3.1 Build the `linux/amd64` image and inspect its entrypoint, runtime user, volume metadata, and UDP port metadata.
- [x] 3.2 Smoke-test startup with an empty disposable data mount both with and without `PZ_ADMIN_PASSWORD`; confirm the password is not emitted in server logs or command-line arguments and the data directory is created.
- [ ] 3.3 Deploy the image to Zeabur with its volume and two UDP forwarders, then verify a client can connect and settings and world data survive a redeploy.
