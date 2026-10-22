# Madar (مدار)

[![Release](https://img.shields.io/badge/Release-0.2.0--alpha-blue.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/Platform-Windows%20x64%20|%20AVX2-green.svg)](docs/INSTALL.md)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

> **An AI-Native, High-Performance Dialect and Runtime for the Ring Ecosystem**

**Madar** (مدار) is a high-performance, AI-first fork of **Ring Lite (Ring 1.27 Core)**. Engineered specifically for native tensor arithmetic, direct hardware execution of quantized LLMs, and high-productivity modern syntax extensions, Madar maintains 100% backward compatibility with Ring while providing cutting-edge local inference capabilities on commodity CPU hardware.

---

## 🎯 Core Features & Architecture

1. **Native Continuous Tensor Engine (`ITEMTYPE_TENSOR = 6`):**
   - Implemented at the C core layer with **zero struct overhead** (utilizing Ring's unused 3-bit bitfield in `Item`).
   - Supports zero-copy memory-mapped tensors, strided slicing, reshaping, and full bidirectional conversion bridges (`List <-> Tensor`).
   - Precision formats: `Float32`, `Float16`, `Int8`, `Int32`, `Float64`.
   - Native operator overloading (`+`, `-`, `*`, `/`, scalar arithmetic) and neural activations (`ReLU`, `GELU`, `Sigmoid`, `Softmax`).

2. **Full GGUF & Quantization Support (V2 / V3) + AVX2 SIMD Core:**
   - High-throughput binary reader supporting `Q4_0`, `Q8_0`, `F16`, and `F32`.
   - **Hardware-Accelerated AVX2 & FMA Dot Products**: 256-bit SIMD vectorized kernels unpacking 32 x 4-bit nibbles and calculating matrix multiplications with F16C and FMA instructions for unprecedented CPU generation speed.
   - **Full Q6_K Super-Block Dequantization**: Native vector dot product kernel for `Q6_K` tensors (`output.weight` in modern 6-bit quantized models).
   - Zero-copy OS memory mapping (`MapViewOfFile` / `mmap`), enabling multi-gigabyte models to be mounted in fractions of a second with under 20 MB of active runtime RAM.

3. **In-Core Transformer & Real-Time Token Streaming Engine:**
   - **Real-Time Token Streaming**: Low-level autoregressive generator API (`prefill`, `step`, `hasMore`, `generateStream`) pushing generated words directly to `stdout` with UTF-8 byte assembly.
   - **FP16 Compressed KV-Cache (2048 Context Window)**: Halves KV cache memory usage and scales context window up to 2048 tokens with Anti-Looping repetition penalty.
   - Built-in GGUF Byte-Pair Encoding (BPE) and GPT-2 Byte-Level Tokenizer with full Arabic and multilingual UTF-8 multi-byte decoding.
   - Native Mean-Pooling Embedding generation with token-0 attention-sink skipping.

4. **Native RAG (Retrieval-Augmented Generation) & AlQalam Integration:**
   - **VectorStore & RAG Pipeline (`libraries/madar_ai/rag.ring`)**: In-memory and binary cached vector storage (`saveBinary`/`loadBinary`) with sub-10ms knowledge retrieval.
   - **AlQalam C++17 Hybrid Search**: Blends semantic dense vector embeddings (70%) with O(1) lexical inverted indexing (`QalamIndex`, 30%) and direct PDF ingestion via `QalamReader`.

5. **Autonomous AI Agents & Long-Term Episodic Memory (`libraries/madar_ai/agent.ring`):**
   - **Persistent Vector Memory**: Saves facts, user preferences, and project rules to disk in binary format (`.bin`) with automated cosine similarity retrieval.
   - Declarative tool registration (`agent.registerTool`).
   - Automated ReAct execution loop: intercepts `<tool_call>`, executes native Ring functions, injects `<tool_response>`, and synthesizes final factual answers.
   - Built-in tools: exact mathematics (`calc`), system time/clock (`get_time`), file access (`read_file`), directory listing (`list_files`), OS diagnostics (`sys_info`), currency exchange (`currency_rate`), knowledge search (`rag_search`), memory inscription (`remember_fact`), and CSV DataFrame analytics (`csv_summary`, `csv_query`).
   - **Interactive Agent REPL CLI (`examples/ai/agent_chat.ring`)**: Full live terminal session with streaming output, slash commands (`/remember`, `/recall`, `/learn`, `/memory`, `/undo`, `/history`), and multi-lingual dialogue.

6. **Madar DataFrame for Fast Table Analytics (`libraries/madar_ai/dataframe.ring`):**
   - Pure Ring + C-Tensor table engine parsing CSVs with zero external dependencies.
   - Binds numeric columns to continuous `RingTensor` views for microsecond statistical calculations (`mean`, `sum`, `min`, `max`, `std`, `describe`).
   - High-productivity filtering (`df.filter("salary", ">", 4500)`) and column selection.

7. **Self-Healing AI Agent Feedback Loop (`--json-errors`):**
   - RFC 8259 standardized structured JSON compiler and runtime diagnostics.
   - Provides line context, exact error codes, call stacks, and context-aware intelligent fix suggestions.

8. **Native Python-Like Modern Syntax Enhancements:**
   - **Native `f-strings` (`f"Hello {name}, 1+2={1+2}"`):** Direct scanner-level expression interpolation with zero runtime overhead, nested expressions, and brace escaping (`{{...}}`, `\{...\}`).
   - **Default Arguments (`func add(a, b = 10)`):** Native C99 bytecode-level default parameters evaluated dynamically at call time, avoiding Python's shared mutable default bug. Includes `argcount()` / `paramcount()` introspection.
   - **Advanced Slicing (`seq[start:stop:step]`):** 1-based inclusive slicing for strings and lists with stride, negative steps (`seq[::-1]` reversal), negative indexing (`seq[-1]`), and full backward compatibility with Ring hash maps (`dict[:name]`).
   - **List Comprehensions (`[x*x for x in list if x > 2]`):** Pythonic list comprehensions with single/multiple `if` filters, multi-variable nested `for` clauses, matrix construction, and expressions/f-strings/functions projections.
   - **High-Performance JIT Loops (`dour x = 1 to N`, `[x*x dour x in 1:N]`):** Native Arabic-derived loop keyword triggering Madar Auto-JIT via SLJIT to compile loops on the fly into native CPU machine code (7x - 90x speedup) while preserving 100% Ring standard interpreter compatibility with `for`.

---

## 🚀 Quick Start & Interactive Sessions

### 1. Download Model
Download supported quantized models directly into the `models/` directory:
```cmd
tools\download_deepseek.bat   :: DeepSeek-R1-Distill-Qwen-1.5B (Q4_0, ~1.1 GB)
tools\download_model.bat      :: Qwen2.5-0.5B / 3B-Instruct (Q4_0, ~350 MB - 1.9 GB)
```

### 2. Autonomous Agent Terminal (مع الذاكرة المتجهية الدائمة)
```cmd
bin\ring.exe examples\ai\agent_chat.ring
```

### 3. Real-Time Token Streaming (بث الكلمات فائق السرعة)
```cmd
bin\ring.exe examples\ai\stream_demo.ring
```

### 4. Interactive Reasoning Chat (DeepSeek-R1 & Qwen)
```cmd
bin\ring.exe examples\ai\chat.ring
```

### 3. Declarative Scripting API
```ring
load "madar_ai.ring"

# Load Qwen or DeepSeek directly
model = new DeepSeekModel("models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf")
model.setThreads(4)
model.setTemperature(0.6)

# Generate response
response = model.chatStream("ما هي عاصمة الجزائر؟", 128)
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
- [AI Engine & Real-Time Streaming Architecture](docs/AI_ENGINE.md)
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
