---
name: review-simplicity
description: Independently review Humstead specifications or diffs for unnecessary complexity; read-only.
---

# Humstead review simplicity

Read [WORKFLOW.md](../../../docs/WORKFLOW.md), approved contracts and raw source/diff. Ignore writer persuasion. Consider deleting speculative work, reusing existing code, standard library/native capability, then inlining or shrinking mechanisms. Preserve required lifecycle, concurrency, privacy, sandbox, accessibility and proof coverage.

Return only concrete actionable findings: location, unnecessary work, smaller alternative and contract evidence. Product-scope cuts belong to the user. No edits or generic requests for extra tests. If none, say no actionable simplicity findings.
