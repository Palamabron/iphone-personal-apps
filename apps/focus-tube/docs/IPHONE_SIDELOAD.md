# iPhone without a personal Mac

Status: 21 October 2026. The Xcode app and extension build and IPA validation passed. [Download the package and instructions](https://github.com/Palamabron/iphone-personal-apps). SideStore signing, simulator and physical iPhone tests remain outstanding. The original repository remains private; selected sources were published in a separate repository with the owner's consent.

## Selected Focus Tube option

A custom iOS app containing a Safari extension, built from the same filter as Userscripts. Installing the IPA replaces the Userscripts manager and manual JavaScript file transfer. Viewing remains in Safari and therefore uses the same YouTube account session. This is not an in-app video player or an overlay for the official YouTube app.

The Xcode packager generates an app container and extension. The package has a Polish setup screen and icons. The phone must be used to verify SideStore signing of the extension, launch, and the MAIN context in the target Safari version. Compilation alone does not establish Premium support. [Build report and known generator warning](https://github.com/Palamabron/iphone-personal-apps/blob/main/docs/BUILD-VALIDATION.md).

## Building without a company MacBook

- `node scripts/build-ios.mjs` runs on macOS with Xcode. It creates a project in a new local `build/ios/` folder, builds for a device, and packages an unsigned IPA.
- The `iPhone IPA (zero paid runners)` workflow uses standard `macos-15` in GitHub Actions and runs only when manually triggered.
- While the repository is private, the job is intentionally skipped. No paid minutes were used and repository visibility was not changed.
- Standard runners are free in public repositories under GitHub's current rules. Changing visibility requires the user's decision; a separate public repository containing only sanitized build sources and no history is another option.
- Private alternatives include a self-hosted macOS runner or a verified free Actions allowance and hard spending limit. Do not set account-wide budgets without consent.

No Apple ID, password, certificate, or provisioning profile is sent to GitHub. The user signs the package during installation.

## Installing the IPA

1. Install SideStore on your Windows or Ubuntu computer using its official guide, initially over USB.
2. Enable Developer Mode and trust your profile on the iPhone. Current SideStore instructions use LocalDevVPN and Wi-Fi.
3. Download the IPA artifact from a successful build, unpack the artifact ZIP, and import the `.ipa` in SideStore. Signing requires your Apple Account; do not share the password in this conversation.
4. Enable the Focus Tube extension in Safari settings and allow access to YouTube. Disable the old copy of the same filter in Userscripts first so the two filters do not conflict.
5. Refresh the app before seven days have passed. Automatic renewal is not guaranteed. SideStore occupies one of the three standard app slots; Focus Tube and Radar would occupy the remaining two. The extension also consumes its own App ID.

## Sources

- Apple Personal Team: https://developer.apple.com/help/account/basics/about-your-developer-account
- Safari packager: https://developer.apple.com/documentation/safariservices/packaging-a-web-extension-for-safari
- GitHub Actions and costs: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- SideStore installation: https://docs.sidestore.io/docs/installation/install
- Prerequisites: https://docs.sidestore.io/docs/installation/prerequisites
