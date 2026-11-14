@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERRORLEVEL="
set "probe=import sys; raise SystemExit(0 if sys.version_info >= (3,11) and sys.prefix == sys.base_prefix else 1)"

where.exe py.exe >nul 2>&1
if errorlevel 1 goto try_python
py.exe -3 -I -c "%probe%" >nul 2>&1
if errorlevel 1 goto try_python
py.exe -3 "%~dp0bewerbung.py" %*
exit /b %errorlevel%

:try_python
where.exe python.exe >nul 2>&1
if errorlevel 1 goto missing_python
python.exe -I -c "%probe%" >nul 2>&1
if errorlevel 1 goto missing_python
python.exe "%~dp0bewerbung.py" %*
exit /b %errorlevel%

:missing_python
echo Python 3.11+ fehlt. Ausfuehren: Tools\setup.cmd --runtime --dry-run --format json
exit /b 2
