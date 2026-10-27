param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Release')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $cachePath = 'build/windows/x64/CMakeCache.txt'
    if (-not (Test-Path -LiteralPath $cachePath)) {
        throw 'Build Windows first: fvm flutter build windows --release.'
    }
    $cmakeEntry = Select-String -LiteralPath $cachePath -Pattern '^CMAKE_COMMAND:INTERNAL='
    if (-not $cmakeEntry) { throw 'CMake executable missing from build configuration.' }
    $nativeCmake = $cmakeEntry.Line.Split('=', 2)[1]
    & $nativeCmake --build build/windows/x64 --config $Configuration --target captured_path_test application_config_test
    if ($LASTEXITCODE -ne 0) { throw 'Native regression test build failed.' }
    foreach ($name in @('captured_path_test', 'application_config_test')) {
        & (Join-Path $projectRoot "build/windows/x64/tests/$Configuration/$name.exe")
        if ($LASTEXITCODE -ne 0) { throw "Native test failed: $name" }
    }
} finally {
    Pop-Location
}
