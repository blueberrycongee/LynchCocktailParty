param(
  [switch]$FullAuto,
  [switch]$ClearLog,
  [switch]$NoSearch,
  [switch]$BypassSandbox,
  [switch]$SkipGround,
  [string]$Model = 'gpt-5.2',
  [ValidateSet('read-only', 'workspace-write', 'danger-full-access')]
  [string]$Sandbox = 'read-only'
)

$ErrorActionPreference = 'Stop'

function Get-Block {
  param(
    [string]$Text,
    [string]$StartMarker,
    [string]$EndMarker
  )

  $pattern = [regex]::Escape($StartMarker) + '\s*(.*?)\s*' + [regex]::Escape($EndMarker)
  $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $match.Success) {
    throw "Missing block: $StartMarker -> $EndMarker"
  }
  return $match.Groups[1].Value.Trim()
}

function Get-BlockToEnd {
  param(
    [string]$Text,
    [string]$StartMarker
  )

  $pattern = [regex]::Escape($StartMarker) + '\s*(.*?)\s*$'
  $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $match.Success) {
    throw "Missing block: $StartMarker"
  }
  return $match.Groups[1].Value.Trim()
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
  Write-Error 'codex CLI not found. Install or add it to PATH.'
  exit 1
}

$topicPath = Join-Path $root 'state/topic.txt'
if (-not (Test-Path $topicPath)) {
  Write-Error "Missing topic file: $topicPath"
  exit 1
}

$lockPath = Join-Path $root 'state/.run.lock'
if (Test-Path $lockPath) {
  Write-Error 'Another run is already in progress.'
  exit 1
}

