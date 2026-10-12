# Fabrique l'installateur Windows : dist\Amplyfin-<version>-installation.exe
# Il faut Flutter, Visual Studio Build Tools (C++) et Inno Setup 6.
# Lancement : powershell -ExecutionPolicy Bypass -File windows\installer\build.ps1

$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
Push-Location $root
try {
    # Version de l'appli (pubspec.yaml), sans le numéro de fabrication
    $version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value

    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "La fabrication de l'appli a échoué" }

    # Bibliothèques C++ de Microsoft fournies avec Visual Studio
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products * -property installationPath
    $crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT" |
        Sort-Object FullName | Select-Object -Last 1
    if (-not $crt) { throw "Bibliothèques C++ introuvables dans $vs" }

    $iscc = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw "Inno Setup 6 introuvable (winget install JRSoftware.InnoSetup)" }

    & $iscc "/DAppVersion=$version" "/DVcRedist=$($crt.FullName)" windows\installer\amplyfin.iss
    if ($LASTEXITCODE -ne 0) { throw "La fabrication de l'installateur a échoué" }
} finally {
    Pop-Location
}
