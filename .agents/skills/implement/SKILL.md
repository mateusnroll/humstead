---
name: implement
description: Implement an approved immutable Humstead milestone with mapped proofs and independent review.
---

# Humstead implement

Read [WORKFLOW.md](../../../docs/WORKFLOW.md), the candidate/index and affected code. Require exact candidate and ancillary document hashes, verified approval, resolved questions and satisfied dependencies. During Liftoff the preceding milestone must have accepted OCR evidence.

Write mapped proofs and observe intended red before behavior. Use Swift Testing for logic and XCTest UI for real sandboxed application journeys. Keep macOS13 API availability, arm64 and Swift6; avoid third-party runtime dependencies. Run scripts/check, focused proofs and scripts/verify. GUI/tool failures block the corresponding proof.

At first green request fresh read-only review-simplicity and review-platform with raw contracts/source/evidence. Apply or rebut findings, reverify changes, and allow one focused follow-up. Stop for unresolved accepted findings. Product/architecture changes require human approval; technical changes require a new immutable approval lifecycle. Hardware proofs stay pending until final acceptance, as authorized.

Update only index lifecycle metadata when local gates pass. The caller then commits and runs installed OCR; local green is not OCR approval. Do not publish, push, merge or release through this skill.
