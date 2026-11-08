# AccessHub Casino iOS build

Native SwiftUI iPhone source, original artwork, and a macOS build workflow. Accounts start with 0 Access Hub Credits. Only an administrator can add credits; credits cannot be purchased, transferred or redeemed.

Open `casino-app/AccessHubCasino.xcodeproj` in Xcode. The workflow builds an unsigned arm64 iPhone IPA for signing by a compatible installer using the installing Apple account. It also runs the provided simulator tests.

An unsigned IPA needs valid signing and provisioning before installation. This repository contains no Apple credentials, private loader source, customer data, or backend secrets.
