## 1. Launcher configuration

- [x] 1.1 Preserve an immutable copy of the installed `ProjectZomboid64.json` in the image for entrypoint restoration.
- [x] 1.2 Extend the Dockerfile-generated entrypoint to restore the baseline launcher configuration on every container start.
- [x] 1.3 Validate `PZ_JAVA_XMX` as a positive whole-number `m`/`g` value and fail before server startup for invalid input.
- [x] 1.4 Replace exactly one launcher `-Xmx` argument when a valid override is configured, without writing under the persistent Zomboid data directory.

## 2. Verification

- [x] 2.1 Extend the entrypoint test coverage for an unset value, a valid `2g` override, and an invalid value that prevents the server command from running.
- [x] 2.2 Build the image and verify the launcher configuration is restored and the selected heap value is applied for a local test invocation.

## 3. Documentation

- [x] 3.1 Document `PZ_JAVA_XMX` in the local run instructions, including an example and the distinction between Java heap and Docker's total memory use.
