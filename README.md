# Humstead

A free native macOS home for lofi music and ambience. Humstead is under development: the current milestone is a sandboxed native shell, not a functioning player yet.

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

## Project contracts

Read [product](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md), [workflow](docs/WORKFLOW.md) and [spec index](docs/specs/README.md). Approved source documents retain their original bytes; historical approval/build status in them is superseded by the run ledger. Construction has been authorized separately.

## License

Humstead source is [MIT licensed](LICENSE) and the app will be free forever. Audio is separately licensed CC0 or CC BY; the source license does not relicense media. No audio ships in this scaffold. [Audio research](docs/AUDIO-RESEARCH.md) records candidates that still require audition and final curation. Artist and original source links will remain visible with each shipped recording.
