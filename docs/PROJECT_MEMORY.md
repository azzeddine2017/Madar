# Madar Project Memory & Architectural Registry

## 🏛️ Strategic Vision: Unified Cognitive, Tensor & Decision Intelligence Runtime
**Madar (مدار)** is engineered as an ultra-fast, lightweight (< 4 MB runtime core), multi-modal cognitive, tensor, and mathematical execution engine built on **Ring**.

It unifies three decoupled pillars:
1. **Modernized Ring/Madar VM & Language Core:** Pythonic ergonomics (`f-strings`, comprehensions, slicing, default args), `dour` SLJIT Auto-JIT, native `async`/`await`, Computed Gotos, UTF-8 Arabic support, and RFC 8259 `--json-errors`.
2. **Native Tensor & Neural Inference Engine (`madar_ai`):** Embedded C99 GGML, zero-copy `RingTensor`, memory-mapped GGUF (`Q4_0`, `Q8_0`, `Q6_K`, BitNet `I2_S`), AVX2/FMA SIMD, OpenCL GPU offloading, LoRA training/export, BGE-M3 RAG, C-backed `DataFrame`, and Three-Tier `MadarAgent`.
3. **Decision Intelligence & Operations Research (`MadarOpt`):** High-speed combinatorial optimization and algebraic LP/MILP solvers for industrial problems (1D/2D Cutting Stock, Bin Packing, What-If Simulation).

---

## 🛠️ Engineering Standards & Protocols (`AgentCodeGear_EN.md`)
1. **Supreme Operating Principles (Code Gear-1):**
   - **Module-Driven Engineering (MDE):** Deconstruct into prioritized, self-contained modules; verify each before proceeding.
   - **Madar-First Modern Syntax:** Prefer `f-strings`, `dour` JIT loops, list comprehensions, `seq[start:stop:step]` slicing, default arguments, and `RingTensor` over legacy workarounds.
   - **Surgical Precision:** Read/inspect before editing; avoid blind overwrites.
   - **Autonomous Self-Correction:** Diagnose compiler/runtime/tensor issues via `ring --json-errors <file.ring>`.
   - **Zero Node.js Dependency:** Use `ringpm` or native C extensions exclusively.
   - **Intuition-First UI/UX:** Follow Jacob's Law for user interfaces.
2. **Coding Conventions:**
   - **Hungarian Notation:** `c` (String), `n` (Number), `a` (List/Array), `o` (Object), `b` (Boolean).
   - **Encapsulation & Safety:** Use `private` class sections, `try ... catch` with contextual `cCatchError` (`Line %d %s in %s`), and inline function docblocks.
3. **Persistent Memory Protocol:** Bootstrap context from `docs/PROJECT_MEMORY.md` / `CHANGELOG.md` / `git log` on new sessions; record verified architectural milestones here and in `CHANGELOG.md`.

---

## ⚙️ Core Runtime & Language Milestones (`0.1.0-alpha` – `0.4.0-alpha`)

### 1. Modern Syntax & VM Dispatch Acceleration
- **Scanner & Parser Enhancements:**
  - `f-strings` (`f"..."`, `f'...'`, `f`...``): Scanner-level desugaring with up to 8 nesting levels (`RING_SCANNER_MAXFSTRINGLEVEL = 8`).
  - **List Comprehensions:** `[expr for var in source (if cond)?]` supporting chained `if` filters and nested `for` clauses (`ICO_LISTSTART`, `ICO_JUMPFOR`, `ICO_LISTITEM`, `ICO_LISTEND`).
  - **Advanced Slicing (`ICO_SLICE`):** 1-based inclusive Python-style `seq[start:stop:step]`, negative indices, and `seq[::-1]` reversal while preserving `user[:key]` map lookups.
  - **Default Arguments (`ICO_CHECKARG`):** Dynamic call-time evaluation in callee scope (no shared mutable default bug), plus `argcount()` / `paramcount()`.
  - **Native `async` / `await` (`ICO_AWAIT`):** First-class `K_ASYNC` / `K_AWAIT` keywords (78 total keywords) and `ring_vm_await()`.
