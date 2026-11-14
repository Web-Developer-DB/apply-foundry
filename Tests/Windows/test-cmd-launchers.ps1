$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$temp = Join-Path ([IO.Path]::GetTempPath()) ("apply foundry " + [guid]::NewGuid())
$tools = Join-Path $temp 'Start with spaces'
$bin = Join-Path $temp 'bin'
$stub = Join-Path $temp 'stub.exe'
$launchers = @('bewerbung', 'neue-bewerbung', 'setup')

try {
    New-Item -ItemType Directory -Path $tools, $bin | Out-Null
    foreach ($name in $launchers) {
        Copy-Item (Join-Path $repo "Tools/$name.cmd") $tools
    }
    Add-Type -OutputAssembly $stub -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;

public class Stub {
    public static int Main(string[] args) {
        string name = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
        if (name == "winget") {
            File.WriteAllLines("winget-args.txt", args);
            return Int32.Parse(Environment.GetEnvironmentVariable("TEST_WINGET_CODE"));
        }
        if (Array.IndexOf(args, "-c") >= 0)
            return name == "py" && Environment.GetEnvironmentVariable("TEST_PY_FAIL") == "1" ? 1 : 0;
        Console.WriteLine(name + ":" + String.Join("|", args));
        return Int32.Parse(Environment.GetEnvironmentVariable("TEST_PYTHON_CODE"));
    }
}
'@

    function Invoke-Launcher($Name, $CommandArguments, $ExpectedCode, $ExpectedText = '') {
        $process = New-Object Diagnostics.Process
        $process.StartInfo.FileName = Join-Path $env:SystemRoot 'System32/cmd.exe'
        $process.StartInfo.Arguments = '/d /s /c ""' + (Join-Path $tools "$Name.cmd") + '" ' + $CommandArguments + '"'
        $process.StartInfo.WorkingDirectory = $temp
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.EnvironmentVariables['PATH'] = "$bin;$env:SystemRoot\System32"
        $process.StartInfo.EnvironmentVariables['ERRORLEVEL'] = '99'
        $process.StartInfo.EnvironmentVariables['TEST_PY_FAIL'] = $script:pyFail
        $process.StartInfo.EnvironmentVariables['TEST_WINGET_CODE'] = $script:wingetCode
        $process.StartInfo.EnvironmentVariables['TEST_PYTHON_CODE'] = $script:pythonCode
        $process.StartInfo.EnvironmentVariables['LocalAppData'] = Join-Path $temp 'local'
        $process.StartInfo.EnvironmentVariables['ProgramW6432'] = Join-Path $temp 'machine'
        $process.StartInfo.EnvironmentVariables['ProgramFiles'] = Join-Path $temp 'machine'
        try {
            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne $ExpectedCode -or !$stdout.Contains($ExpectedText)) {
                throw "$Name $CommandArguments returned $($process.ExitCode), expected $ExpectedCode and '$ExpectedText'. Output: $stdout $stderr"
            }
        } finally {
            $process.Dispose()
        }
    }

    $script:pyFail = '0'
    $script:wingetCode = '0'
    $script:pythonCode = '7'
    Copy-Item $stub (Join-Path $bin 'py.exe')
    Copy-Item $stub (Join-Path $bin 'python.exe')
    foreach ($name in $launchers) {
        Invoke-Launcher $name '"two words & more"' 7 "py:-3|$tools\$name.py|two words & more"
    }
    $script:pyFail = '1'
    foreach ($name in $launchers) {
        Invoke-Launcher $name '--help' 7 "python:$tools\$name.py|--help"
    }
    Remove-Item (Join-Path $bin 'py.exe')
    foreach ($name in $launchers) {
        Invoke-Launcher $name '--help' 7 "python:$tools\$name.py|--help"
    }
    Remove-Item (Join-Path $bin 'python.exe')
    Copy-Item $stub (Join-Path $bin 'winget.exe')
    Invoke-Launcher 'bewerbung' '--help' 2
    Invoke-Launcher 'neue-bewerbung' '--help' 2
    foreach ($arguments in @('--runtime', '--yes', '--runtime --yes --dry-run', '--runtime --yes --all', '--runtime --yes --format', '--runtime --yes-please')) {
        Invoke-Launcher 'setup' $arguments 2
    }
    $wingetArgs = Join-Path $temp 'winget-args.txt'
    if (Test-Path $wingetArgs) { throw 'A read-only or invalid request invoked winget.' }

    $script:wingetCode = '3'
    Invoke-Launcher 'setup' '--runtime --yes' 1
    $script:wingetCode = '0'
    $installed = Join-Path $temp 'local/Programs/Python/Python313'
    New-Item -ItemType Directory -Path $installed -Force | Out-Null
    Copy-Item $stub (Join-Path $installed 'python.exe')
    Invoke-Launcher 'setup' '--runtime --yes --format json' 7 "python:$tools\setup.py|--runtime|--yes|--format|json"
    Invoke-Launcher 'setup' '--runtime --yes --format=json' 7 "python:$tools\setup.py|--runtime|--yes|--format|json"
    $expected = @('install', '--id', 'Python.Python.3.13', '--exact', '--source', 'winget', '--architecture', 'x64')
    $actual = Get-Content $wingetArgs
    if (($actual[0..7] -join '|') -ne ($expected -join '|')) {
        throw "Unexpected WinGet command: $actual"
    }

    foreach ($name in $launchers) {
        $launcher = Join-Path $repo "Tools/$name.cmd"
        & $launcher --help | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$name --help failed with $LASTEXITCODE." }
        & $launcher --unsupported-test-option 2>$null | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "$name returned $LASTEXITCODE for an invalid option." }
    }
    Write-Output 'Windows CMD launchers passed.'
} finally {
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
}
