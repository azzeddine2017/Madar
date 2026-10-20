@echo off
setlocal
echo ====================================================================
echo   Madar AI - Download DeepSeek-R1-Distill-Qwen-1.5B (Q4_0 GGUF)
echo ====================================================================

set "MODELS_DIR=%~dp0..\models"
if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%"

set "MODEL_FILE=%MODELS_DIR%\deepseek-r1-distill-qwen-1.5b-q4_0.gguf"
set "MODEL_URL=https://huggingface.co/ggml-org/DeepSeek-R1-Distill-Qwen-1.5B-Q4_0-GGUF/resolve/main/deepseek-r1-distill-qwen-1.5b-q4_0.gguf"

if exist "%MODEL_FILE%" (
    echo [INFO] DeepSeek-R1 model already exists at:
    echo        %MODEL_FILE%
    goto :done
)

echo [INFO] Target Model: DeepSeek-R1-Distill-Qwen-1.5B (~1.1 GB)
echo [INFO] Destination : %MODEL_FILE%
echo [INFO] Downloading from Hugging Face...
echo.

curl -L --progress-bar -o "%MODEL_FILE%" "%MODEL_URL%"

if exist "%MODEL_FILE%" (
    echo.
    echo ====================================================================
    echo   [SUCCESS] Model downloaded successfully!
    echo   File: %MODEL_FILE%
    echo   You can now run: ring examples\ai\chat.ring
    echo ====================================================================
) else (
    echo.
    echo [ERROR] Download failed. Please check your internet connection.
)

:done
endlocal
