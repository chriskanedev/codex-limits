# Codex Limits

Codex Limits is a native macOS 26 menu-bar companion for the ChatGPT desktop app. It shows how much of your Codex allowance remains and when each limit resets.

The compact menu-bar label adapts to the limits returned for your account:

- Plus-style two-window response: `5h 79% · 7d 89%`
- Weekly-only response: `7d 89%`

Click the label for Liquid Glass progress cards, relative and absolute reset times, connection status, manual refresh, Launch at Login, and shortcuts to ChatGPT or Quit.

## Requirements

- macOS 26
- Apple Silicon
- The latest [ChatGPT desktop app](https://chatgpt.com/download/) installed and signed in with ChatGPT authentication
- Xcode 26 and Swift 6.2 to build from source

API-key-only Codex sessions do not expose ChatGPT subscription limits.

## Install

From this repository:

```sh
./scripts/install.sh
```

The script builds a release executable, creates and ad-hoc signs a local app bundle, installs it at `~/Applications/Codex Limits.app`, and opens it. The app registers itself as a login item on first launch. macOS may ask you to approve it in **System Settings → General → Login Items & Extensions**.

Run the same command to update an existing installation.

## Development

```sh
swift test
swift run CodexLimits
```

Running with `swift run` is useful for development but cannot register as a main-app login item because it is not inside an application bundle.

## How it works

Codex Limits locates the installed ChatGPT app by its bundle identifier, verifies its OpenAI code-signing identity, and launches the Codex CLI bundled inside it. It connects over the documented newline-delimited [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server), reads `account/rateLimits/read`, and listens for `account/rateLimits/updated` notifications. A non-overlapping refresh every 15 seconds handles missed notifications and reconnects after an update or interruption.

The server reports used percentage. Codex Limits displays remaining percentage (`100 − used`) and clamps unexpected values to 0–100. It selects the `codex` bucket, ignores unrelated buckets, and formats each returned window from its actual duration rather than assuming a subscription plan.

## Privacy

Codex Limits does not read browser cookies, inspect ChatGPT UI, store tokens, or send analytics. Authentication remains owned by the bundled Codex app-server. Usage data is kept only in memory.

## Troubleshooting

### The menu bar says `Codex —`

Click it to read the error. Confirm that ChatGPT is installed in a location macOS can discover, open it, and sign in using ChatGPT authentication. Then choose **Refresh**.

### Values are marked stale

The last successful values remain visible during temporary network or app-server failures. Open ChatGPT to confirm connectivity, then refresh. Automatic refresh continues every 15 seconds.

### Launch at Login needs approval

Use **Approve in Login Items** in the popup, or open **System Settings → General → Login Items & Extensions** and enable Codex Limits.

### A ChatGPT update changes compatibility

Codex Limits resolves the currently installed ChatGPT bundle on launch and does not pin a CLI version. If a future app-server response changes incompatibly, update this repository and reinstall rather than granting the app access to ChatGPT cookies or files.

## Uninstall

Turn off **Launch at Login** from the popup, quit Codex Limits, and move `~/Applications/Codex Limits.app` to the Trash.
