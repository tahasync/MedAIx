@echo off
setlocal
cd /d "%~dp0"
title Pixel 4 Emulator

if not defined ANDROID_SDK_ROOT set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
if not defined ANDROID_HOME set "ANDROID_HOME=%ANDROID_SDK_ROOT%"

set "EMULATOR=%ANDROID_SDK_ROOT%\emulator\emulator.exe"
if not exist "%EMULATOR%" (
  echo Android emulator not found:
  echo %EMULATOR%
  echo.
  pause
  exit /b 1
)

echo Starting Pixel_4 with host GPU acceleration.
echo Close this window to stop the emulator.
echo.

REM -gpu host  uses this PC's GPU for emulator graphics
REM -accel on   uses hardware virtualization (WHPX / AEHD)
"%EMULATOR%" -avd Pixel_4 -gpu host -accel on
if errorlevel 1 (
  echo.
  echo The emulator exited with an error.
  pause
  exit /b 1
)
