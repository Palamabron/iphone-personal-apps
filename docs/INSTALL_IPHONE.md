# Installation on your iPhone

Requirements: iOS 18 or later, your own Apple Account, Wi-Fi, and a USB cable for initial SideStore setup. Windows or Ubuntu is sufficient; a personal Mac and paid Apple Developer account are not required. The IPA files are unsigned; SideStore signs them with your account during installation.

## 1. Set up SideStore

Follow the current official [Windows/Ubuntu prerequisites](https://docs.sidestore.io/docs/installation/prerequisites) and [SideStore installation guide](https://docs.sidestore.io/docs/installation/install).

Windows requires iTunes or supported Apple drivers and iloader. Ubuntu requires usbmuxd and iloader. Install LocalDevVPN from the iPhone App Store. Connect the phone over USB, trust the computer when prompted, and select the stable SideStore installation in iloader.

On the phone, trust your profile in Settings → General → VPN & Device Management. Enable Settings → Privacy & Security → Developer Mode and perform the required restart. Connect LocalDevVPN, open SideStore and first refresh SideStore itself by tapping its day counter in My Apps. Prompts vary by iOS version.

## 2. Download and install the apps

Download `FocusTube-unsigned.ipa` and `TechRadar-unsigned.ipa` from the [latest release](https://github.com/Palamabron/iphone-personal-apps/releases/latest), preferably in Safari on the iPhone. They are saved in Files, usually under Downloads.

In SideStore, open My Apps, tap “+” and select the `.ipa` file. Repeat for the other app. Installation and renewal require Wi-Fi and a connected LocalDevVPN. Enter your account name and password only in installation tools, never in the repository or the app website.

The first installation on a physical iPhone remains unverified. A successful build and package inspection do not prove signing will succeed with a particular Apple Account.

## 3. Open Radar

Open Tech Radar from the home screen. Events and saved choices are stored inside the app; no website hosting login is needed. “Refresh sources” reads public pages using the phone's network. If a source restricts access, the report shows the problem and earlier data remains available. Facebook and LinkedIn listings still require manual import.

To transfer choices from the web version, expand “Your interests and data”, select “Export my data”, then select “Restore backup” in the new app and choose the JSON file. Keep the old copy until the import has been checked.

## 4. Enable the Focus Tube Safari extension

Open Focus Tube and follow the instructions. Under Settings → Apps → Safari → Extensions, enable Focus Tube and allow access to YouTube. If the Focus Tube Userscripts script is already active, keep only one copy of the filter enabled.

Enter `m.youtube.com` in a regular Safari tab. The green search screen or “filter active” label confirms activation. Use “Switch account” to change accounts. The YouTube account remains in Safari; the official YouTube app is outside the filter's scope. Premium, background playback and PiP need device testing.

## Renewal

Free signing expires after seven days. Before expiry, open SideStore on Wi-Fi, connect LocalDevVPN and refresh the apps. Do not rely solely on background refresh. Do not remove apps during normal renewal; Radar also allows data export.

The standard limit is three active apps signed with a free account, including SideStore. SideStore, Focus Tube and Tech Radar fill those three slots. The Safari extension also uses a separate App ID. See [SideStore limits and renewal](https://docs.sidestore.io/docs/faq).
