@echo off
setlocal
cd /d "%~dp0"

set "FLUTTER_CMD=D:\DevTools\flutter\bin\flutter.bat"
if not exist "%FLUTTER_CMD%" (
  where flutter >nul 2>nul
  if not errorlevel 1 set "FLUTTER_CMD=flutter"
)
if /i not "%FLUTTER_CMD%"=="flutter" if not exist "%FLUTTER_CMD%" goto no_flutter

set "PUB_CACHE=D:\DevTools\PubCache"
set "TEMP=D:\DevTools\Temp"
set "TMP=D:\DevTools\Temp"
if not exist "%PUB_CACHE%" mkdir "%PUB_CACHE%"
if not exist "%TEMP%" mkdir "%TEMP%"

if not exist ".dart_tool\package_config.json" (
  echo Mengambil dependency Flutter...
  call "%FLUTTER_CMD%" pub get
  if errorlevel 1 goto failed
)

echo Membuka Wesbar di Chrome...
call "%FLUTTER_CMD%" run -d chrome --dart-define=SUPABASE_URL=https://eiorjqrkwomabpvmtuft.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_dpkSkqr-B2BGH4uc938Kcg_3uuonQpt
if errorlevel 1 goto failed
exit /b 0

:no_flutter
echo Flutter tidak ditemukan.
echo Pastikan Flutter ada di PATH atau D:\DevTools\flutter\bin\flutter.bat
pause
exit /b 1

:failed
echo Aplikasi berhenti dengan error. Baca pesan di atas untuk detail.
pause
exit /b 1
