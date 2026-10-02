# Codex & Claude Limits

Codex & Claude Limits is a native macOS 26 menu-bar companion for Codex and Claude. It shows the remaining subscription limit and reset times for each installed provider.

The menu bar puts each provider’s logo immediately to the left of its limits: a purple-blue Codex mark and an orange Claude starburst. Limit text and separators use the system’s default menu bar appearance, while the logos keep their provider colours. Typical values look like `Codex 5h 79% · 7d 89% | Claude 5h 92% · 7d 98%`; weekly-only Codex accounts show just their returned weekly limit. Providers that are not installed are omitted, and Claude works with **Claude Desktop, Claude Code, or both**.

Click the label for a Control Centre-style Liquid Glass panel. Codex limit cards have a subtle purple-blue glass tint; Claude cards have a subtle orange tint. Progress bars retain their existing appearance, including red when limit is low. Each provider has its **own updated timestamp**, stale indicator, errors, and reset times. A failure for one leaves the other available. The panel also has a circular Refresh button and a glass Launch at Login pill, and follows system appearance and accessibility settings.

The menu-bar item is a native `NSStatusItem`. Its popup is a transparent, borderless `NSPanel`, with an AppKit `NSGlassEffectContainerView` grouping the glass surfaces. The whole popup background is an `NSGlassEffectView` using clear glass, and each limit card is a separate `NSGlassEffectView` using regular glass to keep text legible over desktop content. Refresh is a native `NSButton` with a `.glass` bezel and circular border. The larger action pills use SwiftUI's `.glass(.clear)` button style and capsule borders. All glass rendering comes from Apple's public APIs.

Clicks inside the popup keep it open. Clicking outside, pressing Escape, switching apps, or clicking the menu-bar label again dismisses it. Local and global mouse-event monitors check the popup and status-item bounds; losing key focus alone does not dismiss this nonactivating panel. Monitors are removed when the popup hides.

The panel uses a 1% alpha backing beneath the native glass so its entire area catches mouse input. A fully clear window backing allowed clicks through the composited glass to the app underneath, which also changed focus and the glass appearance. The glass itself continues to use Apple's native clear and regular materials.

## Requirements

