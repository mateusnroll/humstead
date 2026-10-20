# Download operations

Humstead uses local audio. Optional collection downloads use a fixed release-configured HTTPS origin backed by R2 Standard. This document specifies the release gates and shutdown procedure; it does not claim that any bucket, domain or Cloudflare rule has been deployed.

## Local validation

Run `scripts/test-download-shutdown` from the repository root. The fixture exercises a separate simulated edge block against known cached and uncached audio URLs, confirms zero origin reads for denied requests and leaves catalog/control readable. `scripts/verify` also runs the sandboxed download, recovery, offline restart, update and removal journeys. Local fixtures do not prove Cloudflare propagation or billing behavior.

## Before enabling production downloads

- Set one production custom HTTPS domain for the R2 Standard bucket. Disable r2.dev and every other public bucket alias. Do not distribute public S3 or administrative credentials.
- Publish only audited CC0 or standard CC BY media with retained source/license evidence and human audio approval. Each object is immutable under `/audio/<sha256>.<m4a|caf>`; verify its digest and byte length against the catalog. Preserve original creator/source/profile links, attribution, required notices and modifications.
- Give immutable audio long cache lifetimes and `/catalog/v1.json` short caching. Serve `/control/v1.json` with `Cache-Control: no-store`, an explicit CDN cache-bypass rule and stale serving disabled. Test the actual response headers and regional behavior.
- Control schema1 is a bounded JSON object with `downloadsEnabled` and a nonnegative `revision`. Increase revision for each operator change. Clients reject an unavailable or malformed control response and cannot begin objects using a check60seconds old.
- Preconfigure an independently operable Cloudflare WAF custom Block rule matching the production hostname and `/audio/` path. Leave `/catalog/` and `/control/` reachable. Confirm the selected account/plan supports the rule before enabling public downloads.
- Perform an authorized real edge shutdown drill. Retain activation time, edge propagation observations, responses from known cached and uncached objects, and evidence that denied requests do not read the R2 origin. Verify disabling custom-domain access as a fallback. If these controls cannot be verified, keep production downloads disabled.
- Inject the fixed HTTPS origin into the release build. Unconfigured builds explain that online collections are unavailable. Testing-only loopback configuration must not be enabled in a production build.

No cloud provisioning, rule change or public upload is part of local v1 construction. Those actions need their own authorization.

## Emergency shutdown

1. Publish `downloadsEnabled: false` with an increased revision at `/control/v1.json`. Confirm the uncached response reflects the change.
2. Activate the preconfigured edge Block rule for all `/audio/` requests. Do not rely on the client flag alone: modified open-source clients can ignore it.
3. Request known cached and uncached audio URLs and confirm denial. Check available edge/origin telemetry to establish that denied requests do not fetch R2 objects. Record when each observation was made; do not invent a propagation SLA.
4. Verify catalog and control remain readable, then confirm an official client refuses new downloads while already installed and bundled audio continue working.
5. If the edge block is unavailable or ineffective, disable public custom-domain access and verify asset denial. Control/catalog may also become unreachable; official clients fail closed for downloads in that case.
6. Investigate the cost or operational incident before restoring service. Record the incident and the measured enforcement result.

During an active transfer, official clients begin control refresh by50seconds after the last success, use a5second timeout and independently expire admission at60seconds. Disabled, failed, malformed or expired control cancels owned transfers and removes partial staging. The local acceptance target is cancellation within65seconds after a disabled response is globally available while the process is running. OS scheduling and earlier CDN propagation are not guaranteed. No control polling occurs while only listening.

An edge block cannot recall completed requests or bytes already transmitted. This mechanism is an emergency control, not an automatic dollar cap. Monitor actual R2 storage/operation usage; local retention and bounded cooperative retries reduce repeat traffic but cannot prevent all public-origin abuse.

## Restore service

After fixing the cause and verifying the host/path policy, publish a fresh enabled control revision and verify its uncached response. Remove the edge block only when explicitly authorized to resume public downloads. Verify one small known object through the intended domain and recheck that alternate aliases remain disabled. Official clients require a user-requested Retry; they never silently restart cancelled transfers.

## Local storage and removal

Application Support/Humstead contains the installed library manifest, cached catalog, content-addressed Audio files and operation-owned Staging files. A verified complete manifest is committed atomically; an interrupted update leaves the old installed version usable. Shared or actively leased audio is retained until unreferenced and released. Settings removal explains playback effects before confirmation, switches affected music to bundled audio and disables only removed ambience. Bundled audio is never removed.
