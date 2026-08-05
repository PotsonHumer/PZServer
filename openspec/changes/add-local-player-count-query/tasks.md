## 1. Bundle the local A2S query command

- [x] 1.1 Add the minimal distribution runtime dependency and a bundled executable `pz-query` to the final image.
- [x] 1.2 Implement A2S information requests, including challenge-response retry, and parse current and maximum player counts from validated replies.
- [x] 1.3 Resolve the loopback target port from the selected PZ server INI, with a safe `16261` default and validation.
- [x] 1.4 Define exact success output and nonzero error behavior without accepting a remote target or requiring RCON configuration.

## 2. Verify query behavior

- [x] 2.1 Add automated protocol tests for direct and challenge A2S responses, a zero-player response, a customized port, and malformed or timeout failures.
- [x] 2.2 Build the image and verify `docker exec pz-server pz-query` returns explicit counts from an isolated running PZ server without a published management port.

## 3. Document operation

- [x] 3.1 Document `pz-query`, its success output, and the difference between an empty server (`players=0`) and an unavailable query (nonzero exit).
