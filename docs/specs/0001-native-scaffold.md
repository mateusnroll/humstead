# 0001 — Reproducible sandboxed native scaffold

## Origin

Stage base f9afe80ec046e0a9c27c3118d87cccade3808494, documents-only main. Approved docs/PRODUCT.md SHA256 5779d0719039618c7644450624ce02be1c96c8c0ba68dc245c41e5febc23931b and docs/ARCHITECTURE.md SHA256 5485d021221ef14257fc4d73416312962615871a6d6c25f2e58a9924ea27a345. The frozen milestone requirements projection retains product foundation requirements and architecture-authorized scaffold aliases. No prerequisite implementation. Human authorized public mateusnroll/humstead, codex/v1 construction, local ad-hoc signing, app/test containers and USD10 aggregate paid reviews.

## Scope and non-goals

Create the real native app shell and portable development/verification workflows. Shell UI shows Humstead and an explicit development-stage description; it has no fake player controls. No audio assets/playback, downloads, persisted preferences, timer, system media integration, analytics, cloud setup, release/signing identity or monetization. Later milestones supply product behavior. Preserve approved product/architecture bytes unchanged. Existing docs/AUDIO-RESEARCH.md is included on the feature branch as research, not the base.

## Acceptance criteria

- AC-1: scripts/setup resolves full Xcode, verifies a macOS SDK and Swift compiler, obtains XcodeGen 2.46.0 from its official xcodegen.zip release using SHA256 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806, installs only under .tools, and deterministically generates Humstead.xcodeproj from project.yml. A failed download/checksum/tool check exits nonzero without replacing a verified generator. Existing verified installation supports offline setup. All configurable caches/logs/DerivedData go to .build or .tools; no global configuration is changed. Trace: PRD-R-042,043.
- AC-2: scripts/build produces .build/DerivedData/Build/Products/Release/Humstead.app with bundle ID com.mateusnroll.humstead, version 0.1.0 build 1, arm64 only, minimum macOS13, ad-hoc signature and sandbox plus network-client entitlement only; no other privacy or file access privilege. MIT LICENSE covers source and README distinguishes separately licensed future media. Trace: PRD-R-027,028,029,042.
- AC-3: scripts/dev builds and launches the actual Debug sandboxed app. The normal titled/resizable SwiftUI window has a readable Humstead heading and development description, native Quit/Close behavior, accessible text and system appearance; no false completed-player presentation. XCTest UI launches the sandboxed shell, verifies a visible window and heading, closes/reopens via application activation where supported, and terminates it. Local GUI unavailability is reported as blocked, never green. Trace: PRD-R-029,042.
- AC-4: scripts/verify executes scripts/check, a real Swift Testing target (validating build metadata supplied by the target, not a constant truth assertion), XCTest UI through the shared Humstead scheme and Humstead.xctestplan, signed entitlement/architecture/deployment-target checks, and Release build. It preserves result bundles and fails if any required stage fails. Isolated UI test hosting uses com.mateusnroll.humstead.testing; UI runner and test IDs are com.mateusnroll.humstead.uitests.xctrunner and com.mateusnroll.humstead.tests. Test mode changes only bundle identity/container, not sandbox/network entitlements or shell behavior. No destructive container cleanup is used. Trace: PRD-R-028,029,043.
- AC-5: scripts/check fails on format drift, generated-project drift, missing/nonexecutable mandatory scripts, unresolved local workflow links, missing skill frontmatter/metadata or undocumented command mismatch. Negative harness checks with run-owned temporary fixtures prove checksum rejection and failure propagation; never mutate shared or user state. Trace: PRD-R-043,044.
- AC-6: AGENTS.md, docs/WORKFLOW.md, docs/specs/TEMPLATE.md and docs/specs/README.md establish immutable numbered contracts and exact commands. Five local skills spec, implement, review-simplicity, polish and review-platform have validated SKILL.md and agents/openai.yaml, with prompts naming their corresponding skill. Platform review explicitly covers native SwiftUI/AppKit semantics and does not invent ARIA checks. No machine-specific absolute path, dangling reference or unfilled template survives in instantiated contracts, operational workflow documents, skills or scripts. The reusable docs/specs/TEMPLATE.md intentionally retains authoring instructions and example IDs and is exempt only from placeholder rejection. Trace: PRD-R-044.
- AC-7: .github/workflows/ci.yml defines static-contracts and macos-build on macos-26 arm64, selects installed Xcode 26 explicitly, uses read-only contents permission and invokes portable repository entrypoints. It runs checks, build-for-testing, Release build and entitlement inspection without running any application/unit/UI test on CI. Missing tools fail rather than skip. No deployment or credentials. Actual hosted CI green is required at final PR, not claimed from YAML inspection. Trace: PRD-R-028,029,045.

## Test mapping

