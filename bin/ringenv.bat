@echo off
rem ringenv CLI launcher
set "RINGENV_CALLER_DIR=%CD%"
pushd "%~dp0..\tools\ringpm\packages\ringenv"
ring main.ring %*
set "EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %EXIT_CODE%
