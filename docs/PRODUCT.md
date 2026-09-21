# Humstead — v1 product specification

## Origin and goals

Source: the Humstead Liftoff conversation with Mateus, September 7, 2026. This is a draft for human review, not an approved build contract. Approval provenance and exact digest are recorded separately.

- G1: Start a pleasant lofi listening session quickly and continue without an internet connection.
- G2: Make music and ambience behave as one coherent, native Mac listening experience.
- G3: Offer a compact, tasteful and accessible player with little ongoing maintenance.
- G4: Respect artists and keep the application free forever and open source.

## Requirements

Each numbered item is independently observable. Its acceptance statement defines the intended proof, to be refined in architecture and milestone contracts.

- PRD-R-001: Provide Mellow, Jazzy and Late Night stations. Acceptance: all three can be selected and play their curated music. Goal: G1.
- PRD-R-002: Bundle at least three tracks per station. Acceptance: a fresh install can play each station without network access. Goal: G1.
- PRD-R-003: Shuffle station music without immediate track repeats when multiple tracks are available. Acceptance: successive selections satisfy this rule. Goal: G1.
- PRD-R-004: Continue station playback indefinitely by default. Acceptance: reaching the end of a track or a catalog pass does not stop the session. Goal: G1.
- PRD-R-005: Bundle rain, café, fireplace and forest ambience. Acceptance: each sound plays without a download. Goal: G1.
- PRD-R-006: Allow multiple simultaneous ambience layers with individual volume controls. Acceptance: changing one layer leaves other configured levels unchanged. Goal: G2.
- PRD-R-007: Support ambience-only listening. Acceptance: users can silence music while ambience continues. Goal: G2.
- PRD-R-008: Provide Music Only (the default without ambience), Rainy Window, Café, Fireside and Forest presets in every station. Acceptance: selecting a preset applies its original mix on first use. Original levels will be specified and auditioned during design. Goal: G2.
- PRD-R-009: Remember the selected ambience preset independently for each station and retain adjustments for every preset within each station. Acceptance: switching stations restores that station's selection; switching away from a preset and back restores its edits, including after relaunch. Goal: G2.
- PRD-R-010: Provide Reset ambience beside ambience controls. Acceptance: it restores the selected preset's original enabled sounds and volume levels, without changing music or downloads. Goal: G2.
- PRD-R-011: Restore the last station, preset and volume settings after relaunch without autoplay. Acceptance: relaunch presents the saved setup in a paused state. Goal: G2.
- PRD-R-012: Global play/pause pauses and resumes the whole mix while preserving levels. Acceptance: in-app and supported Mac system controls agree on the playback state. Goal: G2.
- PRD-R-013: Next track changes the music while ambience continues. Acceptance: skipping does not reset or interrupt the ambience mix. Goal: G2.
- PRD-R-014: Integrate Mac media keys, Control Center/Now Playing and supported headphone playback controls. Acceptance: real-app verification demonstrates command handling and truthful metadata/state, including coexistence with another media app. Platform limitations must be documented rather than assumed away. Goal: G2.
- PRD-R-015: Pause the entire mix when active headphones disconnect. Acceptance: playback does not unexpectedly continue through speakers; reconnecting does not autoplay. Goal: G2.
- PRD-R-016: Closing the player window preserves playback and exposes menu-bar controls to pause, change stations and reopen the player. Acceptance: each action works with the main window closed. Goal: G2.
- PRD-R-017: Quitting stops all playback. Acceptance: no audio continues after the application exits. Goal: G2.
- PRD-R-018: Provide a compact, beautiful native player with tasteful animation and native interactions. Acceptance: human visual review approves the implemented compact layout and motion, alongside platform interaction verification. Goal: G3.
- PRD-R-019: Expose play/pause, next, station selection, music volume, ambience presets and individual ambience sliders; keep current track title and artist links visible. Acceptance: all controls are usable from the compact player without queue editing or a full library interface. Goal: G3.
- PRD-R-020: Offer an optional 15/30/60-minute sleep timer which fades out the entire mix. Acceptance: selecting a duration enables the timer; expiry fades then stops playback; the default is disabled. Users can cancel the countdown; it uses elapsed real time and continues while paused. Expiry leaves playback paused, and quitting clears the timer. Ordinary playback defaults to an unlimited session. Goal: G2.
- PRD-R-021: Let users explicitly download station collections, displaying their size beforehand. Acceptance: bundled music is immediately playable and successful collection downloads work offline. Goal: G1.
- PRD-R-022: Retain downloaded audio locally until users remove it in Settings. Acceptance: repeated listening does not fetch the same retained audio again; removal frees its storage without deleting bundled audio. Goal: G1, G3.
- PRD-R-023: Bound automatic download retries and check catalog updates infrequently. Acceptance: a network failure cannot cause an unbounded request loop; exact limits are established in architecture. Goal: G3.
- PRD-R-024: Provide an operator-controlled emergency shutdown for new downloads. Acceptance: activation prevents new downloads within a documented propagation window while bundled and already downloaded audio remain usable. Mechanism, in-flight behavior and offline control-state policy require architecture resolution. Goal: G1, G3.
- PRD-R-025: Use only CC0 or standard CC BY audio with verified provenance. Acceptance: every shipped or published sound has a source, license/version and evidence of its redistribution eligibility. Goal: G4.
- PRD-R-026: Actively credit artists and sound creators with original asset URLs and profile URLs when available. Acceptance: credits and license information are available offline, links open the original pages when online, and required modification notices are preserved. Goal: G4.
- PRD-R-027: License application source under MIT and keep Humstead free forever without monetization. Acceptance: repository licensing distinguishes source code from separately licensed media; the app has no purchases, subscription or paywall. Goal: G4.
- PRD-R-028: Target Apple Silicon Macs only, with App Store and direct-download distribution as product destinations. Acceptance: supported hardware and distribution requirements are explicit; public release requires separate authorization and evidence. Support the widest practical range of macOS versions on Apple Silicon without substantial compatibility complexity; architecture will select and justify the exact minimum. Goal: G3, G4.