- macOS 26 on Apple Silicon
- At least one signed-in provider:
  - [ChatGPT/Codex desktop app](https://chatgpt.com/download/) with ChatGPT subscription authentication. No separate Codex CLI is required: the app uses the signed executable bundled with the desktop app.
  - [Claude Desktop](https://claude.com/download) **or** [Claude Code](https://code.claude.com/docs/en/overview), signed in with a Claude subscription. Desktop-only users do not need to install Claude Code; Code-only users do not need Desktop.
- Xcode 26 and Swift 6.2 to build from source

Claude shows the account’s **5-hour and 7-day** limits. These are subscription limits, not local token estimates or separate quotas for Desktop and Code. When both are installed, the app tries Code first and falls back to Desktop if the Code credential is unavailable or expired. The Claude section identifies the credential source that succeeded; if the apps are signed into different accounts, it represents that source’s account.

Claude Desktop must have a saved subscription OAuth credential (opening its Code tab or usage view can establish it). If Keychain approval is needed, click Refresh in the popup to request it. Startup, reopening, and background checks never display a password dialog. API-key-only, third-party inference, and Claude Console sessions do not expose these subscription limits.

## Install

From this repository:

```sh
./scripts/install.sh
```

The script builds a release executable, creates and ad-hoc signs a local app bundle, stops the running older version, installs it at `~/Applications/Codex & Claude Limits.app`, and opens it. It backs up an existing installation during replacement and restores it if copying fails. The app registers itself as a login item on first launch. macOS may ask you to approve it in **System Settings → General → Login Items & Extensions**.

Run the same command to update an existing installation. Version 1.2.0 replaces the previous `~/Applications/Codex Limits.app` after copying the new app successfully. The bundle identifier, executable name (`CodexLimits`), preferences, and login-item identity remain stable.

Build products live in `~/Library/Caches/com.chriskane.codexlimits/build`, outside iCloud/file-provider folders. The script uses `swift build --show-bin-path` to locate the executable, so it works with current Swift build-system output layouts. No `sudo` or developer signing certificate is needed for this local installation.

## Agent installation and validation runbook

1. Work from the repository root. Inspect `git status --short` and preserve unrelated local changes. Confirm macOS 26 on Apple Silicon, a selected Xcode 26+ toolchain (`xcode-select -p` and `swift --version`), and at least one supported provider installed and signed in. Do not install a separate Codex CLI.
2. Run the offline regression suite. Use the cache scratch path even if the repository is in Documents or iCloud Drive:

   ```sh
   swift test --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests"
   ```

3. Validate the installed providers with opt-in read-only live tests. For Codex, validate discovery, OpenAI signature verification, initialization, and two usage reads:

   ```sh
   CODEX_LIMITS_LIVE_TEST=1 swift test \
     --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests"
   ```

   This opt-in test requires a signed-in desktop installation and network access. It reads usage only, does not submit prompts, and stops its child app-server when finished. The live test is skipped unless the environment variable is set.

   Validate each Claude installation independently (only enable the tests for installations available on the machine):

   ```sh
   CLAUDE_LIMITS_LIVE_TEST=1 swift test \
     --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests" \
     --filter readsDesktopLimitsWithoutCLI
   CLAUDE_CODE_LIMITS_LIVE_TEST=1 swift test \
     --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests" \
     --filter readsCodeLimitsWithoutDesktop
   ```

   These read usage using each app’s existing credential, without submitting prompts, changing login state, or printing credentials.

4. Install or replace the app:

   ```sh
   ./scripts/install.sh
   codesign --verify --deep --strict "$HOME/Applications/Codex & Claude Limits.app"
   pgrep -fl CodexLimits
   ```

   Require the install script to report `Installed and running`. Check that the running process is the executable inside `~/Applications/Codex & Claude Limits.app`, not a development build. The installer closes all running processes named `CodexLimits`, so finish any development session first.

5. Click the menu-bar item, or reopen `~/Applications/Codex & Claude Limits.app` in Finder to show the actual installed popup. A computer-use tool can attach to this native panel; use the real app for UI validation rather than compiling a separate preview. Confirm both providers’ logos sit to the left of their limits in the menu bar, that each has its own timestamp, and that Codex/Claude cards have subtle purple-blue/orange tints. Confirm percentages, reset times, glass styling over both light and dark desktop content, and a successful manual Refresh. Test physical mouse clicks on the header, limit cards, padding, and Refresh: the popup must remain open, keep its glass appearance, and Refresh must run. Put an underlying app's clickable content behind the popup and verify that interior clicks never activate it. An accessibility action or input delivered directly to the app does not validate WindowServer mouse routing. Repeat after opening the menu-bar item while another app is active. Verify Escape, clicking outside, switching apps, and clicking the menu-bar label again dismiss the popup, and that reopening restores it. Preserve the user's existing Launch at Login preference; do not toggle it just to test. If macOS shows an approval request, use **Approve in Login Items**. Allow at least one 15-second Codex refresh and one 60-second Claude refresh and confirm values remain available.
6. For a requested source update, update this README and bump `Resources/Info.plist`'s app version/build. Update the unbundled development client version in `CodexAppServerClient.swift` too. Run `git diff --check` and review the change. If the user requests a visual review before pushing, finish the local installation and validation, then wait for their explicit approval. Commit and push to `origin main` only when authorized. Do not force-push.

Version **1.2.4 (build 11)** prevents repeated background Keychain prompts, reuses approved Claude credentials in memory, keeps system-default menu bar text and separators, omits the duplicate summary from the popup, uses “limit” throughout the interface, and includes optional Claude Desktop and Claude Code support, coloured provider logos in the menu bar, subtly tinted native glass limit cards, and separate provider timestamps and errors. It retains the existing native panel, mouse routing, dismissal behavior, and login preferences. Claude Desktop’s encrypted credential format and usage endpoint are private interfaces and may need updates when Anthropic changes them.

## Development

```sh
swift test --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/tests"
swift run --scratch-path "$HOME/Library/Caches/com.chriskane.codexlimits/build" CodexLimits
```

Running with `swift run` is useful for development but cannot register as a main-app login item because it is not inside an application bundle.

## How it works

### Codex

Codex & Claude Limits locates the installed desktop app through macOS Launch Services using bundle identifier `com.openai.codex`, verifies its OpenAI code-signing identity (team `2DC432GLL2`), and launches this executable relative to that discovered app:

```text
Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
```

For a typical installation, the full path is `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`. The app name or installation folder is not hard-coded. The earlier `Contents/Resources/codex` layout is no longer supported.

It launches `app-server --listen stdio://`, connects over the documented newline-delimited [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server), performs the `initialize` / `initialized` handshake, reads `account/rateLimits/read`, and listens for `account/rateLimits/updated` notifications. A non-overlapping refresh every 15 seconds handles missed notifications and reconnects after an interruption. Relaunch Codex & Claude Limits after a desktop update to resolve the installed app again.

The server reports used percentage. Codex & Claude Limits displays remaining percentage (`100 − used`) and clamps unexpected values to 0–100. It selects the `codex` bucket, ignores unrelated buckets, and formats each returned window from its actual duration rather than assuming a subscription plan.

### Claude

Installation discovery checks the Desktop bundle identifier `com.anthropic.claudefordesktop` and Claude Code’s native, Homebrew, legacy local, and PATH locations; it does not start a model session. GUI launches do not need your shell’s PATH for the standard CLI locations.

For Claude Code, the app reads the `Claude Code-credentials` Keychain item, with `.credentials.json` as Claude Code’s file fallback. If the app process has `CLAUDE_CONFIG_DIR` set, it reads that directory and its matching Keychain service instead. For Desktop, it reads only the OAuth caches in `~/Library/Application Support/Claude/config.json`, decrypting them in memory using the `Claude Safe Storage` Keychain item. Account-tagged Desktop entries are restricted to its current account; custom endpoints and config-only scopes are excluded.

It sends a read-only request to `https://api.anthropic.com/api/oauth/usage` and maps `five_hour` and `seven_day` utilization and reset times to remaining percentages. Null or absent limits are unavailable, never treated as 100% remaining. Claude checks run at most once a minute, including manual Refresh and reopening the popup. HTTP 429 pauses retries for at least a minute and respects numeric `Retry-After` (five minutes by default). Cached values keep their original fetched timestamp, and errors preserve the last successful snapshot with a stale label. Redirects are refused.

The app leaves credential renewal to Claude. If a login expires, open the matching Claude app to let it renew, then refresh the monitor. No refresh tokens are used or modified by this app.

## Privacy

Codex & Claude Limits does not read browser cookies, inspect conversation history, submit prompts, write authentication files, store tokens, or send analytics. Codex authentication stays inside its bundled app-server. Claude credentials are read from its existing local OAuth stores and cached only in process memory until expiry or rejection, so a one-time Keychain approval can support later usage checks. Usage snapshots are kept only in memory. See [Claude’s credential-management documentation](https://code.claude.com/docs/en/authentication#credential-management) for its Keychain and file storage.

## Troubleshooting

### The Codex logo shows `—`

Click it to read the error. Confirm that ChatGPT is installed in a location macOS can discover, open it, and sign in using ChatGPT authentication. Then choose **Refresh**.

### Claude is installed but limits are unavailable

Open the installed Claude app and sign in with your subscription. For Desktop-only setups, open its Code tab or usage view to establish the subscription OAuth cache, then refresh. For Code-only setups, run `claude` and sign in. If the Claude section requests Keychain access, click Refresh to display the specific macOS approval request. Denied access is reported in the Claude section and background polling stays silent. The app reads credentials without modifying them.

Expired credentials need renewal in Claude itself. When both applications are installed, another usable credential is tried automatically. If a future Desktop update changes its private cache or encryption format, update this repository and reinstall. API billing and third-party provider sessions are not subscription quotas.

### Repeated Keychain password requests

Version 1.2.4 makes all automatic reads noninteractive using `LAContext.interactionNotAllowed`. Only the popup’s Refresh button can request an approval dialog when an uncached credential needs it. A successful one-time approval keeps the OAuth credential in process memory until expiry or rejection. Silent reads still pick up renewed credentials when persistent Keychain access is available.

[Apple explains](https://support.apple.com/en-gb/guide/keychain-access/kyca1243/mac) that **Allow** approves the current access and **Always Allow** grants persistent access. The local installer uses ad-hoc signing; its designated requirement is a code hash that changes on rebuild. An update can therefore require approval again, even after Always Allow. The app now reports this in the popup and waits for an explicit Refresh instead of repeatedly showing a password dialog. It never changes the Keychain item's access rules or saves your Keychain password.

### Claude is rate-limiting checks

The last successful values remain visible with Claude’s own stale timestamp. Let the automatic retry pause finish; repeated Refresh clicks respect the same cooldown.

### Values are marked stale

The last successful values remain visible during temporary network or app-server failures. Open the affected provider to confirm connectivity, then refresh. Codex checks run every 15 seconds and Claude checks at most once a minute, with longer pauses during rate limiting.

### Launch at Login needs approval

Use **Approve in Login Items** in the popup, or open **System Settings → General → Login Items & Extensions** and enable Codex & Claude Limits.

### A ChatGPT update changes compatibility

Codex & Claude Limits resolves the currently installed ChatGPT bundle on launch and does not pin a CLI version. If a future app-server response changes incompatibly, update this repository and reinstall rather than granting the app access to ChatGPT cookies or files.

If the error says the desktop app does not contain Codex, inspect its current bundled executable location and update `UsageController.bundledCodexExecutableURL(in:)`, then run the live test and reinstall. Version 1.1.0 fixes the move from `Contents/Resources/codex` to the nested `codex-cli/CodexCLI.app` layout.

### Code signing fails with “resource fork, Finder information, or similar detritus not allowed”

File-provider folders can add Finder metadata to generated `.app` and `.xctest` bundles. Use the cache scratch paths in the runbook; the installer already does this. Do not remove metadata from source files or disable code-signature verification.

### The popup looks less transparent

The panel and buttons use Apple's [native Liquid Glass APIs](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). Their rendering follows macOS appearance and accessibility settings, including Reduce Transparency. Do not change the user's accessibility settings to force a visual effect.

Judge glass against the actual desktop. A window-only snapshot may omit the desktop backdrop and make composited glass appear blank or flat. Use the installed popup over light and dark content when checking transparency, refraction, contrast, and pressed-button feedback. The clear outer surface lets desktop content through; the regular limit surfaces preserve text contrast.

### Clicks pass through the glass or change its appearance

Reinstall the current version. Keep the panel's nonzero backing alpha and `ignoresMouseEvents = false`; setting the latter alone does not prevent holes in a fully transparent window's mouse hit map. Global event monitors cannot cancel clicks already routed to another app.

For an agent diagnosing a regression, temporarily inspect the actual popup after it is visible with [`NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`](https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:)). Sample screen points in padding, the header, cards, and controls. With `belowWindowWithWindowNumber: 0`, each should resolve to the popup's `windowNumber` while it is frontmost, both before and after clicking. Confirm key focus stays in the panel. Remove temporary diagnostic logs before installing the final build.

## Uninstall

Turn off **Launch at Login** from the popup, quit Codex & Claude Limits using Activity Monitor or `pkill -x CodexLimits`, and move `~/Applications/Codex & Claude Limits.app` to the Trash.
