@echo off
rem Double-click to install coop-re7. Runs install-coop-re7.ps1 with this run's
rem script policy relaxed (Windows blocks downloaded scripts by default).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-coop-re7.ps1" %*
echo.
pause
