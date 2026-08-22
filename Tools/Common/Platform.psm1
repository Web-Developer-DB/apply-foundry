#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('ApplyFoundry.Platform.NativeProcessRunner' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace ApplyFoundry.Platform
{
    public sealed class BoundedTextCapture
    {
        private readonly object _gate = new object();
        private readonly StringBuilder _text = new StringBuilder();
        private readonly int _maximumCharacters;

        public bool Truncated { get; private set; }

        public BoundedTextCapture(int maximumCharacters)
        {
            if (maximumCharacters < 0) throw new ArgumentOutOfRangeException(nameof(maximumCharacters));
            _maximumCharacters = maximumCharacters;
        }

        public void Append(char[] buffer, int count)
        {
            if (buffer == null) throw new ArgumentNullException(nameof(buffer));
            if (count < 0 || count > buffer.Length) throw new ArgumentOutOfRangeException(nameof(count));
            lock (_gate)
            {
                int remaining = _maximumCharacters - _text.Length;
                if (remaining > 0)
                {
                    _text.Append(buffer, 0, Math.Min(remaining, count));
                }
                if (count > remaining) Truncated = true;
            }
        }

        public void MarkTruncated()
        {
            lock (_gate) Truncated = true;
        }

        public override string ToString()
        {
            lock (_gate) return _text.ToString();
        }
    }

    public sealed class NativeProcessResult
    {
        public string FilePath { get; set; }
        public int ProcessId { get; set; }
        public int? ExitCode { get; set; }
        public bool TimedOut { get; set; }
        public long DurationMs { get; set; }
        public string StandardOutput { get; set; }
        public string StandardError { get; set; }
        public bool StdoutTruncated { get; set; }
        public bool StderrTruncated { get; set; }
    }

    public static class NativeProcessRunner
    {
        private static async Task PumpAsync(System.IO.StreamReader reader, BoundedTextCapture destination)
        {
            var buffer = new char[4096];
            try
            {
                while (true)
                {
                    int count = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                    if (count == 0) return;
                    destination.Append(buffer, count);
                }
            }
            catch (System.IO.IOException) { }
            catch (ObjectDisposedException) { }
        }

        public static NativeProcessResult Run(
            string filePath,
            string[] arguments,
            string workingDirectory,
            IDictionary environment,
            int timeoutMilliseconds,
            int maximumStdoutCharacters,
            int maximumStderrCharacters)
        {
            if (String.IsNullOrWhiteSpace(filePath)) throw new ArgumentException("Executable path is required.", nameof(filePath));
            if (timeoutMilliseconds < 1) throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));

            Encoding redirectedOutputEncoding = new UTF8Encoding(false, false);
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
                redirectedOutputEncoding = Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage);
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = filePath,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = redirectedOutputEncoding,
                StandardErrorEncoding = redirectedOutputEncoding
            };
            if (!String.IsNullOrWhiteSpace(workingDirectory)) startInfo.WorkingDirectory = workingDirectory;
            if (arguments != null)
            {
                foreach (string argument in arguments) startInfo.ArgumentList.Add(argument ?? String.Empty);
            }
            if (environment != null)
            {
                foreach (DictionaryEntry entry in environment)
                {
                    string key = Convert.ToString(entry.Key);
                    if (String.IsNullOrEmpty(key)) throw new ArgumentException("Environment variable names must not be empty.", nameof(environment));
                    string value = entry.Value == null ? null : Convert.ToString(entry.Value);
                    if (value == null) startInfo.Environment.Remove(key);
                    else startInfo.Environment[key] = value;
                }
            }

            var stdout = new BoundedTextCapture(maximumStdoutCharacters);
            var stderr = new BoundedTextCapture(maximumStderrCharacters);
            var stopwatch = Stopwatch.StartNew();
            using (var process = new Process { StartInfo = startInfo })
            {
                if (!process.Start()) throw new InvalidOperationException("The native process could not be started.");
                int processId = process.Id;
                Task stdoutPump = PumpAsync(process.StandardOutput, stdout);
                Task stderrPump = PumpAsync(process.StandardError, stderr);

                bool exited = process.WaitForExit(timeoutMilliseconds);
                bool timedOut = !exited;
                if (timedOut)
                {
                    try { process.Kill(true); }
                    catch
                    {
                        try { process.Kill(); } catch { }
                    }
                    exited = process.WaitForExit(5000);
                }
                if (exited)
                {
                    process.WaitForExit();
                    if (!Task.WaitAll(new[] { stdoutPump, stderrPump }, 5000))
                    {
                        stdout.MarkTruncated();
                        stderr.MarkTruncated();
                    }
                }
                stopwatch.Stop();

                return new NativeProcessResult
                {
                    FilePath = filePath,
                    ProcessId = processId,
                    ExitCode = exited ? process.ExitCode : (int?)null,
                    TimedOut = timedOut,
                    DurationMs = stopwatch.ElapsedMilliseconds,
                    StandardOutput = stdout.ToString(),
                    StandardError = stderr.ToString(),
                    StdoutTruncated = stdout.Truncated,
                    StderrTruncated = stderr.Truncated
                };
            }
        }
    }
}
'@
}

