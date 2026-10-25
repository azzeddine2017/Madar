@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ====================================================================
echo   Madar Release Packaging Tool [Madar 0.2.0-alpha]
echo   - Packaging Full SDK, AI Libraries, Tools, and Runtime
echo ====================================================================

set "VERSION=0.3.0-alpha"
set "PKG_NAME=madar-%VERSION%-windows-x64"
set "ROOT=%~dp0..\"
set "DIST_DIR=%ROOT%dist"
set "STAGE_DIR=%DIST_DIR%\%PKG_NAME%"
set "ZIP_FILE=%DIST_DIR%\%PKG_NAME%.zip"

echo [1/8] Cleaning existing staging directory...
if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"
if exist "%ZIP_FILE%" del /f /q "%ZIP_FILE%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo [2/8] Packaging Core Binaries (bin\) and Libraries (lib\)...
mkdir "%STAGE_DIR%\bin"
mkdir "%STAGE_DIR%\lib"
if not exist "%ROOT%bin\ring.exe" (
    echo [ERROR] ring.exe not found in bin! Please build first.
    exit /b 1
)
xcopy /s /e /y /q "%ROOT%bin\*" "%STAGE_DIR%\bin\" >nul
del /q /f "%STAGE_DIR%\bin\*.obj" 2>nul
del /q /f "%STAGE_DIR%\bin\*.ilk" 2>nul
del /q /f "%STAGE_DIR%\bin\*.pdb" 2>nul
del /q /f "%STAGE_DIR%\bin\*.idb" 2>nul

if exist "%ROOT%lib\*" xcopy /s /e /y /q "%ROOT%lib\*" "%STAGE_DIR%\lib\" >nul
del /q /f "%STAGE_DIR%\lib\*.obj" 2>nul
del /q /f "%STAGE_DIR%\lib\*.ilk" 2>nul

echo [3/8] Packaging C Core Runtime Source ^& Build Scripts (language\)...
mkdir "%STAGE_DIR%\language"
xcopy /s /e /y /q "%ROOT%language\*" "%STAGE_DIR%\language\" >nul
del /q /f "%STAGE_DIR%\language\src\*.obj" 2>nul
del /q /f "%STAGE_DIR%\language\src\*.ilk" 2>nul
del /q /f "%STAGE_DIR%\language\src\*.pdb" 2>nul
del /q /f "%STAGE_DIR%\language\build\*.obj" 2>nul
del /q /f "%STAGE_DIR%\language\build\*.ilk" 2>nul

echo [4/8] Packaging Extensions Source ^& Binaries (extensions\)...
mkdir "%STAGE_DIR%\extensions"
xcopy /s /e /y /q "%ROOT%extensions\*" "%STAGE_DIR%\extensions\" >nul
del /s /q /f "%STAGE_DIR%\extensions\*.obj" 2>nul
del /s /q /f "%STAGE_DIR%\extensions\*.ilk" 2>nul
del /s /q /f "%STAGE_DIR%\extensions\*.pdb" 2>nul

echo [5/8] Packaging Standard ^& AI Libraries (libraries\)...
mkdir "%STAGE_DIR%\libraries"
xcopy /s /e /y /q "%ROOT%libraries\*" "%STAGE_DIR%\libraries\" >nul

echo [6/8] Packaging Developer Tools (tools\)...
mkdir "%STAGE_DIR%\tools"
xcopy /s /e /y /q "%ROOT%tools\*" "%STAGE_DIR%\tools\" >nul
del /s /q /f "%STAGE_DIR%\tools\*.obj" 2>nul
del /s /q /f "%STAGE_DIR%\tools\*.ilk" 2>nul

echo [7/8] Packaging Examples, Tests, Docs, Models (examples\, tests\, docs\, models\)...
mkdir "%STAGE_DIR%\examples"
xcopy /s /e /y /q "%ROOT%examples\*" "%STAGE_DIR%\examples\" >nul
del /s /q /f "%STAGE_DIR%\examples\*.bin" 2>nul

mkdir "%STAGE_DIR%\tests"
xcopy /s /e /y /q "%ROOT%tests\*" "%STAGE_DIR%\tests\" >nul

mkdir "%STAGE_DIR%\docs"
xcopy /s /e /y /q "%ROOT%docs\*" "%STAGE_DIR%\docs\" >nul

mkdir "%STAGE_DIR%\models"
if exist "%ROOT%models\README.md" copy /y "%ROOT%models\README.md" "%STAGE_DIR%\models\" >nul
if exist "%ROOT%models\.gitkeep" copy /y "%ROOT%models\.gitkeep" "%STAGE_DIR%\models\" >nul

copy /y "%ROOT%README.md" "%STAGE_DIR%\" >nul
copy /y "%ROOT%LICENSE" "%STAGE_DIR%\" >nul
copy /y "%ROOT%CHANGELOG.md" "%STAGE_DIR%\" >nul
copy /y "%ROOT%RingCMD.bat" "%STAGE_DIR%\" >nul

echo [8/8] Creating Comprehensive ZIP archive (%PKG_NAME%.zip)...
powershell -NoProfile -Command "Compress-Archive -Path '%STAGE_DIR%' -DestinationPath '%ZIP_FILE%' -Force"

if exist "%ZIP_FILE%" (
    echo.
    echo ====================================================================
    echo   [SUCCESS] Full SDK Release package created successfully!
    echo   Archive : %ZIP_FILE%
    echo   Staging : %STAGE_DIR%
    echo ====================================================================
) else (
    echo [ERROR] Failed to create ZIP archive!
    exit /b 1
)

endlocal
