$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$topicPath = Join-Path $root 'state/topic.txt'
$outPath = Join-Path $root 'state/ground_facts.json'
$logPath = Join-Path $root 'state/party.log'

if (-not (Test-Path $topicPath)) {
  Write-Error "Missing topic file: $topicPath"
  exit 1
}

$text = Get-Content -Raw -Path $topicPath
$fields = @{}
foreach ($line in $text -split "`r?`n") {
  if ($line -match '^\s*([^:]+)\s*:\s*(.*)$') {
    $fields[$matches[1].Trim()] = $matches[2].Trim()
  }
}

$topic = $fields['topic']
if (-not $topic) { $topic = 'unknown' }
$timeRange = $fields['time_range']
if (-not $timeRange) { $timeRange = 'last_7_days' }
$notes = $fields['notes']

function New-RssUrl([string]$query) {
  $encoded = [Uri]::EscapeDataString($query)
  return "https://news.google.com/rss/search?q=$encoded&hl=en-US&gl=US&ceid=US:en"
}

function Try-ParseDate([string]$value) {
  if (-not $value) { return $null }
  try {
    return [DateTime]::Parse($value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
  } catch {
    return $null
  }
}

function Clean-Text([string]$value) {
  if (-not $value) { return '' }
  $text = [System.Net.WebUtility]::HtmlDecode($value)
  $text = $text -replace '<[^>]+>', ' '
  $text = $text -replace '\s+', ' '
  $text = $text.Trim()
  if ($text.Length -gt 300) {
    $text = $text.Substring(0, 300).Trim()
  }
  return $text
}

$queries = New-Object System.Collections.Generic.List[string]
$queries.Add($topic) | Out-Null
$queries.Add("$topic price") | Out-Null
$queries.Add("$topic demand") | Out-Null
$queries.Add("$topic policy") | Out-Null
$queries.Add("$topic ETF") | Out-Null

if ($topic -match 'China|Chinese|Shanghai|SGE|PBoC|SAFE') {
  $queries.Add('Shanghai Gold Exchange premium') | Out-Null
  $queries.Add('PBoC gold reserves') | Out-Null
  $queries.Add('China gold import quotas') | Out-Null
}

if ($notes) {
  $queries.Add($notes) | Out-Null
}

$queries = $queries | Select-Object -Unique | Select-Object -First 5
$rssUrls = $queries | ForEach-Object { New-RssUrl $_ }

$items = @()
$rssUnavailable = @()

foreach ($url in $rssUrls) {
  try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    [xml]$xml = $resp.Content
    foreach ($item in $xml.rss.channel.item) {
      $summaryRaw = ($item.description | Out-String).Trim()
      $summary = Clean-Text $summaryRaw
      $items += [pscustomobject]@{
        title = ($item.title | Out-String).Trim()
        url = ($item.link | Out-String).Trim()
        published_at = ($item.pubDate | Out-String).Trim()
        outlet = ($item.source.'#text' | Out-String).Trim()
        summary = $summary
        rss_url = $url
      }
    }
  } catch {
    $rssUnavailable += $url
  }
}

$cutoff = (Get-Date).ToUniversalTime().AddDays(-7)
$seen = @{}
$filtered = @()

foreach ($it in $items) {
  if (-not $it.title) { continue }
  if (-not $it.url) { continue }
  if ($seen.ContainsKey($it.url)) { continue }
  $pub = Try-ParseDate $it.published_at
  if ($pub -and $pub.ToUniversalTime() -lt $cutoff) { continue }
  $seen[$it.url] = $true
  if (-not $it.outlet) { $it.outlet = 'Google News' }
  $filtered += $it
}

$sources = $filtered | Select-Object -First 15

function Get-StooqRows([string]$url) {
  $csv = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
  return $csv.Content | ConvertFrom-Csv
}