| AC | Primary proof layer | Named test / command | What failure proves |
| --- | --- | --- | --- |
| AC-1 | Setup integration | scripts/test-harness setup-contract | Tool checksum/offline/generation behavior absent |
| AC-2 | Native artifact inspection | scripts/inspect-app Release | Artifact identity, deployment, architecture, signing, entitlement or license wrong |
| AC-3 | XCTest UI | ScaffoldUITests.visibleWindowLifecycle | Actual sandboxed shell not reachable |
| AC-4 | End-to-end verification harness | scripts/test-harness verification-contract | A required suite/build can be skipped or a failure swallowed |
| AC-5 | Static negative fixtures | scripts/test-harness static-contract | Guard fails to reject controlled invalid fixture |
| AC-6 | Repository workflow validation | scripts/validate-workflows | Lifecycle/local workflow contract incomplete |
| AC-7 | CI contract validation | scripts/validate-ci | CI missing prescribed jobs or adds runtime testing/deployment |

## PRD traceability

| Review requirement | Original source ID | Acceptance criteria |
| --- | --- | --- |
| PRD-R-027 | PRD-R-027 foundation | AC-2 |
| PRD-R-028 | PRD-R-028 foundation | AC-2, AC-4, AC-7 |
| PRD-R-029 | PRD-R-029 foundation; remaining actual player journeys deferred to assigned milestones | AC-2, AC-3, AC-4, AC-7 |
| PRD-R-042 | Architecture scaffold native boot | AC-1, AC-2, AC-3 |
| PRD-R-043 | Architecture scripts and proof harness | AC-1, AC-4, AC-5 |
| PRD-R-044 | Architecture repo workflows | AC-5, AC-6 |
| PRD-R-045 | Architecture static/build CI | AC-7 |

## Implementation changes

- project.yml, tools.lock, Humstead.xcodeproj/project.pbxproj, Humstead.xcodeproj/xcshareddata/xcschemes/Humstead.xcscheme, Humstead.xctestplan: one app target, Swift Testing and XCTest UI targets; generated project committed and compared deterministically. Swift language mode 6. Local Xcode27/Swift6.4 is verified; CI Xcode26 uses the same language mode/macOS13 API floor.
- Humstead/HumsteadApp.swift, Humstead/ContentView.swift, Humstead/Humstead.entitlements: small SwiftUI shell; no production async/data/service abstractions yet. App Sandbox and outgoing client access enabled identically for delivered/test-host variants.
- HumsteadTests/ScaffoldTests.swift, HumsteadUITests/ScaffoldUITests.swift: real target metadata and visible app lifecycle proofs.
- scripts/environment, scripts/setup, scripts/dev, scripts/check, scripts/verify, scripts/build, scripts/build-for-testing, scripts/inspect-app, scripts/test-harness, scripts/validate-workflows, scripts/validate-ci: POSIX/bash and Python3 standard-library helpers with explicit working-directory resolution and failing status propagation. Python3, curl, unzip, shasum, Git and full Xcode are documented developer prerequisites; Node is not an app build prerequisite. Swift formatting via xcrun swift-format. DerivedData at .build/DerivedData, clang/Swift module caches at .build/ModuleCache, test results at .build/results, generator at .tools/xcodegen; OS-managed app/test-owned container state is allowed. No simulator, package dependency cache or new global tooling needed.
- .github/workflows/ci.yml: the two prescribed static/build jobs; setup/check/build-for-testing/inspect-app/build paths only, no cloud deployment.
- AGENTS.md, docs/WORKFLOW.md, docs/specs/TEMPLATE.md: exact proposed ancillary bytes bundled with this candidate. docs/specs/README.md: lifecycle index and official evidence references; normative spec saved as docs/specs/0001-native-scaffold.md.
- .agents/skills/spec/SKILL.md, .agents/skills/spec/agents/openai.yaml; .agents/skills/implement/SKILL.md, .agents/skills/implement/agents/openai.yaml; .agents/skills/review-simplicity/SKILL.md, .agents/skills/review-simplicity/agents/openai.yaml; .agents/skills/polish/SKILL.md, .agents/skills/polish/agents/openai.yaml; .agents/skills/review-platform/SKILL.md, .agents/skills/review-platform/agents/openai.yaml: specialize installed Liftoff templates to WORKFLOW.md and validate using installed skill-creator.
- README.md, .gitignore, LICENSE: portable setup/launch/verify, actual prerequisites, generated file policy, source/media license split, ignored local outputs. docs/AUDIO-RESEARCH.md preserves existing research as unapproved asset candidates. docs/PRODUCT.md and docs/ARCHITECTURE.md remain byte-identical.

## Compatibility and migration

No persistent schema or network interface exists yet. App containers are framework-created; no preferences or files are written by scaffold application logic. Tests use the isolated test-host bundle ID; no reset of user containers. Existing research is retained. Native availability checks enforce macOS13 compilation; this does not prove runtime operation on macOS13. Only local macOS26.6.2 executes tests.

## Verification

Run named primary proofs and scripts/verify from a clean project entrypoint. First create failing harness/UI assertions for the absent scaffold; missing Xcode cannot count as intended red. Capture build/entitlement output and local xcresult evidence externally. Independent simplicity and native platform reviews follow first green; official OCR is required after the clean scaffold checkpoint. Remote creation and initial main/topic publication occur only after accepted scaffold OCR, using the separate authorized publication workflow.

## Simplicity dispositions

Use only native SwiftUI shell and standard tools. No service protocols or UI component library without a consumer. Independent read-only scaffold_spec_simplicity review found the reusable template exemption ambiguous; explicitly exempted only docs/specs/TEMPLATE.md from placeholder rejection. No other actionable blockers.

## Open questions

None.
