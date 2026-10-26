param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    if (-not $SkipBuild) {
        & fvm flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    }
    $releaseDirectory = Join-Path $projectRoot 'build/windows/x64/runner/Release'
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory 'schului.exe'))) {
        throw 'Release build missing. Run fvm flutter build windows --release.'
    }
    $packageName = 'schului-windows-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    $packageDirectory = Join-Path $projectRoot ('build/packages/' + $packageName)
    New-Item -ItemType Directory -Path $packageDirectory | Out-Null
    Get-ChildItem -LiteralPath $releaseDirectory | Copy-Item -Destination $packageDirectory -Recurse
    Copy-Item -LiteralPath (Join-Path $projectRoot 'examples') -Destination $packageDirectory -Recurse
    foreach ($name in @('LICENSE', 'START-HIER.txt')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $packageDirectory
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-example.cmd') -Destination (Join-Path $packageDirectory 'start-beispiel.cmd')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-inspector.cmd') -Destination $packageDirectory
    $archivePath = $packageDirectory + '.zip'
    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $archivePath
    Write-Output $archivePath
} finally {
    Pop-Location
}
