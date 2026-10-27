param(
    [switch]$SkipBuild,
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$')]
    [string]$PackageName = ('schului-windows-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [string]$CrtDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    if (-not $SkipBuild) {
        & fvm flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    }
    $releaseDirectory = Join-Path $projectRoot 'build/windows/x64/runner/Release'
    foreach ($name in @('schului.exe', 'flutter_windows.dll', 'file_selector_windows_plugin.dll', 'url_launcher_windows_plugin.dll', 'webview_windows_plugin.dll', 'WebView2Loader.dll', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets', 'data/flutter_assets/assets/legal/impressum.txt', 'data/flutter_assets/assets/legal/datenschutz.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory $name))) {
            throw "Release file missing: $name. Run fvm flutter build windows --release."
        }
    }
    # App-local Visual C++ runtime, from the same Visual Studio used by CMake.
    # See https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows
    $crtNames = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
    $missingCrt = @($crtNames | Where-Object { -not (Test-Path -LiteralPath (Join-Path $releaseDirectory $_)) })
    if ($missingCrt.Count -gt 0 -or $CrtDirectory) {
        if (-not $CrtDirectory) {
            $instance = Select-String -LiteralPath 'build/windows/x64/CMakeCache.txt' -Pattern '^CMAKE_GENERATOR_INSTANCE:INTERNAL='
            if (-not $instance) { throw 'Visual Studio instance missing from CMake cache; pass -CrtDirectory.' }
            $redistRoot = Join-Path $instance.Line.Split('=', 2)[1] 'VC/Redist/MSVC'
            $versions = Get-ChildItem -LiteralPath $redistRoot -Directory |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
                Sort-Object { [version]$_.Name } -Descending
            foreach ($version in $versions) {
                $candidates = Get-ChildItem -LiteralPath (Join-Path $version.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT'
                foreach ($candidate in $candidates) {
                    if (@($crtNames | Where-Object { -not (Test-Path -LiteralPath (Join-Path $candidate.FullName $_)) }).Count -eq 0) {
                        $CrtDirectory = $candidate.FullName
                        break
                    }
                }
                if ($CrtDirectory) { break }
            }
        }
        if (-not $CrtDirectory) { throw 'Visual C++ x64 redistributable DLLs not found; pass -CrtDirectory.' }
        foreach ($name in $crtNames) {
            if (-not (Test-Path -LiteralPath (Join-Path $CrtDirectory $name))) { throw "Visual C++ runtime file missing: $name" }
        }
    }
    $packageDirectory = Join-Path $projectRoot ('build/packages/' + $PackageName)
    $archivePath = $packageDirectory + '.zip'
    if ((Test-Path -LiteralPath $packageDirectory) -or (Test-Path -LiteralPath $archivePath)) {
        throw "Package already exists: $PackageName. Choose another package name."
    }
    New-Item -ItemType Directory -Path $packageDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $releaseDirectory 'schului.exe') -Destination $packageDirectory
    Get-ChildItem -LiteralPath $releaseDirectory -File -Filter '*.dll' | Copy-Item -Destination $packageDirectory
    if ($CrtDirectory) {
        Get-ChildItem -LiteralPath $CrtDirectory -File -Filter '*.dll' | Copy-Item -Destination $packageDirectory
    }
    Copy-Item -LiteralPath (Join-Path $releaseDirectory 'data') -Destination $packageDirectory -Recurse
    $nativeAssets = Join-Path $releaseDirectory 'native_assets.json'
    if (Test-Path -LiteralPath $nativeAssets) {
        Copy-Item -LiteralPath $nativeAssets -Destination $packageDirectory
    }
    foreach ($name in @('LICENSE', 'START-HIER.txt')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $packageDirectory
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-inspector.cmd') -Destination $packageDirectory
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-lernen.bat') -Destination $packageDirectory
    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $archivePath
    # Check the distributable itself, including both launchers and the AOT data.
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        foreach ($name in @('schului.exe', 'flutter_windows.dll', 'file_selector_windows_plugin.dll', 'url_launcher_windows_plugin.dll', 'webview_windows_plugin.dll', 'WebView2Loader.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets/AssetManifest.bin', 'data/flutter_assets/assets/legal/impressum.txt', 'data/flutter_assets/assets/legal/datenschutz.txt', 'start-lernen.bat', 'start-inspector.cmd', 'LICENSE', 'START-HIER.txt')) {
            if ($entries -notcontains "$PackageName/$name") { throw "ZIP entry missing: $name" }
        }
    } finally {
        $zip.Dispose()
    }
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumName = [System.IO.Path]::GetFileName($archivePath)
    [System.IO.File]::WriteAllText("$archivePath.sha256", "$hash  $checksumName`n", [System.Text.UTF8Encoding]::new($false))
    Write-Output $archivePath
} finally {
    Pop-Location
}
