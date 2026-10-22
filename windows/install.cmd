@echo off
cd /d "%~dp0"
if not exist "resources\gentledesk-extension-id.txt" (
  echo Please download your installer from GentleDesk - Connect desktop.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0resources\install.ps1" -FromFile "%~dp0resources\gentledesk-extension-id.txt"
if errorlevel 1 (
  echo Installation failed. Please return to GentleDesk for help.
  pause
  exit /b 1
)
echo Installed. Return to GentleDesk and connect your desktop.
pause