function Join-PathSegments {
  param(
    [Parameter(Mandatory)][string]$BasePath,
    [Parameter(Mandatory)][string[]]$Segments
  )

  $result = $BasePath
  foreach ($segment in $Segments) {
    $result = Join-Path -Path $result -ChildPath $segment
  }
  return $result
}

function Get-LinuxOsRelease {
  $values = @{}
  $path = '/etc/os-release'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
    if ($line -notmatch '^(?<key>[A-Z][A-Z0-9_]*)=(?<value>.*)$') { continue }
    $value = $Matches.value.Trim()
    if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $values[$Matches.key] = $value -replace '\\"', '"' -replace '\\\\', '\'
  }
  return $values
}

function Get-PlatformInfo {
  [CmdletBinding()]
  param()

  $distribution = if ($IsLinux) { Get-LinuxOsRelease } else { @{} }
  $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
  $name = if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } elseif ($IsMacOS) { 'macos' } else { 'unknown' }
  $distributionId = if ($distribution.ContainsKey('ID')) { [string]$distribution.ID } else { $null }
  $distributionVersion = if ($distribution.ContainsKey('VERSION_ID')) { [string]$distribution.VERSION_ID } else { $null }
  $isWsl = $false
  if ($IsLinux) {
    $isWsl = -not [string]::IsNullOrWhiteSpace($env:WSL_DISTRO_NAME)
    if (-not $isWsl -and (Test-Path -LiteralPath '/proc/sys/kernel/osrelease' -PathType Leaf)) {
      $isWsl = (Get-Content -LiteralPath '/proc/sys/kernel/osrelease' -Raw) -match '(?i)microsoft|wsl'
    }
  }
  $supported = ($IsWindows -and $architecture -eq 'x64') -or
    ($IsLinux -and $architecture -eq 'x64' -and $distributionId -eq 'ubuntu' -and $distributionVersion -eq '24.04')

  [pscustomobject][ordered]@{
    Name = $name
    IsWindows = [bool]$IsWindows
    IsLinux = [bool]$IsLinux
    IsMacOS = [bool]$IsMacOS
    IsWsl = [bool]$isWsl
    Supported = [bool]$supported
    OSDescription = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    DistributionId = $distributionId
    DistributionVersion = $distributionVersion
    Architecture = $architecture
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    PSEdition = $PSVersionTable.PSEdition
  }
}

function Get-PathStringComparison {
  [CmdletBinding()]
  param()

  if ($IsWindows) { return [System.StringComparison]::OrdinalIgnoreCase }
  return [System.StringComparison]::Ordinal
}

