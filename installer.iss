#define AppName "PreTra"
#define AppVersion "1.0.0"
#define AppExeName "breathe_garden_flutter.exe"

[Setup]
AppId={{A6F40A83-3269-4D32-9AE1-9A0DE4A8D80C}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=PreTra
DefaultDirName={localappdata}\Programs\PreTra
DefaultGroupName=PreTra
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=dist
OutputBaseFilename=PreTra-Setup-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb,*.exp,*.lib,*.ilk,.env"
; PreTra reads .env beside the installed executable. This local file is ignored by Git.
Source: ".env"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\PreTra"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\PreTra"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch PreTra"; Flags: postinstall nowait skipifsilent
