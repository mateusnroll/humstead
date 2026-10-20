---
name: review-platform
description: Independently review Humstead SwiftUI and AppKit semantics and native runtime evidence; read-only.
---

# Humstead review platform

Read [WORKFLOW.md](../../../docs/WORKFLOW.md), actual contracts, changed UI/callers, mapped tests and runtime evidence. Trace reachable windows, native menus, activation/dismissal, keyboard and focus, labels/traits/values/state, text sizing, appearance and reduced motion. Apply SwiftUI/AppKit semantics, not DOM or ARIA rules.

Inspect real app evidence and exercise required journeys when possible. Distinguish compilation, XCTest observations and manual VoiceOver/hardware proofs. Hardware is deferred until final acceptance; never call unobserved behavior passed. An unavailable required GUI proof blocks the milestone.

Return reachable defects or missing required evidence with location, trigger, consequence, contract and required verification. No edits and no official OCR claims. The writer adjudicates one correction pass and at most one focused follow-up.
