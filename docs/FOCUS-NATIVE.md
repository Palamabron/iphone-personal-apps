# Focus Tube Native 0.2.0

A standalone app, separate from the Safari extension 0.1.1, with bundle identifier `dev.palamabron.focustube.native`. Its SwiftUI home screen includes search, local storage for up to 100 links, back and refresh controls, subscriptions and account selection. Results and the official YouTube player run inside the app in WKWebView, without switching to Safari. This is not a fully native clone of every YouTube screen.

The built-in filter hides recognized Shorts and recommendations, limits results to batches of 15, and restricts autoplay. It also runs during navigation without page reloads. There is no filter-disable switch. The YouTube view remains covered unless the filter confirms activation. A separate native navigation policy blocks Shorts and unapproved hosts, while permitting YouTube and selected Google sign-in and consent hosts. WebKit handles embedded frames and media. The app does not spoof the User-Agent, extract streams, or copy Safari sessions. Cookies in WebKit's default store retain the session between launches.

## Installation

Download **FocusTubeNative-unsigned.ipa** from release `focus-native-0.2.0`, then open SideStore → My Apps → + and select the downloaded file. Downloading alone does not install the app. Enter Apple credentials only in the installation tool. For Windows/Ubuntu SideStore setup, see [INSTALL_IPHONE.md](INSTALL_IPHONE.md).

The older Focus Tube Safari extension is a separate app. With the three-app limit, which includes SideStore, deactivate the old extension before installing Native alongside Tech Radar. You do not need to remove Userscripts from the App Store.

## First test

1. Open the app, search for a long video, and start playback manually.
2. Save a video using the bookmark, return home, open the saved item, and check it after restarting the app.
3. Open Account. Test sign-in to the Premium account and check whether the session survives a restart. Google may refuse sign-in in an embedded browser; the app does not bypass this.
4. Check that Shorts are absent, subsequent batches of 15 require a deliberate action, and the next video does not start automatically.
5. Test fullscreen, Premium, picture in picture and screen lock separately. They remain unverified. Offline downloads are unavailable.

The app does not block the official YouTube app, app removal, or device settings. Not every Short shared as a regular `/watch` link can be recognized.

## Reproducing the build

The public **Build Focus Tube Native** workflow runs Swift URL-policy and filter tests, builds an iPhoneOS/ARM64 IPA, and separately builds the simulator app. It uses no Apple account or paid runner. On macOS run `node scripts/build-native-ios.mjs`. Windows can be used to develop code and install the package, but cannot compile iOS.

See [BUILD-VALIDATION.md](BUILD-VALIDATION.md) for test evidence. A simulator screenshot does not establish that sign-in or Premium works on a device.
