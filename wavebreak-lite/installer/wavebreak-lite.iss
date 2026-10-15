; WAVEBREAK Lite — installer for 32-bit Windows (also installs on 64-bit,
; into Program Files (x86)). Built by wavebreak-lite/build.sh, which passes
; /DMyAppVersion=<version>.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppName "WAVEBREAK Lite"
#define MyAppExeName "wavebreak-lite.exe"

[Setup]
; Its own AppId: Lite and the full Windows app are separate programs.
AppId={{6E0B7C4A-2F1D-4B8E-9A55-3C7D2E91F4A0}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=WAVEBREAK
AppPublisherURL=https://wavebreak.com.tr
DefaultDirName={autopf}\WAVEBREAK Lite
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; sing-box creates a TUN adapter and changes routes: admin either way.
PrivilegesRequired=admin
OutputDir=Output
OutputBaseFilename=WaveBreak-Lite-Setup-{#MyAppVersion}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\app_icon.ico
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Go and sing-box need Windows 10 or newer (32-bit Windows 10 included).
MinVersion=10.0
; No ArchitecturesAllowed / 64-bit mode on purpose: this is the x86 build.
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
CloseApplications=force
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\runtime_deps\sing-box.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\runtime_deps\wintun.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Run]
; As the user who ran the installer: the program asks for elevation
; itself and opens its page in that user's browser.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
; Closing the program also stops its sing-box (job object) and the tunnel.
Filename: "{sys}\taskkill.exe"; Parameters: "/IM {#MyAppExeName} /F"; Flags: runhidden; RunOnceId: "StopLite"
