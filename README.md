# Codex Limits

Codex Limits is a native macOS 26 menu-bar companion for the ChatGPT desktop app. It shows how much of your Codex allowance remains and when each limit resets.

The compact menu-bar label adapts to the limits returned for your account:

- Plus-style two-window response: `5h 79% · 7d 89%`
- Weekly-only response: `7d 89%`

Click the label for a Control Centre-style Liquid Glass panel with rounded allowance cards, relative and absolute reset times, connection status, a circular Refresh button, and a glass Launch at Login pill. It follows the system appearance and accessibility settings.

The menu-bar item is a native `NSStatusItem`. Its popup is a transparent, borderless `NSPanel`, with an AppKit `NSGlassEffectContainerView` grouping the glass surfaces. The whole popup background is an `NSGlassEffectView` using clear glass, and each allowance card is a separate `NSGlassEffectView` using regular glass to keep text legible over desktop content. Refresh is a native `NSButton` with a `.glass` bezel and circular border. The larger action pills use SwiftUI's `.glass(.clear)` button style and capsule borders. All glass rendering comes from Apple's public APIs.

Clicks inside the popup keep it open. Clicking outside, pressing Escape, switching apps, or clicking the menu-bar label again dismisses it. Local and global mouse-event monitors check the popup and status-item bounds; losing key focus alone does not dismiss this nonactivating panel. Monitors are removed when the popup hides.

The panel uses a 1% alpha backing beneath the native glass so its entire area catches mouse input. A fully clear window backing allowed clicks through the composited glass to the app underneath, which also changed focus and the glass appearance. The glass itself continues to use Apple's native clear and regular materials.

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

5. Click the menu-bar item, or reopen `~/Applications/Codex Limits.app` in Finder to show the actual installed popup. A computer-use tool can attach to this native panel; use the real app for UI validation rather than compiling a separate preview. Confirm percentages, reset times, glass styling over both light and dark desktop content, and a successful manual Refresh. Test physical mouse clicks on the header, allowance cards, padding, and Refresh: the popup must remain open, keep its glass appearance, and Refresh must run. Put an underlying app's clickable content behind the popup and verify that interior clicks never activate it. An accessibility action or input delivered directly to the app does not validate WindowServer mouse routing. Repeat after opening the menu-bar item while another app is active. Verify Escape, clicking outside, switching apps, and clicking the menu-bar label again dismiss the popup, and that reopening restores it. Preserve the user's existing Launch at Login preference; do not toggle it just to test. If macOS shows an approval request, use **Approve in Login Items**. Allow at least one 15-second automatic refresh and confirm values remain available.
6. For a requested source update, update this README and bump `Resources/Info.plist`'s app version/build. Update the unbundled development client version in `CodexAppServerClient.swift` too. Run `git diff --check` and review the change. If the user requests a visual review before pushing, finish the local installation and validation, then wait for their explicit approval. Commit and push to `origin main` only when authorized. Do not force-push.

Version 1.1.4 targets desktop app **26.928.31416 (12553)** with its bundled **Codex CLI 0.159.2**. Compatibility targets the current desktop bundle layout, with no old-layout fallback. It replaces the earlier SwiftUI `MenuBarExtra` popup shell with the transparent native panel, native glass cards and controls. The popup handles Escape and outside clicks directly in AppKit, catches clicks across its entire background, and preserves focus during internal clicks. Refresh and Launch at Login are the remaining controls; the Quit and Open ChatGPT buttons have been removed.

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

Judge glass against the actual desktop. A window-only snapshot may omit the desktop backdrop and make composited glass appear blank or flat. Use the installed popup over light and dark content when checking transparency, refraction, contrast, and pressed-button feedback. The clear outer surface lets desktop content through; the regular allowance surfaces preserve text contrast.

### Clicks pass through the glass or change its appearance

Reinstall the current version. Keep the panel's nonzero backing alpha and `ignoresMouseEvents = false`; setting the latter alone does not prevent holes in a fully transparent window's mouse hit map. Global event monitors cannot cancel clicks already routed to another app.

For an agent diagnosing a regression, temporarily inspect the actual popup after it is visible with [`NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`](https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:)). Sample screen points in padding, the header, cards, and controls. With `belowWindowWithWindowNumber: 0`, each should resolve to the popup's `windowNumber` while it is frontmost, both before and after clicking. Confirm key focus stays in the panel. Remove temporary diagnostic logs before installing the final build.

## Uninstall

Turn off **Launch at Login** from the popup, quit Codex Limits using Activity Monitor or `pkill -x CodexLimits`, and move `~/Applications/Codex Limits.app` to the Trash.
