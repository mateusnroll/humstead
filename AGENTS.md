# Humstead

Native SwiftUI macOS app. Read docs/PRODUCT.md, docs/ARCHITECTURE.md and docs/WORKFLOW.md before nontrivial work. Approved product and architecture bytes are immutable; lifecycle/authorization is recorded separately.

Use scripts/setup, scripts/dev, scripts/check, scripts/verify and scripts/build from the repository root. Missing tools or required checks fail; never silently skip. Keep application code Swift 6, arm64, macOS13+, sandboxed and free of third-party runtime dependencies. SwiftUI sends intents to the app model; audio/file/network owners remain separate. Do not introduce a backend, user accounts, streaming playback or persistent analytics IDs.

Use .agents/skills/spec to draft contracts, implement for approved behavior, review-simplicity for independent reduction review, review-platform for SwiftUI/AppKit accessibility and runtime evidence, and polish only for explicitly authorized prototypes. docs/WORKFLOW.md controls approval and completion.

Work on the authorized feature branch, never main. Preserve unrelated changes; no destructive reset/clean. Keep Markdown paragraphs and list items on one physical line. Write decisions in docs/decisions only when an actual durable tradeoff needs explanation. No merge, cloud provisioning, distribution signing, notarization or public release is authorized by local development.
