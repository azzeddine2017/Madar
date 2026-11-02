# Madar AI Models Directory

This directory stores GGUF models used by Madar AI runtime for local LLM inference.

Large model files (`*.gguf`) are excluded from Git version control.

### Download Models
To download the recommended Qwen-1.5B model (~0.9 GB, ideal for intelligent chat in Arabic and English):
```cmd
tools\download_model.bat
```
This downloads `qwen2.5-0.5b-instruct-q4_0.gguf` (Qwen-1.5B) into this directory.

To download DeepSeek-R1-Distill-1.5B (~1.1 GB):
```cmd
tools\download_deepseek.bat
```

To download Microsoft BitNet b1.58 2B-4T (1.58-bit Native LLM, I2_S GGUF ~0.75 GB):
```cmd
tools\download_bitnet.bat
```
