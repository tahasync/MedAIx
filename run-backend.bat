@echo off
setlocal
cd /d "%~dp0api"
title MedAIx API

where uv >nul 2>&1
if errorlevel 1 (
  echo uv was not found on PATH.
  echo Install it with: winget install astral-sh.uv
  echo.
  pause
  exit /b 1
)

echo Starting MedAIx API at http://127.0.0.1:8000
echo Swagger: http://127.0.0.1:8000/docs
echo From the Pixel 4 emulator, the PC is http://10.0.2.2:8000
echo.

uv run uvicorn main:app --reload --host 0.0.0.0 --port 8000
if errorlevel 1 (
  echo.
  echo The API exited with an error.
  pause
  exit /b 1
)
