# AccessHub Casino for iPhone

Native SwiftUI application, iOS 17+, Xcode 16 or newer, no third-party runtime dependencies. All stakes, results, balances, account settings, progress and rakeback are resolved by the Cloudflare backend. All amounts are **Access Hub Credits — No cash value**.

Build 2 starts new accounts at 0. Only an administrator can add credits; players have no refill or credit-purchase control. Profile displays a copyable account ID for the administrator. Game returns and earned rakeback claims continue to work normally. The interface uses “Access Hub Credits” without a “No cash value” label; the currency remains non-transferable and cannot be redeemed.

## Open and run

1. Copy this project to a Mac with Xcode and open `AccessHubCasino.xcodeproj`.
2. Set `ACCESSHUB_API_BASE_URL` in `Config.xcconfig` to your deployed backend. Keep the `https:/$()/` escaping: Xcode expands it to `https://`.
3. Select the `AccessHubCasino` scheme and an iPhone simulator. Build and Run.
4. For a real device, select your Apple development team under Signing & Capabilities and choose a unique bundle identifier if needed.

The included artwork and audio are already in the app bundle. To regenerate the project after adding files, run `python3 scripts/generate_project.py`. To re-import the source artwork, run `python3 scripts/import_artwork.py`. Neither step is required to open the supplied project.

## Build and export an IPA

On a Mac with the relevant signing certificate and provisioning access:

```sh
export APPLE_TEAM_ID=YOUR_TEAM_ID
bash scripts/build-ipa.sh
```

The script archives to `build/AccessHubCasino.xcarchive` and exports to `build/export`. The supplied export method is development; choose the supported method appropriate to your installed Xcode and membership (`EXPORT_METHOD=app-store-connect` for TestFlight/App Store, or `release-testing` for registered distribution devices). Signing is not included. Review the App Store's current metadata, age rating and privacy requirements before distribution.

Alternatively use Product → Archive → Distribute App in Xcode and select the destination supported by your account. Xcode can generate the exact ExportOptions.plist for that destination.

For an IPA that AccessHub Loader signs with the installing user's Apple account, run:

```sh
bash scripts/build-loader-ipa.sh
```

This builds the Release `iphoneos` target without a signing identity and packages `build/loader/output/AccessHubCasino.ipa`. The script checks the bundle identifier, arm64 device architecture, iOS platform, HTTPS backend configuration and ZIP integrity, then writes SHA-256 and build metadata alongside it. This unsigned artifact must be signed by the loader before iPhone installation. The loader workflow template is `scripts/github-loader-ipa.yml`; it expects this project's contents under `casino-app/` in its repository.

## Tests and verification

`scripts/validate_sources.py` checks resources, plists, storyboard, scheme, asset files and, when optional Python parsers are installed, Swift syntax and Xcode object references. This is **not** a Swift type check, Xcode compilation or simulator test.

`ClientContractTests` covers integer credit precision, hidden-card/hidden-board null values, durable request serialization, Keychain persistence, stake validation and Crash potential-return state/rounding. `AccessHubCasinoUITests` contains launch/account-form checks and explicit opt-in connected game/navigation tests. The connected tests create a genuine guest, verify its zero balance and absence of refill controls, then sign in through the UI to a separate administrator-funded test account. Each game test waits for a **new** round identifier and its actual settlement, so an old result cannot satisfy it. Mines handles either a mine or a safe-tile collection; Blackjack handles natural settlement or an available stand; Crash follows actual shared timing. Use fresh simulators for acceptance runs.

```sh
xcrun simctl list devices available
SMALL_IPHONE='iPhone SE (3rd generation)' LARGE_IPHONE='iPhone 16 Pro Max' bash scripts/test-simulators.sh
# Set TEST_RUNNER_ACCESSHUB_TEST_USERNAME and TEST_RUNNER_ACCESSHUB_TEST_PASSWORD
# in your shell to an administrator-funded test account; then opt in:
ACCESSHUB_RUN_ONLINE_TESTS=1 SMALL_IPHONE='iPhone SE (3rd generation)' LARGE_IPHONE='iPhone 16 Pro Max' bash scripts/test-simulators.sh
```

Change those names to installed devices. Inspect retained screenshot attachments in each `.xcresult`. Run VoiceOver and large Dynamic Type checks and profile animation performance with Instruments on actual target devices. The target is 60 fps; it has not been measured in this Windows delivery environment.

