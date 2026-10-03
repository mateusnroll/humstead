# 0002 — Offline stations and creator-first player

## Origin

Approved PRODUCT.md SHA256: 5779d0719039618c7644450624ce02be1c96c8c0ba68dc245c41e5febc23931b. Approved ARCHITECTURE.md SHA256: 5485d021221ef14257fc4d73416312962615871a6d6c25f2e58a9924ea27a345. Stage base 5ef113e7639ce862bfa47cb691e1e58f2d1ffdab, accepted scaffold. Preserve approved PRODUCT.md, ARCHITECTURE.md and earlier contracts unchanged. Frozen requirement projection retains the assigned original IDs and full acceptance text, with explicitly deferred ambience/system/manual proofs.

## Scope and non-goals

Build local music playback, shuffle/repeat, compact native music controls and offline credits. Bundle nine CC0 songs and four CC0 ambience assets with evidence. No streaming, downloads, remote catalog, accounts, analytics, timer, settings persistence or system media commands yet. Multiple ambience/preset controls and playing after window close belong to0003; the current window lifecycle is not claimed as the final behavior. Do not introduce runtime packages.

## Acceptance criteria

- AC-1: A validated bundled catalog provides Mellow, Jazzy and Late Night with three unique music tracks each and rain/café/fireplace/forest assets. Asset metadata contains stable IDs, local resource name, byte length, SHA256, duration/codec, title/creator, original and profile URLs, CC0 1.0 license URL/attribution and modification notices. Every bundled file and retained original/license evidence digest is checked; missing/corrupt media never becomes silently playable. Source and media licenses stay distinct. Provisional derivatives may exist as untracked local working-tree resources for builds, tests and audition. Human listening approval is required before any audio is committed, published, or accepted in this milestone. Running tests does not require a Git commit; keep the audio untracked until approval, then record approval, commit the complete checkpoint and run OCR. Trace: PRD-R-001,002,005,025,026,027.
- AC-2: Each station's shuffle bag visits every available track before reshuffling and excludes the just-played track at a new bag boundary when there is more than one track. End-of-track and Next advance; default playback has no end-of-session stop. Next while paused prepares the next track and stays paused. Selecting a station preserves play/pause intent; initial launch is paused on Mellow at music volume0.65. Trace: PRD-R-001,003,004,013 foundation.
- AC-3: File-backed AVAudioPlayer work is serialized off MainActor, including creation/prepare/play/pause/stop/volume updates and completion handling. UI actions carry generation identity; late completions from a replaced/stopped player cannot change the new station or resume paused audio. Rapid switch/next/pause operations end in the last requested state. Music volume ranges0–1; zero pauses the music player and preserves its position, increasing it resumes only when playback is requested. On load/decode/play failure try each remaining station track at most once, then pause with a visible retry message; no unbounded loop or network fallback. Trace: PRD-R-003,004,013,028.
- AC-4: The standard titled/resizable player initially about380×520pt displays station picker, current track/title, clearly clickable creator, original-source/credits links, Play/Pause, Next and labeled native music-volume slider. Selecting a station updates the displayed prepared track even while paused. Controls have meaningful native accessibility names/values and keyboard focus. Playback errors appear nearby without modal alerts or focus theft. There are no fake ambience, download or timer controls. Trace: PRD-R-018,019 music foundation,031,032 native semantics,033.
- AC-5: Settings offers Credits, listing all13 bundled recordings with readable local attribution/license/source/profile text even offline. Creator and original links open only their declared HTTPS destinations through the native browser; no telemetry or hidden network requests. Command-comma and standard dismissal work with focus returning to the player. The current creator/original links remain reachable directly in the player. Trace: PRD-R-019,025,026,030,031,032.
- AC-6: Cold launch without connectivity needs no account and all three stations can be played, paused, skipped and volume-adjusted from local assets. UI tests verify these outcomes and truthful metadata/state in the isolated sandbox test application; real audio integration tests verify bundled decoder compatibility, advancing completion and stale callback suppression. Automated silent playback checks do not claim human sound-quality approval. The strict app entitlements remain only sandbox/network-client. No user preference/container is reset. Trace: PRD-R-001,002,005 bundled decode,004,013,027,028,030.
- AC-7: Use native SF typography and semantic warm-neutral surfaces with restrained amber accents in both appearances. There is no perpetual animation. Any short native state transition is removed when reduced motion is enabled. All controls and credit text remain available at the minimum window size through scrolling where needed. Local manual keyboard journey and native accessibility inspection supplement UI assertions; physical VoiceOver and final visual/auditory acceptance follow the recorded human gate. Trace: PRD-R-018,019,031,032,033.

