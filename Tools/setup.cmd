@echo off
setlocal
where py >nul 2>nul && py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)" >nul 2>nul && py -3 "%~dp0setup.py" %* & exit /b %errorlevel%
where python >nul 2>nul && python -c "import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)" >nul 2>nul && python "%~dp0setup.py" %* & exit /b %errorlevel%
echo Python 3.11+ fehlt. Plan: winget install --id Python.Python.3.13 --exact --source winget.
echo Mit --runtime --yes wird nur diese Runtime installiert.
echo %* | findstr /c:"--runtime" >nul || exit /b 2
echo %* | findstr /c:"--yes" >nul || exit /b 2
winget install --id Python.Python.3.13 --exact --source winget --accept-source-agreements --accept-package-agreements || exit /b 1
py -3.13 "%~dp0setup.py" %*
exit /b %errorlevel%
