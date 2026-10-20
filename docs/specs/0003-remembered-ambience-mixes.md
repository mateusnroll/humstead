# 0003 — Remembered ambience mixes and Mac listening controls

## Origin

Approved PRODUCT.md SHA256 5779d0719039618c7644450624ce02be1c96c8c0ba68dc245c41e5febc23931b and ARCHITECTURE.md SHA256 5485d021221ef14257fc4d73416312962615871a6d6c25f2e58a9924ea27a345 remain immutable. Stage base7933b2dc48eebdd2221d5d956aebb179be8be849 is accepted0002 after validated OCR. Existing docs/specs/0001-native-scaffold.md and docs/specs/0002-offline-station-player.md remain unchanged; new lifecycle metadata lives in docs/specs/README.md. This contract supersedes0002's explicitly temporary no-persistence/window-close behavior for this milestone only.

## Scope and non-goals

Add bundled ambience, station/preset memory, sandbox settings, menu-bar/background playback, optional timer and native media/lifecycle adapters. Preserve approved13 audio files, current licensing, shuffle and serial audio ownership. No downloads, remote catalog, analytics, account, new runtime dependency, cloud provision or public release. Use macOS13-compatible Swift6 APIs. Physical-device and final human visual/mix acceptance remain explicitly pending; this milestone cannot assert headphone speaker-leak prevention based on callbacks alone.

## Acceptance criteria

- AC-1: Mix playback uses the existing dedicated serial audio queue: one music player plus enabled ambience players at independent normalized levels0–1, looping authored CAF indefinitely. Enable/disable or adjust one layer without restarting other layers; Next changes only music. Global play/pause affects the whole mix while retaining configured levels and positions. Music volume0 pauses/freezes music, allows ambience-only playback, and does not consume the music shuffle bag; raising music level resumes only with playing intent. Current generation/ordered snapshots prevent stale starts. Missing/failed ambience is reported by layer without a retry loop; other functioning layers continue. Bound enabled layers to16 with an accessible explanation; bundled UI currently exposes four. Trace: PRD-R-006,007,012.
- AC-2: Every station has Music Only, Rainy Window, Café, Fireside and Forest. First-use original mixes: Music Only all off; rain0.35, café0.25, fireplace0.30, forest0.30 in corresponding preset only; other disabled sliders0.25. Selecting a station restores its selected preset and selecting a preset restores that station/preset's independent edits. Reset ambience restores exactly that preset's original enabled flags/levels, leaving music volume/station/timer unchanged. Only bundled sound IDs appear in original presets. Trace: PRD-R-008,009,010,041.
- AC-3: SettingsStore serializes schemaVersion1 settings.json in app-owned Application Support/Humstead, with currentStationID, musicVolume, stationSettings(selectedPresetID and presetMixes), and reserved analyticsChoice undecided. No identifiers for installations, network access or account. A250ms debounced atomic sibling replacement persists the latest validated snapshot; stale writes cannot overwrite later ones. Relaunch waits for load, restores station/mix/volume paused, and neither timer, track position nor shuffle order persists. Missing file uses defaults. Invalid JSON/values preserve original as a uniquely named recovery file before replacing; failed preservation disables writes for that run and shows a nonblocking warning. Newer schema remains byte-identical/read-only with disclosed defaults. Unknown station/preset/sound IDs recover to known bundled defaults; numeric values must be finite and within0–1. Failed writes retain last durable file and show a warning. Quit flush is bounded to one second. Trace: PRD-R-009,011,029.
- AC-4: Sleep timer is off initially, offers15/30/60 real elapsed minutes, replaces/cancels an existing timer and keeps counting while paused. Use a monotonic ContinuousClock deadline including system sleep. At expiry fade master gain over five seconds then pause everything, preserving saved per-layer/music levels. Already paused expires directly; wake pauses immediately and expires a past deadline without restart. Cancellation/replacement invalidates old tick/fade callbacks and restores master gain, never stale-pausing a later session. During an active expiry fade, a new explicit Play cancels that expired timer/fade and starts at configured gain; volume edits retain their saved value under master fade. Quit clears timer. UI countdown updates no faster than once per second while displayed; fade work stays off MainActor. Trace: PRD-R-020,012.
- AC-5: SystemMediaBridge registers standard play/pause/toggle/next on MPRemoteCommandCenter and publishes truthful MPNowPlayingInfoCenter title/artist/station and macOS playbackState from actual audio snapshots. Play and pause are idempotent. Disable seek/previous; Next enabled only when music is audible (music volume>0 and a prepared song), with ambience-only metadata identifying station/preset rather than a silent song. Remote callbacks hop to MainActor actions; retain/remove command targets explicitly, do not intercept global keys or control another app. Native bridge initialization and metadata can be inspected in sandbox; real OS arbitration/headphone commands remain final hardware proofs. Trace: PRD-R-014,012.
- AC-6: Closing the main window preserves playback. A native MenuBarExtra exposes play/pause, all stations and Show Humstead, which opens/activates the existing single player window. Quit stops all players and detaches native callbacks, flushes settings within the bounded termination deadline and leaves no process/audio running. Menu and player state agree. Trace: PRD-R-016,017,012.
- AC-7: AppKit sleep notification pauses the entire mix; wake never autoplays. Core Audio observer monitors default output, current device alive/transport/data-source changes and sends conservative pause events on output-route replacement or active device disappearance. Marshal events into the model's ordered intents and ignore callbacks after teardown. No global audio routing/settings modifications or accessibility-control entitlement. Simulated events prove pause/no-autoresume and stale-callback suppression. Physical wired/Bluetooth leakage prevention remains a final gate; if observer timing cannot prevent reroute leakage, architecture must be revised before final acceptance, not silently waived. Trace: PRD-R-015,012.
- AC-8: Compact scrollable native player adds preset picker, Reset ambience, labeled toggles/sliders for four sounds and optional timer with Cancel. Controls expose meaningful native names, values/states and visible keyboard focus; Space never hijacks focused native controls. Accessible inline warnings for layer/persistence errors do not steal focus or stop functioning playback. Menu and Settings/Credits remain keyboard reachable. Use semantic light/dark colors and no decorative/perpetual animation; reduced motion loses no information. Native app tests use dedicated Testing identity/container, exercising fresh defaults, edits, station/preset return, reset, restart-paused, ambience-only, timer presentation and menu-bar reopen with strict sandbox/network-client entitlements. Test fixtures may use only app/test-owned containers and restore owned synthetic files; never reset ordinary user settings. Trace: PRD-R-029,031,032,033.

