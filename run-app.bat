@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title MedAIx App

set "SUPABASE_URL=https://fmjcifnrwbazdlrhklta.supabase.co"
set "SUPABASE_ANON_KEY="

if exist "api\.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("api\.env") do (
    if /I "%%A"=="SUPABASE_URL" set "SUPABASE_URL=%%B"
    if /I "%%A"=="SUPABASE_ANON_KEY" set "SUPABASE_ANON_KEY=%%B"
  )
)

if "%SUPABASE_ANON_KEY%"=="" (
  echo Add this line to api\.env, using the publishable key from
  echo Supabase dashboard, project fmjcifnrwbazdlrhklta, Settings, API Keys.
  echo.
  echo SUPABASE_ANON_KEY=your-publishable-key
  echo.
  echo Do not use the secret key.
  pause
  exit /b 1
)

echo Starting MedAIx on the emulator.
echo API: http://10.0.2.2:8000
echo Start run-pixel4.bat first if the emulator is not open.
echo.
cd app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
if errorlevel 1 (
  echo.
  echo The app failed to start.
  pause
  exit /b 1
)
