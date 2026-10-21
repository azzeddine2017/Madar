@echo off
setlocal
echo ========================================================
echo   Madar AI - Download Qwen-3B (Qwen2.5-3B-Instruct Q4_0)
echo ========================================================

set "MODELS_DIR=%~dp0..\models"
if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%"

set "MODEL_FILE=%MODELS_DIR%\qwen2.5-0.5b-instruct-q4_0.gguf"
set "MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf"

if exist "%MODEL_FILE%" (
    echo [INFO] Model already exists at: %MODEL_FILE%
    goto :done
)

echo [INFO] Downloading Qwen-0.5B / Qwen2.5-0.5B-Instruct (~0.425 GB)...
echo [INFO] Target: %MODEL_FILE%
echo.

curl -L --progress-bar -o "%MODEL_FILE%" "%MODEL_URL%"

if exist "%MODEL_FILE%" (
    echo.
    echo [SUCCESS] Model downloaded successfully to: %MODEL_FILE%
) else (
    echo.
    echo [ERROR] Download failed. Please check internet connection.
)

:done
endlocal
