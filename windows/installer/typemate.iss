; Inno Setup script for the TypeMate Windows installer.
; Build (from the repo root, after `flutter build windows --release`):
;   ISCC.exe windows\installer\typemate.iss
; The installer lands in build\windows\installer\.

#define MyAppName "Type Mate"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "com.typemate"
#define MyAppExeName "typemate.exe"
#define MyBuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{7A3F9C41-2E8B-4D5A-9C6F-1B0E8A7D4F23}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\TypeMate
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\windows\installer
OutputBaseFilename=TypeMate-Setup-v{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
; The bundled speech models are already compressed formats; lzma2/fast
; keeps the build minutes short for a negligible size difference.
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