$priceMoves = @()
$priceFacts = @()
$stooqUrls = @{
  XAUUSD = 'https://stooq.com/q/d/l/?s=xauusd&i=d'
  XAGUSD = 'https://stooq.com/q/d/l/?s=xagusd&i=d'
  USDCNY = 'https://stooq.com/q/d/l/?s=usdcny&i=d'
}
$stooqUnavailable = @()

foreach ($pair in $stooqUrls.GetEnumerator()) {
  $symbol = $pair.Key
  $url = $pair.Value
  try {
    $rows = Get-StooqRows $url
    $rows = $rows | Where-Object { $_.Date } | Sort-Object Date
    if ($rows.Count -ge 2) {
      $last = $rows[-1]
      $prev = $rows[-2]
      $lastClose = [double]$last.Close
      $prevClose = [double]$prev.Close
      $chg = $lastClose - $prevClose
      $chgPct = if ($prevClose -ne 0) { ($chg / $prevClose) * 100.0 } else { 0.0 }
      $priceMoves += "$symbol close $($last.Date): $([math]::Round($lastClose,4)) (change $([math]::Round($chg,4)), $([math]::Round($chgPct,2))%)."
    }
    if ($rows.Count -ge 7) {
      $window = $rows | Select-Object -Last 7
      $start = $window[0]
      $end = $window[-1]
      $startClose = [double]$start.Close
      $endClose = [double]$end.Close
      $chg = $endClose - $startClose
      $chgPct = if ($startClose -ne 0) { ($chg / $startClose) * 100.0 } else { 0.0 }
      $priceFacts += "$symbol 7-trading-day change $($start.Date) to $($end.Date): $([math]::Round($chg,4)) ($([math]::Round($chgPct,2))%)."
      $lows = $window | ForEach-Object { [double]$_.Low }
      $highs = $window | ForEach-Object { [double]$_.High }
      if ($lows.Count -gt 0 -and $highs.Count -gt 0) {
        $priceFacts += "$symbol 7-trading-day range $($start.Date) to $($end.Date): low $([math]::Round(($lows | Measure-Object -Minimum).Minimum,4)), high $([math]::Round(($highs | Measure-Object -Maximum).Maximum,4))."
      }
    }
  } catch {
    $stooqUnavailable += $url
  }
}

$facts = @()
foreach ($s in $sources) {
  if ($s.title) {
    if ($s.published_at) {
      $facts += "$($s.published_at): $($s.outlet) reported '$($s.title)'."
    } else {
      $facts += "$($s.outlet) reported '$($s.title)'."
    }
  }
}

foreach ($url in ($rssUnavailable | Select-Object -Unique)) {
  $facts += "Gap: Google News RSS unavailable for $url."
}
foreach ($url in $stooqUnavailable) {
  $facts += "Gap: Stooq CSV unavailable for $url."
}
if ($sources.Count -lt 8) {
  $facts += "Gap: Only $($sources.Count) Google News RSS items available within last_7_days for the selected queries."
}

$facts += $priceFacts
if ($facts.Count -lt 12) {
  foreach ($pm in $priceMoves) {
    $facts += "Price data: $pm"
  }
}

$facts = $facts | Select-Object -First 25

$ground = [pscustomobject]@{
  topic = $topic
  time_range = $timeRange
  generated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  sources = $sources | Select-Object title, url, published_at, outlet, summary
  price_moves = $priceMoves
  facts = $facts
}

$ground | ConvertTo-Json -Depth 6 | Set-Content -Path $outPath

if (-not (Test-Path $logPath)) {
  New-Item -ItemType File -Path $logPath | Out-Null
}

$logStamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$logLine = @"
[$logStamp][ground]
inputs: state/topic.txt
sources: $($rssUrls -join ', '), $($stooqUrls.Values -join ', ')
thoughts: Google News RSS headlines for China gold/silver/SGE/PBoC and Stooq spot price/FX closes.
signal: n/a
"@

Add-Content -Path $logPath -Value $logLine
