# Humstead

A free native macOS home for lofi music and ambience. Humstead is under development. The local station-player milestone provides Mellow, Jazzy and Late Night, shuffled continuous playback, music volume and offline creator credits. The current mix milestone adds four simultaneous ambience layers, five remembered presets per station, optional sleep timer, menu-bar playback and native media/lifecycle adapters. Optional downloads add verified local collections, cancellable updates, offline attribution and emergency shutdown. Settings → Privacy adds optional weekly usage summaries; production reporting is disabled in the default build.

## Development

Requires an Apple Silicon Mac, macOS13 or later, full Xcode26 or later (license accepted), Git, Python3, curl, unzip and shasum. Xcode supplies Swift and swift-format. Local verification currently uses macOS26.6.2 and Xcode27; older supported macOS versions have not been runtime tested. Node and global XcodeGen installation are not required.

From the repository root:

```sh
scripts/setup
scripts/dev
scripts/check
scripts/verify
scripts/build
```

Setup downloads checksum-pinned XcodeGen2.46.0 into .tools and generates Humstead.xcodeproj. Once cached, setup works offline and revalidates its archive. Edit project.yml, rerun setup and commit the generated project. Check rejects generated-project or Swift formatting drift. Use `xcrun swift-format format --in-place --recursive Humstead HumsteadTests HumsteadUITests` with the selected Xcode to format Swift.

Scripts select /Applications/Xcode.app when DEVELOPER_DIR is unset; set DEVELOPER_DIR explicitly for another full Xcode installation. They never change global xcode-select. DerivedData, module caches and results live in .build; tooling lives in .tools. The Release app is .build/DerivedData/Build/Products/Release/Humstead.app. Local builds are ad-hoc signed and are not notarized distribution artifacts.

Full verification requires an unlocked logged-in desktop with Xcode UI testing permissions. It runs Swift Testing and XCTest UI in the Testing configuration; the app uses a separate com.mateusnroll.humstead.testing container. No user container is reset. Failure or unavailable GUI is not a successful skip. scripts/build-for-testing compiles test bundles without executing them; scripts/inspect-app Release checks the delivered sandbox and architecture. scripts/test-harness exercises setup and verification failures using disposable project-local fixtures. CI runs static-contracts and macos-build only; runtime tests run locally.

For native keyboard tests, temporarily enable System Settings → Keyboard → Keyboard navigation, then restore your setting afterward. Run the standard UI suite at the player’s default 380×520 content size; minimum-window accessibility is a separate acceptance check.

Full verification also prepares an isolated2,000-asset/200-collection library outside the XCTest runner sandbox, reusing approved bundled audio. For a focused BoundedLibraryUITests run, first use scripts/verify --prepare-bounded-library. This creates a fresh Testing-only state, records its name in .build/bounded-library-state.json, and removes only the previous fixture created by that command. It does not change ordinary app preferences or audio.


## Player walkthrough

Launch with scripts/dev, choose a station and press Play. Next advances without starting paused playback. Music volume zero pauses the track at its current position; raising it resumes only if playback is requested. Space toggles playback when the player background has focus; focused controls retain their native key handling. Playback → Play/Pause (Command-P) and Next track (Command-Right) expose keyboard commands. Command-comma opens Settings; the player’s Credits link selects Credits directly. Relaunch restores the saved station, preset and volumes paused. Choose an ambience preset, toggle layers and adjust their volumes; Reset ambience restores that preset’s original mix. Closing the window keeps playback available from the Humstead menu-bar item. The optional15/30/60-minute sleep timer fades out over five seconds; cancel it to continue indefinitely. System sleep or an observed output-route change pauses playback; wake/reconnect never autoplays.

All bundled recordings have listening approval; final preset-level tuning and physical headphone/Now Playing/VoiceOver acceptance are still pending. The current build is not approved for distribution. The app is intentionally compact and uses standard macOS focus, menus, links and sliders. It has no decorative animation.

## Optional downloads

Settings → Downloads shows collection versions and sizes. Confirm the frozen version and missing bytes before download; Cancel leaves installed audio intact. Removing a collection switches its active music to bundled music in the same station and disables removed ambience while remembering its saved levels. Original presets remain bundled. Files and artist notices work offline after installation.

Development builds omit a production origin and issue no public download requests. A release builder may supply the fixed HTTPS origin through the HumsteadDownloadOrigin Info.plist key; remote catalogs cannot change endpoints. No cloud provisioning is included. The [download operations runbook](docs/DOWNLOAD-OPERATIONS.md) covers the separate production edge setup and shutdown drill.

Full verification launches the loopback fixture outside the app via scripts/with-download-fixture, using port38476 only during tests; an occupied port fails instead of adopting another server. The strict Testing app accepts --test-download-origin http://127.0.0.1:38476 and isolated --test-settings names. Release ignores test arguments. Tests reuse approved bundled recordings without changing attribution. scripts/test-download-shutdown independently verifies cached/uncached edge denial and zero denied origin reads in the local fixture; it does not claim Cloudflare enforcement. To run focused download UI tests, wrap the usual xcodebuild test command with scripts/with-download-fixture.

## Privacy

Listening needs no account. Settings → Privacy explains the optional weekly summary: five broad feature flags, a bucketed download-failure count and the release major/minor version. Each attempt uses a new random ID that is never saved. Humstead sends no track data, listening history, persistent identity or crash report. Disabling stops collection, cancels delivery where possible and clears local pending data; reports already accepted cannot be recalled.

Default Debug, Testing and Release builds cannot collect or send usage. Production reporting requires separately verified PostHog EU privacy, retention and no-overage settings, an explicit Release attestation and a public ingest token. The [analytics release prerequisites](docs/ANALYTICS-RELEASE.md) describe the evidence required before enabling it. Provider-visible IP and receipt time are disclosed in the app; local tests do not prove provider enforcement.

Verification runs scripts/with-analytics-fixture on loopback port38477 outside the app sandbox. Only the Testing bundle accepts --test-usage-origin http://127.0.0.1:38477 and --test-usage-clock YES. The latter exposes a test-only clock button for weekly-window acceptance. Both fixture wrappers fail if their port is occupied and stop their own servers on exit. No test data goes to public analytics. Production build values come from project.yml into a generated .build/Humstead-Info.plist; scripts/setup recreates it.

## Project contracts

Read [product](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md), [workflow](docs/WORKFLOW.md) and [spec index](docs/specs/README.md). Approved source documents retain their original bytes; historical approval/build status in them is superseded by the run ledger. Construction has been authorized separately.

## License

Humstead source is [MIT licensed](LICENSE) and the app will be free forever. Audio is separately licensed CC0 or CC BY; the source license does not relicense media. The local development build uses nine approved songs and four ambience recordings, all offered under CC0 1.0. All 13 bundled recordings received human listening approval on October 3, 2026. [Provenance](docs/audio/PROVENANCE.md) and the [asset manifest](docs/audio/manifest.json) preserve source, creator, license, modifications and content digests. Artist and original recording links appear in the player; Settings → Credits retains readable notices offline. No network connection or account is needed for playback.
