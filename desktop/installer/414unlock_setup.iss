; 414Unlock Windows Inno Setup Script
; Conforms to APP_UPDATE_CONTRACT.md and includes pre-install update check.

#define MyAppName "414Unlock"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "414Unlock"
#define MyAppURL "https://414unlock.pages.dev"
#define MyAppExeName "414Unlock.exe"
#define UpdateEndpoint "https://414unlock-auth-api.414unlock.workers.dev/api/app/update?version=1.0.1&platform=windows"

[Setup]
AppId={{9F82A45C-1D38-4C8D-981F-E31976A0350B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/support.html
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=414Unlock_Setup
SetupIconFile=installer_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Automatically launch 414Unlock on Windows startup (in system tray)"; GroupDescription: "Startup Options:"; Flags: checkedonce

[Files]
Source: "..\apps\unlock_iphone\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Configure auto-launch on startup always on by default in system tray
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"" --tray"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Pre-installation update check against live API
function CheckForInstallerUpdates(): Boolean;
var
  WinHttpReq: Variant;
  ResponseText: String;
  PosLatest: Integer;
  LatestVer: String;
  PosAvail: Integer;
  UpdateAvail: String;
  PosUrl: Integer;
  ReleaseUrl: String;
  Msg: String;
begin
  Result := True; // Default to allowing installation if check fails
  try
    WinHttpReq := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    WinHttpReq.Open('GET', '{#UpdateEndpoint}', False);
    WinHttpReq.SetRequestHeader('User-Agent', '414Unlock-Installer/{#MyAppVersion} (Windows)');
    WinHttpReq.SetRequestHeader('Cache-Control', 'no-store');
    WinHttpReq.SetTimeouts(3000, 5000, 5000, 5000);
    WinHttpReq.Send();

    if WinHttpReq.Status = 200 then
    begin
      ResponseText := WinHttpReq.ResponseText;

      // Check if updateAvailable: true
      PosAvail := Pos('"updateAvailable":true', ResponseText);
      if PosAvail > 0 then
      begin
        // Extract latestVersion
        PosLatest := Pos('"latestVersion":"', ResponseText);
        if PosLatest > 0 then
        begin
          LatestVer := Copy(ResponseText, PosLatest + 17, 16);
          PosLatest := Pos('"', LatestVer);
          if PosLatest > 0 then
            LatestVer := Copy(LatestVer, 1, PosLatest - 1);
        end;

        // Extract releaseUrl
        PosUrl := Pos('"releaseUrl":"', ResponseText);
        if PosUrl > 0 then
        begin
          ReleaseUrl := Copy(ResponseText, PosUrl + 14, 255);
          PosUrl := Pos('"', ReleaseUrl);
          if PosUrl > 0 then
            ReleaseUrl := Copy(ReleaseUrl, 1, PosUrl - 1);
        end;

        Msg := 'A newer version of 414Unlock is available on the server (v' + LatestVer + ').' + #13#10 + #13#10 +
               'This installer contains version {#MyAppVersion}.' + #13#10 + #13#10 +
               'Would you like to open the latest release page to download the newer version?';

        if MsgBox(Msg, mbConfirmation, MB_YESNO) = IDYES then
        begin
          if Pos('https://', ReleaseUrl) = 1 then
          begin
            // Open default browser with release URL
            ShellExec('open', ReleaseUrl, '', '', SW_SHOWNORMAL, ewNoWait, PosLatest);
          end;
          Result := False; // Cancel current installation
        end;
      end;
    end;
  except
    // Safe network fallback: do not block installation on network failure
    Result := True;
  end;
end;

function InitializeSetup(): Boolean;
begin
  Result := CheckForInstallerUpdates();
end;
