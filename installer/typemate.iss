; TypeMate Windows installer (Inno Setup 6).
;
; Build (from the repo root, after `flutter build windows --release`):
;   ISCC.exe /DAppVersion=X.Y.Z installer\typemate.iss
; Output: dist\TypeMate-Setup-vX.Y.Z.exe
;
; Per-user install (no admin prompt): the app is a personal utility and
; registers its own run-at-startup entry, so nothing needs elevation.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; NEVER change AppId: upgrades match on it.
AppId={{9B7C1F62-3C63-4E8A-9B15-TypeMateWin1}
AppName=Type Mate
AppVersion={#AppVersion}
AppPublisher=TypeMate
DefaultDirName={localappdata}\TypeMate
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=TypeMate-Setup-v{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\typemate.exe
; The bundle is dominated by already-quantized models; heavy compression
; buys little and costs minutes.
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userprograms}\Type Mate"; Filename: "{app}\typemate.exe"
Name: "{userdesktop}\Type Mate"; Filename: "{app}\typemate.exe"; \
  Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; \
  GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\typemate.exe"; Description: "Launch Type Mate"; \
  Flags: nowait postinstall skipifsilent
