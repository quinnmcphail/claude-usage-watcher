; Inno Setup 6 script for Claude Usage Watcher
; CI passes the version with /DAppVersion=x.y.z ; fall back to 1.0.0 for local builds.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
; Fixed AppId GUID - must never change across releases so upgrades are detected.
AppId={{8F3A6C2E-5B41-4D9A-9E7C-1A2B3C4D5E6F}
AppName=Claude Usage Watcher
AppVersion={#AppVersion}
AppVerName=Claude Usage Watcher {#AppVersion}
AppPublisher=deltaecho801
; Per-user install: no admin rights, no UAC prompt for the app itself.
PrivilegesRequired=lowest
; Under PrivilegesRequired=lowest, {autopf} resolves to %LOCALAPPDATA%\Programs.
DefaultDirName={autopf}\ClaudeUsageWatcher
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=ClaudeUsageWatcher-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\ClaudeUsageWatcher.exe
MinVersion=10.0

[Files]
; Pull in the entire published output (publish/ sits at the repo root, one level up from installer/).
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Start with Windows"; Flags: unchecked

[Icons]
Name: "{autoprograms}\Claude Usage Watcher"; Filename: "{app}\ClaudeUsageWatcher.exe"
Name: "{autodesktop}\Claude Usage Watcher"; Filename: "{app}\ClaudeUsageWatcher.exe"; Tasks: desktopicon

[Registry]
; Only write the autostart Run value when the user opted into the task.
; uninsdeletevalue removes it on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "ClaudeUsageWatcher"; ValueData: """{app}\ClaudeUsageWatcher.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\ClaudeUsageWatcher.exe"; Description: "{cm:LaunchProgram,Claude Usage Watcher}"; Flags: nowait postinstall skipifsilent

[Code]
var
  DownloadPage: TDownloadWizardPage;

{ ----------------------------------------------------------------------------
  Kill any running instance so files aren't locked during install/uninstall.
  Runs taskkill silently and ignores any failure (it's perfectly fine if the
  app isn't running). A short Sleep gives Windows time to release file handles.
  ---------------------------------------------------------------------------- }
procedure KillRunningApp;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{cmd}'), '/C taskkill /f /im ClaudeUsageWatcher.exe',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Ignore ResultCode: nonzero just means the process wasn't running.
  Sleep(500);
end;

{ ----------------------------------------------------------------------------
  .NET 8 Desktop Runtime detection.
  The .NET installer records Desktop runtimes as value names under the 32-bit
  registry view (verified on a real machine - the key lives under WOW6432Node):
    HKLM\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App
  Each value name is a full version string (e.g. "8.0.28"). HKLM32 maps
  SOFTWARE\dotnet\... to the WOW6432Node path. Return True if any value name
  starts with "8.". Any failure / missing key = "not installed" (False).
  ---------------------------------------------------------------------------- }
function IsDotNet8DesktopInstalled: Boolean;
var
  Names: TArrayOfString;
  I: Integer;
begin
  Result := False;
  if RegGetValueNames(HKLM32,
    'SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App',
    Names) then
  begin
    for I := 0 to GetArrayLength(Names) - 1 do
    begin
      if Copy(Names[I], 1, 2) = '8.' then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
end;

{ DownloadPage progress callback (from the official CodeDownloadFiles.iss sample). }
function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  if Progress = ProgressMax then
    Log(Format('Successfully downloaded file to {tmp}: %s', [FileName]));
  Result := True;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), SetupMessage(msgPreparingDesc), @OnDownloadProgress);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
begin
  // Only act on the Ready page, and only when the runtime is actually missing.
  if (CurPageID = wpReady) and (not IsDotNet8DesktopInstalled) then
  begin
    DownloadPage.Clear;
    // Evergreen MS link that always resolves to the latest .NET 8 Desktop x64 runtime.
    DownloadPage.Add('https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe', 'windowsdesktop-runtime.exe', '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download; // raises an exception on failure or user cancel
        // Run the runtime installer. NOTE: this triggers ONE UAC prompt on machines
        // lacking the runtime - that is expected and acceptable for a per-user app.
        if not Exec(ExpandConstant('{tmp}\windowsdesktop-runtime.exe'),
          '/install /quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
        begin
          MsgBox('Failed to launch the .NET 8 Desktop Runtime installer. Setup cannot continue.',
            mbCriticalError, MB_OK);
          Result := False;
          Exit;
        end;
        // 0 = success, 3010 = success but reboot required. Anything else is a failure.
        if (ResultCode <> 0) and (ResultCode <> 3010) then
        begin
          MsgBox(Format('The .NET 8 Desktop Runtime installer failed (exit code %d). Setup cannot continue.', [ResultCode]),
            mbCriticalError, MB_OK);
          Result := False;
          Exit;
        end;
        Result := True;
      except
        // Download failed or was cancelled by the user.
        if DownloadPage.AbortedByUser then
          Log('Download aborted by user.')
        else
          MsgBox(AddPeriod(GetExceptionMessage), mbCriticalError, MB_OK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;
  end
  else
    Result := True;
end;

{ Make sure the app is closed before we copy files over it. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillRunningApp;
  Result := '';
end;

{ Make sure the app is closed before uninstall removes its files. }
function InitializeUninstall: Boolean;
begin
  KillRunningApp;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    // The app's own tray toggle may have created this Run value even if the
    // install task didn't, so remove it directly (guarded) during uninstall.
    if RegValueExists(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'ClaudeUsageWatcher') then
      RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'ClaudeUsageWatcher');
  end;
end;
