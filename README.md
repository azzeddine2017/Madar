# Madar (مدار)

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

3. **In-Core Transformer & LLM Inference Pipeline:**
   - Standalone ANSI C99 inference runtime with RMSNorm, RoPE (with NeoX split mode & GQA support), SwiGLU FFN, and multi-thread worker dispatch.
   - Built-in GGUF Byte-Pair Encoding (BPE) and GPT-2 Byte-Level Tokenizer with full Arabic and multilingual UTF-8 multi-byte decoding.
   - Native Mean-Pooling Embedding generation with token-0 attention-sink skipping.
   - Prompt prefill acceleration (skipping redundant logits projection on prompt tokens).
   - Real-time token streaming REPL (`examples/ai/chat.ring`).

4. **Native RAG (Retrieval-Augmented Generation) & AlQalam Integration:**
   - **VectorStore & RAG Pipeline (`libraries/madar_ai/rag.ring`)**: In-memory and binary cached vector storage (`saveBinary`/`loadBinary`) with sub-10ms knowledge retrieval.
   - **AlQalam C++17 Hybrid Search**: Blends semantic dense vector embeddings (70%) with O(1) lexical inverted indexing (`QalamIndex`, 30%) and direct PDF ingestion via `QalamReader`.

5. **Self-Healing AI Agent Feedback Loop (`--json-errors`):**
   - RFC 8259 standardized structured JSON compiler and runtime diagnostics.
   - Provides line context, exact error codes, call stacks, and context-aware intelligent fix suggestions.

6. **Native Python-Like Modern Syntax Enhancements:**
   - **Native `f-strings` (`f"Hello {name}, 1+2={1+2}"`):** Direct scanner-level expression interpolation with zero runtime overhead, nested expressions, and brace escaping (`{{...}}`, `\{...\}`).
   - **Default Arguments (`func add(a, b = 10)`):** Native C99 bytecode-level default parameters evaluated dynamically at call time, avoiding Python's shared mutable default bug. Includes `argcount()` / `paramcount()` introspection.
   - **Advanced Slicing (`seq[start:stop:step]`):** 1-based inclusive slicing for strings and lists with stride, negative steps (`seq[::-1]` reversal), negative indexing (`seq[-1]`), and full backward compatibility with Ring hash maps (`dict[:name]`).
   - **List Comprehensions (`[x*x for x in list if x > 2]`):** Pythonic list comprehensions with single/multiple `if` filters, multi-variable nested `for` clauses, matrix construction, and expressions/f-strings/functions projections.
   - *Roadmap:* Context managers (`with expr as var`), Keyword / Named arguments (`func(name="Ali")`), tuple unpacking / multiple assignments (`a, b = b, a`), chained comparisons (`10 <= x <= 100`).

---

## 🚀 Quick Start & Interactive Chat

### 1. Download Model
You can download supported quantized models directly into the `models/` directory:
```cmd
tools\download_deepseek.bat   :: Downloads DeepSeek-R1-Distill-Qwen-1.5B (Q4_0, ~1.1 GB)
tools\download_model.bat      :: Downloads Qwen2.5-3B-Instruct (Q4_0 / Q6_K, ~1.9 GB)
```

### 2. Interactive Terminal Chat
Launch local interactive AI chat directly from your terminal:
```cmd
:: Run with DeepSeek-R1 (with real-time reasoning & CoT)
bin\ring.exe examples\ai\chat.ring

:: Run with Qwen-3B
bin\ring.exe examples\ai\chat.ring qwen
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

- [Detailed Technical Architecture](docs/ARCHITECTURE.md)
- [Formatted String Literals (f-strings) Guide](docs/FSTRINGS.md)
- [Complete Changelog & Release Notes](CHANGELOG.md)

---

## 📜 License
Madar is released under the MIT License, adhering to the upstream Ring ecosystem.
