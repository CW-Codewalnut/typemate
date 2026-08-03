; TypeMate Windows installer (Inno Setup 6).
;
; Build via scripts/package-windows-release.sh, which stages the Release
; bundle into build\package\typemate-windows-x64 and strips the on-demand
; speech models (they download on first use) before this script packs it.
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
; The remaining bundle (binaries + small models) compresses fine at the
; fast preset; the large speech models are not shipped at all.
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Files]
Source: "..\build\package\typemate-windows-x64\*"; DestDir: "{app}"; \
  Flags: recursesubdirs ignoreversion

[InstallDelete]
; Retired in 1.4.x: English and the GTCRN denoiser run in-process now
; (sherpa_onnx plugin); the whole bin\sherpa folder is dead weight from
; older installs. The large model files from fat installs are
; deliberately KEPT on upgrade — they keep working offline and spare the
; user a re-download.
Type: filesandordirs; Name: "{app}\bin\sherpa"

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