- **Execution Speedups:**
  - **`dour` (دُر) Auto-JIT Loops:** SLJIT native x86_64 compilation for pure numerical loops (**7x–90x speedup**). Introspection: `jit_available()`, `jit_autoloops()`, `jit_sumsq(N)`.
  - **Computed Gotos (`RING_VM_COMPUTEDGOTO 1`):** GCC/Clang direct threading and MSVC monolithic inlined dispatch loop (`language/src/vmcgoto.c`).
  - **`for-in` Compiler Fixes:** Single-evaluation hoisting for anonymous expressions (eliminating $O(N^2)$ bottleneck: >2 min $\to$ ~15 ms) and `lFastLen` zero-copy substring/list indexing.

### 2. Diagnostics, Unicode & System Primitives
- **Structured JSON Diagnostics (`--json-errors` / `MADAR_JSON_ERRORS=1` / `madar_json_errors()`):** Full RFC 8259 coverage (`C1`–`C31`, `S1`–`S3`, `R1`–`R55`, `E1`–`E18`, `TENSOR_ERR`), token reconstruction for `eval()`, visual caret markers, and Levenshtein fuzzy fix hints.
- **Native UTF-8 Arabic & Unicode:** Bijective multi-byte UTF-8 `ascii(cChar)` and `char(nCode)` (`char(ascii("م")) == "م"`).
- **Hardware Monotonic Timers & Console I/O:** `nanotime()`, `microtime()`, `perf_counter()`, `hrtime()`, `Chronos` class (`libraries/chronos.ring`), and non-blocking `checkkey()`, `kbhit()`, `getkey()`.

---

## 🧠 Tensor, AI & Cognitive Runtime (`0.1.0-alpha` – `0.4.3-alpha`)

### 1. `RingTensor`, GGML & GGUF Core
- **Native `RingTensor` (`language/src/ring_tensor.c`):** Ref-counted contiguous `RingTensorStorage` (up to 8 dims, `Float32`, `Float16`, `Int8`, `Int32`, `Float64`), zero-copy views/slices/reshapes, cache-blocked $IKJ$ `tensor_matmul`, and native VM operator overloading (`+`, `-`, `*`, `/`) in `vmexpr.c`.
- **Embedded C99 GGML & Zero-Copy GGUF (`ring_gguf.c`):** Win32 `CreateFileMapping` / `MapViewOfFile` memory-mapped GGUF v2/v3 loader; BPE (GPT-2/Qwen) and SentencePiece/T5 tokenizers; `Q4_0`, `Q8_0`, `Q6_K`, `F16`/`F32`, and **BitNet b1.58 `I2_S`** ternary weights (`RING_GGUF_TENSOR_I2_S = 35`, 7.5x compression vs FP16).

### 2. Hybrid CPU (AVX2) + OpenCL GPU Inference & LoRA Training
- **SIMD & Dynamic OpenCL (`opencl_stub.h`):** Runtime `LoadLibraryA("OpenCL.dll")` with zero SDK link dependencies and automatic AVX2/FMA/F16C CPU fallback.
- **Zero-Copy VRAM & Fused Pipelines:** Pre-mapped `pGPUBuf` across all 28 layers ($Q, K, V, \text{Out}$, FFN Gate/Up/Down, LM Head); chunked layer-wise prefill ($B \le 32$, 32x DRAM traffic reduction); fused SwiGLU FFN GPU pipeline (`madar_gpu_ffn_fused_batch`, 3x decode speedup); FP16 compressed KV-Cache (`nMaxSeq = 2048`).
- **Native LoRA Inference, Training & Export (`0.4.2`–`0.4.3`):**
  - Runtime adapter fusion $y += \text{scale} \cdot (B \cdot (A \cdot x))$ via `.loadLoRA()`, `.enableLoRA()`, `.setLoRAScale()`.
  - Chunked teacher-forcing LoRA training (`ring_model_train_chunk`, 66x fewer OpenCL launches, sub-second per sample on T4) with Fisher-Yates `MadarInstructDataset.shuffle()`.
  - Standalone merged GGUF exporter (`ring_model_export_merged_gguf` + `quantize_row_q4_0_fast`, <4s export).

