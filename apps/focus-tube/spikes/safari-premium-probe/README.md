# Internal Safari playback probe

This isolated development experiment tests a possible way to use a YouTube
Premium account in an iOS system browser presented within an app. It is not a
Focus Tube release, and it is not a solution to Shorts or endless scrolling:
the filter does not run in the system view and YouTube may show either. Do not
ship this probe as the user-facing product.

The app opens only public YouTube URLs using `SFSafariViewController`. It has no
scripts, cookie access, external analytics, account APIs or password handling.
Apple states that apps cannot inspect the browsing data or interact with the
page. Do not assume that signing in here signs the user into Focus Tube's
WKWebView or provides access to subscriptions. Google documents that Premium
may work in another app's lightweight browser after signing in there; this
specific configuration and the user's device have not been tested.

## Build for a device

On a Mac with Xcode and Node.js 22 or later, run from this folder:

```
node build.mjs
```

This produces `build/PremiumProbe-unsigned.ipa`. Sign and install it using the
user's own sideloading workflow if a physical test is desired. It uses bundle ID
`dev.palamabron.focustube.premiumprobe`, separate from Focus Tube, so it does
not intentionally replace it; free-account sideloading limits may apply. It
does not alter the production app or automate certificate changes.

## Manual iPhone test

1. Open **Open YouTube account** and sign into the YouTube Premium account if
   needed. Check whether YouTube displays the Premium logo. Do not record or
   share the password, authentication codes, cookies, or account details.
2. Dismiss the system view. Open **Open regular video page** and play the
   long-form video. Note whether playback starts and whether ads are shown.
3. Dismiss it, then repeat with **Open embedded player**. Record whether it
   plays, is signed in, and shows ads. A lack of ads on a single video does not
   establish Premium access; the logo or account status is stronger evidence.
4. Close and reopen the probe, then repeat one check to see if the session is
   retained. Separately test whether installed Safari content blockers or the
   Userscripts extension run in this system view; neither is assumed.

Pass/fail results should distinguish account access, actual playback, apparent
Premium status, session persistence and filtering. This test does not verify
offline downloads, background playback, Shorts blocking or new-video feeds.

Primary references: [Apple system browser documentation](https://developer.apple.com/documentation/SafariServices/SFSafariViewController?changes=_2),
[YouTube Premium in another app](https://support.google.com/youtube/answer/7437519?co=GENIE.Platform%3DiOS&hl=en).

Status: source only. Neither an iOS build, simulator nor iPhone test has been
performed for this probe.
