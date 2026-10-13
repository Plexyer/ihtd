; Compile with scripts/package-windows.ps1. Versions come from pubspec.yaml.
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef AppBuild
  #error AppBuild is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
; Permanent identity: do not change this GUID between upgrades.
AppId={{E216F57E-504E-43AB-8536-FC8509C1A40D}
AppName=IHTD
AppVersion={#AppVersion}
AppPublisher=Plexyer
AppPublisherURL=https://github.com/Plexyer/ihtd
AppSupportURL=https://github.com/Plexyer/ihtd/issues
VersionInfoVersion={#AppVersion}.{#AppBuild}
DefaultDirName={localappdata}\Programs\IHTD
DefaultGroupName=IHTD
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 11 is the product target; Server 2022 is used for native CI checks.
MinVersion=10.0.19041
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes
UninstallDisplayIcon={app}\ihtd.exe
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=IHTD-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=yes
CloseApplications=yes
CloseApplicationsFilter=ihtd.exe,*.dll
RestartApplications=no
; Inno's uninstall log removes only installed files, registry and shortcuts.
; No deletion rule may target collections or the application support directory.

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked
Name: "fileassociation"; Description: "Register IHTD for .ihtd collection files"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\IHTD"; Filename: "{app}\ihtd.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\IHTD"; Filename: "{app}\ihtd.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Advertise an Open-with handler without replacing another app's default or
; Windows UserChoice. Windows lets the user select the default application.
Root: HKCU; Subkey: "Software\Classes\.ihtd\OpenWithProgids"; ValueType: none; ValueName: "IHTD.Collection"; Flags: uninsdeletevalue; Tasks: fileassociation
Root: HKCU; Subkey: "Software\Classes\IHTD.Collection"; ValueType: string; ValueName: ""; ValueData: "IHTD collection"; Flags: uninsdeletekey; Tasks: fileassociation
Root: HKCU; Subkey: "Software\Classes\IHTD.Collection\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\ihtd.exe,0"; Tasks: fileassociation
Root: HKCU; Subkey: "Software\Classes\IHTD.Collection\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\ihtd.exe"" ""%1"""; Tasks: fileassociation

[Run]
Filename: "{app}\ihtd.exe"; Description: "Open IHTD"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