- PRD-R-029: Build and verify the real macOS application with Apple App Sandbox enabled from the start. Acceptance: inspect the built app's signed sandbox entitlement and exercise bundled/offline playback, downloads and removal, preference restoration, creator links, menu-bar/system media controls, headphone disconnection and timer expiry inside the actual sandboxed app. Run integration/UI acceptance with the intended sandbox/file/network entitlements and a clean app-container state as well as a persisted state. Unsandboxed-only results cannot satisfy this gate. App Store signing, submission and review remain separate release gates. Goal: G2, G3.

- PRD-R-030: Require no account and persist user preferences locally. Acceptance: all listening and settings journeys work without registration or login, with no account or preference-sync service. Goal: G1, G3.
- PRD-R-031: Provide keyboard navigation for all user-facing controls. Acceptance: keyboard-only completion of core journeys with visible focus. Goal: G3.
- PRD-R-032: Support VoiceOver. Acceptance: controls expose meaningful names, values and states and core journeys work with VoiceOver in the real sandboxed app. Goal: G3.
- PRD-R-033: Respect reduced motion. Acceptance: nonessential animation is suppressed or simplified without losing information or controls. Goal: G3.
- PRD-R-034: Make collection updates explicit and show download size before approval. Acceptance: discovering an update does not automatically download replacement audio. Goal: G1, G3.
- PRD-R-035: Show download progress and provide cancellation and retry. Acceptance: users can cancel active downloads and recover from failures; interruption preserves installed audio, incomplete or unverified downloads do not become playable, and insufficient space produces a recoverable message. Goal: G1, G3.
- PRD-R-036: Collect usage analytics only after explicit opt-in, with an easy disable control. Acceptance: before consent and after disabling, no usage collection or delivery occurs; analytics failure cannot interrupt listening. Goal: G3, G4.
- PRD-R-037: Send weekly summaries without persistent installation or device identifiers. Acceptance: reports contain no stable or derived identifier, fingerprint or other application-supplied cross-report linkage; analytics cannot measure installation-level retention. Exact transport and provider configuration must preserve this property. Goal: G4.
- PRD-R-038: Limit analytics to broad feature-usage and download-failure summaries. Acceptance: an approved closed schema excludes track names, artist URLs, listening history and exact listening timestamps; crash uploads are excluded from v1. Sandbox transport tests use local test sinks and send no test data to public analytics services. Goal: G3, G4.
- PRD-R-039: Keep analytics within a free-tier allowance without paid overages. Acceptance: verify provider configuration drops excess reports without charging or affecting listening; unsupported cost controls block enabling the production analytics integration. Goal: G3, G4.

