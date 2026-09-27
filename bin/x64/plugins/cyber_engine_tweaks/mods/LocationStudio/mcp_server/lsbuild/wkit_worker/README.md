# cp77wb WolvenKit worker

.NET 10 sidecar used by cp77wb v1.0. It references WolvenKit 9.0.1 packages and discovers the RED JSON/CR2W services at runtime. `selftest --json` is authoritative: cp77wb only enables this backend when default RED instance serialization and a real CR2W round-trip both succeed.

Build:

```sh
./build.sh
./publish/cp77wb-wkit-worker selftest --json
```

Then either place the worker on `PATH`, set `CP77WB_WKIT_WORKER=/absolute/path/cp77wb-wkit-worker`, or pass `--worker` to cp77wb.

## Diagnostics (v1.0.1)

`cp77wb-wkit-worker inspect --json` reports the discovered WolvenKit serializer/writer reflection surface and a stable `apiProfile` fingerprint. cp77wb exposes this through `worker-inspect` and includes it in `worker-doctor` support bundles.
