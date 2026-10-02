# Codex Limits

Codex Limits is a native macOS 26 menu-bar companion for the ChatGPT desktop app. It shows how much of your Codex allowance remains and when each limit resets.

The compact menu-bar label adapts to the limits returned for your account:

- Plus-style two-window response: `5h 79% · 7d 89%`
- Weekly-only response: `7d 89%`

Click the label for a Control Centre-style Liquid Glass panel with rounded allowance tiles, relative and absolute reset times, connection status, circular Refresh and Quit buttons, and glass tiles for Launch at Login and opening ChatGPT. The panel uses macOS 26's native `glassEffect`, `GlassEffectContainer`, and `.glass` button style; it follows the system appearance and accessibility settings.

The whole popup background uses native `.glassEffect(.regular)`, with SwiftUI's `.containerBackground(.clear, for: .window)` removing the ordinary window backing. Control tiles use `.regular.interactive()` glass with explicit rounded corners, and the circular buttons use `.buttonStyle(.glass)`.

## Requirements

- macOS 26
- Apple Silicon
- The latest [ChatGPT desktop app](https://chatgpt.com/download/) installed and signed in with ChatGPT authentication
- Xcode 26 and Swift 6.2 to build from source

**No separate Codex CLI installation is required.** The desktop app includes its own signed Codex app-server executable. Codex Limits uses that bundled copy directly; it does not use `codex` from your shell's PATH, Homebrew, or npm. Users who only have the desktop app can use Codex Limits.

API-key-only Codex sessions do not expose ChatGPT subscription limits.

## Install

From this repository:

```sh
./scripts/install.sh
```

The script builds a release executable, creates and ad-hoc signs a local app bundle, stops the running older version, installs it at `~/Applications/Codex Limits.app`, and opens it. It backs up an existing installation during replacement and restores it if copying fails. The app registers itself as a login item on first launch. macOS may ask you to approve it in **System Settings → General → Login Items & Extensions**.

Run the same command to update an existing installation.

Build products live in `~/Library/Caches/com.chriskane.codexlimits/build`, outside iCloud/file-provider folders. The script uses `swift build --show-bin-path` to locate the executable, so it works with current Swift build-system output layouts. No `sudo` or developer signing certificate is needed for this local installation.

## Agent installation and validation runbook

1. Work from the repository root. Inspect `git status --short` and preserve unrelated local changes. Confirm macOS 26 on Apple Silicon, a selected Xcode 26+ toolchain (`xcode-select -p` and `swift --version`), and the signed desktop app installed and signed in. Do not install a separate CLI.
2. Run the offline regression suite. Use the cache scratch path even if the repository is in Documents or iCloud Drive:

   ```sh
   swift test --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests"
   ```

3. Validate discovery, OpenAI signature verification, initialization, and two usage reads against the actual installed desktop app:

   ```sh
   CODEX_LIMITS_LIVE_TEST=1 swift test \
     --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests"
   ```

   This opt-in test requires a signed-in desktop installation and network access. It reads usage only, does not submit prompts, and stops its child app-server when finished. The live test is skipped unless the environment variable is set.

4. Install or replace the app:

   ```sh
   ./scripts/install.sh
   codesign --verify --deep --strict "$HOME/Applications/Codex Limits.app"
   pgrep -fl CodexLimits
   ```

   Require the install script to report `Installed and running`. Check that the running process is the executable inside `~/Applications/Codex Limits.app`, not a development build. The installer closes all running processes named `CodexLimits`, so finish any development session first.

5. Click the menu-bar item. Confirm percentages, reset times, glass styling, and a successful manual Refresh. Verify the Open ChatGPT tile opens the desktop app. Preserve the user's existing Launch at Login preference; do not toggle it just to test. If macOS shows an approval request, use **Approve in Login Items**. Allow at least one 15-second automatic refresh and confirm values remain available.
6. For a requested source update, update this README and bump `Resources/Info.plist`'s app version/build. Update the unbundled development client version in `CodexAppServerClient.swift` too. Run `git diff --check`, review the change, commit, and push to `origin main` when the user has authorized pushing. Do not force-push.

Version 1.1.0 was validated on desktop app **26.928.31416 (12553)** with its bundled **Codex CLI 0.159.2**. Compatibility targets the current desktop bundle layout, with no old-layout fallback.

## Development

```sh
swift test --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests"
swift run --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/build" CodexLimits
```

Running with `swift run` is useful for development but cannot register as a main-app login item because it is not inside an application bundle.

## How it works

Codex Limits locates the installed desktop app through macOS Launch Services using bundle identifier `com.openai.codex`, verifies its OpenAI code-signing identity (team `2DC432GLL2`), and launches this executable relative to that discovered app:

```text
Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
```

For a typical installation, the full path is `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`. The app name or installation folder is not hard-coded. The earlier `Contents/Resources/codex` layout is no longer supported.

It launches `app-server --listen stdio://`, connects over the documented newline-delimited [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server), performs the `initialize` / `initialized` handshake, reads `account/rateLimits/read`, and listens for `account/rateLimits/updated` notifications. A non-overlapping refresh every 15 seconds handles missed notifications and reconnects after an interruption. Relaunch Codex Limits after a desktop update to resolve the installed app again.

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

If the error says the desktop app does not contain Codex, inspect its current bundled executable location and update `UsageController.bundledCodexExecutableURL(in:)`, then run the live test and reinstall. Version 1.1.0 fixes the move from `Contents/Resources/codex` to the nested `codex-cli/CodexCLI.app` layout.

### Code signing fails with “resource fork, Finder information, or similar detritus not allowed”

File-provider folders can add Finder metadata to generated `.app` and `.xctest` bundles. Use the cache scratch paths in the runbook; the installer already does this. Do not remove metadata from source files or disable code-signature verification.

### The popup looks less transparent

The panel and buttons use Apple's [native Liquid Glass APIs](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). Their rendering follows macOS appearance and accessibility settings, including Reduce Transparency. Do not change the user's accessibility settings to force a visual effect.

## Uninstall

Turn off **Launch at Login** from the popup, quit Codex Limits, and move `~/Applications/Codex Limits.app` to the Trash.
