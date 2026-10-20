@echo off
setlocal
echo ========================================================
echo   Madar Runtime - Quick Core Build & Test Pipeline
echo ========================================================

set "MADAR_ROOT=%~dp0..\"

echo [1/2] Building Core Compiler and VM (ring.exe, ring.dll)...
cd /d "%MADAR_ROOT%language\build"
call buildvc_x64.bat
if errorlevel 1 (
    echo [ERROR] Failed to build Core Runtime!
    exit /b 1
)

echo [2/2] Running Test Suite...
cd /d "%MADAR_ROOT%tests"
call run_all.bat

echo.
echo ========================================================
echo   Quick Build & Test Completed!
echo ========================================================
endlocal
