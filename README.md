# AccessHub native iOS build

Native SwiftUI iPhone source, original artwork, and a macOS build workflow for AccessHub 2.0. Home, Play, Rewards, Community and Profile integrate AccessHub Casino, authoritative live Snake, free Hub rewards, cosmetic inventory and marketplace, friends/chat, private support and an in-app notification inbox.

Accounts start with 0 Access Hub Credits. Only an administrator can add credits; credits cannot be purchased, transferred or redeemed. Hub Points and nongambling cosmetic rewards are separate, with no conversion between currencies. Existing Casino accounts, histories and credit ledgers are preserved.

Open `casino-app/AccessHubCasino.xcodeproj` in Xcode. The workflow builds an unsigned arm64 iPhone IPA for signing by a compatible installer using the installing Apple account. It also runs the provided simulator tests.

An unsigned IPA needs valid signing and provisioning before installation. This repository contains no Apple credentials, private loader source, customer data, or backend secrets.

The chosen generic loader build uses in-app notifications. Device push requires a separately configured owner-signed distribution; it is disabled in this build. Read [the client architecture and verification notes](casino-app/ACCESSHUB-CLIENT.md) and [the build instructions](casino-app/README.md). The internal target and bundle identity remain `AccessHubCasino` and `app.accesshub.casino` to preserve installed accounts.

Backend and administration code are maintained privately and are not included in this client-only build repository. The optional Hub simulator workflow uses isolated staging and creates only its own zero-credit guest accounts; funded Casino tests remain a separate opt-in.
