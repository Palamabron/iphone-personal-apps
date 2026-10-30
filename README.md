# Personal iPhone apps

Two projects for iOS 18 and later, installable without a paid Apple Developer account. Windows or Ubuntu can be used with SideStore. Sources were selected for publication with the owner's consent; the original repositories remain private. This repository contains no private hosting configuration, account credentials, certificates, or personal preferences. Bundled events come from public listings.

| App | Description | Download |
|---|---|---|
| Focus Tube Native 0.3.0 | Standalone app with a native home screen, embedded YouTube, and a Shorts filter | [IPA](https://github.com/Palamabron/iphone-personal-apps/releases/download/focus-native-0.3.0/FocusTubeNative-unsigned.ipa) |
| Focus Tube 0.1.1 | Safari extension that filters YouTube | [IPA](https://github.com/Palamabron/iphone-personal-apps/releases/download/iphone-2026.10.21/FocusTube-unsigned.ipa) |
| Tech Radar 0.3.0 | Standalone event app with local storage and public-source refresh | [IPA](https://github.com/Palamabron/iphone-personal-apps/releases/download/radar-0.3.0/TechRadar-unsigned.ipa) |

[Installation instructions for Windows and Ubuntu](docs/INSTALL_IPHONE.md). The downloaded IPA must be signed during installation using SideStore, Sideloadly, or a similar tool. Downloading it alone does not install it. Free signing expires after seven days and must be refreshed.

Xcode builds and package validation have passed. Real-device behavior, account sign-in, and automatic renewal still need verification. See [build validation](docs/BUILD-VALIDATION.md) and the [Focus Native notes](docs/FOCUS-NATIVE.md).

Run the appropriate GitHub Actions workflow manually to build on a standard public macOS runner without Apple credentials. Private repositories are excluded to avoid consuming metered minutes. Action artifacts expire; release assets use the links above. See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

On a Mac with Xcode, enter `apps/<name>` and run `node scripts/build-ios.mjs`. Run `node --test` in an app directory for shared logic tests. Recreate icons with `node scripts/create-icons.mjs` and update the source manifest with `node scripts/update-source-manifest.mjs`.
