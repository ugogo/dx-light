# Create a Desktop shortcut to DX Light (no bash required).
param(
    [ValidateSet("Desktop", "StartMenu", "Both")]
    [string]$Location = "Desktop",
    [switch]$BuildIfMissing
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TrayProject = Join-Path $Root "Windows\DXLight.Tray\DXLight.Tray.csproj"
$ReleaseExe = Join-Path $Root "Windows\DXLight.Tray\bin\Release\net8.0-windows\DXLight.Tray.exe"
$DebugExe = Join-Path $Root "Windows\DXLight.Tray\bin\Debug\net8.0-windows\DXLight.Tray.exe"

function Get-TrayExe {
    if (Test-Path $ReleaseExe) { return $ReleaseExe }
    if (Test-Path $DebugExe) { return $DebugExe }
    return $null
}

$exe = $null
if (Test-Path $ReleaseExe) {
    $exe = $ReleaseExe
} elseif ($BuildIfMissing) {
    Write-Host "Building DX Light (Release)..."
    Push-Location $Root
    try {
        dotnet build $TrayProject -c Release --nologo -v q
    } finally {
        Pop-Location
    }
    if (Test-Path $ReleaseExe) {
        $exe = $ReleaseExe
    }
}
if (-not $exe) {
    $exe = Get-TrayExe
}

if (-not $exe) {
    throw @"
DX Light is not built yet. Run one of:
  npm run windows:build
  pwsh -File scripts/create-shortcut.ps1 -BuildIfMissing
"@
}

$exe = (Resolve-Path $exe).Path
$workDir = Split-Path $exe -Parent
$shortcutName = "DX Light.lnk"

function New-DXLightShortcut([string]$Folder) {
    $path = Join-Path $Folder $shortcutName
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = $exe
    $link.WorkingDirectory = $workDir
    $link.Description = "Control Robobloq DX Light LED strip"
    $link.Save()
    Write-Host "Created: $path"
    return $path
}

$created = @()
if ($Location -eq "Desktop" -or $Location -eq "Both") {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $created += New-DXLightShortcut $desktop
}
if ($Location -eq "StartMenu" -or $Location -eq "Both") {
    $programs = [Environment]::GetFolderPath("Programs")
    $folder = Join-Path $programs "DX Light"
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $created += New-DXLightShortcut $folder
}

$created