## Test mapping

| AC | Primary proof layer | Named proof | Failure meaning |
| --- | --- | --- | --- |
| AC-1 | Audio integration | MixAudioTests.layerLifecycleAndOrdering | Looping/mute/independent layers, shared pause or ordered ownership fails |
| AC-2 | Domain tests | MixSettingsTests.stationPresetRecallAndReset | Station/preset edits or original mix definitions are lost or altered |
| AC-3 | Real filesystem integration | SettingsStoreTests.atomicRecoveryAndLatestWrite | Saved settings corrupt, unsafe recovery, overwrite ordering or paused restore fails |
| AC-4 | Controlled-clock integration | SleepTimerTests.expiryPauseCancelAndReplacement | Timing/fade/pause/cancel or gain preservation violates policy |
| AC-5 | Native integration | SystemMediaTests.metadataAndCommandLifecycle | Native command mapping, metadata/state or cleanup is wrong |
| AC-6 | XCTest UI | MixUITests.backgroundReopenAndQuit | Closed-window controls/reopening or quit fails in actual sandboxed app |
| AC-7 | Lifecycle integration | LifecycleTests.routeAndSleepPause | Route/sleep event fails to pause or wrongly resumes stale playback |
| AC-8 | Native UI/platform review | MixUITests.rememberedMixJourney plus mix-platform-review.md | Real controls, keyboard/native AX semantics or persisted journey is unusable |

## PRD traceability

| Requirement | Criteria |
| --- | --- |
| PRD-R-006 | AC-1 |
| PRD-R-007 | AC-1, AC-8 |
| PRD-R-008 | AC-2 |
| PRD-R-009 | AC-2, AC-3 |
| PRD-R-010 | AC-2 |
| PRD-R-011 | AC-3 |
| PRD-R-012 | AC-1, AC-4, AC-5, AC-6, AC-7 |
| PRD-R-014 | AC-5 |
| PRD-R-015 | AC-7 |
| PRD-R-016 | AC-6 |
| PRD-R-017 | AC-6 |
| PRD-R-020 | AC-4 |
| PRD-R-029 | AC-3, AC-8 |
| PRD-R-031 | AC-8 |
| PRD-R-032 | AC-8 |
| PRD-R-033 | AC-8 |
| PRD-R-041 | AC-2 |

## Implementation changes

