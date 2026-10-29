# Madar (مدار)

[![Release](https://img.shields.io/badge/Release-0.4.0--alpha-blue.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20Google%20Colab-green.svg)](docs/INSTALL.md)
[![Colab](https://colab.research.google.com/assets/colab-badge.svg)](notebooks/Madar_Colab_Quickstart.ipynb)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

> **An AI-Native, High-Performance Dialect and Runtime for the Ring Ecosystem**

**Madar** (مدار) is a high-performance, AI-first fork of **Ring Lite (Ring 1.27 Core)**. Engineered specifically for native tensor arithmetic, direct hardware execution of quantized LLMs, and high-productivity modern syntax extensions, Madar maintains 100% backward compatibility with Ring while providing cutting-edge local inference capabilities on commodity CPU and integrated GPU hardware.

---

## 🎯 Core Features & Architecture

1. **Native Continuous Tensor Engine (`ITEMTYPE_TENSOR = 6`):**
   - Implemented at the C core layer with **zero struct overhead** (utilizing Ring's unused 3-bit bitfield in `Item`).
   - Supports zero-copy memory-mapped tensors, strided slicing, reshaping, and full bidirectional conversion bridges (`List <-> Tensor`).
   - Precision formats: `Float32`, `Float16`, `Int8`, `Int32`, `Float64`.
   - Native operator overloading (`+`, `-`, `*`, `/`, scalar arithmetic) and neural activations (`ReLU`, `GELU`, `Sigmoid`, `Softmax`).

2. **Full GGUF & Quantization Support (V2 / V3) + AVX2 SIMD Core:**
   - High-throughput binary reader supporting `Q4_0`, `Q8_0`, `Q6_K`, `F16`, and `F32`.
   - **Hardware-Accelerated AVX2 & FMA Dot Products**: 256-bit SIMD vectorized kernels unpacking 32 x 4-bit nibbles and calculating matrix multiplications with F16C and FMA instructions for unprecedented CPU generation speed.
   - **Full Q6_K Super-Block Dequantization**: Native vector dot product kernel for `Q6_K` tensors (`output.weight` in modern 6-bit quantized models).
   - Zero-copy OS memory mapping (`MapViewOfFile` / `mmap`), enabling multi-gigabyte models to be mounted in fractions of a second with under 20 MB of active runtime RAM.

3. **OpenCL GPU Acceleration Engine (Intel / AMD / NVIDIA):**
   - **Dynamic OpenCL Loading**: GPU acceleration enabled via `LoadLibrary("OpenCL.dll")` at runtime — **zero linker dependencies**, no external SDK required. Falls back cleanly to CPU-only mode if no GPU driver is present.
   - **Zero-Copy GPU Weight Binding**: FFN layer weights (`gate`, `up`, `down`) and the LM Head (`output.weight`) are pre-mapped to GPU memory once at model load using `CL_MEM_USE_HOST_PTR`, eliminating all runtime buffer allocations during inference.
   - **128-bit SIMD OpenCL Kernels**: All GPU kernels (`Q4_0`, `Q8_0`, `Q6_K`) use `vload4` / `convert_float4` 128-bit vector reads and accumulate into `float4` registers, fully utilizing Intel HD Graphics Execution Units.
   - **Hybrid CPU+GPU Pipeline**: The GPU handles the computationally dense FFN layers (Gate/Up/Down projections) and LM Head; the CPU handles latency-sensitive attention and KV-cache operations with AVX2.
   - **Runtime Toggle**: `/gpu on|off` interactive command in `chat.ring`, and `model.setGPU(1/0)` in the scripting API.
   - **Measured Speedup**: +100% (2×) token generation on DeepSeek-R1-1.5B (4.17 vs 2.11 tok/s) with Intel HD Graphics 5500. Larger models benefit proportionally more.

4. **In-Core Transformer & Real-Time Token Streaming Engine:**
   - **Real-Time Token Streaming**: Low-level autoregressive generator API (`prefill`, `step`, `hasMore`, `generateStream`) pushing generated words directly to `stdout` with UTF-8 byte assembly.
   - **FP16 Compressed KV-Cache (2048 Context Window)**: Halves KV cache memory usage and scales context window up to 2048 tokens with Anti-Looping repetition penalty.
   - Built-in GGUF Byte-Pair Encoding (BPE) and GPT-2 Byte-Level Tokenizer with full Arabic and multilingual UTF-8 multi-byte decoding.
   - Native Mean-Pooling Embedding generation with token-0 attention-sink skipping for causal decoder models.

5. **BGE-M3 & BERT/XLM-RoBERTa Bidirectional Embedding Engine:**
   - **Native 24-Layer Bidirectional Encoder**: Direct C99 execution of non-causal Transformer encoder architectures (`general.architecture = "bert"` / `"xlm-roberta"`). All tokens attend across the entire sequence via $Q K^T / \sqrt{d}$ without causal masking.
   - **AVX2 Vectorized LayerNorm & GELU**: Hardware-accelerated standard LayerNorm with mean subtraction, scaling, and bias parameters alongside fast GELU activation for intermediate FFN projections.
   - **Learned Absolute Position & Type Embeddings**: Native handling of `position_embd.weight` (with RoBERTa padding offset $+2$) and `token_types.weight`.
   - **Token Embedding Q6_K Dequantization**: Full vector dequantization of 6-bit super-blocks in `token_embd.weight` (1024 x 250002).
   - **SentencePiece (SPM / T5) Tokenizer**: Automatically maps word boundaries via ` ` (`\xe2\x96\x81`), inserts `<s>` (ID 0) and `</s>` (ID 2), and tokenizes across 250k multilingual tokens.
   - **State-of-the-Art Dense Vectors (`BgeModel`)**: Produces 1024-dimensional $L_2$-normalized unit vectors via `[CLS]` token pooling for unparalleled semantic retrieval accuracy.

6. **Native RAG (Retrieval-Augmented Generation) & AlQalam Integration:**
   - **Dual-Model RAG Architecture**: Seamlessly pairs dedicated dense embedding models (`BgeModel` with `bge-m3-q4_0.gguf`) for retrieval with instruction LLMs (`QwenModel` / `DeepSeekModel`) for factual text generation.
   - **VectorStore & RAG Pipeline (`libraries/madar_ai/rag.ring`)**: In-memory and binary cached vector storage (`saveBinary`/`loadBinary`) with sub-10ms knowledge retrieval.
   - **AlQalam C++17 Hybrid Search**: Blends semantic dense vector embeddings (70%) with O(1) lexical inverted indexing (`QalamIndex`, 30%) and direct PDF ingestion via `QalamReader`.

7. **Autonomous AI Agents & Intent-Driven Cognitive Architecture (`examples/MadarAgent`):**
   - **Rasa-Style Three-Tier Execution Hierarchy**: Solves prompt saturation (+1,200 tokens) on commodity hardware by routing inputs into three distinct execution paths:
     - **Tier 1 (Zero-LLM Direct Response)**: Sub-second instantaneous responses ($< 1$s) for greetings, identity queries, and FAQs with zero LLM compute.
     - **Tier 2 (Zero-LLM Direct Tool Execution)**: PCRE2 regular expression extraction (`ringregex`) for mathematical expressions, running tools like `calc` directly in $\sim 1.4$s with 100% precision without LLM inference.
     - **Tier 3 (Scoped Prompting & Ephemeral RAG)**: Dynamic prompt synthesis injecting *only* authorized tools and relevant skill overlays (e.g. `ring_coder`), dropping prompt size to ~250–350 tokens and slashing prefill latency from minutes to seconds.
   - **Semantic Intent Router (`core/semantic_router.ring`)**: High-accuracy intent detection via BGE-M3 (1024-dim Cosine Similarity) backed by a $< 1$ms binary cache (`intent_cache.bin`) with automated seed re-indexing.
   - **Ephemeral RAG Context**: Ground-truth knowledge chunks are injected strictly for the active turn and never appended into `aHistory`, preventing context bloat.
   - **Configurable Sliding Window**: `bUseSlidingWindow` and `nHistoryWindow = 2` preventing context saturation on long conversations.
   - **Interactive Agent Production CLI (`examples/MadarAgent/main.ring`)**: Live terminal session with ANSI badges, real-time performance profiler, and slash directives (`/intents`, `/reindex_intents`, `/history_window`, `/debug`, `/skills`, `/memory`).

8. **Madar DataFrame for Fast Table Analytics (`libraries/madar_ai/dataframe.ring`):**
   - Pure Ring + C-Tensor table engine parsing CSVs with zero external dependencies.
   - Binds numeric columns to continuous `RingTensor` views for microsecond statistical calculations (`mean`, `sum`, `min`, `max`, `std`, `describe`).
   - High-productivity filtering (`df.filter("salary", ">", 4500)`) and column selection.

9. **Self-Healing AI Agent Feedback Loop (`--json-errors`):**
   - RFC 8259 standardized structured JSON compiler and runtime diagnostics.
   - Provides line context, exact error codes, call stacks, and context-aware intelligent fix suggestions.

10. **Native Python-Like Modern Syntax Enhancements:**
   - **Native `f-strings` (`f"Hello {name}, 1+2={1+2}"`):** Direct scanner-level expression interpolation with zero runtime overhead, nested expressions, and brace escaping (`{{...}}`, `\{...\}`).
   - **Default Arguments (`func add(a, b = 10)`):** Native C99 bytecode-level default parameters evaluated dynamically at call time, avoiding Python's shared mutable default bug. Includes `argcount()` / `paramcount()` introspection.
   - **Advanced Slicing (`seq[start:stop:step]`):** 1-based inclusive slicing for strings and lists with stride, negative steps (`seq[::-1]` reversal), negative indexing (`seq[-1]`), and full backward compatibility with Ring hash maps (`dict[:name]`).
   - **List Comprehensions (`[x*x for x in list if x > 2]`):** Pythonic list comprehensions with single/multiple `if` filters, multi-variable nested `for` clauses, matrix construction, and expressions/f-strings/functions projections.
   - **High-Performance JIT Loops (`dour x = 1 to N`, `[x*x dour x in 1:N]`):** Native Arabic-derived loop keyword triggering Madar Auto-JIT via SLJIT to compile loops on the fly into native CPU machine code (7x - 90x speedup) while preserving 100% Ring standard interpreter compatibility with `for`.

---

## 🚀 Quick Start & Interactive Sessions
 
### ⚡ Google Colab Cloud Quickstart (Zero-Setup & GPU Enabled)
Experience the full power of Madar with 7B reasoning models and NVIDIA GPU acceleration in your browser:
- 🇸🇦 **[Madar Colab (Arabic)](notebooks/Madar_Colab_Quickstart.ipynb)** — Includes `%%madar` interactive cell magic, GPU OpenCL, and live AI Agent chat.
- 🇬🇧 **[Madar Colab (English)](notebooks/Madar_Colab_Quickstart_EN.ipynb)** — Complete English guide with GPU acceleration, AlQalam Hybrid RAG, and 7B models.

### 1. Download Model (Windows / Local)
Download supported quantized models directly into the `models/` directory:
```cmd
tools\download_deepseek.bat   :: DeepSeek-R1-Distill-Qwen-1.5B (Q4_0, ~1.1 GB)
tools\download_model.bat      :: Qwen2.5-0.5B / 3B-Instruct (Q4_0, ~350 MB - 1.9 GB)
```

### 2. Dual-Model RAG with BGE-M3 & Qwen (البحث الدلالي عالي الدقة)
```cmd
bin\ring.exe examples\ai\bge_rag_demo.ring
```

### 3. Production Autonomous Agent (MadarAgent 2.0 - المعمارية الهجينة الموجهة بالنوايا)
```cmd
cd examples\MadarAgent
ring main.ring "0.5b"    :: Ultra-fast intent-driven agent (Qwen2.5-0.5B, sub-second responses)
ring main.ring coder     :: Specialized coding agent (Qwen2.5-Coder-1.5B, Style 3 syntax)
```

### 4. Real-Time Token Streaming (بث الكلمات فائق السرعة)
```cmd
bin\ring.exe examples\ai\stream_demo.ring
```

### 5. Interactive Reasoning Chat (DeepSeek-R1 & Qwen)
```cmd
bin\ring.exe examples\ai\chat.ring
```

### 6. Declarative Scripting API with BGE-M3 & GPU
```ring
load "madar_ai.ring"
load "rag.ring"

# 1. High-accuracy 1024-dim embedding extraction with BGE-M3
embed_model = model_open("models/bge-m3-q4_0.gguf")
store = new VectorStore(embed_model)
store.addText("لحل خطأ نفاد الذاكرة في C، تأكد من استدعاء free() وتجنب تسريب الموارد.")

# 2. Query retrieval
query_vec = embed_model.get_embedding("كيف أعالج تسريب الذاكرة البرمجية؟")
matches = vector_search(query_vec, store, 1)
see "Top Match: " + matches[1][2] + nl

# 3. Text generation with Qwen (with GPU acceleration)
llm = model_open("models/qwen2.5-0.5b-instruct-q4_0.gguf")
llm.setGPU(1)
llm.chatStream("أجب باختصار بالاعتماد على: " + matches[1][2], 64)
```

---

## 🏗 Building Madar

### Prerequisites
- Windows 10/11 with Visual Studio 2022 (MSVC) or MinGW/GCC / Clang.

### 1. Fast Build (Core Runtime & AI Engine)
```cmd
build_vc.bat
```
Produces `bin\ring.exe`, `bin\ring.dll`, and static libraries in `lib\`.

### 2. Run Test Suites
```cmd
tests\run_all.bat
```
Runs comprehensive test suites covering core backward compatibility, tensor math, GGUF loader, Q6_K kernel, tokenizer, and JSON diagnostics.

---

## 📄 Documentation

- [Installation & Quickstart Guide (دليل التثبيت والتشغيل)](docs/INSTALL.md)
- [MadarAgent 2.0: Intent-Driven Hybrid Cognitive Architecture (دليل الوكيل الذكي)](docs/MADAR_AGENT.md)
- [AI Engine, GPU Acceleration & Real-Time Streaming](docs/AI_ENGINE.md)
- [Detailed Technical Architecture](docs/ARCHITECTURE.md)
- [Madar 'DOUR' (دُر) Loops & Auto-JIT Engine (حلقات دُر ومحرك الجيت)](docs/DOUR_LOOPS.md)
- [Python-style List Comprehensions Guide](docs/COMPREHENSIONS.md)
- [Advanced Slicing & Strided Indexing Guide](docs/SLICING.md)
- [Default Arguments & Parameter Introspection](docs/DEFAULT_ARGS.md)
- [Formatted String Literals (f-strings) Guide](docs/FSTRINGS.md)
- [Complete Changelog & Release Notes](CHANGELOG.md)

---

## 📜 License
Madar is released under the MIT License, adhering to the upstream Ring ecosystem.