### 3. BGE-M3 RAG, DataFrames & `MadarAgent`
- **BGE-M3 / BERT Encoder (`BgeModel`):** 24-layer bidirectional non-causal transformer with AVX2 `layernorm`, `fast_gelu`, and 1024-dim $L_2$-normalized CLS embeddings; `VectorStore` binary cache (<9 ms) and `RAGPipeline` (`libraries/madar_ai/rag.ring`).
- **C-Accelerated `DataFrame` (`libraries/madar_ai/dataframe.ring`):** Zero-dependency `read_csv()` binding numerical columns to `RingTensor` (`mean`, `sum`, `min`, `max`, `std`, `filter`, `select`, `describe`).
- **Three-Tier `MadarAgent` (`examples/MadarAgent/`):**
  - Tier 1: Zero-LLM instant FAQ/greeting (<1s).
  - Tier 2: Zero-LLM PCRE2 (`ringregex`) direct tool execution (~1.4s).
  - Tier 3: Scoped prompt + Ephemeral RAG + `SemanticIntentRouter` (BGE-M3 `intent_cache.bin`, <1ms load) + real-time streaming with `Esc`/`Ctrl+C` cancellation.

---

## 📦 Decoupled Architecture Principles
1. **Zero-Coupling Boundary:**
   - Neural/LLM inference (`MadarAgent`, GGUF) is strictly decoupled from the mathematical optimization engine (`MadarOpt`).
   - `MadarOpt` has zero dependency on neural weights, GPU VRAM, or prompt text generation.
2. **Headless & Microservice Design:**
   - Industrial plants run headless solvers. Inputs are structured tables (CSV, JSON, SQL/ERP databases), and outputs are deterministic execution schedules (Gantt-compatible JSON, CSV cutting lists).
3. **Numerical Acceleration Rules:**
   - `dour` JIT (SLJIT) accelerates scalar arithmetic, numeric loop reductions, and continuous arrays.
   - Dynamic objects and strings remain in standard VM bytecode; inner calculation kernels stay strictly numerical.

---

## 🔬 `MadarOpt` Milestones & Verified Benchmarks

### 1. `MadarOpt 0.1.0-alpha` (Cutting Stock & Bin Packing)
- **Module:** `libraries/madar_opt/`
- **Problem Formulation:** 1D Linear Cutting Stock with blade saw kerf compensation.
- **Solvers:**
  - `HeuristicCuttingSolver`: First-Fit Decreasing (FFD) and Best-Fit Decreasing (BFD).
  - `GeneticCuttingSolver`: Multi-generation evolutionary search with elitism, tournament selection, and Order Crossover (OX).
- **Industrial Benchmark Results:**
  - Work order: 80 parts, 173 linear meters of profile.
  - Manual naive baseline: 40 stock bars, 67 meters waste (27.92% scrap), Cost: $1,800 USD.
  - MadarOpt BFD / GA: 30 stock bars, 7 meters waste (3.89% scrap), Cost: $1,350 USD.
  - **Direct ROI: $450 USD saved and 60 meters of metal saved on a single order.**
  - **Latency:** BFD solver finished in **6 milliseconds**.

