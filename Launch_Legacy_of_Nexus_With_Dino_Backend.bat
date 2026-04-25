@echo off
REM =====================================================
REM  Legacy of Nexus — Dino Buddy launcher
REM  1) Starts ActivatePrime API on port 8001 (background)
REM  2) Opens this project in Godot
REM  3) When Godot closes, stops the process listening on 8001
REM
REM  Optional env vars:
REM   ACTIVATE_PRIME_DIR — ActivatePrime repo root (folder with backend\ and venv\)
REM   GODOT — full path to Godot.exe if not on PATH
REM =====================================================

setlocal EnableDelayedExpansion
set "NEXUS_DIR=%~dp0"
set "NEXUS_DIR=!NEXUS_DIR:~0,-1!"

title Legacy of Nexus + Dino backend

if not defined ACTIVATE_PRIME_DIR (
    if exist "!NEXUS_DIR!\..\ActivatePrime\backend\main.py" (
        set "ACTIVATE_PRIME_DIR=!NEXUS_DIR!\..\ActivatePrime"
    ) else if exist "G:\ActivatePrime\backend\main.py" (
        set "ACTIVATE_PRIME_DIR=G:\ActivatePrime"
    )
)

if not defined ACTIVATE_PRIME_DIR (
    echo ERROR: ActivatePrime not found.
    echo Set ACTIVATE_PRIME_DIR to the folder that contains backend\main.py
    pause
    exit /b 1
)

set "PYTHON_CMD="
if exist "!ACTIVATE_PRIME_DIR!\venv\Scripts\python.exe" (
    set "PYTHON_CMD=!ACTIVATE_PRIME_DIR!\venv\Scripts\python.exe"
) else (
    where python >nul 2>&1 && set "PYTHON_CMD=python"
)

if not defined PYTHON_CMD (
    echo ERROR: Python not found. Create venv in ActivatePrime or add Python to PATH.
    pause
    exit /b 1
)

set "BACKEND_DIR=!ACTIVATE_PRIME_DIR!\backend"
if not exist "!BACKEND_DIR!\main.py" (
    echo ERROR: Missing !BACKEND_DIR!\main.py
    pause
    exit /b 1
)

echo.
echo  =============================================
echo    Legacy of Nexus + ActivatePrime backend
echo  =============================================
echo    ActivatePrime: !ACTIVATE_PRIME_DIR!
echo    Nexus:         !NEXUS_DIR!
echo  =============================================
echo.

for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| find ":8001" ^| find "LISTENING"') do (
    echo Stopping previous listener on 8001 ^(PID %%a^)...
    taskkill /f /pid %%a >nul 2>&1
)

echo Starting backend on port 8001...
start /b "" "!PYTHON_CMD!" -u "!BACKEND_DIR!\main.py" > "!NEXUS_DIR!\dino_backend_log.txt" 2>&1

timeout /t 2 /nobreak >nul

echo Waiting for http://127.0.0.1:8001/health ...
set "READY=0"
for /L %%i in (1,1,45) do (
    if !READY! EQU 0 (
        powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8001/health' -TimeoutSec 2 -UseBasicParsing; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            set "READY=1"
            echo Backend is ready.
        ) else (
            <nul set /p "=."
            timeout /t 1 /nobreak >nul
        )
    )
)

if !READY! EQU 0 (
    echo.
    echo WARNING: Backend did not respond in time. Dino chat may not work.
    echo Log: !NEXUS_DIR!\dino_backend_log.txt
    echo.
)

set "GODOT_EXE="
if defined GODOT set "GODOT_EXE=!GODOT!"
if not defined GODOT_EXE (
    if exist "!NEXUS_DIR!\Godot_v4.6.2-stable_win64.exe" (
        set "GODOT_EXE=!NEXUS_DIR!\Godot_v4.6.2-stable_win64.exe"
        goto :godot_found
    )
)
if not defined GODOT_EXE (
    if exist "!NEXUS_DIR!\Godot.exe" (
        set "GODOT_EXE=!NEXUS_DIR!\Godot.exe"
        goto :godot_found
    )
)
if not defined GODOT_EXE (
    where godot4 >nul 2>&1 && for /f "delims=" %%a in ('where godot4 2^>nul') do (
        set "GODOT_EXE=%%a"
        goto :godot_found
    )
)
if not defined GODOT_EXE (
    where godot >nul 2>&1 && for /f "delims=" %%a in ('where godot 2^>nul') do (
        set "GODOT_EXE=%%a"
        goto :godot_found
    )
)
:godot_found

if not defined GODOT_EXE (
    echo ERROR: Godot not found. Add Godot to PATH or set GODOT to Godot.exe full path.
    echo Backend is still running on 8001. Check dino_backend_log.txt if needed.
    pause
    exit /b 1
)

echo Launching Godot: !GODOT_EXE!
echo Project: !NEXUS_DIR!
echo.
start /wait "" "!GODOT_EXE!" --path "!NEXUS_DIR!"

echo.
echo Godot closed. Stopping backend on 8001...
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| find ":8001" ^| find "LISTENING"') do (
    taskkill /f /pid %%a >nul 2>&1
)
echo Done.
timeout /t 2 /nobreak >nul
exit /b 0