## Test mapping

| AC | Primary proof layer | Named test / command | Failure meaning |
| --- | --- | --- | --- |
| AC-1 | Catalog/provenance validation | CatalogTests.bundledAssetsMatchProvenance | A recording or required license record is missing, invalid or mismatched |
| AC-2 | Swift Testing | ShuffleBagTests.coverageAndBoundary | Repetition/order/playback advancement violates station policy |
| AC-3 | Audio integration | AudioControllerTests.orderedIntentsAndFailureBound | Async work resumes stale playback or retries indefinitely |
| AC-4 | XCTest UI | PlayerUITests.stationPlaybackControls | Actual native music controls or state cannot be used |
| AC-5 | XCTest UI | CreditsUITests.offlineNoticesAndLinks | Required creator information or native Settings journey is unavailable |
| AC-6 | Sandboxed integration | PlayerUITests.offlineStationJourney | Fresh local playback relies on network/account or fails in sandbox |
| AC-7 | Native platform review | player-platform-review.md with actual app evidence | Layout, keyboard or native accessibility fails reachable controls |

## PRD traceability

| Requirement | Criteria |
| --- | --- |
| PRD-R-001 | AC-1, AC-2, AC-6 |
| PRD-R-002 | AC-1, AC-6 |
| PRD-R-003 | AC-2, AC-3 |
| PRD-R-004 | AC-2, AC-3, AC-6 |
| PRD-R-005 | AC-1, AC-6; layer playback control in0003 |
| PRD-R-013 | AC-2, AC-3, AC-6; uninterrupted simultaneous ambience in0003 |
| PRD-R-018 | AC-4, AC-7 |
| PRD-R-019 | AC-4, AC-5, AC-7; ambience/preset controls in0003 |
| PRD-R-025 | AC-1, AC-5 |
| PRD-R-026 | AC-1, AC-5 |
| PRD-R-027 | AC-1, AC-6 |
| PRD-R-028 | AC-3, AC-6 |
| PRD-R-030 | AC-5, AC-6; preference persistence in0003 |
| PRD-R-031 | AC-4, AC-5, AC-7 |
| PRD-R-032 | AC-4, AC-5, AC-7 |
| PRD-R-033 | AC-4, AC-7 |

## Implementation changes

