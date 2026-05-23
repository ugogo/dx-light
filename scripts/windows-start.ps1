# Build (if needed) and launch DX Light tray app on Windows.
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

$exe = Get-TrayExe
if (-not $exe) {
    Write-Host "Building DX Light (Release)..."
    Push-Location $Root
    try {
        dotnet build $TrayProject -c Release --nologo -v q
    } finally {
        Pop-Location
    }
    $exe = Get-TrayExe
    if (-not $exe) {
        throw "Tray executable not found after build. Expected: $ReleaseExe"
    }
}

$running = Get-Process -Name "DXLight.Tray" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "DX Light is already running."
    exit 0
}

Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent)
Write-Host "Started DX Light."
