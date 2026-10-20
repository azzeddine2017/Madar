@echo off
setlocal
echo ========================================================
echo   Madar Runtime - Complete Project Build Pipeline
echo ========================================================

set "MADAR_ROOT=%~dp0..\"
set "PATH=%MADAR_ROOT%bin;%PATH%"

echo [1/5] Building Core Compiler and VM (ring.exe, ring.dll)...
cd /d "%MADAR_ROOT%language\build"
call buildvc_x64.bat
if errorlevel 1 (
    echo [ERROR] Failed to build Core Runtime!
    exit /b 1
)

echo [2/5] Building Windowed Runner (ringw.exe)...
call buildvcw_x64.bat

echo [3/5] Building Core Extensions...
cd /d "%MADAR_ROOT%extensions\ringcurl"
call buildvc_x64.bat

cd /d "%MADAR_ROOT%extensions\ringconsolecolors"
call buildvc_x64.bat

cd /d "%MADAR_ROOT%extensions\ringinternet"
call buildvc_x64.bat

echo [4/5] Building CLI Tools (ring2exe, ringfmt, ringpm, ringrepl)...

echo   - Building ring2exe...
cd /d "%MADAR_ROOT%tools\ring2exe"
call build.bat

echo   - Building ringfmt...
cd /d "%MADAR_ROOT%tools\ringfmt"
call build.bat

echo   - Building ringpm...
cd /d "%MADAR_ROOT%tools\ringpm"
call build.bat

echo   - Building ringrepl...
cd /d "%MADAR_ROOT%tools\ringrepl"
call build.bat

echo [5/5] Verifying Binaries...
if not exist "%MADAR_ROOT%bin\ring.exe" (
    echo [ERROR] ring.exe was not produced in bin!
    exit /b 1
)
if exist "%MADAR_ROOT%bin\ring2exe.exe" echo   [OK] ring2exe.exe
if exist "%MADAR_ROOT%bin\ringfmt.exe"  echo   [OK] ringfmt.exe
if exist "%MADAR_ROOT%bin\ringpm.exe"   echo   [OK] ringpm.exe
if exist "%MADAR_ROOT%bin\ringrepl.exe" echo   [OK] ringrepl.exe

echo.
echo ========================================================
echo   Madar Build Pipeline Completed Successfully!
echo ========================================================
endlocal
