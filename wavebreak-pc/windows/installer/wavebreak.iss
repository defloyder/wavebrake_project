; WAVEBREAK Windows installer — Inno Setup script.
;
; Wraps the Flutter release build (build\windows\x64\runner\Release\*,
; produced by `flutter build windows --release`) into a proper installer:
; Start Menu shortcut, optional desktop shortcut, a real uninstaller
; registered with Windows (Apps & Features), and a standard install
; wizard — instead of a raw folder of files/DLLs a user has to run
; wavebreak.exe from directly.
;
; Build with (from wavebreak-pc\):
;   flutter build windows --release
;   "C:\Users\<you>\AppData\Local\Programs\Inno Setup 6\ISCC.exe" windows\installer\wavebreak.iss
; Output lands in windows\installer\Output\WaveBreak-Setup-<version>.exe.
;
; AppVersion below is a fixed literal, not read from pubspec.yaml — Inno
; Setup's preprocessor has no built-in YAML parsing, and pulling in an
; external tool just to read one line isn't worth it for a value that
; only changes on a deliberate release. Bump it by hand alongside
; pubspec.yaml's own version when cutting a new release.
#define MyAppName "WAVEBREAK"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "WAVEBREAK"
#define MyAppURL "https://wavebreak.com.tr"
#define MyAppExeName "wavebreak.exe"
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{B1E4C1E4-3B8F-4C6F-9C3A-1D2E5A7F9B10}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
; Program Files + per-machine install — sing-box.exe needs to create a
; TUN adapter and change routes, which needs admin rights either way
; (runner.exe.manifest already requests elevation for the app itself);
; installing per-machine matches that and avoids a per-user install
; silently missing the elevation prompt on first run.
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
; A single self-contained installer exe, not an installer + a separate
; folder of loose files next to it.
OutputDir=Output
OutputBaseFilename=WaveBreak-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; No custom wizard banner/sidebar bitmaps — Inno Setup's default modern
; wizard styling (set above) already reads as a proper, professional
; installer; the app's own icon (set via SetupIconFile above) carries
; the actual WAVEBREAK branding into the installer exe, taskbar, and
; Add/Remove Programs entry, which is the branding that actually matters
; without sinking time into custom wizard artwork the product owner
; explicitly said not to over-invest in.
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Everything flutter build windows produces next to the exe — the app
; itself, flutter_windows.dll, every plugin DLL, the "data" folder
; (Dart snapshot + assets), and the bundled sing-box.exe/wintun.dll the
; real VPN tunnel needs. Recursive: "data" has its own subtree.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Standard "launch after install" checkbox, matching the wizard's own
; finish-page convention.
; runascurrentuser: the installer is already elevated (PrivilegesRequired
; above) and wavebreak.exe's own manifest also requires admin (see
; windows/runner/CMakeLists.txt's /MANIFESTUAC:level='requireAdministrator')
; — without this flag, Inno's launch tries to negotiate a SECOND elevation
; from an already-elevated process and Windows returns error 740
; (ERROR_ELEVATION_REQUIRED) instead of just starting it. This reuses the
; installer's own elevated token directly.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent runascurrentuser

[UninstallDelete]
; sing-box writes its generated config to the system temp dir at connect
; time (see WindowsVpnAdapter._writeConfig), not under {app} — nothing
; else to clean up there, but the app's own local data (secure storage,
; prefs — %APPDATA%\WAVEBREAK\WAVEBREAK) deliberately is NOT removed on
; uninstall, matching how most desktop apps treat user data vs. program
; files (a reinstall shouldn't force a fresh login).