- Humstead/Domain/MixSettings.swift: Codable value types, five fixed presets and defaults/validation/reset. Reuse IDs from Humstead/Domain/Catalog.swift without changing its catalog contract; no generic state framework or preset editor.
- Humstead/Persistence/SettingsStore.swift: one serial file owner, injectable directory for tests, debounced last-snapshot save, atomic replacement, recoverable invalid data and read-only unknown schema, bounded flush. No UserDefaults shadow copy.
- Humstead/Audio/AudioController.swift: extend existing serial owner/AudioPlaying with ambience loop count, common device-time scheduled starts where supported and master gain. Maintain independent layers across song Next; typed commands carry request/generation identity; emit layer status/errors with music state. Retain injectable real-player factory; no AVAudioEngine/DSP boundary.
- Humstead/Domain/SleepTimer.swift: small monotonic deadline/state owner with injected clock for tests; model schedules bounded UI updates and sends fade intent to serial audio owner. Cancel/replace tokens protect against stale expiry.
- Humstead/System/SystemMediaBridge.swift and Humstead/System/AudioRouteObserver.swift: narrowly owned MediaPlayer/CoreAudio registrations and teardown, Sendable events marshaled to model. Native API calls in appropriate executor; no remote command simulation claimed as physical hardware proof.
- Humstead/PlayerModel.swift: own settings/mix/timer state, ordered playback intents and adapters. Apply loaded settings before first preparation; persist only user configuration, not transient playback snapshots. Add explicit setPlaying(bool), leaving toggle as a UI convenience. Native publication never writes redundant settings.
- Humstead/ContentView.swift, Humstead/MenuBarView.swift and Humstead/HumsteadApp.swift: real controls, focus tracking including new controls, openWindow/menu scene, standard app termination and sleep/wake hooks. Keep CreditsView compatible; no downloads/privacy placeholders before their milestones. Settings persistence warnings appear in player. Humstead/CreditsView.swift may adapt model access only, preserving all existing notices.
- HumsteadTests/MixSettingsTests.swift, HumsteadTests/SettingsStoreTests.swift, HumsteadTests/MixAudioTests.swift, HumsteadTests/SleepTimerTests.swift, HumsteadTests/SystemMediaTests.swift, HumsteadTests/LifecycleTests.swift; HumsteadUITests/MixUITests.swift. Adapt existing HumsteadTests/AudioControllerTests.swift and HumsteadUITests/PlayerUITests.swift, HumsteadUITests/ScaffoldUITests.swift and HumsteadUITests/CreditsUITests.swift for persisted state isolation and expanded API, preserving all prior meaningful assertions.
- project.yml and generated Humstead.xcodeproj/project.pbxproj, Humstead.xcodeproj/xcshareddata/xcschemes/Humstead.xcscheme: include new domain/persistence/system code in test targets as required. Humstead.xctestplan and scripts/verify retain all native suites. HumsteadTests/ScaffoldTests.swift metadata assertions stay unchanged. .gitignore remains unchanged. README.md and docs/specs/README.md update capability/lifecycle truthfully.

## Compatibility and migration

Schema v1 is first durable preferences; existing installations have no preferences to migrate. App-created files only, no container reset or unrelated file modifications. Newer versions are read-only; malformed originals preserved before recovery. Validate against known bundled station/preset/assets and bound enabled layers before audio commands. Inconsistent original mix inputs fail tests rather than fallback to a remote source. Teardown invalidates every adapter/timer callback before releasing model; actual process exit is the final audio stop guarantee. The app retains sandbox/network-client-only entitlements in Debug/Testing/Release; any additional permission need requires architecture review.

## Verification

Show intended missing behavior red before implementing. Run scripts/verify on this Mac; record actual OS/toolchain and macOS13 compile target, not older-OS runtime claims. Use real AVAudioPlayer layered decode/play/pause/Next tests with authored resources, plus controlled-clock/fake-boundary tests for long deadlines and races. Native smoke tests create MPRemoteCommandCenter targets and update/clear Now Playing metadata without synthesizing hardware buttons or claiming ownership arbitration. UI tests use a dedicated synthetic test settings directory beneath the Testing app container; integration filesystem fixtures use test-owned temporary paths. Run manual keyboard/native AX and compact layout proofs for all new controls. Keep actual preset listening, VoiceOver, headphone speaker-leak prevention, media ownership and hardware sleep/wake pending final integrated acceptance. No production telemetry or remote provider calls in tests.

## Simplicity dispositions

Fresh independent read-only review by mix_spec_simplicity found no actionable simplicity findings. Existing serial ownership and native capabilities are reused; required lifecycle and recovery boundaries are retained.

## Open questions

None. Five-second expiry fade and original preset levels retain approved architecture values. Final mix/hardware acceptance stays explicitly pending.
