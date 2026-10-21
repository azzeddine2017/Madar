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