- PRD-R-040: Offer optional downloadable ambience packs with size shown before explicit download, persistent offline storage, removal, progress, cancellation/retry and emergency-shutdown behavior equivalent to station collections. Acceptance: successful pack downloads can be used offline; failure preserves installed audio and shutdown prevents new downloads under the same policy. Goal: G1, G3.
- PRD-R-041: Keep all five built-in ambience presets dependent only on bundled sounds. Acceptance: every original preset mix works on a fresh offline installation and after optional ambience packs are removed. Goal: G1.

## Core journeys

1. First launch: select a station, press Play, hear bundled music with the no-ambience default (001–005, 008, 012).
2. Personalize: select an ambience preset, adjust layers, optionally silence music, switch stations and return to the remembered setup; reset restores the selected preset (006–011).
3. Listen in the background: close the window, control the mix from the menu bar or Mac playback controls, and pause safely on headphone disconnection (012–017).
4. Expand offline listening: inspect collection size, download and retain audio, then remove optional content through Settings if needed (021–024). Updates require explicit approval; progress, cancellation and retry are provided, and interruption preserves installed audio (034–035).
5. End a session: manually pause/quit, or opt into a sleep timer; ordinary playback keeps looping (004, 012, 017, 020).
6. Discover creators: follow visible artist and original-source links, with attribution retained locally (019, 025–026).

## Constraints and settled technical preferences

- Exact authorized new project path: /Users/mateus/dev/humstead. Definition documents are authorized; construction is not yet authorized.
- R2 Standard, static catalog, CDN caching, persistent local downloads and bounded requests were selected during the interview.
- Planning estimate: USD 0–5/month for early R2 adoption under the modeled workload, not a spending cap or guarantee. Domain, developer membership, reviews and other services are separate.
- Compact native macOS experience; Apple Silicon only. Detailed framework/toolchain and minimum OS selection belong to architecture after product clarification.
- Artist assets retain their original licenses; MIT does not replace their licenses.
- App Sandbox is required throughout real-app verification. Reference: https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox (checked September 7, 2026). Sandbox verification alone does not constitute App Store approval.

## Non-goals

- Immersive illustrated scenes in v1.
- User-named saved mixes, track seeking, queue editing or favorites.
- Intel, Windows, mobile or web clients.
- Monetization of any kind.
- Crash-report uploads, persistent analytics identifiers, installation-level retention metrics, or tracking individual listening histories.
- Public deployment, store submission, signing/notarization or releases without separate authorization.

## Assumptions and risks

- No tracks or sound recordings have yet been selected or auditioned. Catalog quality and verified rights are release prerequisites.
- Audio interruptions, headphone behavior and media-command ownership require testing in the actual application and on supported hardware.
- Emergency shutdown must remain operable if the app is malfunctioning; the detailed enforcement design is not settled.
- The consolidated product contract awaits explicit human approval. Remaining items below are architecture, design and build-authorization details. No Git repository, remote, paid review, scaffold or application build has been created.

## Details to resolve in architecture and build authorization

- Q1 (architecture detail): Select the oldest practical supported macOS release on Apple Silicon without substantial compatibility complexity; verify required APIs and available test coverage.
- Q2 (design detail): Preset names and availability are settled; define and audition their original layers and volume levels during design.
- Q4 (architecture detail): Timer semantics are settled; select a short fade duration.
- Q6 (architecture detail): Analytics policy is settled (036–039): explicit opt-in, easy disable, weekly broad summaries, no persistent IDs, no crash uploads, no paid overages. Resolve the exact closed schema, destination/provider, retention, consent surface, local accumulator/disable lifecycle and network metadata disclosures. No claim of complete anonymity may hide processor-visible source IPs or infrastructure logs. Read-only inspiration: /Users/mateus/dev/markzen/docs/specs/0008-opt-in-pseudonymous-telemetry.md (Draft, read September 7, 2026); Humstead deliberately does not adopt its stable identifiers, providers or crash integration.
- Q7: Define bounded library size, simultaneous ambience count, resource-use and startup expectations during architecture.
- Q8 (build authorization detail): Initial delivery is a tested sandboxed local application and an open, unmerged PR. Signing for distribution, notarization, App Store submission and direct-download publication belong to a separate release phase. Exact GitHub identity and construction/review authorization remain unset.
