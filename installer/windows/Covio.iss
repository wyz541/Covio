#ifndef AppVersion
  #define AppVersion "0.6.0"
#endif

#ifndef InstallerVersion
  #define InstallerVersion "0.6.0.25"
#endif

#ifndef SourceExe
  #define SourceExe "..\..\rust\target\release\covio-windows.exe"
#endif

#ifndef IconFile
  #define IconFile "..\..\assets\windows\Covio.ico"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\build\windows-package"
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "Covio-0.6.0.25-setup"
#endif

#ifndef VersionFile
  #define VersionFile "..\..\build\windows-package\build-info.txt"
#endif

[Setup]
AppId={{AE88CA7A-4E43-462A-B2BA-096FC4D2C816}
AppName=Covio
AppVersion={#AppVersion}
AppVerName=Covio {#AppVersion}
AppPublisher=Covio
AppPublisherURL=https://github.com/wyz541/kmp-Covio
AppSupportURL=https://github.com/wyz541/kmp-Covio/issues
AppUpdatesURL=https://github.com/wyz541/kmp-Covio/releases
DefaultDirName={localappdata}\Programs\Covio
DefaultGroupName=Covio
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\Covio.exe
UninstallDisplayName=Covio
VersionInfoVersion={#InstallerVersion}
VersionInfoCompany=Covio
VersionInfoDescription=Covio Windows installer
VersionInfoProductName=Covio
VersionInfoProductVersion={#InstallerVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
AppMutex=Local\com.wyz.covio.windows

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; DestName: "Covio.exe"; Flags: ignoreversion
Source: "{#IconFile}"; DestDir: "{app}"; DestName: "Covio.ico"; Flags: ignoreversion
Source: "{#VersionFile}"; DestDir: "{app}"; DestName: "build-info.txt"; Flags: ignoreversion

[Icons]
Name: "{group}\Covio"; Filename: "{app}\Covio.exe"; IconFilename: "{app}\Covio.ico"; AppUserModelID: "com.wyz.covio"
Name: "{userdesktop}\Covio"; Filename: "{app}\Covio.exe"; IconFilename: "{app}\Covio.ico"; AppUserModelID: "com.wyz.covio"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\Covio.exe"; Parameters: "--background"; Description: "Start Covio"; Flags: nowait postinstall skipifsilent