Simulator tests use local ad hoc signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`) so the app receives the entitlements needed for Keychain access. This requires no Apple developer certificate. Keep the device IPA's separate unsigned build configuration for loader signing. A secure-session roundtrip test checks Keychain creation, read and update before connected UI acceptance.

For CI, an administrator provisions two ordinary test accounts before the run. Configure four GitHub Actions secrets: `ACCESSHUB_TEST_USERNAME_SMALL`, `ACCESSHUB_TEST_PASSWORD_SMALL`, `ACCESSHUB_TEST_USERNAME_LARGE`, and `ACCESSHUB_TEST_PASSWORD_LARGE`. Each simulator step passes only those unprivileged fixture credentials using `TEST_RUNNER_` environment forwarding, which [Xcode supports for test-runner processes](https://developer.apple.com/documentation/xcode/environment-variable-reference). The admin secret never enters CI or the app, and passwords are not supplied as xcodebuild command-line build settings. Treat `.xcresult` attachments as test evidence that can contain test-account details. The loader workflow uploads the small-device log immediately, then the full evidence after both devices finish.

The repository includes `.github/workflows/ios.yml` (also copied to `scripts/github-ios.yml`). It expects this `ios` directory at the repository root. It compiles on macOS, selects a small and a large installed iPhone, and uploads logs, `.xcresult` bundles and screenshot attachments even on failure. Connected tests are off for pushes and pull requests. Enable the `online_tests` checkbox when manually running the workflow to exercise all four games on the configured backend. The loader variant, `scripts/github-loader-ipa.yml`, was executed in the public casino build repository as documented below.

On this delivery's Windows workspace, the exact static validation command is:

```powershell
Set-Location C:\Users\007ha\Downloads\Codex\AccessHubCasinoNative\ios
python scripts/validate_sources.py
```

The validator prepends `ios/.python-tools` to Python's module search path itself. Optional parser installation on another machine: `python -m pip install --target .python-tools tree-sitter tree-sitter-swift openstep-parser`. Those packages are developer checks only and are excluded from the delivery archive and application.

## Session and animation behavior

- The bearer token and guest creation secret live in Keychain. Interrupted game/claim requests retain their original UUID and payload on disk until a definitive response; repeated submissions never create a new operation.
- One-second foreground state polling follows the same server round for everyone. Controls pause on disconnect, requests restore on reconnection, and the Crash graph extrapolates only briefly from its latest server timestamp. The server decides all collection cutoffs.
- While the current Crash position is running, its live return follows the graph's bounded interpolation from the authoritative clock and committed stake, rounded down to one microcredit and displayed to two decimal places. It never extrapolates more than 1.5 seconds past the latest snapshot or exceeds the configured automatic-collection return. A short estimate label makes clear that the server must accept collection; offline the amount freezes at the published snapshot and is labeled as the last confirmed return. Finished and previous positions show their actual settlement instead. This display never changes the balance.
- The app restores actual game state on foregrounding. Slot animations terminate on the exact server grid. Hidden Blackjack/Mines values remain hidden until the server reveals them.
- Sound, haptics, motion reduction and quick reel effects are independent persisted settings. iOS Reduce Motion overrides decorative motion. System silent mode is respected.
- Account deletion requires explicit confirmation. Cosmetic selections independently apply to avatars, profile decorations, Blackjack tables and card backs. Halo and Laurel decorations are original native vector artwork and appear around the selected avatar on Home, Progress and Profile. Learning XP does not affect game probabilities or the fixed 1% rakeback rate.
- Positive net results receive a restrained glow, with 6, 12 or 18 small particles for returns of at least 1.25×, 2× or 5× the committed stake. Reduced Motion uses only the glow/crossfade. A returned amount below the stake is never celebrated. Settled round IDs are remembered per account so navigating or reconnecting does not replay result effects. Six original sounds include distinct win, push and low loss feedback; Slots outcome feedback waits until its reels stop.

## Delivery verification boundary

The native Release arm64 iPhone target compiled and was packaged into an unsigned IPA on macOS using Xcode 16.4 and the iOS 18.5 SDK. [Build run 42524613350](https://github.com/angussaw4134/AccessHubCasino-iOS-Build-20261109/actions/runs/42524613350) passed on commit `6245d200299200dffccdc9d0a3c778286ad17514`. Seven client contract tests and the welcome/account-form UI test passed on each of iPhone SE (3rd generation) and iPhone 16 Pro Max simulators. The two connected tests were intentionally skipped in that offline run. Both welcome screenshots were inspected: artwork, text and controls render correctly; the small layout scrolls to reach its legal footer. The machine-readable record is `../reports/ios-runs/42524613350/summary.json`.

The first connected run, [42525330197](https://github.com/angussaw4134/AccessHubCasino-iOS-Build-20261109/actions/runs/42525330197), exposed a simulator build configuration failure before any guest API request: Keychain session storage failed. Local simulator signing corrected it. The [connected retest 42526805587](https://github.com/angussaw4134/AccessHubCasino-iOS-Build-20261109/actions/runs/42526805587) passed all 22 tests: 8 unit tests and 3 UI tests on each device, with no skips. It exercised guest access, saved-session restore, all five tabs, completed Blackjack/Mines/Slots rounds, shared Crash entry and settlement, and the original refill/rakeback flow. Production source in that retest was unchanged from the first IPA build.

Both devices' screenshots were reviewed. They exposed two visual defects despite the passing interaction checks: small Home content overflowed horizontally, and the settled Slots strips were outside their reel windows. Build 2 includes width containment and a full-height clipped reel-strip correction, alongside the new credit policy and live Crash return. These new changes require a fresh device build and connected simulator run; the earlier success does not verify build 2. Detailed records and screenshot paths are in `../reports/ios-runs/42526805587/summary.json`.

The CI-produced IPA needs loader signing. Simulator evidence does not establish physical iPhone installation or animation performance on hardware; 60 fps remains a target. Backend and device-installation evidence are documented separately in the repository's root documentation.
