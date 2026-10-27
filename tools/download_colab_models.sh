#!/usr/bin/env bash
set -e

# ====================================================================
#   Madar AI - Colab High-Intelligence Model Downloader
#   Downloads powerful 7B & 3B reasoning models suitable for Colab RAM & GPU
# ====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$(cd "$SCRIPT_DIR/../models" && pwd)"
mkdir -p "$MODELS_DIR"

CHOICE="${1:-deepseek7b}"

echo "=========================================================="
echo "  Madar AI - Colab Model Downloader                       "
echo "  Target Directory: $MODELS_DIR"
echo "=========================================================="

download_file() {
    local FILE_NAME="$1"
    local URL="$2"
    local DESC="$3"
    local DEST="$MODELS_DIR/$FILE_NAME"

    if [ -f "$DEST" ]; then
        echo "[INFO] $DESC already exists at: $DEST"
        return 0
    fi

    echo "[INFO] Downloading $DESC..."
    echo "[INFO] Source: $URL"
    echo "[INFO] Target: $DEST"
    curl -L --progress-bar -o "$DEST" "$URL"
    if [ -f "$DEST" ]; then
        echo "[SUCCESS] Successfully downloaded: $FILE_NAME"
    else
        echo "[ERROR] Download failed for: $FILE_NAME"
        exit 1
    fi
}

case "$CHOICE" in
    "deepseek7b"|"r1"|"deepseek")
        download_file \
            "deepseek-r1-distill-qwen-7b-q4_0.gguf" \
            "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_0.gguf" \
            "DeepSeek-R1-Distill-Qwen-7B (Q4_0, ~4.68 GB - Advanced Reasoning & CoT)"
        ;;
    "qwen7b")
        download_file \
            "qwen2.5-7b-instruct-q4_0.gguf" \
            "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_0.gguf" \
            "Qwen2.5-7B-Instruct (Q4_0, ~4.48 GB - High Intelligence, Arabic & Coding)"
        ;;
    "qwen3b")
        download_file \
            "qwen2.5-3b-instruct-q4_0.gguf" \
            "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_0.gguf" \
            "Qwen2.5-3B-Instruct (Q4_0, ~1.93 GB - Fast & Smart)"
        ;;
    "bge"|"bge-m3")
        download_file \
            "bge-m3-q4_0.gguf" \
            "https://huggingface.co/CompendiumLabs/bge-m3-gguf/resolve/main/bge-m3-q4_0.gguf" \
            "BGE-M3 (Q4_0, ~1.19 GB - Multilingual Dense Embeddings for RAG)"
        ;;
    "qwen14b"|"14b")
        download_file \
            "qwen2.5-14b-instruct-q4_0.gguf" \
            "https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_0.gguf" \
            "Qwen2.5-14B-Instruct (Q4_0, ~8.54 GB - Frontier Intelligence, SOTA Arabic, Math & Code)"
        ;;
    "deepseek14b"|"r1-14b")
        download_file \
            "deepseek-r1-distill-qwen-14b-q4_0.gguf" \
            "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-14B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-14B-Q4_0.gguf" \
            "DeepSeek-R1-Distill-Qwen-14B (Q4_0, ~8.54 GB - Superhuman Reasoning & Deep CoT)"
        ;;
    "all")
        echo "[INFO] Downloading full high-intelligence suite (Qwen2.5-7B + DeepSeek-R1-7B)..."
        "$0" qwen7b
        "$0" deepseek7b
        ;;
    *)
        echo "Usage: bash download_colab_models.sh [qwen14b | deepseek14b | qwen7b | deepseek7b | qwen3b | bge | all]"
        exit 1
        ;;
esac

echo "=========================================================="
echo "  Download completed successfully!                        "
echo "=========================================================="
