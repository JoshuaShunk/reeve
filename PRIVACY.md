# Privacy Policy

**Reeve** is designed so that your data stays yours. The app has no
backend, no account system, and collects no analytics or telemetry.

_Last updated: 2026-05-31_

## What we collect

**Nothing.** The developer does not collect, transmit, store, or have access to
any of your data. There is no analytics SDK, no advertising identifier, no
tracking, and no crash-reporting service that sends data off your device.

In App Store terms, our data collection is **"Data Not Collected."**

## Where your data lives

- **Server addresses, preferences, and app settings** are stored locally on your
  device (in `UserDefaults` / an app group shared with the widget).
- **Secrets:** Proxmox API tokens, SSH passwords, and any AI provider API key are
  stored in the device **Keychain**. They never leave your device except to
  authenticate directly with the servers you configure.

## Network connections the app makes

The app only connects to endpoints **you** configure:

- **Your Proxmox VE server(s)** and any self-hosted services you add (AdGuard,
  Jellyfin, Home Assistant, TrueNAS, Uptime Kuma, etc.), over your LAN, Tailscale,
  or the address you provide.
- **Your local network**, only when you explicitly tap to discover a server: the
  app probes the Proxmox port on your subnet to find your own server and confirm
  it is Proxmox. It does not enumerate or report other devices.
- **An AI provider you choose** (a local Ollama server, or any OpenAI-compatible
  endpoint), only if you enable the AI agent. Your prompts, and any context you
  include, are sent to that endpoint using a key you supply. Choose a provider you
  trust; their handling of your data is governed by their policy, not ours.
- **Notification channels you configure** (Discord, Slack, Telegram, or a custom
  webhook): only the alert text you opt into is sent, to the URL you provide.

No data is sent to the app developer or any third party we control.

## Permissions

- **Local Network:** to discover and connect to your servers on your LAN.
- **Face ID / Touch ID:** optional app lock; authentication happens on-device via
  the Secure Enclave. The app never sees your biometric data.
- **Microphone / Speech Recognition:** optional voice input for the AI agent.
- **Photos:** optional image input for the AI agent, via the system photo picker
  (the app only receives the image you pick; it has no broader library access).

All of these are optional and used only for the feature described.

## Children

The app is a system-administration tool and is not directed at children.

## Changes

If this policy changes, the updated version will be published in this repository.

## Contact

Questions: open an issue at
<https://github.com/joshuashunk/reeve> or email the maintainer listed
there.
