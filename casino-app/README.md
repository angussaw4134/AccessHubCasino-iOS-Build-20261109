# AccessHub Casino for iPhone

Native SwiftUI application, iOS 17+, Xcode 16 or newer, no third-party runtime dependencies. All stakes, results, balances, account settings, progress and rakeback are resolved by the Cloudflare backend. All amounts are **Access Hub Credits — No cash value**.

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

## Tests and verification

`scripts/validate_sources.py` checks resources, plists, storyboard, scheme, asset files and, when optional Python parsers are installed, Swift syntax and Xcode object references. This is **not** a Swift type check, Xcode compilation or simulator test.

`ClientContractTests` covers integer credit precision, hidden-card/hidden-board null values, durable request serialization and stake validation. `AccessHubCasinoUITests` contains launch/account-form checks and explicit opt-in connected game/navigation tests. The connected tests create genuine free-credit activity on the configured backend. Each game test waits for a **new** round identifier and its actual settlement, so an old result cannot satisfy it. Mines handles either a mine or a safe-tile collection; Blackjack handles natural settlement or an available stand; Crash follows actual shared timing. Use fresh simulators for acceptance runs.

```sh
xcrun simctl list devices available
SMALL_IPHONE='iPhone SE (3rd generation)' LARGE_IPHONE='iPhone 16 Pro Max' bash scripts/test-simulators.sh
# Explicitly enable genuine connected round tests:
ACCESSHUB_RUN_ONLINE_TESTS=1 SMALL_IPHONE='iPhone SE (3rd generation)' LARGE_IPHONE='iPhone 16 Pro Max' bash scripts/test-simulators.sh
```

Change those names to installed devices. Inspect retained screenshot attachments in each `.xcresult`. Run VoiceOver and large Dynamic Type checks and profile animation performance with Instruments on actual target devices. The target is 60 fps; it has not been measured in this Windows delivery environment.

The repository includes `.github/workflows/ios.yml` (also copied to `scripts/github-ios.yml`). It expects this `ios` directory at the repository root. It compiles on macOS, selects a small and a large installed iPhone, and uploads logs, `.xcresult` bundles and screenshot attachments even on failure. Connected tests are off for pushes and pull requests. Enable the `online_tests` checkbox when manually running the workflow to exercise all four games on the configured backend. This workflow has been supplied, not remotely executed.

On this delivery's Windows workspace, the exact static validation command is:

```powershell
Set-Location C:\Users\007ha\Downloads\Codex\AccessHubCasinoNative\ios
python scripts/validate_sources.py
```

The validator prepends `ios/.python-tools` to Python's module search path itself. Optional parser installation on another machine: `python -m pip install --target .python-tools tree-sitter tree-sitter-swift openstep-parser`. Those packages are developer checks only and are excluded from the delivery archive and application.

## Session and animation behavior

- The bearer token and guest creation secret live in Keychain. Interrupted game/claim requests retain their original UUID and payload on disk until a definitive response; repeated submissions never create a new operation.
- One-second foreground state polling follows the same server round for everyone. Controls pause on disconnect, requests restore on reconnection, and the Crash graph extrapolates only briefly from its latest server timestamp. The server decides all collection cutoffs.
- The app restores actual game state on foregrounding. Slot animations terminate on the exact server grid. Hidden Blackjack/Mines values remain hidden until the server reveals them.
- Sound, haptics, motion reduction and quick reel effects are independent persisted settings. iOS Reduce Motion overrides decorative motion. System silent mode is respected.
- Account deletion requires explicit confirmation. Cosmetic selections independently apply to avatars, profile decorations, Blackjack tables and card backs. Halo and Laurel decorations are original native vector artwork and appear around the selected avatar on Home, Progress and Profile. Learning XP does not affect game probabilities or the fixed 1% rakeback rate.
- Positive net results receive a restrained glow, with 6, 12 or 18 small particles for returns of at least 1.25×, 2× or 5× the committed stake. Reduced Motion uses only the glow/crossfade. A returned amount below the stake is never celebrated. Settled round IDs are remembered per account so navigating or reconnecting does not replay result effects. Six original sounds include distinct win, push and low loss feedback; Slots outcome feedback waits until its reels stop.

## Delivery verification boundary

The project, native screens, assets, backend connection and test sources are implemented. Static checks were run on Windows. Xcode compilation, signing, simulator screenshots, device layout checks and animation profiling require macOS and have not been represented as completed. Backend verification and deployment evidence are documented separately in the repository's root documentation.
