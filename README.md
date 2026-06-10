# Claude Usage Watcher

A small Windows desktop widget that shows your Claude subscription usage at a
glance. It sits as a corner widget plus a system-tray icon and tracks your
5-hour and weekly usage limits. It reads Claude Code's stored OAuth credentials
to query usage, so there's nothing extra to log into.

## Install

1. Download the latest `ClaudeUsageWatcher-Setup-x.y.z.exe` from the
   [Releases](https://github.com/deltaecho801/claude-usage-watcher/releases) page.
2. Run it. Because the installer isn't code-signed, Windows SmartScreen may show
   an "unrecognized app" warning. Click **More info** then **Run anyway**.
3. If the **.NET 8 Desktop Runtime** isn't already present, the installer
   downloads and installs it automatically (this step shows one UAC prompt).

The app installs per-user (no admin rights needed) under
`%LOCALAPPDATA%\Programs\ClaudeUsageWatcher`. You can optionally enable
"Start with Windows" during install, or toggle it later from the tray menu.

## Requirements

- Windows 10 or 11 (64-bit).
- Claude Code installed and logged in with a Pro or Max subscription (the app
  reads the OAuth credentials it stores).
- The `.NET 8 Desktop Runtime` (installed automatically if missing).

### Environment variables (optional)

- `CLAUDE_CONFIG_DIR` — override the directory Claude Code config/credentials
  are read from.
- `CLAUDE_CODE_OAUTH_TOKEN` — supply an OAuth token directly instead of reading
  the stored credentials.

## Development

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
