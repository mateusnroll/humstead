# Humstead

A free native macOS home for lofi music and ambience. Humstead is under development. The local station-player milestone provides Mellow, Jazzy and Late Night, shuffled continuous playback, music volume and offline creator credits. Ambience controls, saved preferences, system media controls and downloads follow in later milestones.

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

## Player walkthrough

Launch with scripts/dev, choose a station and press Play. Next advances without starting paused playback. Music volume zero pauses the track at its current position; raising it resumes only if playback is requested. Space toggles playback when the player background has focus; focused controls retain their native key handling. Playback → Play/Pause (Command-P) and Next track (Command-Right) expose keyboard commands. Command-comma opens Credits. Playback starts paused on each launch in this milestone.

The development audio is not yet approved for release. The app is intentionally compact and uses standard macOS focus, menus, links and sliders. It has no decorative animation.

## Project contracts

Read [product](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md), [workflow](docs/WORKFLOW.md) and [spec index](docs/specs/README.md). Approved source documents retain their original bytes; historical approval/build status in them is superseded by the run ledger. Construction has been authorized separately.

## License

Humstead source is [MIT licensed](LICENSE) and the app will be free forever. Audio is separately licensed CC0 or CC BY; the source license does not relicense media. The local development build uses nine approved songs and four ambience recordings, all offered under CC0 1.0. All 13 bundled recordings received human listening approval on October 3, 2026. [Provenance](docs/audio/PROVENANCE.md) and the [asset manifest](docs/audio/manifest.json) preserve source, creator, license, modifications and content digests. Artist and original recording links appear in the player; Settings → Credits retains readable notices offline. No network connection or account is needed for playback.