New-Item -ItemType File -Path $lockPath -Force | Out-Null
try {
  $logPath = Join-Path $root 'state/party.log'
  if (-not (Test-Path $logPath)) {
    New-Item -ItemType File -Path $logPath | Out-Null
  }

  if ($ClearLog) {
    '# party.log - append-only role log' | Set-Content -Path $logPath
  }

  $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Add-Content -Path $logPath -Value "`n===== Run $stamp ====="

  $commonArgs = @()
  if (-not $NoSearch) {
    $commonArgs += '--search'
  }
  if ($BypassSandbox) {
    $commonArgs += '--dangerously-bypass-approvals-and-sandbox'
  }
  if ($Model) {
    $commonArgs += @('-m', $Model)
  }
  $commonArgs += @('exec', '--skip-git-repo-check', '-C', $root)
  if ($FullAuto) {
    $commonArgs += '--full-auto'
  }
  $commonArgs += @('-s', $Sandbox)

  $steps = @(
    @{
      name = 'ground'
      prompt = 'prompts/00_ground_env.md'
      outJson = 'state/ground_facts.json'
      requires = @('state/topic.txt')
      format = 'json-log'
    },
    @{
      name = 'level0'
      prompt = 'prompts/01_level0_noise_trader.md'
      outJson = 'state/level0.json'
      requires = @('state/ground_facts.json')
      format = 'json-log'
    },
    @{
      name = 'level1'
      prompt = 'prompts/02_level1_trend_follower.md'
      outJson = 'state/level1.json'
      requires = @('state/ground_facts.json', 'state/level0.json')
      format = 'json-log'
    },
    @{
      name = 'level2'
      prompt = 'prompts/03_level2_fundamentalist.md'
      outJson = 'state/level2.json'
      requires = @('state/ground_facts.json')
      format = 'json-log'
    },
    @{
      name = 'level3'
      prompt = 'prompts/04_level3_contrarian.md'
      outJson = 'state/level3.json'
      requires = @('state/ground_facts.json', 'state/level0.json', 'state/level1.json', 'state/level2.json')
      format = 'json-log'
    },
    @{
      name = 'level4'
      prompt = 'prompts/05_level4_skeptic.md'
      outJson = 'state/level4.json'
      requires = @('state/ground_facts.json', 'state/level0.json', 'state/level1.json', 'state/level2.json', 'state/level3.json')
      format = 'json-log'
    },
    @{
      name = 'god'
      prompt = 'prompts/06_god_oracle.md'
      outJson = 'state/report.json'
      outNarrative = 'state/report.md'
      requires = @('state/ground_facts.json', 'state/level0.json', 'state/level1.json', 'state/level2.json', 'state/level3.json', 'state/level4.json')
      format = 'json-narrative-log'
    }
  )

  if ($SkipGround) {
    $steps = $steps | Where-Object { $_.name -ne 'ground' }
  }

  foreach ($step in $steps) {
    $promptPath = Join-Path $root $step.prompt
    if (-not (Test-Path $promptPath)) {
      throw "Missing prompt: $promptPath"
    }

    foreach ($req in $step.requires) {
      $reqPath = Join-Path $root $req
      if (-not (Test-Path $reqPath)) {
        throw "Missing required input file: $req"
      }
    }

    $promptText = Get-Content -Raw -Path $promptPath
    if ($step.format -eq 'json-narrative-log') {
      $formatSpec = @"
Output format (exact, no extra text):
<<<JSON>>>
{...}
<<<NARRATIVE>>>
plain text narrative
<<<LOG>>>
[YYYY-MM-DDTHH:MM:SSZ][role]
inputs: ...
sources: ...
thoughts: ...
signal: ...
"@
    }
    else {
      $formatSpec = @"
Output format (exact, no extra text):
<<<JSON>>>
{...}
<<<LOG>>>
[YYYY-MM-DDTHH:MM:SSZ][role]
inputs: ...
sources: ...
thoughts: ...
signal: ...
"@
    }

    $fullPrompt = @"
You are running step: $($step.name).
Follow the instructions below exactly. Use only the specified inputs. Write outputs to the specified files. Append a log block to state/party.log.
If a required input file is missing, stop and report the missing path.

$promptText

IMPORTANT:
- Do not write files or run shell commands to write.
- Only read inputs if needed.
- Output must follow the format below exactly, with no extra text.

$formatSpec
"@

    $lastMessagePath = Join-Path $root ("state/.last_message_{0}.txt" -f $step.name)
    if (Test-Path $lastMessagePath) {
      Remove-Item -Path $lastMessagePath -Force
    }

    $cmdArgs = $commonArgs + @('--output-last-message', $lastMessagePath)
    $fullPrompt | codex @cmdArgs -
    if ($LASTEXITCODE -ne 0) {
      throw "codex exec failed at step: $($step.name)"
    }

    if (-not (Test-Path $lastMessagePath)) {
      throw "Missing output message file: $lastMessagePath"
    }

    $response = Get-Content -Raw -Path $lastMessagePath
    if ($step.format -eq 'json-narrative-log') {
      $jsonBlock = Get-Block -Text $response -StartMarker '<<<JSON>>>' -EndMarker '<<<NARRATIVE>>>'
      $narrativeBlock = Get-Block -Text $response -StartMarker '<<<NARRATIVE>>>' -EndMarker '<<<LOG>>>'
      $logBlock = Get-BlockToEnd -Text $response -StartMarker '<<<LOG>>>'

      $jsonPath = Join-Path $root $step.outJson
      $narrativePath = Join-Path $root $step.outNarrative
      $jsonBlock | Set-Content -Path $jsonPath -NoNewline
      $narrativeBlock | Set-Content -Path $narrativePath -NoNewline
      Add-Content -Path $logPath -Value "`n$logBlock"
    }
    else {
      $jsonBlock = Get-Block -Text $response -StartMarker '<<<JSON>>>' -EndMarker '<<<LOG>>>'
      $logBlock = Get-BlockToEnd -Text $response -StartMarker '<<<LOG>>>'

      $jsonPath = Join-Path $root $step.outJson
      $jsonBlock | Set-Content -Path $jsonPath -NoNewline
      Add-Content -Path $logPath -Value "`n$logBlock"
    }
  }
}
finally {
  if (Test-Path $lockPath) {
    Remove-Item -Path $lockPath -Force
  }
}
