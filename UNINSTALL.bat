@echo off
chcp 65001 >nul
setlocal EnableExtensions
title SpellUnlocker v1.7.0 Uninstaller
echo ==========================================================
echo   SpellUnlocker v1.7.0 - Uninstaller
echo ==========================================================
echo   Add  -KeepUE4SS  to keep UE4SS and other UE4SS mods.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto ok
if "%RC%"=="5" goto needadmin
goto fail

:needadmin
echo.
echo [INFO] Administrator privileges are required to write to the game folder.
choice /c YN /n /m "Restart this uninstaller as administrator? [Y/N] "
if errorlevel 2 goto fail
echo.
echo [INFO] Opening an elevated uninstaller window...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ok
echo.
echo [OK] Uninstallation finished.
echo.
pause
exit /b 0

:fail
echo.
echo [FAILED] Uninstallation did not complete. Read the messages above.
echo.
pause
exit /b 1
