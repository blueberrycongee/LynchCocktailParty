param(
  [int]$IntervalSeconds = 2,
  [switch]$FullAuto
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$topicPath = Join-Path $root 'state/topic.txt'

if (-not (Test-Path $topicPath)) {
  Write-Error "Missing topic file: $topicPath"
  exit 1
}

$lastWrite = (Get-Item $topicPath).LastWriteTimeUtc
Write-Host "Watching $topicPath. Press Ctrl+C to stop."

while ($true) {
  Start-Sleep -Seconds $IntervalSeconds
  $currentWrite = (Get-Item $topicPath).LastWriteTimeUtc
  if ($currentWrite -gt $lastWrite) {
    $lastWrite = $currentWrite
    Write-Host 'Change detected. Running pipeline...'
    Start-Sleep -Milliseconds 500

    $runArgs = @()
    if ($FullAuto) {
      $runArgs += '-FullAuto'
    }

    try {
      & (Join-Path $root 'run.ps1') @runArgs
    }
    catch {
      Write-Host $_.Exception.Message
    }
  }
}
