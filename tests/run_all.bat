@echo off
setlocal
set "RING_EXE=%~dp0..\bin\ring.exe"

if not exist "%RING_EXE%" (
    echo [ERROR] %RING_EXE% not found! Please build the runtime first using language\build\buildvc_x64.bat.
    exit /b 1
)

echo ========================================================
echo   Running Madar Test Suite
echo   Binary: %RING_EXE%
echo ========================================================

echo.
echo === [1/3] Core Dialect and Runtime Tests ===
cd "%~dp0core"
"%RING_EXE%" test_backward_compat.ring
echo.
"%RING_EXE%" test_fstrings.ring
echo.
"%RING_EXE%" test_default_args.ring
echo.
"%RING_EXE%" test_slicing.ring
echo.
"%RING_EXE%" test_comprehensions.ring
echo.
"%RING_EXE%" test_dour.ring
echo.
"%RING_EXE%" test_arabic_utf8.ring
echo.
"%RING_EXE%" test_try_catch_context.ring
echo.
"%RING_EXE%" test_json_errors.ring
cd "%~dp0"

echo.
echo === [2/3] Native Tensor Engine and GGML Tests ===
cd "%~dp0tensor"
"%RING_EXE%" test_tensor_operations.ring
echo.
"%RING_EXE%" test_tensor_math.ring
echo.
"%RING_EXE%" test_tensor_operators.ring
echo.
"%RING_EXE%" test_ggml.ring
echo.
"%RING_EXE%" test_gguf_loader.ring
cd "%~dp0"

echo.
echo === [3/3] AI Engine and Tokenizer Tests ===
cd "%~dp0ai"
"%RING_EXE%" test_qwen.ring
if exist test_tok.gguf del test_tok.gguf
cd "%~dp0"

echo.
echo ========================================================
echo   Test Execution Complete
echo ========================================================
endlocal
