# AccessHub native client — version 2.0, build 3

This is the existing native SwiftUI application, expanded into Home, Play, Rewards, Community and Profile. The internal Xcode target/product stays `AccessHubCasino`; the display name is AccessHub. The signed bundle identifier remains `app.accesshub.casino`.

## Preservation and storage

The existing CasinoStore, four Casino games, game mathematics, account IDs, `/v1` protocol, credit ledger, 1% rakeback and settings remain in place. `app.accesshub.casino.session` remains the Keychain service. Existing `accesshub.pending.v1` and presented-result keys remain intact. No native balance migration or reset is performed.

HubStore shares the authenticated Casino transport. Late responses from another session are discarded. Hub mutations are stored before transmission under `accesshub.hub.pending.v2.<account ID>` and retried with the original UUID and payload. Only the matching accepted receipt, or a definitive client rejection, clears a command. Unresolved Hub commands prevent switching accounts. Each live room/channel has an account-scoped command journal; only acknowledged commands are removed. Gameplay input sequences resume after the server's last accepted input.

Access Hub Credits begin at zero and remain administrator funded. There is no player refill or currency exchange. Hub Points, free daily rewards, vouchers, marketplace and cosmetic learning use the separate `/v2` authority. Hub cosmetics are applied to the profile, Blackjack backs/table and Snake skins/trails without modifying Casino requests or Snake movement inputs.

## Client structure

- `HubStore.swift`: bootstrap, paged collections, exact-once request receipts, account lifecycle and typed notification routes.
- `HubViews.swift`: Home, Play, Rewards, daily schedule/claim, giveaways, voucher probabilities/wallet, inventory, market purchase/listing confirmation, points history and original cosmetic previews.
- `HubCommunityViews.swift`: friends, privacy, reporting, private support, authenticated image attachment uploads/downloads, notification inbox/preferences and nongambling learning/badges.
- `LiveSession.swift`: authenticated WebSockets, server snapshots, room recovery, persistent request acknowledgements, actual presence, chat history/cursors/replies/reactions/moderation controls.
- `SnakeViews.swift`: solo/friend/private rooms, explicit terms/credit acceptance, countdown, server-driven interpolated arena, swipe/pad controls, results, forfeit and published rules.
- `PushCoordinator.swift`: capability-gated APNs lifecycle for a future owner-signed distribution. The chosen loader release uses the in-app inbox.

Top-level Swift source files are included by `scripts/generate_project.py`. Regenerate the project after adding a source file. There is no runtime package dependency.

## Build and test

The ordinary loader build uses `Config.xcconfig`, `ACCESSHUB_PUSH_ENABLED=NO`, and no push entitlement. Build/export/sign using the existing `README.md` and loader IPA script. Changing native code or bundled artwork requires a new signed IPA; server content, supported campaign schedules, artwork/configuration, moderation, support and inbox updates can change live.

To build against staging, pass `ACCESSHUB_API_BASE_URL=https://accesshub-staging.fejiofasj.workers.dev` to `xcodebuild`; do not silently ship the staging endpoint as production. Run the small and large iPhone simulator suites using the existing scripts. Offline tests do not create accounts. Live inspection must use a fresh simulator and explicitly opt in:

```sh
export TEST_RUNNER_ACCESSHUB_RUN_ZERO_CREDIT_TESTS=1
export TEST_RUNNER_ACCESSHUB_RUN_HUB_TESTS=1
export TEST_RUNNER_ACCESSHUB_RUN_ONLINE_TESTS=0
# Then use the existing test-simulators.sh workflow against staging.
```

The zero-credit test creates its own guest, verifies administrator-only funding and every Casino game control is disabled at zero. With the Hub flag, it also claims one daily Hub reward, opens real global chat and completes an authoritative zero-stake solo Snake session. Cleanup checks the generated account ID before deleting that test guest. Funded Casino tests remain a separate explicit opt-in and require approved test credentials; no such credentials are embedded in source.

Contract tests cover exact Hub receipts and saved payloads, safe notification route mapping and the existing Casino accounting/receipt/card-state contracts. Backend concurrency, duplicate claims/trades, private authorization and two-player settlement checks live in the backend test suite. Simulator success is not a physical-device frame-rate or installation claim. See the release report for actual test counts and build identifiers.

## Notifications and private content

The owner chose generic loader distribution plus in-app notifications. This build never asks for device push permission. The inbox and its typed routes work independently of APNs. A notification's ticket/voucher/room is fetched with the current session; attachments always use an authorized request and are kept in memory rather than a public image cache. Logout/account switching clears account-bound Hub state and live sessions.

`Push.xcconfig` and `AccessHub.entitlements` are provided only for a future owner-signed release. That route requires a push-enabled App ID and provisioning profile, matching team/topic/environment/provider credentials and physical iPhone testing. Ordinary recipient re-signing through a loader does not establish that identity. No provider key belongs in this repository. Enabling that variant would require changing the signed build configuration deliberately, registering its token with the configured backend, and testing token invalidation/account switching. Provider acceptance is never reported as device receipt/read confirmation.

## Motion and accessibility

All scenes use the existing sound/haptics settings and respect the iPhone's Reduce Motion setting. Snake renders interpolation only between authoritative positions; reduced motion shows discrete server snapshots. Casino animation remains state driven. The five tabs, scroll layouts, multiline descriptions, accessible control labels and directional pad support small iPhone screens. Physical-device performance and push capability verification remain distinct from simulator checks.
