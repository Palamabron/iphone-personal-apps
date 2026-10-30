# Radar as a standalone iPhone app

Status 21 October 2026: the Xcode iPhone build and IPA validation passed. [Package and installation instructions](https://github.com/Palamabron/iphone-personal-apps). Simulator, SideStore signing, and physical iPhone tests have not been performed. The existing web app remains available.

## Source contents

`ios/RadarApp.swift` creates a standalone iOS app with a locally bundled Radar interface. Appearance, matching rules and parsers are shared with the web app; the interface is not rewritten from scratch in SwiftUI. Swift provides the shell, persistent UserDefaults storage, system sharing of ICS/JSON backups, and public-source fetching via URLSession. The app requires neither a private Sites hosting login nor a server.

Sources are fetched over the phone's network. The same limits apply: Luma and Evenea errors or rate limits are reported, while Facebook and LinkedIn require manual import. Requests use an explicit host allowlist, a 2 MB limit and a timeout. Each redirect returns to the shared collector for validation. Browser headers, cookies and sessions are not copied.

`node scripts/prepare-ios.mjs` prepares self-contained HTML on Windows or Ubuntu. On a Mac with Xcode, `node scripts/build-ios.mjs` generates the project, builds for a device, and creates `build/ios/TechRadar-unsigned.ipa`. The target is iOS 18 or later. An iOS icon is included. System file import, export error reporting, data persistence across renewal, and source access require device verification.

On Windows, 20 logic tests and `scripts/check-ios-ui.mjs` passed: the self-contained HTML was opened in Chromium with a mocked bridge, testing save/restore, ICS and JSON export, public-source import, rejection of external addresses, and preservation of saved events after collector failure. This is not a Swift, Safari, or iPhone test. The optional test uses Playwright (`PLAYWRIGHT_MODULE`, `BROWSER_CHANNEL`).

## No extra charges

The manually triggered workflow is guarded so its job does not run in private repositories. The original repository remains private. With the owner's consent, selected sources were moved to a separate [public build repository](https://github.com/Palamabron/iphone-personal-apps) and built without charge on a standard macOS runner. Account budgets were not changed.

The public repository contains sanitized build sources without the original repositories' history, private hosting or preference data. The [build report](https://github.com/Palamabron/iphone-personal-apps/blob/main/docs/BUILD-VALIDATION.md) separates package checks from tests requiring an iPhone.

After a successful build, download the artifact, unpack the ZIP, and sign the IPA in SideStore on your own iPhone. SideStore can be set up using Windows/Ubuntu. Do not share an Apple Account password or pairing file in the repository or this conversation. SideStore uses one of three slots; Radar and Focus Tube can occupy the other two. Renewal is still required before seven days have elapsed.

## Sources

- https://docs.sidestore.io/docs/installation/prerequisites
- https://docs.sidestore.io/docs/installation/install
- https://docs.sidestore.io/docs/faq
- https://developer.apple.com/help/account/basics/about-your-developer-account
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
