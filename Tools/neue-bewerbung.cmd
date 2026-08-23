@echo off
setlocal
where py >nul 2>nul && py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)" >nul 2>nul && py -3 "%~dp0neue-bewerbung.py" %* & exit /b %errorlevel%
where python >nul 2>nul && python -c "import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)" >nul 2>nul && python "%~dp0neue-bewerbung.py" %* & exit /b %errorlevel%
echo Python 3.11+ fehlt. Ausfuehren: Tools\setup.cmd --runtime --dry-run --format json
exit /b 2
