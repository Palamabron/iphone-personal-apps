# Validation of the first IPAs — 21 October 2026

App code: commit `66979d8d48449b4e0ae0ee1aef23026a59d5ad8e`. [Build and reports](https://github.com/Palamabron/iphone-personal-apps/actions/runs/39633098802) succeeded for both apps. Later documentation changes do not change the code of this release.

## Completed

- Standard public `macos-15` runners, Xcode 16.4, iPhoneOS SDK 18.5; iOS 18.0+, ARM64, Release configuration.
- Seven Focus Tube logic tests and 20 Radar logic/collector tests on macOS runners.
- Both apps and the Safari extension compiled without Apple Account credentials or signing profiles.
- ZIP/Info.plist/Mach-O checks confirmed iPhoneOS/ARM64 packages, matching identifiers and versions, icons, code and resources. Focus contains a Safari extension, a YouTube-only manifest, a Polish setup screen and an account-switch link. Radar contains self-contained HTML with a native bridge.
- Package checks were repeated after download to Windows; SHA-256 hashes matched CI reports.
- A previous Chromium Radar UI test used a mocked bridge to check save/reopen, ICS/JSON export, public-source import, rejection of external addresses, and saved data after source failure. This is not a Swift or mobile Safari test.

| File | Bytes | SHA-256 |
|---|---:|---|
| FocusTube-unsigned.ipa | 103739 | `69ecf062f76e353e36e5a7654e0b0822d161e5961c61eea3fb67b0461eb9af9b` |
| TechRadar-unsigned.ipa | 108357 | `e178e41bcb4814f417effedda17060f5c3bc0e3a779f7ffe2de0f96c3bad4f68` |

## Not performed

No simulator or physical iPhone test was performed for these initial packages. Remaining checks include SideStore and Personal Team signing, including the extension; launch and Safari visibility; real storage and playback; sharing and file import; source access on the phone network; and renewal without data loss. YouTube account/Premium, background audio and PiP remain unverified.

## Tool warnings

The Xcode 16.4 extension generator warns about `content_scripts.world`. `MAIN` and minimum iOS 18 were retained. [MDN compatibility data](https://github.com/mdn/browser-compat-data/blob/main/webextensions/manifest/content_scripts.json) lists support from Safari 18; this is not a phone Safari test. The runtime also observes DOM changes and periodically checks the URL rather than relying solely on history method replacement.

There were also AppIntents metadata-skipping messages, as the apps do not implement App Intents, and GitHub Actions messages about the actions' Node.js runtime. There were no missing-icon warnings or compilation errors.

## Focus Tube Native 0.2.0 — 22 October 2026

App code: `fda4586`. [Build 39696970191](https://github.com/Palamabron/iphone-personal-apps/actions/runs/39696970191) passed. This is a separate SwiftUI/WKWebView app, not the earlier extension container.

- Filter JavaScript tests passed 7/7. Swift URL-policy checks passed for search, valid videos, Shorts blocking, encoded URLs and deceptive hosts. The existing filter also passed 39 synthetic Chromium checks on Windows; these are not WebKit tests.
- Xcode compiled a Release iPhoneOS/ARM64 device app targeting iOS 18+. ZIP, Info.plist, icon and bundled-filter checks passed in CI and again after download to Windows. Bundle `dev.palamabron.focustube.native`, version 0.2.0, unsigned and without extensions.
- A separate simulator build, installation, launch and screenshot succeeded. Manual screenshot inspection showed a readable Polish home screen without clipping. Search, playback, login and bookmarks were not tested in the simulator.
- Package: `FocusTubeNative-unsigned.ipa`, 119891 bytes, SHA-256 `628794525ab0561b4365af4cb54f33042c8151a0679f1805b90b62cd2bacf890`.

Not performed: SideStore signing and installation, actual mobile YouTube/WKWebView search and playback, session and saved-item persistence after closing, Google account/Premium, PiP, background playback, and signature renewal on a physical iPhone. The user reported an iPhone 16 Pro/iOS 27.0.1; the simulator is not a test of that combination. Google may refuse embedded sign-in. See FOCUS-NATIVE.md for setup and scope.