### 2. RingTensor vs `dour` in Operations Research (Empirical Findings)
- **The Reality of `dour` (Auto-JIT):** Excellent for pure scalar mathematical reductions without branching ($s += x \cdot x$). Falls back to interpreted VM bytecode on dynamic list indexing (`aList[i]`) or conditional branching (`if`).
- **The Dominance of `RingTensor` (In-Core AVX2 SIMD):**
  - Formulated batched GA candidate evaluation as matrix multiplication $Y = A \cdot w$ ($A \in \{0, 1\}^{M \times N}$, $w \in \mathbb{R}^{N \times 1}$) via single hardware GEMM call.
  - **Benchmark (`benchmarks/benchmark_tensor_vs_list.ring`):** 1,000 evaluations across 40 bars $\times$ 80 items (3.2M ops): Standard Ring List loops **2,775.02 ms** vs Madar `RingTensor` **24.42 ms** (**113.64x FASTER**).

### 3. Production Ingestion & Headless CLI Engine
- **Module:** `libraries/madar_opt/io/` & `libraries/madar_opt/cli.ring`
- **Data Ingestion (`OptDataLoader`):** Ingests factory CSV work orders (`item_id, length, quantity`).
- **Plan Export (`OptPlanExporter`):** Emits `cutting_plan.csv` and CNC/MES-ready `cutting_plan.json`.
- **Verification Run:** 106 pieces (193.9 meters) solved in **21.5 ms** (34 bars vs theoretical lower bound 33; waste ratio **4.95%**).

### 4. What-If Multi-Scenario Simulation Engine & Data Isolation Protocol
- **Module:** `libraries/madar_opt/core/scenario_engine.ring`, `io/decision_reporter.ring`
- **Data Directory Isolation:** Inputs strictly in `libraries/madar_opt/data/inputs/`; outputs strictly in `libraries/madar_opt/data/outputs/`.
- **Scenario Simulation:** Evaluates competing supply/procurement scenarios in parallel, identifying **Recommended Winner** (Pareto-optimal), **Cheapest Option**, and **Greenest Option**, exporting `scenario_comparison.csv` and `executive_decision_brief.json`.
- **Benchmark Performance:** 4 enterprise scenarios (106 parts, 193.9 meters) in **20.21 ms**; Regression Suite: **7/7 Passed**.

### 5. Generalized Mathematical Modeler & Algebraic Optimization Engine
- **Module:** `libraries/madar_opt/modeler/`
- **Algebraic Modeler (`OptModel`, `OptVariable`, `OptConstraint`):** Continuous (`OPT_CONTINUOUS`), integer (`OPT_INTEGER`), and binary (`OPT_BINARY`) variables compiled into `RingTensor` matrices ($A x \le b$, $A x \ge b$, $A x == b$).
- **Solvers:** `OptSimplexSolver` (Two-Phase Simplex) and `OptBranchBoundSolver` (MILP Branch-and-Bound).
- **Verification (`tests/test_modeler.ring`, 4/4 Passed):**
  1. Dantzig Product Mix LP: $x_1^* = 2.0, x_2^* = 6.0, Z^* = 36.0$ (**665 us**).
  2. Two-Phase Diet LP: $x_1^* = 3.0, x_2^* = 1.0, Z^* = 9.0$ (**422 us**).
  3. Discrete Knapsack MILP: $x_1^* = 2, x_2^* = 1, Z^* = 16.0$ (**4.6 ms**).
  4. Capital Budgeting Binary 0/1: $P_1 = 1, P_2 = 0, P_3 = 1, Z^* = 35.0$ (**1.01 ms**).

### 6. 2D Rectangular Cutting Stock & Generalized MILP Nesting
- **Modules:** `cutting_stock_2d.ring` (`toPatternMILP()`), `heuristic_2d_solver.ring` (BSSF guillotine with 90° rotation), `plan_exporter.ring`, `cli.ring` (`--2d` workflow).
- **Optimization Insight:** Integer objective ceiling pruning rule `ceil(nNodeObj - 0.0001) >= nBestObj` reduced Branch-and-Bound exploration from 500 nodes (25s) to 5 nodes (**11.49 ms**).
- **Verification (`tests/test_cutting_2d.ring`):** **4/4 Passed** (Total `MadarOpt` suite: **15/15 Passed**).