function Get-NormalizedFullPath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$BasePath = (Get-Location).ProviderPath
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1F\x7F]') {
    throw [System.ArgumentException]::new('Ein Pfad darf weder leer sein noch Steuerzeichen enthalten.')
  }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Get-CanonicalPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$AllowMissing
  )

  $fullPath = Get-NormalizedFullPath -Path $Path
  $rootPart = [System.IO.Path]::GetPathRoot($fullPath)
  if ([string]::IsNullOrWhiteSpace($rootPart)) {
    throw "Pfad besitzt keinen gültigen Dateisystem-Root: $Path"
  }

  $current = $rootPart
  $remaining = $fullPath.Substring($rootPart.Length)
  $separatorPattern = if ($IsWindows) { '[\\/]+' } else { '/+' }
  $segments = @($remaining -split $separatorPattern | Where-Object { $_.Length -gt 0 })
  for ($index = 0; $index -lt $segments.Count; $index++) {
    $next = Join-Path -Path $current -ChildPath $segments[$index]
    try {
      $item = Get-Item -LiteralPath $next -Force -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
      if (-not $AllowMissing) { throw }
      for ($missingIndex = $index; $missingIndex -lt $segments.Count; $missingIndex++) {
        $current = Join-Path -Path $current -ChildPath $segments[$missingIndex]
      }
      return [System.IO.Path]::GetFullPath($current)
    }

    $isReparsePoint = ([int]$item.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isReparsePoint) {
      $target = $item.ResolveLinkTarget($true)
      if ($null -eq $target) {
        throw "Symbolischer Link oder Junction konnte nicht aufgelöst werden: $next"
      }
      $current = [System.IO.Path]::GetFullPath($target.FullName)
    } else {
      $current = [System.IO.Path]::GetFullPath($item.FullName)
    }
    if ($index -lt ($segments.Count - 1) -and -not [System.IO.Directory]::Exists($current)) {
      throw "Bestehendes Pfadsegment ist kein Ordner und darf keine Unterpfade maskieren: $next"
    }
  }
  return [System.IO.Path]::GetFullPath($current)
}

function Test-NormalizedContainment {
  param(
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$Root,
    [switch]$AllowRoot
  )

  $comparison = Get-PathStringComparison
  $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $candidateTrimmed = $Candidate.TrimEnd($trimChars)
  $rootTrimmed = $Root.TrimEnd($trimChars)
  if ([string]::Equals($candidateTrimmed, $rootTrimmed, $comparison)) {
    return [bool]$AllowRoot
  }
  $rootPrefix = $rootTrimmed + [System.IO.Path]::DirectorySeparatorChar
  return $candidateTrimmed.StartsWith($rootPrefix, $comparison)
}

function Resolve-SafePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$Root,
    [switch]$AllowRoot,
    [switch]$MustExist,
    [switch]$ForWrite,
    [ValidateSet('Any', 'Leaf', 'Container')][string]$PathType = 'Any'
  )

  $rootFull = Get-NormalizedFullPath -Path $Root
  if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
    throw "Sicherheits-Root muss als vorhandener Ordner existieren: $rootFull"
  }
  $candidateFull = if ([System.IO.Path]::IsPathRooted($Candidate)) {
    Get-NormalizedFullPath -Path $Candidate
  } else {
    Get-NormalizedFullPath -Path $Candidate -BasePath $rootFull
  }

  if (-not (Test-NormalizedContainment -Candidate $candidateFull -Root $rootFull -AllowRoot:$AllowRoot)) {
    throw "Pfad liegt lexikalisch außerhalb des zulässigen Roots: $candidateFull"
  }

  $rootCanonical = Get-CanonicalPath -Path $rootFull
  $candidateCanonical = Get-CanonicalPath -Path $candidateFull -AllowMissing
  if (-not (Test-NormalizedContainment -Candidate $candidateCanonical -Root $rootCanonical -AllowRoot:$AllowRoot)) {
    throw "Pfad verlässt den zulässigen Root über einen symbolischen Link oder eine Junction: $candidateFull"
  }

  $exists = Test-Path -LiteralPath $candidateFull
  if ($MustExist -and -not $exists) {
    throw "Pfad muss existieren: $candidateFull"
  }
  if ($exists -and $PathType -eq 'Leaf' -and -not (Test-Path -LiteralPath $candidateFull -PathType Leaf)) {
    throw "Pfad muss eine reguläre Datei sein: $candidateFull"
  }
  if ($exists -and $PathType -eq 'Container' -and -not (Test-Path -LiteralPath $candidateFull -PathType Container)) {
    throw "Pfad muss ein Ordner sein: $candidateFull"
  }
  if ($ForWrite -and $exists) {
    $writeTarget = Get-Item -LiteralPath $candidateFull -Force -ErrorAction Stop
    if (([int]$writeTarget.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Schreibziel darf kein symbolischer Link und keine Junction sein: $candidateFull"
    }
  }
  return $candidateFull
}

function Test-PathWithinRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$Root,
    [switch]$AllowRoot
  )

  try {
    $null = Resolve-SafePath -Candidate $Candidate -Root $Root -AllowRoot:$AllowRoot
    return $true
  } catch {
    return $false
  }
}

function Test-SamePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Left,
    [Parameter(Mandatory)][string]$Right
  )

  try {
    $leftCanonical = Get-CanonicalPath -Path $Left -AllowMissing
    $rightCanonical = Get-CanonicalPath -Path $Right -AllowMissing
    return [string]::Equals($leftCanonical, $rightCanonical, (Get-PathStringComparison))
  } catch {
    return $false
  }
}

