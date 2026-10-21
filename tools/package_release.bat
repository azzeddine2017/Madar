@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ====================================================================
echo   Madar Release Packaging Tool [Madar 0.2.0-alpha]
echo ====================================================================

set "VERSION=0.2.0-alpha"
set "PKG_NAME=madar-%VERSION%-windows-x64"
set "ROOT=%~dp0..\"
set "DIST_DIR=%ROOT%dist"
set "STAGE_DIR=%DIST_DIR%\%PKG_NAME%"
set "ZIP_FILE=%DIST_DIR%\%PKG_NAME%.zip"

echo [1/6] Cleaning existing staging directory...
if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"
if exist "%ZIP_FILE%" del /f /q "%ZIP_FILE%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo [2/6] Creating release folder structure...
mkdir "%STAGE_DIR%\bin"
mkdir "%STAGE_DIR%\bin\load"
mkdir "%STAGE_DIR%\libraries\madar_ai"
mkdir "%STAGE_DIR%\examples\ai"
mkdir "%STAGE_DIR%\models"
mkdir "%STAGE_DIR%\tools"
mkdir "%STAGE_DIR%\docs"

echo [3/6] Copying core binaries and runtime...
if not exist "%ROOT%bin\ring.exe" (
    echo [ERROR] ring.exe not found in bin! Please build first.
    exit /b 1
)

copy /y "%ROOT%bin\ring.exe" "%STAGE_DIR%\bin\" >nul
copy /y "%ROOT%bin\ring.dll" "%STAGE_DIR%\bin\" >nul
if exist "%ROOT%bin\ringw.exe" copy /y "%ROOT%bin\ringw.exe" "%STAGE_DIR%\bin\" >nul
if exist "%ROOT%bin\*.dll" copy /y "%ROOT%bin\*.dll" "%STAGE_DIR%\bin\" >nul
if exist "%ROOT%bin\ring2exe.exe" copy /y "%ROOT%bin\ring2exe.exe" "%STAGE_DIR%\bin\" >nul
if exist "%ROOT%bin\ringfmt.exe" copy /y "%ROOT%bin\ringfmt.exe" "%STAGE_DIR%\bin\" >nul
if exist "%ROOT%bin\ringpm.exe" copy /y "%ROOT%bin\ringpm.exe" "%STAGE_DIR%\bin\" >nul
if exist "%ROOT%bin\ringrepl.exe" copy /y "%ROOT%bin\ringrepl.exe" "%STAGE_DIR%\bin\" >nul
if exist "%ROOT%bin\load\*" xcopy /s /e /y "%ROOT%bin\load\*" "%STAGE_DIR%\bin\load\" >nul

echo [4/6] Copying AI libraries and examples...
copy /y "%ROOT%libraries\madar_ai\*.ring" "%STAGE_DIR%\libraries\madar_ai\" >nul
copy /y "%ROOT%examples\ai\*.ring" "%STAGE_DIR%\examples\ai\" >nul
copy /y "%ROOT%examples\ai\*.csv" "%STAGE_DIR%\examples\ai\" >nul
if exist "%ROOT%examples\ai\README.md" copy /y "%ROOT%examples\ai\README.md" "%STAGE_DIR%\examples\ai\" >nul

echo [5/6] Copying documentation and auxiliary tools...
copy /y "%ROOT%README.md" "%STAGE_DIR%\" >nul
copy /y "%ROOT%LICENSE" "%STAGE_DIR%\" >nul
copy /y "%ROOT%CHANGELOG.md" "%STAGE_DIR%\" >nul
copy /y "%ROOT%RingCMD.bat" "%STAGE_DIR%\" >nul

copy /y "%ROOT%docs\*.md" "%STAGE_DIR%\docs\" >nul
copy /y "%ROOT%tools\download_*.bat" "%STAGE_DIR%\tools\" >nul
if exist "%ROOT%models\README.md" copy /y "%ROOT%models\README.md" "%STAGE_DIR%\models\" >nul

echo [6/6] Creating ZIP archive (%PKG_NAME%.zip)...
powershell -NoProfile -Command "Compress-Archive -Path '%STAGE_DIR%' -DestinationPath '%ZIP_FILE%' -Force"

if exist "%ZIP_FILE%" (
    echo.
    echo ====================================================================
    echo   [SUCCESS] Release package created successfully!
    echo   Archive : %ZIP_FILE%
    echo   Staging : %STAGE_DIR%
    echo ====================================================================
) else (
    echo [ERROR] Failed to create ZIP archive!
    exit /b 1
)

endlocal
