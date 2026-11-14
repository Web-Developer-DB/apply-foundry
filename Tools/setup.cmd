@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERRORLEVEL="
set "probe=import sys; raise SystemExit(0 if sys.version_info >= (3,11) and sys.prefix == sys.base_prefix else 1)"

where.exe py.exe >nul 2>&1
if errorlevel 1 goto try_python
py.exe -3 -I -c "%probe%" >nul 2>&1
if errorlevel 1 goto try_python
py.exe -3 "%~dp0setup.py" %*
exit /b %errorlevel%

:try_python
where.exe python.exe >nul 2>&1
if errorlevel 1 goto missing_python
python.exe -I -c "%probe%" >nul 2>&1
if errorlevel 1 goto missing_python
python.exe "%~dp0setup.py" %*
exit /b %errorlevel%

:missing_python
echo Python 3.11+ fehlt. Plan: winget install --id Python.Python.3.13 --exact --source winget --architecture x64. 1>&2
echo Mit --runtime --yes wird nur diese Runtime installiert. 1>&2
set "native_arch=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "native_arch=%PROCESSOR_ARCHITEW6432%"
if /i not "%native_arch%"=="AMD64" exit /b 2

set "runtime="
set "confirmed="
set "output_format=text"

:bootstrap_options
if "%~1"=="" goto bootstrap
if "%~1"=="--runtime" (
    set "runtime=1"
) else if "%~1"=="--yes" (
    set "confirmed=1"
) else if "%~1"=="--format" (
    shift
    goto bootstrap_format
) else if "%~1"=="--format=json" (
    set "output_format=json"
) else if "%~1"=="--format=text" (
    set "output_format=text"
) else (
    exit /b 2
)
shift
goto bootstrap_options

:bootstrap_format
if "%~1"=="json" goto save_format
if "%~1"=="text" goto save_format
exit /b 2

:save_format
set "output_format=%~1"
shift
goto bootstrap_options

:bootstrap
if not defined runtime exit /b 2
if not defined confirmed exit /b 2
where.exe winget.exe >nul 2>&1
if errorlevel 1 (
    echo winget fehlt. Stelle Microsoft App Installer bereit und wiederhole den Aufruf. 1>&2
    exit /b 2
)
winget.exe install --id Python.Python.3.13 --exact --source winget --architecture x64 --accept-source-agreements --accept-package-agreements 1>&2
if errorlevel 1 exit /b 1

where.exe py.exe >nul 2>&1
if errorlevel 1 goto installed_python
py.exe -3.13 -I -c "%probe%" >nul 2>&1
if errorlevel 1 goto installed_python
py.exe -3.13 "%~dp0setup.py" --runtime --yes --format %output_format%
exit /b %errorlevel%

:installed_python
rem The parent CMD process may still have its pre-installation PATH.
for %%I in ("%LocalAppData%\Programs\Python\Python313\python.exe" "%ProgramW6432%\Python313\python.exe" "%ProgramFiles%\Python313\python.exe") do (
    if exist "%%~I" (
        "%%~I" -I -c "%probe%" >nul 2>&1
        if not errorlevel 1 (
            set "installed_python=%%~I"
            goto run_installed_python
        )
    )
)
echo Python wurde installiert. Oeffne ein neues Terminal und starte das Setup erneut. 1>&2
exit /b 1

:run_installed_python
"%installed_python%" "%~dp0setup.py" --runtime --yes --format %output_format%
exit /b %errorlevel%