function Resolve-NativeExecutable {
  param([Parameter(Mandatory)][string]$FilePath)

  if ([string]::IsNullOrWhiteSpace($FilePath) -or $FilePath -match '[\x00-\x1F\x7F]') {
    throw [System.ArgumentException]::new('Executable-Pfad darf weder leer sein noch Steuerzeichen enthalten.')
  }
  if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
    return (Resolve-Path -LiteralPath $FilePath).Path
  }
  $command = Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $command -or [string]::IsNullOrWhiteSpace($command.Source)) {
    throw "Natives Programm wurde nicht gefunden: $FilePath"
  }
  return (Resolve-Path -LiteralPath $command.Source).Path
}

function Invoke-NativeProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 30,
    [ValidateRange(0, 10000000)][int]$MaxStdoutChars = 65536,
    [ValidateRange(0, 10000000)][int]$MaxStderrChars = 65536,
    [string]$WorkingDirectory,
    [hashtable]$Environment
  )

  $resolvedExecutable = Resolve-NativeExecutable -FilePath $FilePath
  $resolvedWorkingDirectory = $null
  if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $resolvedWorkingDirectory = Get-NormalizedFullPath -Path $WorkingDirectory
    if (-not (Test-Path -LiteralPath $resolvedWorkingDirectory -PathType Container)) {
      throw "Arbeitsverzeichnis existiert nicht: $resolvedWorkingDirectory"
    }
  }
  return [ApplyFoundry.Platform.NativeProcessRunner]::Run(
    $resolvedExecutable,
    [string[]]$ArgumentList,
    $resolvedWorkingDirectory,
    $Environment,
    $TimeoutSeconds * 1000,
    $MaxStdoutChars,
    $MaxStderrChars
  )
}

function Get-BrowserDefinitions {
  $definitions = [System.Collections.Generic.List[object]]::new()
  $platform = Get-PlatformInfo

  if ($platform.IsWindows) {
    $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $local = $env:LOCALAPPDATA
    $chromePaths = @($programFiles | ForEach-Object { Join-PathSegments -BasePath $_ -Segments @('Google', 'Chrome', 'Application', 'chrome.exe') })
    $edgePaths = @($programFiles | ForEach-Object { Join-PathSegments -BasePath $_ -Segments @('Microsoft', 'Edge', 'Application', 'msedge.exe') })
    $chromiumPaths = @($programFiles | ForEach-Object { Join-PathSegments -BasePath $_ -Segments @('Chromium', 'Application', 'chrome.exe') })
    $firefoxPaths = @($programFiles | ForEach-Object { Join-PathSegments -BasePath $_ -Segments @('Mozilla Firefox', 'firefox.exe') })
    if ($local) {
      $chromePaths += Join-PathSegments -BasePath $local -Segments @('Google', 'Chrome', 'Application', 'chrome.exe')
      $edgePaths += Join-PathSegments -BasePath $local -Segments @('Microsoft', 'Edge', 'Application', 'msedge.exe')
      $chromiumPaths += Join-PathSegments -BasePath $local -Segments @('Chromium', 'Application', 'chrome.exe')
      $firefoxPaths += Join-PathSegments -BasePath $local -Segments @('Mozilla Firefox', 'firefox.exe')
    }
    $definitions.Add([pscustomobject]@{ Name = 'chrome'; Engine = 'chromium'; Paths = $chromePaths; Commands = @('chrome.exe', 'chrome', 'google-chrome') })
    $definitions.Add([pscustomobject]@{ Name = 'edge'; Engine = 'chromium'; Paths = $edgePaths; Commands = @('msedge.exe', 'msedge') })
    $definitions.Add([pscustomobject]@{ Name = 'chromium'; Engine = 'chromium'; Paths = $chromiumPaths; Commands = @('chromium.exe', 'chromium', 'chromium-browser') })
    $definitions.Add([pscustomobject]@{ Name = 'firefox'; Engine = 'gecko'; Paths = $firefoxPaths; Commands = @('firefox.exe', 'firefox') })
  } elseif ($platform.IsLinux) {
    $definitions.Add([pscustomobject]@{ Name = 'chrome'; Engine = 'chromium'; Paths = @('/usr/bin/google-chrome-stable', '/usr/bin/google-chrome'); Commands = @('google-chrome-stable', 'google-chrome', 'chrome') })
    $definitions.Add([pscustomobject]@{ Name = 'chromium'; Engine = 'chromium'; Paths = @('/usr/bin/chromium', '/usr/bin/chromium-browser'); Commands = @('chromium', 'chromium-browser') })
    $definitions.Add([pscustomobject]@{ Name = 'edge'; Engine = 'chromium'; Paths = @('/usr/bin/microsoft-edge-stable', '/usr/bin/microsoft-edge'); Commands = @('microsoft-edge-stable', 'microsoft-edge', 'msedge') })
    $definitions.Add([pscustomobject]@{ Name = 'firefox'; Engine = 'gecko'; Paths = @('/usr/bin/firefox'); Commands = @('firefox') })
  } elseif ($platform.IsMacOS) {
    $definitions.Add([pscustomobject]@{ Name = 'chrome'; Engine = 'chromium'; Paths = @('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'); Commands = @('google-chrome') })
    $definitions.Add([pscustomobject]@{ Name = 'edge'; Engine = 'chromium'; Paths = @('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'); Commands = @('microsoft-edge') })
    $definitions.Add([pscustomobject]@{ Name = 'chromium'; Engine = 'chromium'; Paths = @('/Applications/Chromium.app/Contents/MacOS/Chromium'); Commands = @('chromium') })
    $definitions.Add([pscustomobject]@{ Name = 'firefox'; Engine = 'gecko'; Paths = @('/Applications/Firefox.app/Contents/MacOS/firefox'); Commands = @('firefox') })
  }
  return $definitions.ToArray()
}