- Humstead/Domain/Catalog.swift, Humstead/Domain/ShuffleBag.swift: typed bundled metadata and deterministic shuffle rules. A random source is injected for reproducible order tests; no persisted queue.
- Humstead/Audio/AudioController.swift: a serial DispatchQueue owns the native player/delegate and generation. Publish immutable sequenced state back to MainActor; the model rejects older publications. Narrow injectable player creation supports failure/completion ordering tests, while real AVAudioPlayer integration covers shipped assets.
- Humstead/PlayerModel.swift: MainActor ObservableObject, user intents and presentation; no file/network work in views. Holds selected station, prepared track, playback intent, volume and error. No service locator or generic state framework.
- Humstead/ContentView.swift, Humstead/CreditsView.swift, Humstead/HumsteadApp.swift: compact native player and Settings Credits, accessible controls, shortcuts and system appearance. Only capability-appropriate controls exist.
- Humstead/Resources/catalog.json; Humstead/Resources/Audio/morning-coffee.m4a, a-little-shade.m4a, creature-comforts.m4a, keeping-cool.m4a, chills.m4a, everything-you-ever-dreamed.m4a, foggy-headed.m4a, snow-drift.m4a, 2-hour-delay.m4a, rain.caf, cafe.caf, fireplace.caf, forest.caf: resource metadata and locally prepared development derivatives, initially untracked and provisional. Do not stage or commit these files until human listening approval; the checkpoint includes them only after that approval is recorded. Music AAC-LC192kbps; ambience lossless loop-ready CAF. Human-approved station placement: Mellow first3, Jazzy next3, Late Night last3. Rain uses Joseph SARDIN’s Rain on Puddle; preserve the approved audition PCM exactly when wrapping as CAF. Human approved all13 final recordings; record exact original/derived/audition digests. The prior The Past, Ooame and Rain in the Gutter Loop selections are rejected and excluded from the bundle. No omfgdude recording with unresolved source-loop provenance is selected.
- docs/audio/PROVENANCE.md, docs/audio/manifest.json: original and derived SHA256/size, acquisition date, evidence quotes and canonical source/license/profile links, source filenames/archive members, exact transformations and human approval state. No private local absolute paths or source archives are published.
- HumsteadTests/CatalogTests.swift, HumsteadTests/ShuffleBagTests.swift, HumsteadTests/AudioControllerTests.swift; HumsteadUITests/PlayerUITests.swift, HumsteadUITests/CreditsUITests.swift; update HumsteadUITests/ScaffoldUITests.swift to retain launch/lifecycle coverage against real content instead of development description.
- project.yml and generated Humstead.xcodeproj/project.pbxproj and Humstead.xcodeproj/xcshareddata/xcschemes/Humstead.xcscheme, Humstead.xctestplan: include resources and domain/audio code in test target as needed; keep arm64/macOS13/strict sandbox identities. No production test-only resource substitute.
- README.md, docs/specs/README.md: truthful player launch instructions and immutable lifecycle evidence. Existing operational contracts and numbered prior specs unchanged. CI retains static/build-only jobs; scripts/verify includes all native tests through the existing plan.

- HumsteadTests/ScaffoldTests.swift: retain existing build metadata checks unchanged; the pinned file has no placeholder-content assertions. .gitignore: retain existing exclusions unchanged; approved media is intentionally included in the complete checkpoint, and provisional resources remain untracked until approval. Neither file needs an implementation edit.

## Compatibility, errors and recovery

No schema migration yet; catalog is versioned immutable bundled data. Validate URLs as HTTPS, identifiers unique and referenced paths restricted to known bundle resources; never accept remote file paths. Corrupt catalog stops with an accessible error rather than crashing or pretending playback succeeded. Keep current local track paused when stopped; delegate work cannot outlive ownership. Quit releases/stops the player. Background playback after window close, persisted restoration and system media integration follow0003.

## Verification

Observe mapped tests red on the prior scaffold, then implement and run scripts/verify. Build and inspect the actual Debug/Testing/Release app with unchanged entitlements. Exercise native keyboard and Credits journeys; preserve actual xcresult and platform evidence. Supplement the automated offline journey with a recorded launch/play/next/pause observation across all three stations in the actual signed app under a process-local network-deny sandbox profile. Verify the same profile denies an attempted network connection, and preserve the profile, command, signed entitlement inspection and UI evidence. Do not change machine-wide connectivity, which may interrupt remote control. This supporting proof tests absent connectivity while the ordinary Testing app retains its approved sandbox/network-client entitlements. Full physical audio quality, manual VoiceOver, headphone routing and system media checks are not replaced by mocks. Do not mark human acceptance satisfied without evidence.

## Simplicity dispositions

Fresh independent read-only player_spec_simplicity inspected this draft, projection, approved architecture/product, actual app/test targets and verification scripts. No actionable simplicity, feasibility or traceability blockers.

## Open questions

None. The existing architecture timing remains in force: human listening approval is required before any audio commit, milestone acceptance or audio publication. Provisional media stays untracked locally during development and tests; after human approval, record that approval and commit the complete milestone before OCR. A pending optional request to defer that approval does not authorize deferral or change this contract.
