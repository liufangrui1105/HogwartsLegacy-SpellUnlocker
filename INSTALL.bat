@echo off
chcp 65001 >nul
setlocal EnableExtensions
title SpellUnlocker v1.7.0 Installer
echo ==========================================================
echo   SpellUnlocker v1.7.0 - Hogwarts Legacy
echo   Installer
echo ==========================================================
echo.

if not exist "%~dp0UE4SS\dwmapi.dll" (
    echo [INFO] First run: downloading the official UE4SS runtime ^(~8 MB^) ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fetch-ue4ss.ps1"
    if errorlevel 1 (
        echo.
        echo [FAILED] Could not download UE4SS.
        echo          Download it manually and extract into: %~dp0UE4SS\
        echo          See README "Manual install".
        echo.
        pause
        exit /b 1
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto ok
if "%RC%"=="5" goto needadmin
goto fail

:needadmin
echo.
echo [INFO] Administrator privileges are required to write to the game folder.
choice /c YN /n /m "Restart this installer as administrator? [Y/N] "
if errorlevel 2 goto fail
echo.
echo [INFO] Opening an elevated installer window...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ok
echo.
echo [OK] Installation finished.
echo      Launch the game from Steam or Epic Games.
echo      Log: Phoenix\Binaries\Win64\SpellUnlocker.log
echo.
pause
exit /b 0

:fail
echo.
echo [FAILED] Installation did not complete. Read the messages above.
echo.
pause
exit /b 1