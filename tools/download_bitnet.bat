@echo off
setlocal
echo ========================================================
echo   Madar AI - Download BitNet b1.58 (2B-4T I2_S GGUF)
echo   Official Microsoft 1.58-bit Native LLM
echo ========================================================

set "MODELS_DIR=%~dp0..\models"
if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%"

set "MODEL_FILE=%MODELS_DIR%\bitnet-b1.58-2b-4t-i2_s.gguf"
set "MODEL_URL=https://huggingface.co/microsoft/bitnet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf"

if exist "%MODEL_FILE%" (
    echo [INFO] Model already exists at: %MODEL_FILE%
    goto :done
)

echo [INFO] Downloading Microsoft BitNet b1.58 2B-4T (I2_S GGUF)...
echo [INFO] Target: %MODEL_FILE%
echo [INFO] URL: %MODEL_URL%
echo.

curl -L --progress-bar -o "%MODEL_FILE%" "%MODEL_URL%"

if exist "%MODEL_FILE%" (
    echo.
    echo [SUCCESS] BitNet model downloaded successfully to: %MODEL_FILE%
) else (
    echo.
    echo [ERROR] Download failed. Please check internet connection.
)

:done
endlocal

