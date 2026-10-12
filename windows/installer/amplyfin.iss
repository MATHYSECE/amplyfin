; Installateur Windows d'Amplyfin (Inno Setup 6).
; À lancer avec windows\installer\build.ps1, qui fabrique d'abord l'appli
; et donne la version (pubspec.yaml) et le dossier des bibliothèques C++.
; Résultat : dist\Amplyfin-<version>-installation.exe

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef VcRedist
  #error "Dossier des bibliothèques C++ de Microsoft manquant (passer par build.ps1)"
#endif

#define Root "..\.."
#define Release Root + "\build\windows\x64\runner\Release"

[Setup]
; Ne jamais changer : c'est ce qui fait reconnaître une installation
; existante (mise à jour par-dessus, désinstallation)
AppId={{6A9B0717-EBA5-4C72-BD90-090F98FD7408}
AppName=Amplyfin
AppVersion={#AppVersion}
AppPublisher=Mathys Picheret
; Installé pour la personne seulement (pas besoin d'être administrateur) :
; dans %LOCALAPPDATA%\Programs\Amplyfin
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\Amplyfin
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#Root}\dist
OutputBaseFilename=Amplyfin-{#AppVersion}-installation
SetupIconFile={#Root}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\amplyfin.exe
UninstallDisplayName=Amplyfin
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Appli ouverte pendant une mise à jour : proposée à la fermeture
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Mise à jour : les fichiers de l'ancienne version de l'appli sont retirés
; (les comptes, réglages et téléchargements sont ailleurs et restent)
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bibliothèques C++ de Microsoft, à côté de l'appli : elle démarre même sur
; un PC où elles ne sont pas installées
Source: "{#VcRedist}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedist}\msvcp140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedist}\msvcp140_2.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedist}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedist}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Amplyfin"; Filename: "{app}\amplyfin.exe"
Name: "{autodesktop}\Amplyfin"; Filename: "{app}\amplyfin.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\amplyfin.exe"; Description: "{cm:LaunchProgram,Amplyfin}"; Flags: nowait postinstall skipifsilent