function Get-BrowserIdentity {
  param([Parameter(Mandatory)][string]$ExecutablePath)

  $versionText = ''
  if ($IsWindows) {
    $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExecutablePath)
    $reportedVersion = if (-not [string]::IsNullOrWhiteSpace($fileVersion.ProductVersion)) { $fileVersion.ProductVersion } else { $fileVersion.FileVersion }
    $reportedProduct = (@($fileVersion.ProductName, $fileVersion.FileDescription) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ' '
    if (-not [string]::IsNullOrWhiteSpace($reportedProduct) -and -not [string]::IsNullOrWhiteSpace($reportedVersion)) {
      $versionText = "$reportedProduct $reportedVersion"
    }
  }
  if ([string]::IsNullOrWhiteSpace($versionText)) {
    $probe = Invoke-NativeProcess -FilePath $ExecutablePath -ArgumentList @('--version') -TimeoutSeconds 8 -MaxStdoutChars 4096 -MaxStderrChars 4096
    $versionText = (($probe.StandardOutput + $probe.StandardError) -replace '[\r\n]+', ' ').Trim()
    if ($probe.TimedOut -or $probe.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($versionText)) {
      throw "Browser-Version konnte nicht sicher ermittelt werden: $ExecutablePath"
    }
  }
  $lower = $versionText.ToLowerInvariant()
  $name = if ($lower -match 'microsoft edge|msedge') {
    'edge'
  } elseif ($lower -match 'chromium') {
    'chromium'
  } elseif ($lower -match 'google chrome|google-chrome') {
    'chrome'
  } elseif ($lower -match 'firefox') {
    'firefox'
  } else {
    throw "Executable konnte keinem unterstützten Browser zugeordnet werden: $ExecutablePath"
  }
  $engine = if ($name -eq 'firefox') { 'gecko' } else { 'chromium' }
  $versionMatch = [regex]::Match($versionText, '(?<!\d)(?<version>\d+(?:\.\d+){1,3})(?!\d)')
  if (-not $versionMatch.Success) {
    throw "Browser meldet keine auswertbare Version: $ExecutablePath"
  }
  return [pscustomobject][ordered]@{
    Name = $name
    Type = if ($engine -eq 'chromium') { 'chromium' } else { 'firefox' }
    Engine = $engine
    Path = (Resolve-Path -LiteralPath $ExecutablePath).Path
    Version = $versionMatch.Groups['version'].Value
    VersionText = $versionText
  }
}

