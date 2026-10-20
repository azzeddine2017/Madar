# Madar AI - Interactive Chat Examples

This directory contains interactive examples demonstrating local LLM inference in Madar using pure C99/Ring code without external dependencies.

## Examples

### 1. `chat.ring` - Interactive Terminal Chat
An interactive CLI chat session supporting:
- **Qwen-3B / Qwen2.5-3B-Instruct (Q4_0)** for intelligent multilingual conversation in Arabic and English.
- **DeepSeek-R1-Distill-Qwen-1.5B (Q4_0)** with Chain-of-Thought `<think>` reasoning extraction.
- Context reset (`reset`), exit command (`exit`), parameter tuning (`/tokens <N>`, `/temp <0.0-1.0>`), and real-time generation metrics (tokens/sec).

### How to Run:
1. Download a model if you haven't already:
   - For Qwen-3B (~1.9 GB, Recommended):
     ```cmd
     tools\download_model.bat
     ```
   - For DeepSeek-R1 (1.5B, ~1.1 GB):
     ```cmd
     tools\download_deepseek.bat
     ```
2. Run the interactive chat:
   ```cmd
   bin\ring.exe examples\ai\chat.ring
   ```
   Or explicitly choose Qwen:
   ```cmd
   bin\ring.exe examples\ai\chat.ring qwen
   ```
