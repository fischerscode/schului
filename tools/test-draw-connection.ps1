param(
  [string]$OfficePath = 'C:\Program Files\LibreOffice\program\soffice.exe',
  [string]$AppPath = "$PSScriptRoot\..\build\windows\x64\runner\Release\schului.exe",
  [string]$LauncherPath = "$PSScriptRoot\..\build\connection-test\startup_launcher.exe"
)
$ErrorActionPreference = 'Stop'
$resolvedApp = (Resolve-Path -LiteralPath $AppPath).Path
$resolvedLauncher = (Resolve-Path -LiteralPath $LauncherPath).Path
$previousLauncher = $env:SCHULUI_DRAW_PATH
$previousOffice = $env:SCHULUI_TEST_OFFICE
try {
  $env:SCHULUI_DRAW_PATH = $resolvedLauncher
  $env:SCHULUI_TEST_OFFICE = (Resolve-Path -LiteralPath $OfficePath).Path
  $started = [DateTime]::UtcNow
  $app = Start-Process -FilePath $resolvedApp -ArgumentList '--smoke-test' -WindowStyle Hidden -PassThru
  if (-not $app.WaitForExit(60000)) { throw 'Smoke-Test hat nach 60 Sekunden nicht beendet.' }
  $reportPath = Join-Path (Split-Path -Parent $resolvedApp) 'smoke-test.txt'
  $report = Get-Item -LiteralPath $reportPath
  if ($report.LastWriteTimeUtc -lt $started) { throw 'Kein neuer Testbericht.' }
  $values = @{}
  Get-Content -LiteralPath $reportPath | ForEach-Object {
    $parts = $_.Split('=', 2)
    if ($parts.Length -eq 2) { $values[$parts[0]] = $parts[1] }
  }
  if ($values['connected'] -ne '1' -or $values['connection_method'] -ne 'pidfile' -or $values['accessibility_ready'] -ne '1' -or [int]$values['node_count'] -le 0) {
    throw "Verbindungstest fehlgeschlagen. Bericht: $reportPath"
  }
  $workArea = @($values['work_area'].Split(',') | ForEach-Object { [int]$_ })
  $split = $workArea[0] + [int][Math]::Floor(($workArea[2] - $workArea[0]) / 4)
  $expectedLesson = @($workArea[0], $workArea[1], $split, $workArea[3]) -join ','
  $expectedDraw = @($split, $workArea[1], $workArea[2], $workArea[3]) -join ','
  if ($values['lesson'] -ne $expectedLesson -or $values['draw'] -ne $expectedDraw -or $values['overlay'] -ne $expectedDraw) {
    throw "Fenster passen nicht in den Arbeitsbereich oberhalb der Taskleiste. Bericht: $reportPath"
  }
  $diagnostics = @{}
  $diagnosticPath = Join-Path (Split-Path -Parent $resolvedApp) 'connection-diagnostics.txt'
  Get-Content -LiteralPath $diagnosticPath | ForEach-Object {
    $parts = $_.Split('=', 2)
    if ($parts.Length -eq 2) { $diagnostics[$parts[0]] = $parts[1] }
  }
  if ($diagnostics['placement_error'] -ne '0') { throw 'Draw konnte nicht angeordnet werden.' }
  $profileFile = Join-Path (Split-Path -Parent $diagnostics['pid_file']) 'user/registrymodifications.xcu'
  [xml]$profile = Get-Content -LiteralPath $profileFile -Raw
  $namespace = New-Object System.Xml.XmlNamespaceManager($profile.NameTable)
  $namespace.AddNamespace('oor', 'http://openoffice.org/2001/registry')
  $settings = @{
    Enabled = '/org.openoffice.Office.Update/Update'
    AutoCheckEnabled = "/org.openoffice.Office.Jobs/Jobs/org.openoffice.Office.Jobs:Job['UpdateCheck']/Arguments"
    AutoDownloadEnabled = "/org.openoffice.Office.Jobs/Jobs/org.openoffice.Office.Jobs:Job['UpdateCheck']/Arguments"
  }
  foreach ($name in $settings.Keys) {
    $properties = @($profile.SelectNodes("//prop[@oor:name='$name']", $namespace) | Where-Object {
      $_.ParentNode.GetAttribute('path', 'http://openoffice.org/2001/registry') -eq $settings[$name]
    } | ForEach-Object { $_.SelectSingleNode('value') })
    if ($properties.Count -eq 0 -or @($properties | Where-Object { $_.InnerText -ne 'false' }).Count -gt 0) {
      throw "Update-Abschaltung im Lernprofil fehlt: $name"
    }
  }
  Write-Output "Verbindung ueber PID-Datei erfolgreich; $($values['node_count']) Accessibility-Knoten. Bericht: $reportPath"
} finally {
  $env:SCHULUI_DRAW_PATH = $previousLauncher
  $env:SCHULUI_TEST_OFFICE = $previousOffice
}