function Get-BrowserCandidates {
  [CmdletBinding()]
  param(
    [ValidateSet('auto', 'chrome', 'edge', 'chromium', 'firefox')][string]$RequestedBrowser = 'auto',
    [string]$ExecutablePath,
    [switch]$AllowFirefox,
    [switch]$RequireChromium
  )

  if (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) {
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
      throw "Expliziter Browserpfad muss auf eine vorhandene Datei zeigen: $ExecutablePath"
    }
    $identity = Get-BrowserIdentity -ExecutablePath (Resolve-Path -LiteralPath $ExecutablePath).Path
    if ($RequestedBrowser -ne 'auto' -and $identity.Name -ne $RequestedBrowser) {
      throw "Browserpfad meldet '$($identity.Name)', angefordert wurde '$RequestedBrowser'."
    }
    if ($identity.Engine -ne 'chromium' -and ($RequireChromium -or (-not $AllowFirefox -and $RequestedBrowser -eq 'auto'))) {
      throw 'Firefox ist nur für eine ausdrücklich aktivierte Layoutdiagnose zulässig.'
    }
    return @($identity)
  }

  $definitions = @(Get-BrowserDefinitions)
  if ($RequestedBrowser -ne 'auto') {
    $definitions = @($definitions | Where-Object { $_.Name -eq $RequestedBrowser })
  } elseif (-not $AllowFirefox) {
    $definitions = @($definitions | Where-Object { $_.Name -ne 'firefox' })
  }

  $seen = [System.Collections.Generic.HashSet[string]]::new($(if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }))
  $found = [System.Collections.Generic.List[object]]::new()
  foreach ($definition in $definitions) {
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($knownPath in @($definition.Paths)) {
      if (-not [string]::IsNullOrWhiteSpace($knownPath) -and (Test-Path -LiteralPath $knownPath -PathType Leaf)) {
        $candidatePaths.Add((Resolve-Path -LiteralPath $knownPath).Path)
      }
    }
    foreach ($commandName in @($definition.Commands)) {
      $command = Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        $candidatePaths.Add((Resolve-Path -LiteralPath $command.Source).Path)
      }
    }

    foreach ($candidatePath in $candidatePaths) {
      $canonical = Get-CanonicalPath -Path $candidatePath
      if (-not $seen.Add($canonical)) { continue }
      try {
        $identity = Get-BrowserIdentity -ExecutablePath $candidatePath
        if ($identity.Name -ne $definition.Name) { continue }
        if ($RequireChromium -and $identity.Engine -ne 'chromium') { continue }
        $found.Add($identity)
        break
      } catch {
        continue
      }
    }
  }
  return $found.ToArray()
}

function Resolve-BrowserExecutable {
  [CmdletBinding()]
  param(
    [ValidateSet('auto', 'chrome', 'edge', 'chromium', 'firefox')][string]$RequestedBrowser = 'auto',
    [string]$ExecutablePath,
    [switch]$AllowFirefox,
    [switch]$RequireChromium
  )

  $candidates = @(Get-BrowserCandidates -RequestedBrowser $RequestedBrowser -ExecutablePath $ExecutablePath -AllowFirefox:$AllowFirefox -RequireChromium:$RequireChromium)
  if ($candidates.Count -eq 0) {
    throw "Kein passender Browser gefunden (angefordert: $RequestedBrowser)."
  }
  return $candidates[0]
}

function Get-RuntimeFingerprint {
  [CmdletBinding()]
  param([object]$BrowserInfo)

  $platform = Get-PlatformInfo
  $browser = $null
  if ($null -ne $BrowserInfo) {
    $browser = [ordered]@{
      name = [string]$BrowserInfo.Name
      version = [string]$BrowserInfo.Version
      executable = [System.IO.Path]::GetFullPath([string]$BrowserInfo.Path)
    }
  }
  return [pscustomobject][ordered]@{
    schemaVersion = 1
    os = $platform.Name
    osDescription = $platform.OSDescription
    distributionId = $platform.DistributionId
    distributionVersion = $platform.DistributionVersion
    wsl = $platform.IsWsl
    architecture = $platform.Architecture
    powerShellVersion = $platform.PowerShellVersion
    psEdition = $platform.PSEdition
    browser = $browser
  }
}

Export-ModuleMember -Function @(
  'Get-PlatformInfo',
  'Get-PathStringComparison',
  'Get-CanonicalPath',
  'Test-SamePath',
  'Test-PathWithinRoot',
  'Resolve-SafePath',
  'Invoke-NativeProcess',
  'Get-BrowserCandidates',
  'Resolve-BrowserExecutable',
  'Get-RuntimeFingerprint'
)
