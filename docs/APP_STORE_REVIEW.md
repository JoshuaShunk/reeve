# App Store submission & review guide

Everything needed to get Reeve through App Review cleanly. Work top to bottom; the
**Open items** at the end are the only things not already handled in code/config.

## 1. App Review notes (paste into App Store Connect → App Review Information)

> Reeve is a client for **Proxmox VE**, a self-hosted virtualization server. It has
> **no account system and no backend**. The user points it at their own Proxmox
> server using a read-only API token. There is nothing to sign into and no data is
> collected.
>
> **To review the full functionality you need a Proxmox VE server to connect to.**
> Because that requires self-hosted hardware, we provide a built-in **Demo Mode**:
> on the server list, tap **"Try Demo"** to load a simulated server with sample
> nodes, VMs, containers, metrics, and tasks, so every screen can be exercised
> without real hardware. _(See Open item #1 if Demo Mode is not yet shipped; until
> then, attach a screen-recording walkthrough here instead.)_
>
> Features that talk to live infrastructure (SSH terminal, VNC console, the AI
> agent) require a real server and are demonstrated in the attached video.
>
> No demo account or credentials are required because the app has no login.

## 2. Export compliance (encryption)

- `ITSAppUsesNonExemptEncryption = false` is set in `AppInfo.plist`. Rationale: the
  app's encryption is limited to HTTPS/TLS, an SSH secure channel for remote
  administration, and standard authentication crypto, all via system or standard
  libraries, which are exempt.
- **Confirm this matches your stance.** Because the app includes an SSH client, if
  you treat that as non-exempt you would instead answer "Yes" to the encryption
  question. A general-purpose SSH/remote-admin tool typically qualifies for the
  **mass-market exemption (ECCN 5D992)**, which may warrant a one-time or annual
  **self-classification report to the U.S. BIS**. This is a paperwork step, not a
  code change. When in doubt, consult Apple's
  [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

## 3. App Privacy "nutrition label" (App Store Connect → App Privacy)

- Select **"Data Not Collected."** The app has no analytics, no tracking, and no
  developer backend. This matches `PrivacyInfo.xcprivacy` (`NSPrivacyTracking =
  false`, empty `NSPrivacyCollectedDataTypes`).
- **Privacy Policy URL:** host `PRIVACY.md` (e.g. the repo's raw URL or a GitHub
  Pages link) and paste it into the Privacy Policy field. Required even when no data
  is collected.

## 4. Privacy manifest & required-reason APIs (done)

- `App/PrivacyInfo.xcprivacy` and `Widget/PrivacyInfo.xcprivacy` declare
  `NSPrivacyAccessedAPICategoryUserDefaults` with reason **CA92.1**.
- No other required-reason APIs are used (verified: no disk-space, system-boot-time,
  or file-timestamp APIs).
- **Third-party SDK manifests:** the SSH-console dependencies
  [Citadel](https://github.com/orlandos-nl/Citadel) and
  [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) do not yet ship their own
  `PrivacyInfo.xcprivacy`. This only matters at App Store submission (a local build
  or sideload is unaffected). If Apple flags it, the options are to contribute a
  manifest upstream, vendor a patched copy, or build without the SSH-console feature.

## 5. Usage description strings (done)

Set via `INFOPLIST_KEY_*` in the project:

- `NSLocalNetworkUsageDescription`: server discovery.
- `NSFaceIDUsageDescription`: optional app lock.
- `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`: agent voice input.
- Photos: **not required**. Image input uses the out-of-process `PhotosPicker`.
- Camera: **not required**. The app never captures from the camera.

## 6. Local network / discovery (Guideline 5.1.2) (done)

Discovery is single-purpose: it probes **only the Proxmox port (8006)**, then
**validates each responder is genuinely Proxmox** before showing it, so it never
presents a directory of third-party devices. It runs only inside the user-initiated
"Add Server" flow, with manual entry as an alternative. See `LANScanner.swift`.

## 7. Other guideline checks

- **2.1 Completeness:** see Demo Mode (Open #1). Test on-device first.
- **3.1.1 In-App Purchase:** none; the app is free and open-source. No external purchase links.
- **4.5.4 Notifications:** local notifications plus user-configured webhooks only, opt-in.
- **5.1.1(v) Account deletion / Sign in with Apple:** N/A, no accounts.
- **App Tracking Transparency:** N/A, no tracking or IDFA, so no `NSUserTrackingUsageDescription`.
- **Background modes:** only `BGTaskSchedulerPermittedIdentifiers` is declared (for
  the iOS 26 `BGContinuedProcessingTask`); no unused `UIBackgroundModes`.

## Open items (not yet in code)

1. **Demo Mode (highest priority).** Reviewers cannot test without a Proxmox server.
   Either ship an in-app Demo Mode with canned data (recommended: robust, and
   reusable for screenshots and marketing) **or** attach a full screen-recording to
   the review notes on every submission. Demo Mode is the safer, one-time fix.
2. **Host the Privacy Policy** and add its URL in App Store Connect.
3. **Confirm the export-compliance answer** (section 2) for your situation.
4. **Screenshots** for every supported device size. The **App Store description**
   should state that it requires the user's own Proxmox server, which sets reviewer
   and user expectations.
