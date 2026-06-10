# Claude Usage Watcher

A cross-platform desktop widget that shows your Claude subscription usage at a
glance. The Windows version sits as a corner widget plus a system-tray icon; the
macOS version lives in the menu bar. Both track your 5-hour and weekly usage
limits and read Claude Code's stored OAuth credentials automatically — nothing
extra to log into.

## Install — Windows

1. Download the latest `ClaudeUsageWatcher-Setup-x.y.z.exe` from the
   [Releases](https://github.com/deltaecho801/claude-usage-watcher/releases) page.
2. Run it. Because the installer isn't code-signed, Windows SmartScreen may show
   an "unrecognized app" warning. Click **More info** then **Run anyway**.
3. If the **.NET 8 Desktop Runtime** isn't already present, the installer
   downloads and installs it automatically (this step shows one UAC prompt).

The app installs per-user (no admin rights needed) under
`%LOCALAPPDATA%\Programs\ClaudeUsageWatcher`. You can optionally enable
"Start with Windows" during install, or toggle it later from the tray menu.

## Install — macOS

1. Download the latest `ClaudeUsageWatcher-macOS-x.y.z.zip` from the
   [Releases](https://github.com/deltaecho801/claude-usage-watcher/releases) page.
2. Unzip and drag `ClaudeUsageWatcher.app` to `/Applications`.
3. On first launch, right-click the app icon and choose **Open** (the app is
   ad-hoc signed but not notarized, so Gatekeeper will warn on a normal
   double-click; right-click → Open bypasses this).
4. The first time the app reads your Claude credentials from the macOS Keychain
   you will see a permission prompt — click **Always Allow** (or **Allow**) to
   let it proceed.

Settings are stored at
`~/Library/Application Support/ClaudeUsageWatcher/settings.json`.

## Requirements

### Windows

- Windows 10 or 11 (64-bit).
- Claude Code installed and logged in with a Pro or Max subscription.
- The `.NET 8 Desktop Runtime` (installed automatically if missing).

### macOS

- macOS 13 Ventura or later (universal binary — runs natively on Apple Silicon
  and Intel).
- Claude Code installed and logged in with a Pro or Max subscription.

### Environment variables (optional, both platforms)

- `CLAUDE_CONFIG_DIR` — override the directory Claude Code config/credentials
  are read from.
- `CLAUDE_CODE_OAUTH_TOKEN` — supply an OAuth token directly instead of reading
  the stored credentials.

On macOS, credentials are resolved in this order:
1. `CLAUDE_CODE_OAUTH_TOKEN` environment variable.
2. `$CLAUDE_CONFIG_DIR/.credentials.json` or `~/.claude/.credentials.json`.
3. macOS Keychain item **"Claude Code-credentials"** (where Claude Code stores
   OAuth credentials by default — triggers a one-time Keychain permission
   prompt; click **Always Allow**).

## Development

### Windows

```sh
dotnet build
dotnet test
dotnet publish src/ClaudeUsageWatcher -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o publish
```

Build the installer locally with Inno Setup 6 (after publishing):

```sh
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.0 installer\setup.iss
```

The compiled installer lands in `installer\Output\`.

### macOS

```sh
cd macos && swift test
```

Build the app bundle (produces `macos/dist/ClaudeUsageWatcher.app`):

```sh
APP_VERSION=1.0.0 macos/Scripts/make-app.sh
```
