@echo off
REM =====================================================
REM  ActivatePrime backend only (adapted for Legacy of Nexus).
REM  Starts FastAPI on http://127.0.0.1:8001 — Dino Buddy chat uses this API.
REM
REM  Optional: set ACTIVATE_PRIME_DIR to your ActivatePrime repo root first.
REM =====================================================

setlocal EnableDelayedExpansion
set "PYTHONHOME="
set "PYTHONPATH="

set "TOOLS_DIR=%~dp0"
set "TOOLS_DIR=!TOOLS_DIR:~0,-1!"

if not defined ACTIVATE_PRIME_DIR (
 if exist "!TOOLS_DIR!\..\..\ActivatePrime\backend\main.py" (
        set "ACTIVATE_PRIME_DIR=!TOOLS_DIR!\..\..\ActivatePrime"
    ) else if exist "!TOOLS_DIR!\..\ActivatePrime\backend\main.py" (
        set "ACTIVATE_PRIME_DIR=!TOOLS_DIR!\..\ActivatePrime"
    ) else if exist "G:\ActivatePrime\backend\main.py" (
        set "ACTIVATE_PRIME_DIR=G:\ActivatePrime"
    )
)

if not defined ACTIVATE_PRIME_DIR (
    echo ERROR: Could not find ActivatePrime ^(backend\main.py^).
    echo Set ACTIVATE_PRIME_DIR to the ActivatePrime project root.
    pause
    exit /b 1
)

set "BACKEND_DIR=!ACTIVATE_PRIME_DIR!\backend"
if not exist "!BACKEND_DIR!\main.py" (
    echo ERROR: main.py not found in "!BACKEND_DIR!"
    pause
    exit /b 1
)

cd /d "!BACKEND_DIR!"

set "PYTHON_CMD="
if exist "!ACTIVATE_PRIME_DIR!\venv\Scripts\python.exe" (
    set "PYTHON_CMD=!ACTIVATE_PRIME_DIR!\venv\Scripts\python.exe"
    echo Using venv Python: !PYTHON_CMD!
    goto :python_ok
)
REM Prefer stable CPython releases first. 3.15 is currently shipping as an
REM alpha (3.15.0aX) and has almost no prebuilt wheels on PyPI yet, which
REM makes pip fall back to source builds (pypiwin32, pydantic-core, etc.).
REM We intentionally list 3.13/3.12/3.11 ahead of 3.15/3.14.
for %%V in (313 312 311 310 314 315) do (
    if exist "%LOCALAPPDATA%\Programs\Python\Python%%V\python.exe" (
        set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python%%V\python.exe"
        echo Using Python %%V: !PYTHON_CMD!
        goto :python_ok
    )
)
where python >nul 2>&1 && set "PYTHON_CMD=python" && echo Using system Python from PATH
:python_ok

if not defined PYTHON_CMD (
    echo ERROR: Python not found.
    pause
    exit /b 1
)

echo.
echo ActivatePrime root: !ACTIVATE_PRIME_DIR!
echo.
echo Checking for an existing backend on port 8001...
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8001/health' -TimeoutSec 2 -UseBasicParsing; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    echo ActivatePrime is already running on http://127.0.0.1:8001
    echo Reusing existing backend. Nothing else to launch.
    echo.
    pause
    exit /b 0
)

for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| find ":8001" ^| find "LISTENING"') do (
    echo Port 8001 is occupied by PID %%a. Stopping it before launch...
    taskkill /f /pid %%a >nul 2>&1
)

echo.
echo Checking dependencies...
"!PYTHON_CMD!" -c "import fastapi" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    echo Installing dependencies...
    "!PYTHON_CMD!" -m pip install --upgrade pip
    "!PYTHON_CMD!" -m pip install -r requirements.txt
    if !ERRORLEVEL! NEQ 0 (
        echo pip install failed.
        pause
        exit /b 1
    )
)

echo.
echo Starting backend on port 8001 ^(Ctrl+C to stop^)...
echo.
"!PYTHON_CMD!" main.py
echo.
echo Backend exited.
pause
