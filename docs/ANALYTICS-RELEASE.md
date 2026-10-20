# Analytics release prerequisites

Humstead's default builds do not contain production analytics configuration. Local tests use an isolated loopback sink. Passing those tests does not prove the configuration of a PostHog account.

Production analytics remains blocked until separately authorized provisioning supplies dated evidence for all of the following:

- A dedicated PostHog Cloud EU Free account/project, with no payment card or other chargeable billing configuration. Confirm excess analytics events are dropped at the free allowance and cannot generate overage charges. A budget alert alone is insufficient.
- One-year event retention, with the disclosure in Settings matching the actual project policy. Verify the current provider behavior; a pricing-page guarantee is not proof of a configured deletion schedule.
- Discard client IP data enabled, enrichment and identifying transformations disabled, cookieless server hash mode disabled, and no person/profile/identity enrichment. IP discard alone does not stop transformations from using an IP before discarding it.
- Reports accepted as the closed humstead_usage_summary event, with a new report-scoped UUID, $process_person_profile=false and $geoip_disable=true. No identify/alias/profile calls or stable identifiers. Do not interpret report IDs as users, installations or retention cohorts.
- Only the public project ingest token is injected into the Release build. Never embed an administrator token. The host is fixed to https://eu.i.posthog.com and the single-event path to /i/v0/e. Confirm the exact release artifact, build configuration and provider project agree.

Keep project identity, date, reviewer, configuration observations and cost/privacy evidence in the authorized release record, outside the public source repository. The explicit build enablement flag attests that this gate was checked; it does not inspect or enforce remote billing settings. An absent, stale or unsupported prerequisite means leave production analytics disabled. Do not create an account, change billing, configure the provider or send a production test report as part of ordinary local development.

Disabling in the app closes new collection/delivery and clears local pending data, cancelling an active request where possible. It cannot recall a report already accepted by the provider. Processors still observe source IP during a connection and receipt time; never claim complete anonymity. Ordinary listening must work with analytics unavailable, opted out or failing.

Primary references checked October4,2026: [capture API](https://posthog.com/docs/api/capture), [data storage and IP controls](https://posthog.com/docs/privacy/data-storage), [GeoIP processing control](https://github.com/PostHog/posthog-plugin-geoip), and [pricing/free limits](https://posthog.com/pricing). Recheck before production enablement because provider terms and controls can change.
