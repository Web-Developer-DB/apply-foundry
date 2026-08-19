#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-ContractText {
  param([AllowEmptyString()][string]$Text)
  if ($null -eq $Text) { return '' }
  $normalized = [Net.WebUtility]::HtmlDecode($Text).Normalize([Text.NormalizationForm]::FormC)
  $normalized = $normalized.Replace([char]0x2010,'-').Replace([char]0x2011,'-').Replace([char]0x2013,'-').Replace([char]0x2014,'-').Replace([char]0x2212,'-').Replace([char]0x00a0,' ')
  $normalized = $normalized.Replace([string][char]0xfb00,'ff').Replace([string][char]0xfb01,'fi').Replace([string][char]0xfb02,'fl').Replace([string][char]0xfb03,'ffi').Replace([string][char]0xfb04,'ffl')
  return [regex]::Replace($normalized, '\s+', ' ').Trim().ToLowerInvariant()
}

function ConvertTo-ContractTokens {
  param([AllowEmptyString()][string]$Text)
  $normalized = Normalize-ContractText $Text
  $pattern = '(?i)(?:\.[\p{L}\p{N}][\p{L}\p{N}+#._-]*|[\p{L}\p{N}]+(?:[._-][\p{L}\p{N}]+)*[+#]?)'
  return @([regex]::Matches($normalized, $pattern) | ForEach-Object { $_.Value })
}

function Get-ContractNgramCounts {
  param([string[]]$Tokens, [ValidateRange(1,5)][int]$Size)
  $counts = @{}
  if ($Tokens.Count -lt $Size) { return $counts }
  for ($i=0; $i -le $Tokens.Count - $Size; $i++) {
    $key = ($Tokens[$i..($i + $Size - 1)] -join "`u{001f}")
    if (-not $counts.ContainsKey($key)) { $counts[$key] = 0 }
    $counts[$key]++
  }
  return $counts
}

function Get-ContractTextSimilarity {
  param([AllowEmptyString()][string]$SourceText, [AllowEmptyString()][string]$ExtractedText)
  $source = @(ConvertTo-ContractTokens $SourceText)
  $extracted = @(ConvertTo-ContractTokens $ExtractedText)
  $sourceCounts = @{}
  foreach ($token in $source) { if (-not $sourceCounts.ContainsKey($token)) { $sourceCounts[$token] = 0 }; $sourceCounts[$token]++ }
  $extractedCounts = @{}
  foreach ($token in $extracted) { if (-not $extractedCounts.ContainsKey($token)) { $extractedCounts[$token] = 0 }; $extractedCounts[$token]++ }
  $matched = 0; $missing = [Collections.Generic.List[object]]::new()
  foreach ($entry in $sourceCounts.GetEnumerator()) {
    $actual = if ($extractedCounts.ContainsKey($entry.Key)) { [int]$extractedCounts[$entry.Key] } else { 0 }
    $matched += [math]::Min([int]$entry.Value, $actual)
    if ($actual -lt $entry.Value) { $missing.Add([ordered]@{ token = $entry.Key; count = ([int]$entry.Value - $actual) }) | Out-Null }
  }
  $tokenCoverage = if ($source.Count -eq 0) { 100.0 } else { [math]::Round(100.0 * $matched / $source.Count, 2) }
  $ngramCoverage = @{}
  foreach ($size in 2,3) {
    $wanted = Get-ContractNgramCounts -Tokens $source -Size $size
    $actual = Get-ContractNgramCounts -Tokens $extracted -Size $size
    $total = 0; $hit = 0
    foreach ($entry in $wanted.GetEnumerator()) { $total += [int]$entry.Value; if ($actual.ContainsKey($entry.Key)) { $hit += [math]::Min([int]$entry.Value, [int]$actual[$entry.Key]) } }
    $metricName = if ($size -eq 2) { 'bigram' } else { 'trigram' }
    $ngramCoverage[$metricName] = if ($total -eq 0) { 100.0 } else { [math]::Round(100.0 * $hit / $total, 2) }
  }
  $short = $source.Count -lt 25
  $thresholds = [ordered]@{ token = if ($short) { 100.0 } else { 98.0 }; bigram = if ($short) { 100.0 } else { 95.0 }; trigram = if ($short) { 100.0 } else { 90.0 } }
  [pscustomobject][ordered]@{
    sourceTokenCount = $source.Count; extractedTokenCount = $extracted.Count; tokenCoveragePercent = $tokenCoverage
    orderedBigramCoveragePercent = [double]$ngramCoverage.bigram; orderedTrigramCoveragePercent = [double]$ngramCoverage.trigram
    missingTokens = @($missing); thresholds = $thresholds
    passed = ($tokenCoverage -ge $thresholds.token -and [double]$ngramCoverage.bigram -ge $thresholds.bigram -and [double]$ngramCoverage.trigram -ge $thresholds.trigram)
  }
}

function ConvertTo-ContractSlug {
  param([Parameter(Mandatory)][string]$Text)
  $value = Normalize-ContractText $Text
  $value = $value.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
  $value = $value -replace '[^a-z0-9]+', '-'
  return $value.Trim('-')
}

Export-ModuleMember -Function @('Normalize-ContractText','ConvertTo-ContractTokens','Get-ContractTextSimilarity','ConvertTo-ContractSlug')
