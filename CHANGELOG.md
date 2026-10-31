# Changelog - Madar Runtime (مدار)

All notable changes to the **Madar** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.0-alpha] - 2026-10-29

### Added

- **Native Asynchronous Programming Engine (`async` / `await` - Track C Core Architecture):**
  - **First-Class Core Keywords**: Added `K_ASYNC` and `K_AWAIT` to `language/include/scanner.h` and `RING_KEYWORDS[]` (keywords count updated to 78), recognized natively across the scanner and parser with zero third-party dependencies.
  - **Asynchronous Function Declarations (`async func` / `async def`)**: Implemented in `language/src/stmt.c`, marking functions in `pFunctionsMap` with the `lIsAsync` metadata flag, with safe token backtracking when `async` is not followed by a function definition.
  - **Unary Await Operator (`await <expr>`)**: Implemented in `language/src/expr.c` (`ring_parser_factor`), parsing `await` expressions with unary prefix precedence and emitting intermediate bytecode `ICO_AWAIT`.
  - **Bytecode & VM Execution Engine**:
    - Added `ICO_AWAIT` to `IC_OPERATIONS` in `language/include/codegen.h` and mnemonic array `RING_IC_OP[]`.
    - Integrated `ring_vm_await(VM *pVM)` into `language/src/vmfuncs.c`, `language/src/vm.c`, and the Computed Gotos jump table (`language/src/vmcgoto.c`).
    - Inspects operands at runtime on the VM stack, dynamically unrolls and executes registered async resolution dispatchers, and resumes execution seamlessly.
  - **Comprehensive Verification & Tests**: Added [`tests/core/test_async_native.ring`](tests/core/test_async_native.ring) covering primitives, expressions, async function invocations, and compound statements with 100% pass rate.
  - **Interactive Demo**: Created [`examples/async_demo.ring`](examples/async_demo.ring) demonstrating async data fetching, analytical scoring, and list comprehensions with microsecond hardware timing.
  - **Full Documentation**: Published comprehensive technical specifications in [`docs/ASYNC_AWAIT.md`](docs/ASYNC_AWAIT.md).

- **Intent-Driven Hybrid Cognitive Architecture (`examples/MadarAgent/`):**
  - **Rasa-Inspired Three-Tier Execution Engine**: Replaced heavy brute-force prompt construction (+1,200 tokens) with an ultra-fast, zero-overhead Three-Tier execution pipeline:
    - **Tier 1 (Zero-LLM Direct Response)**: Sub-second instantaneous responses ($< 1$s, $0$ tokens prefilled) for identity queries, greetings, and system FAQs without activating LLM inference.
    - **Tier 2 (Zero-LLM Direct Tool Execution)**: Integrated PCRE2 regular expressions (`ringregex`) for instant parameter and arithmetic formula extraction, executing tools (e.g. `calc`) directly in $\sim 1.4$s with 100% mathematical precision and zero LLM compute.
    - **Tier 3 (Scoped Prompting & Ephemeral RAG)**: Dynamic prompt synthesis injecting *only* authorized tools (e.g. 2 coding tools instead of 8 general tools) and targeted skill overlays (e.g. `ring_coder`), dropping prompt token count from 1,200+ down to ~250–350 tokens and slashing prefill latency from minutes to seconds.
  - **Semantic Intent Router (`core/semantic_router.ring` & `core/intent_registry.ring`)**:
    - High-precision dense vector intent classification powered by BGE-M3 (1024-dim Cosine Similarity).
    - **Fast Binary Intent Cache (`memory/intent_cache.bin`)**: Loads pre-computed trigger vectors in $< 1$ms at startup without re-running embedding models.
    - **Smart Auto-Reindexing**: Automatically detects changes in trigger seeds and updates the cache without manual intervention.
    - Added interactive slash directives: `/intents` (view registered intent matrix), `/reindex_intents` (force vector re-indexing), and `/history_window <n>` (dynamic turn control).
  - **PCRE2 Entity Extraction & Tool Caller Upgrade (`core/entity_extractor.ring` & `core/tool_caller.ring`)**:
    - Leverages native C PCRE2 engine (`ringregex`) for robust extraction of arithmetic expressions, filepaths, code blocks, and XML `<tool_call>` tags with nested group parsing.
  - **Ephemeral RAG Context & Sliding Window Management (`app.ring` & `config.ring`)**:
    - Ground-truth RAG knowledge chunks are injected strictly into the active turn's user prompt for immediate factual anchoring, but are **never** appended into persistent conversation history (`aHistory`), completely eliminating context explosion.
    - Configurable conversation sliding window (`bUseSlidingWindow = true`, `nHistoryWindow = 2`), ensuring flat memory usage during long dialogues.
  - **Native Arabic & Unicode UTF-8 Support in `ascii()` and `char()` (`language/src/genlib_e.c`):**
  - **Multi-Byte UTF-8 Decoding in `ascii(cChar)`**: Transparently decodes 2-byte, 3-byte, and 4-byte UTF-8 character sequences into their respective Unicode code points. `ascii("م")` yields `1605` (`0x0645`), `ascii("ا")` yields `1575` (`0x0627`), resolving legacy `Bad parameter length` errors while preserving 100% backward compatibility for ASCII (0–127).
  - **Dynamic Multi-Byte UTF-8 Encoding in `char(nCode)`**: Automatically emits valid 1 to 4-byte UTF-8 string sequences for Unicode code points up to `0x10FFFF`. `char(1605) + char(1583) + char(1575) + char(1585)` directly outputs `"مدار"`.
  - **Bijective Symmetry**: Guarantees `char(ascii("م")) == "م"` and `ascii(char(1605)) == 1605`.

- **High-Resolution Hardware Monotonic Timers (`language/src/genlib_e.c` & `libraries/chronos.ring`):**
  - **Native Core Timers**: Added `nanotime()` (sub-nanosecond resolution monotonic counter), `microtime()` (microsecond precision), `perf_counter()` (high-resolution fractional seconds), and `hrtime()` (alias) backed directly by CPU hardware performance counters (`QueryPerformanceCounter` on Windows and `clock_gettime(CLOCK_MONOTONIC)` on POSIX/Linux).
  - **Solving `clock()` Limitations**: Eliminates the 15.6ms Windows granularity and multi-threading/GPU offload inaccuracies of C standard `clock()`, providing true wall-clock nanosecond benchmarking.
  - **Chronos Stopwatch & Benchmark Library**: Integrated `Chronos` class (`libraries/chronos.ring`) with `.start()`, `.stop()`, `.elapsed_ns()`, `.elapsed_ms()`, and `.elapsed()` human-readable formatting, alongside automated `benchmark(cLabel, nRuns, fBlock)` helper.

- **Contextual `cCatchError` Enhancement (`language/src/vmtry.c`):**
  - Upgraded the native `cCatchError` variable populated inside `try ... catch` blocks to include the active line number, error code/description, and source file name (`Line %d %s in %s`), providing immediate debugging clarity without losing backward compatibility.

- **Comprehensive Diagnostics & Structured Feedback Overhaul (`--json-errors`):**
  - **Full Error Specification Coverage**: Integrated exhaustive diagnostic mappings covering all standard Ring 1.27 specifications: Compiler Errors (`C1`–`C31`), Scanner Errors (`S1`–`S3`), Runtime Errors (`R1`–`R55`), Environment Errors (`E1`–`E18`), and Native Tensor Errors (`TENSOR_ERR`).
  - **In-Memory & `eval()` Snippet Reconstruction**: Automatically reconstructs source lines directly from scanner tokens (`pTokens`) when executing dynamically evaluated code or memory buffers, completely eliminating empty `source_snippet` outputs.
  - **Accurate Token & Visual Marker Targeting**: Identifies the exact offending token (`offending_token`) and column offset (`column`), rendering ASCII visual caret pointers (`visual_marker`: `^`) pointing directly to syntax defects.
  - **Context-Aware Actionable Hints & Suggested Fixes**: Rich explanatory hints (`hint`) coupled with concrete, actionable correction recipes (`suggested_fix`) designed specifically for autonomous LLM self-healing.
  - **De-Duplication & Clean RFC 8259 Stream**: Suppressed duplicate line reporting and silenced plain text messages (e.g. `eval errors count : %d`) during `--json-errors` mode for 100% parseable JSON streams.
  - Dynamic runtime activation across all execution flags (`-e`, files, and `MADAR_JSON_ERRORS=1`).

- **Real-Time Latency & Generation Profiler**:
    - Embedded millisecond-precision profiler displaying Time-To-First-Token (TTFT), prefill speed (tok/s), and generation streaming throughput.

---

## [0.3.1-alpha] - 2026-10-26

### Added

- **BGE-M3 (BAAI General Embedding) & BERT/XLM-RoBERTa Architecture Support (`language/src/ring_inference.c`, `language/include/ring_inference.h`):**
  - **Native 24-Layer Bidirectional Transformer Encoder**: Implemented dedicated non-causal execution path for BERT and XLM-RoBERTa architectures (`general.architecture = "bert"` / `"xlm-roberta"`). Computes all-to-all token attention matrices across the full sequence without causal triangular masking.
  - **AVX2 SIMD LayerNorm Kernel (`layernorm`)**: Vectorized standard LayerNorm with mean subtraction, variance normalization, scale weights, and bias terms, replacing RMSNorm for encoder architectures.
  - **Fast GELU Activation (`fast_gelu`)**: High-precision tanh approximation of Gaussian Error Linear Units for FFN intermediate projection layers.
  - **Learned Absolute Position & Type Embeddings**: Native loading and addition of `position_embd.weight` (supporting RoBERTa's $+2$ padding index offset) and `token_types.weight` prior to layer normalization.
  - **Dense Embedding Extraction via CLS Pooling**: Directly extracts token 0 (`<s>` / `[CLS]`) representations and applies $L_2$ unit-vector normalization to produce 1024-dimensional continuous `RingTensor` embeddings for state-of-the-art Cosine Similarity search.
  - **Flexible Normalization & Biases**: Native parsing and application of per-layer biases (`attn_q.bias`, `attn_k.bias`, `attn_v.bias`, `attn_output.bias`, `ffn_up.bias`, `ffn_down.bias`, `attn_output_norm.bias`, `layer_output_norm.bias`).

- **Q6_K Super-Block Dequantization for Embeddings (`language/src/ring_gguf.c`, `language/include/ring_gguf.h`):**
  - Implemented `ring_gguf_dequantize_q6_k` to dequantize 256-element super-blocks into float32, allowing models with Q6_K quantized `token_embd.weight` (such as `bge-m3-q4_0.gguf`) to run with zero precision loss and maximum CPU cache efficiency.

- **SentencePiece (SPM / T5) Tokenizer Support (`language/src/ring_tokenizer.c`, `language/include/ring_tokenizer.h`):**
  - Added native SPM / T5 tokenizer model detection (`tokenizer.ggml.model = "t5"` / `"spm"`).
  - Handles SentencePiece space marker replacement (` ` / `\xe2\x96\x81`) and space-prefixing (`tokenizer.ggml.add_space_prefix = 1`).
  - Automatic injection of `<s>` (ID 0) prefix and `</s>` (ID 2) suffix special tokens for encoder models.

- **High-Level Framework & RAG Integration (`libraries/madar_ai/madar_ai.ring`, `examples/ai/bge_rag_demo.ring`):**
  - Added dedicated `BgeModel` class providing `.embedding(cText)`, `.get_embedding(cText)`, `.tokenize(cText)`, and thread configuration.
  - Updated `model_open(cPath)` factory to automatically detect BGE and BERT models (`bge-m3-q4_0.gguf`).
  - Created `examples/ai/bge_rag_demo.ring` demonstrating end-to-end Dual-Model RAG: 1024-dimensional dense semantic retrieval via BGE-M3 combined with grounded answer generation via Qwen2.5.

---

## [0.3.0-alpha] - 2026-10-24

### Added


- **OpenCL GPU Acceleration Engine (`language/src/ring_inference.c`, `language/include/opencl_stub.h`):**
  - **Dynamic OpenCL DLL Loading**: Added complete `opencl_stub.h` header defining all required OpenCL types, constants, and function pointer typedefs. GPU is enabled at runtime via `LoadLibraryA("OpenCL.dll")` and `GetProcAddress` — **zero linker-time dependencies** on any OpenCL SDK or `.lib` files. Graceful CPU-only fallback if no OpenCL driver is present.
  - **Zero-Copy GPU Weight Pre-Mapping**: All static model weight buffers (FFN Gate, FFN Up, FFN Down for every transformer layer, plus the LM Head `output.weight`) are bound once at model initialization using `CL_MEM_USE_HOST_PTR` zero-copy OpenCL buffers. This eliminates every dynamic `clCreateBuffer`/`clReleaseMemObject` call during token generation — **0 runtime GPU allocations per token**.
  - **Full-Pipeline Hybrid CPU+GPU Offload**: The GPU now handles all computationally intensive weight projections across the forward pass:
    - All 24–28 FFN layers: Gate projection (`W_gate * xb`), Up projection (`W_up * xb`), Down projection (`W_down * hb`).
    - LM Head: Output logit projection (`output.weight * xb`, up to 151,936 rows).
    - CPU retains: RMSNorm, RoPE, Multi-Head Attention with GQA, KV-Cache, SiLU activation, and sampling — all latency-sensitive operations where DDR3L cache efficiency dominates.
  - **128-bit SIMD OpenCL Kernels** (rewritten from scalar to vectorized):
    - `matvec_q4_0_kernel`: Uses `vload4(qs)` to load 4 nibble bytes at once, `convert_int4` bitmask unpacking, and `float4` accumulation — 4× fewer GPU iterations vs. scalar.
    - `matvec_q8_0_kernel`: Dual `float4` accumulators (`acc0 + acc1`) over 8 signed bytes per cycle — 8× throughput increase over single-element loop.
    - `matvec_q6_k_kernel`: Full vectorized `vload4` for `ql`, `qh`, and 4 `float4` accumulators per sub-block (`acc0`–`acc3`) — eliminates all scalar element-by-element loop overhead.
  - **Tuned Work-Group Size**: Replaced `NULL` local work size with `localSize = 64`, padding `globalSize` to the nearest multiple of 64. This aligns kernel dispatch to Intel HD Graphics SIMD-16 Execution Unit width for optimal occupancy.
  - **Runtime GPU Toggle**: Added `ring_model_set_gpu(pModel, bEnable)` C API, Ring-level `madar_model_set_gpu(h, b)`, `model.setGPU(1/0)` in `madar_ai.ring`, and `/gpu on|off` interactive command in `chat.ring`.
  - **GPU-Aware `matvec_multiply_gpu` Dispatch Function**: Unified internal dispatch function `matvec_multiply_gpu(pModel, pInfo, pGPUBuf, x, y, pBias)` that accepts a pre-mapped `cl_mem` handle directly; falls through to CPU AVX2 path if GPU buffer is `NULL` or GPU is disabled.

- **Measured Performance Improvements (Intel HD Graphics 5500 / Intel Core i3-5005U, DDR3L):**

  | Model | CPU-only (AVX2) | GPU (this release) | Speedup |
  | :--- | :--- | :--- | :--- |
  | Qwen2.5-0.5B (Q4_0 / Q8_0 output) | ~9.0 tok/s | ~8.7 tok/s | ≈ on par (FFN too small for DDR3L bus) |
  | DeepSeek-R1-1.5B (Q4_0 / Q6_K output) | 2.11 tok/s | **4.17 tok/s** | **+98% (≈ 2× speedup)** |

  *Note: GPU benefit scales with model size. Larger models (3B+) with bigger FFN dimensions will see proportionally greater speedup as the CPU becomes increasingly bottlenecked by DDR3L memory bandwidth.*

### Changed

- **`madar_gpu_init` (`language/src/ring_inference.c`):**
  - Now pre-maps all layer FFN buffers (Gate, Up, Down) via a post-initialization loop over `pModel->aLayers[l]` immediately after model weights are located and before `bGPUEnabled` is set to `1`.
  - Startup banner updated from `"(OpenCL Zero-Copy)"` to `"(Zero-Copy LM Head + N FFN Layers)"` showing the actual number of GPU-mapped layers.

- **`madar_gpu_matvec` signature (`language/src/ring_inference.c`):**
  - Removed `cl_context` parameter (no longer needed since no buffers are created at call time).
  - Added explicit `cl_mem bufW` parameter — callers now pass the pre-mapped buffer directly.
  - Eliminated `bOwnsBufW` dynamic buffer lifecycle: no `clCreateBuffer` / `clReleaseMemObject` occurs inside the hot path.

- **`madar_gpu_cleanup` (`language/src/ring_inference.c`):**
  - Extended cleanup loop to release all per-layer `pGPUBufGate`, `pGPUBufUp`, and `pGPUBufDown` handles before releasing global context and queue.

- **`RingLayerWeights` struct (`language/include/ring_inference.h`):**
  - Added three new `void *` fields: `pGPUBufGate`, `pGPUBufUp`, `pGPUBufDown` to hold pre-mapped OpenCL buffer handles for each transformer layer.

- **`ring_model_forward_ex` forward pass (`language/src/ring_inference.c`):**
  - All FFN and output projections now call `matvec_multiply_gpu(...)` directly with the respective pre-mapped buffer pointer, bypassing the generic `matvec_multiply` wrapper entirely for GPU-enabled inference.

- **`opencl_stub.h` (`language/include/opencl_stub.h`):**
  - Added missing `#define CL_DEVICE_TYPE_ALL 0xFFFFFFFF` and `#define CL_DEVICE_TYPE_DEFAULT (1 << 0)` constants that were causing `C2065: undeclared identifier` compilation errors with MSVC.

### Fixed

- **MSVC Build Error `C2065: 'CL_DEVICE_TYPE_ALL': undeclared identifier`**: Added missing OpenCL platform constants to `opencl_stub.h`, restoring clean zero-warning MSVC x64 build.
- **Eliminated GPU Hot-Path Dynamic Allocations**: Previous implementation was creating and releasing `clCreateBuffer` handles inside `madar_gpu_matvec` for every non-output layer call, causing hundreds of driver lock/unlock cycles per token. Fully resolved by restricting calls to pre-mapped buffers only.

---

## [0.2.0-alpha] - 2026-10-21


### Added

- **Modernized CLI Interface & Inline Evaluation (`language/src/state.c`, `language/include/state.h`):**
  - Added `-v, --version` flag to print Madar version, core release, and author attribution cleanly.
  - Added `-h, --help` flag displaying a beautifully categorized and grouped command-line help interface.
  - Added `-e, --eval <code>` flag for immediate one-liner execution of Madar code directly from the terminal.
  - Added `--sysinfo` flag presenting live hardware acceleration diagnostics (AVX2, FMA, F16C, 64-bit architecture) and AI inference runtime specs.
- **Real-Time Token Streaming & Step-by-Step Generator Engine (`language/src/ring_inference.c`, `libraries/madar_ai/madar_ai.ring`, `agent.ring`):**
  - Implemented low-level autoregressive generator API (`ring_model_prefill`, `ring_model_has_more`, `ring_model_step`).
  - Added high-speed native C streaming directly to `stdout` (`ring_model_generate_stream`) with automated UTF-8 byte assembly flushing.
  - Added custom Ring-level token interceptor callbacks (`model.generateStream(prompt, tokens, func(token) { ... })`).
  - Integrated live response streaming into `AIAgent` (`bStream = 1`, `agent.queryStream(...)`), streaming synthesized answers in real time as the agent thinks.
  - Added comprehensive interactive streaming demo `examples/ai/stream_demo.ring`.
- **FP16 Compressed KV-Cache & 2048-Token Context Scaling (`language/src/ring_inference.c`, `language/include/ring_inference.h`):**
  - Compressed Key and Value tensors from FP32 (32-bit) to half-precision `ggml_fp16_t` (16-bit), reducing memory consumption by 50%.
  - Expanded KV context window from 512 to 2048 tokens (`nMaxSeq = 2048`), allowing multi-turn conversations and long-document RAG without running out of context.
  - Implemented dynamic attention scores buffer `pAttScores` replacing fixed-size stack arrays.
  - Hardened repetition penalty (`1.25x` over 64 tokens, and `1.55x` consecutive token penalty) to eliminate repetitive text looping.
- **Autonomous Function Calling & AI Agent Runtime (`libraries/madar_ai/agent.ring`, `examples/ai/agent_chat.ring`):**
  - Added `AIAgent` class supporting declarative tool registration (`registerTool`).
  - Multi-turn conversational memory with history inspection (`/history`), turn rollback (`/undo`), and context reset (`/reset`).
  - Built-in system tools: mathematical evaluation (`calc`), real-time clock/date (`get_time`), local file reader (`read_file`), directory listing (`list_files`), OS diagnostics (`sys_info`), currency converter (`currency_rate`), and DataFrame table query/summary tools (`csv_summary`, `csv_query`).
  - Automated Hybrid ReAct execution loop: combines fast semantic intent routing with LLM tool-calling and response synthesis.
  - Interactive Agent REPL Terminal CLI (`examples/ai/agent_chat.ring`) featuring real-time token streaming, slash commands, and multi-lingual dialogue.
- **High-Performance C-Accelerated DataFrames (`libraries/madar_ai/dataframe.ring`):**
  - Added `DataFrame` class and `read_csv()` function parsing CSV tables with zero external dependencies.
  - Binds numerical columns directly to contiguous C-memory `RingTensor` views for microsecond statistical operations (`mean`, `sum`, `min`, `max`, `std`).
  - Rich analytical API: relational filtering (`df.filter("salary", ">", 4500)`), column projection (`df.select(...)`), row previews (`df.head`, `df.tail`), and summary statistics tables (`df.describe()`).
- **Hardware-Accelerated AVX2 & FMA SIMD Inference Core (`language/src/ring_inference.c`, `ring_tensor.c`, `language/build/buildvc_x64.bat`):**
  - Implemented 256-bit SIMD vector kernels for quantized tensor dot products (`dot_q4_0`, `dot_q8_0`, `dot_f16`, `dot_f32`).
  - `dot_q4_0`: Unpacks 32 x 4-bit nibbles across 4 AVX2 256-bit vector registers with zero-allocation, executing block multiply-adds concurrently.
  - `dot_q8_0`: Vectorized signed 8-bit dequantization with 256-bit FMA accumulation for lightning-fast output logits projection.
  - `dot_f16`: Direct hardware FP16 to FP32 conversion using `_mm256_cvtph_ps` (F16C) instructions.
  - `dot_f32` & `ring_tensor_cosine_similarity`: 8-way parallel vector dot product and norm calculation for embedding and RAG vector searches.
  - Portable design: Automatically falls back to ANSI C scalar implementations on non-AVX2 CPUs. Added `/arch:AVX2` flag to MSVC x64 build pipeline.
- **Native Mean-Pooling Embeddings & RAG Vector Engine (`language/src/ring_inference.c`, `libraries/madar_ai/rag.ring`):**
  - Native Mean Pooling with attention-sink token 0 skipping to eliminate vector anisotropy in modern embedding models (Qwen-Embedding).
  - Standalone `VectorStore` class supporting in-memory and binary disk caching (`saveBinary` / `loadBinary`), reducing database load time to under 9 ms.
  - `RAGPipeline` class offering seamless contextual augmentation for LLMs (`query(question)`).
- **AlQalam (القلم) AI & C++17 Ecosystem Integration (`examples/ai/qalam_rag.ring`):**
  - PDF document ingestion via `QalamReader` and native `pdftotext.exe`.
  - Zero-fragmentation prompt stitching via `QalamInk` dynamic memory buffers.
  - Hybrid Search Engine combining Semantic Vector Search (70%) and `QalamIndex` O(1) Lexical Inverted Index (30%).
  - Nanosecond-precision profiling using `QalamChronos`.
- **Native Python-style List Comprehensions (`[expr for var in source (if cond)?]`) (`language/src/stmt.c`, `language/include/parser.h`):**
  - Added native syntactic and bytecode-level compilation for Python-style list comprehensions (`[x*x for x in list if x > 2]`).
  - Supports single and chained `if` filters (`[x for x in 1:10 if x > 3 if x < 8]`) with short-circuit skipping via `ICO_JUMPZERO`.
  - Supports multi-variable nested `for` clauses (`[x + y for x in [1, 2] for y in [10, 20]]`) for Cartesian products and permutations.
  - Supports projection of arbitrary expressions including functions, sub-lists, dictionaries, and f-strings.
  - Generates optimized C-speed Ring VM bytecode leveraging `ICO_LISTSTART`, `ICO_JUMPFOR`, `ICO_LISTITEM`, and `ICO_LISTEND` with zero new runtime opcodes or VM overhead.
  - Supports multiline syntax and direct slicing on comprehensions (`[x*2 for x in 1:10][1:3]`).
  - Preserves 100% backward compatibility with standard list literals `[1, 2, 3]` and empty lists `[]`.
  - Added comprehensive test suite `tests/core/test_comprehensions.ring` and documentation `docs/COMPREHENSIONS.md`.
- **Madar 'DOUR' (دُر) Loops & Auto-JIT Engine (`language/src/stmt.c`, `vmjump.c`, `ring_jit.c`, `docs/DOUR_LOOPS.md`):**
  - Added native Arabic-derived loop keyword `dour` (دُر) as a high-performance alternative to standard `for` (`dour x = 1 to N`, `[x*x dour x in 1:N]`).
  - Seamlessly triggers the Madar Auto-JIT compiler via SLJIT: loops meeting JIT criteria are compiled on the fly into native machine code (x86_64 CPU instructions) and executed bare-metal.
  - Achieves a **7x to 90x speedup** over interpreted loops for numerical and arithmetic workloads.
  - Preserves 100% backward compatibility: standard `for` continues running on the standard Ring VM interpreter.
  - Added introspection APIs (`jit_available()`, `jit_autoloops()`, `jit_sumsq(N)`) and dedicated documentation `docs/DOUR_LOOPS.md`.
- **Native Python-style Advanced Slicing (`seq[start:stop:step]`) (`language/src/expr.c`, `vmlists.c`, `vmstr.c`, `codegen.h`, `vm.c`, `vmcgoto.c`):**
  - Added native parser and VM support for slicing strings and lists using bracket syntax (`seq[start:stop:step]`).
  - Added new VM opcode `ICO_SLICE` with bit flags (`RING_SLICE_HAS_START`, `RING_SLICE_HAS_STOP`, `RING_SLICE_HAS_STEP`).
  - Adopted natural 1-based inclusive range semantics (`s[1:5]` extracts items 1 to 5), aligning with Ring's range operator `1:3`.
  - Supports omitting bounds: full sequence copy (`seq[:]`), prefix slice (`seq[:stop]`), suffix slice (`seq[start:]`).
  - Supports stride / step (`seq[::2]`, `seq[1:5:2]`).
  - Supports negative step for instant string and list reversal (`seq[::-1]`).
  - Supports negative single indexing and slice indices (`seq[-1]`, `seq[-3:]`, `seq[1:-2]`).
  - 100% backward compatible: preserves existing Ring hash-map lookups with string literal keys (`user[:name]`).
  - Added dedicated test suite `tests/core/test_slicing.ring` and documentation `docs/SLICING.md`.
- **Native Python-style Default Arguments (`func f(a, b=10)`) (`language/src/stmt.c`, `vmfuncs.c`, `vmjump.c`, `vm.c`, `vmcgoto.c`):**
  - Added native parser and VM support for default parameter values in function signatures (`func f(a, b = 10)` and `def f(a, b = 10)`).
  - Added new VM opcode `ICO_CHECKARG` to conditionally bypass default evaluation when the argument is supplied by the caller.
  - Dynamically evaluates default argument expressions at call time inside the callee's scope, avoiding Python's infamous mutable default shared object bug.
  - Allows later default arguments to dynamically reference earlier arguments (e.g., `func rect(w, h = w)`).
  - Works transparently with standard functions, anonymous functions (`func(...)`), and class methods.
  - Enforces syntax validation: non-default parameters cannot follow default parameters.
  - Added introspection built-ins `argcount()` and `paramcount()` to query actual passed argument counts at runtime.
  - Added dedicated test suite `tests/core/test_default_args.ring` and documentation `docs/DEFAULT_ARGS.md`.
- **Native Python-style Formatted String Literals (`f-strings`) (`language/include/scanner.h` & `language/src/scanner.c`):**
  - Added native scanner-level lexical support for formatted string literals (`f"..."`, `f'...'`, and `f`...``).
  - Interpolated expressions in `{...}` are desugared at tokenization time into grouped expression tokens `( "" + ... )`, guaranteeing zero runtime overhead, standard operator precedence, and type coercion.
  - Supports escaped braces via double braces (`{{` and `}}`) as well as backslash escaping (`\{` and `\}`).
  - Supports up to 8 levels of nested f-strings (`RING_SCANNER_MAXFSTRINGLEVEL = 8`) and multiline interpolation.
  - Preserves 100% backward compatibility with Ring Core syntax.
  - Added dedicated test suite `tests/core/test_fstrings.ring` and documentation `docs/FSTRINGS.md`.
- **Q6_K Super-Block Quantization Kernel (`language/src/ring_inference.c` & `language/include/ring_gguf.h`):**
  - Added binary layout structure `RingGGUFBlockQ6_K` (128-byte `ql` lower nibbles, 64-byte `qh` upper 2-bit quants, 16-byte signed 8-bit scales, 2-byte FP16 super-scale).
  - Implemented vectorized dot product routine `dot_q6_k` supporting 256-weight super-blocks and sub-block scale scaling.
  - Resolved `output.weight` type 14 support in Qwen-3B, eliminating the need to fall back to tied `token_embd.weight`.
  - Added dedicated diagnostic test suite `tools/test_q6k.ring`.
- **Dynamic Heap Buffer Scaling for Large LLMs (`language/src/ring_inference.c`):**
  - Migrated stack-allocated attention output (`attnOut`) and feed-forward output (`ffnOut`) to dynamically allocated model buffers `pActAttnProj` and `pActFFNOut`.
  - Prevents stack overflow crashes on models with hidden dimensions larger than 2048 (e.g., 3B, 7B, 14B).
- **Prompting & Generation Stabilization (`language/src/ring_inference.c` & `libraries/madar_ai/madar_ai.ring`):**
  - Implemented early EOS suppression at token index 0, preventing premature empty generation on ChatML prompts.
  - Aligned Qwen ChatML prompt structure in `formatChatPrompt` with official Alibaba Qwen2.5 guidelines.
  - Updated model candidates and download helper scripts for `Qwen2.5-3B-Instruct` and `DeepSeek-R1-Distill-Qwen-1.5B`.

---

## [0.1.0-alpha] - 2026-10-18

### Added

- **Native Tensor Architecture (`language/include/ring_tensor.h`):**
  - Continuous memory buffer storage abstraction (`RingTensorStorage`) with built-in reference counting for safe zero-copy sharing.
  - Multi-dimensional tensor descriptor (`RingTensor`) supporting up to 8 dimensions (`RING_TENSOR_MAX_DIMS = 8`).
  - Supported precision & quantized data types:
    - `RING_TENSOR_TYPE_FLOAT32` (Single-precision 32-bit float)
    - `RING_TENSOR_TYPE_FLOAT16` (Half-precision 16-bit float)
    - `RING_TENSOR_TYPE_INT8` (Quantized 8-bit integer)
    - `RING_TENSOR_TYPE_INT32` (32-bit signed integer)
    - `RING_TENSOR_TYPE_FLOAT64` (Double-precision 64-bit float)
  - Zero-Copy View API (`ring_tensor_create_view`): permits multiple tensor descriptors to view the same underlying storage without duplication.
  - Zero-Copy Slicing API (`ring_tensor_slice`): enables arbitrary sub-tensor slicing with offset and stride adjustment.
  - Zero-Copy Reshaping API (`ring_tensor_reshape`): dynamic shape transformation for contiguous tensors without memory reallocation.
  - Bidirectional Conversion Bridges (`ring_tensor_to_list` and `ring_list_to_tensor`): high-speed data interchange between Ring's dynamic `List` objects and contiguous C tensors.
- **VM Scripting & Standard Library Integration (`language/src/ring_tensor.c` & `language/src/genlib_e.c`):**
  - Exposed first-class Ring scripting functions for native tensors:
    - `tensor(dims, [type])` / `tensor_new(dims, [type])`: Allocate new tensor with dimensions list and optional type string (`"Float32"`, `"Float64"`, `"Int32"`, `"Int8"`).
    - `tensor_from_list(list, [type])`: Convert dynamic Ring list to contiguous C tensor.
    - `tensor_to_list(tensor)`: Convert contiguous C tensor back to 1D Ring list.
    - `tensor_shape(tensor)`: Get dimensions as a Ring list.
    - `tensor_dims(tensor)`: Get number of dimensions (rank).
    - `tensor_elements(tensor)`: Get total element count.
    - `tensor_type(tensor)`: Get data type name as string.
    - `tensor_slice(tensor, dim, start, length)`: Zero-copy strided slice.
    - `tensor_reshape(tensor, new_dims)`: Zero-copy strided reshape.
    - `tensor_print(tensor)`: Pretty-print tensor metadata and contents.
    - `istensor(val)`: Check if variable is a Madar tensor object.
  - Registered `ring_tensor_loadfunctions(pRingState)` into `ring_vm_generallib_loadfunctions()` for global availability.
- **Element Access, Indexing & Mutation (`language/src/ring_tensor.c` & `language/include/ring_tensor.h`):**
  - Added multi-dimensional element getter `tensor_get(t, [indices] | i, j, ...)` with automatic 1-based to 0-based index translation.
  - Added multi-dimensional element setter `tensor_set(t, [indices] | i, j, ..., val)` with bounds checking.
  - Added scalar tensor filling `tensor_fill(t, val)`.
- **High-Performance Math, GEMM & Neural Activations:**
  - Element-wise arithmetic: `tensor_add`, `tensor_sub`, `tensor_mul` (Hadamard), `tensor_div`, `tensor_scale` / `tensor_mul_scalar`, `tensor_add_scalar`.
  - Cache-blocked Matrix Multiplication (`tensor_matmul`): Optimized $IKJ$ loop ordering for $O(1)$ stride sequential access and compiler auto-vectorization (AVX2/FMA), supporting 2D GEMM and 3D Batched GEMM.
  - Neural Network Activation Functions:
    - `tensor_relu(t)`: High-performance vectorized ReLU.
    - `tensor_gelu(t)`: Fast approximation of Gaussian Error Linear Units (used in Transformers/LLMs).
    - `tensor_sigmoid(t)`: Vectorized logistic sigmoid.
    - `tensor_softmax(t, [dim])`: Numerically stable softmax with maximum subtraction.
  - Reductions: `tensor_sum(t)`, `tensor_mean(t)`, `tensor_max(t)`, `tensor_min(t)`.
- **Embedded GGML Core Engine (`language/include/ggml.h` & `language/src/ggml.c`):**
  - Integrated self-contained pure ANSI C (C99) GGML tensor library into the Madar core runtime.
  - Zero external dependencies: completely standalone with native Win32 threading and atomics abstraction.
  - Added half-precision FP16 conversions: `ggml_fp32_to_fp16()` and `ggml_fp16_to_fp32()`.
  - Added runtime version identifier: `ggml_version()`.
- **Native VM Operator Overloading (`language/src/vmexpr.c`):**
  - Integrated zero-overhead bytecode dispatch for mathematical operators on Tensors:
    - `Tensor + Tensor`: Element-wise addition (`ring_tensor_add`).
    - `Tensor - Tensor`: Element-wise subtraction (`ring_tensor_sub`).
    - `Tensor * Tensor`: Element-wise Hadamard product (`ring_tensor_mul`).
    - `Tensor / Tensor`: Element-wise division (`ring_tensor_div`).
    - `Tensor * Number` & `Number * Tensor`: Scalar scaling (`ring_tensor_scale`).
    - `Tensor + Number` & `Number + Tensor`: Scalar offset addition (`ring_tensor_add_scalar`).
    - `Tensor - Number` & `Tensor / Number`: Scalar subtraction and division.
  - Full support for complex linear expressions directly in Ring syntax (e.g. `y = 2.0 * t1 + t2`).
- **GGUF Model Loader & Binary Parser (`language/include/ring_gguf.h` & `language/src/ring_gguf.c`):**
  - **Zero-Copy Memory-Mapped Architecture:** Implemented direct binary memory-mapping via Win32 `CreateFileMapping` / `MapViewOfFile` with cross-platform 64-bit file reading fallback, enabling instant loading of multi-gigabyte models without RAM duplication.
  - **Full GGUF v2 & v3 Specification Support:** Complete parser for GGUF magic (`0x46554747`), header versions, arbitrary metadata key-value pairs (String, Int, Float, Bool, Arrays), alignment configuration, and tensor info descriptor tables.
  - **Dynamic Tensor Extraction & Dequantization:**
    - Zero-copy native `Tensor` view creation for contiguous F32, F16, Int8, and Int32 tensors.
    - On-the-fly vectorized dequantization for block-quantized formats: `Q4_0` (4-bit nibbles) and `Q8_0` (8-bit quantized weights) to single-precision float (`gguf_tensor_to_f32`).
  - **Exposed Scripting APIs:** `gguf_open(file)`, `gguf_close(h)`, `gguf_version(h)`, `gguf_tensor_count(h)`, `gguf_metadata_count(h)`, `gguf_alignment(h)`, `gguf_architecture(h)`, `gguf_metadata_keys(h)`, `gguf_metadata_get(h, key)`, `gguf_tensor_names(h)`, `gguf_tensor_info(h, name_or_idx)`, `gguf_tensor_get(h, name_or_idx)`, `gguf_tensor_to_f32(h, name_or_idx)`.
- **High-Performance VM Dispatch Acceleration (`language/src/vmcgoto.c` & `language/include/rconfig.h`):**
  - **GCC / Clang Direct Threading:** Implemented computed goto dispatch using C labels-as-values (`&&label`), replacing the standard function-call-overhead dispatch with direct threading for superior branch prediction.
  - **MSVC Monolithic Inlined Dispatch Loop:** Implemented a unified zero-overhead inlined opcode dispatch loop eliminating two function call frames (`ring_vm_fetch` and `ring_vm_execute`) per instruction executed, keeping bytecode and state in CPU registers.
  - Activated by default via `#define RING_VM_COMPUTEDGOTO 1` in `language/include/rconfig.h`.
- **AI Agent Compiler Feedback Loop & Structured JSON Diagnostics (`--json-errors`):**
  - **RFC 8259 Standardized JSON Error Output (`language/src/ring_diagnostics.c` & `language/include/ring_diagnostics.h`):**
    - Transforms scanner, parser, and VM runtime errors into machine-actionable JSON diagnostics consumed seamlessly by AI Agents and LLMs for 100% autonomous self-correction.
    - Captures file path, line number, exact source snippet extracted from disk, standardized error code (e.g. `R24`, `P1`, `TENSOR_ERR`), descriptive message, and full call stack frames.
  - **Context-Aware Intelligent Fix Generator:**
    - Detects tensor dimensionality mismatches (element-wise broadcasting rules, GEMM inner-dimension alignment, 1-based indexing).
    - Uninitialized variable detection with Levenshtein-distance fuzzy identifier suggestions.
    - Syntax rule closing hints (e.g., matching `if` with `ok`, `for` with `next`, unclosed quotes, unclosed multiline comments).
  - **Zero-Overhead Dual Triggering & Scripting APIs:**
    - CLI flag: `ring --json-errors file.ring` or `ring -json-errors file.ring`.
    - Environment variable fallback: `MADAR_JSON_ERRORS=1`.
    - In-script dynamic control: `madar_json_errors([lEnable])` and sub-state API `ring_state_setjsonerrors(pState, lEnable)`.
    - Zero-overhead default: 100% backward-compatible with Ring's standard human-readable error output when `--json-errors` is omitted.
- **GGUF Byte-Pair Encoding (BPE) Tokenizer (`language/include/ring_tokenizer.h` & `language/src/ring_tokenizer.c`):**
  - **Direct Metadata Extraction:** Reads `tokenizer.ggml.tokens`, `tokenizer.ggml.scores`, and `tokenizer.ggml.merges` directly from GGUF zero-copy memory mapping.
  - **High-Performance Vocabulary Hash Table:** $O(1)$ string-to-token lookup table with power-of-two bitmask indexing.
  - **Full Byte-Level BPE & GPT-2 Encoding:** Supports raw byte fallback tokens, hex tokens (`<0xHH>`), and GPT-2 unicode byte transformations (`Ġ` for space, `Ċ` for newline).
  - **BPE Merge Prioritization:** Iterative pair merging based on GGUF merge rank priority.
  - **Scripting APIs:** `gguf_tokenize(hGGUF, text)`, `gguf_detokenize(hGGUF, token_or_list)`.
- **Transformer & Qwen LLM Inference Pipeline (`language/include/ring_inference.h` & `language/src/ring_inference.c`):**
  - **Ultra-Lightweight Architecture:** Zero-copy weight execution streaming directly from memory-mapped GGUF files; working activations and 512-token KV cache consume under 20 MB of RAM!
  - **Hardware Optimized for Low-Power Dual-Core CPUs:** Multi-threaded quantized matrix-vector dot product kernels (Q4_0, Q8_0, F16, F32) default-capped to 2 threads to prevent system freezing on Core i3 / 2-core machines.
  - **Complete Modern Transformer Operators:**
    - RMSNorm with configurable epsilon.
    - Rotary Position Embedding (RoPE) with frequency scaling for high-context positions.
    - Multi-Head Attention with Grouped-Query Attention (GQA) support.
    - SwiGLU Feed-Forward Network (FFN) with native SiLU activation.
    - Logits projection and dual sampling modes: Greedy (argmax) and Temperature sampling.
    - Automatic stop-token detection (`<|im_end|>`, `<|endoftext|>`, EOS).
  - **Scripting APIs:** `madar_model_open(path)`, `madar_model_close(h)`, `madar_model_set_threads(h, n)`, `madar_model_tokenize(h, text)`, `madar_model_detokenize(h, tokens)`, `madar_model_generate(h, prompt, max_tokens, [temp])`, `madar_model_reset(h)`.
- **High-Level Declarative AI Module (`lib/madar_ai.ring` & `bin/load/madar_ai.ring`):**
  - Clean `QwenModel` class with ChatML formatting, prompt generation, and token throughput calculation (`tokens/sec`).
  - Added `DeepSeekModel` class subclassing `QwenModel` with specialized ChatML template and Chain-of-Thought reasoning parser (`extractThinking` & `extractAnswer`).
- **Interactive AI Examples & CLI Assistant (`examples/ai/`):**
  - Added `examples/ai/chat.ring`: Interactive REPL terminal assistant supporting DeepSeek-R1 (1.5B) and Qwen2.5 (3B), real-time reasoning display, context memory reset, and performance metrics.
- **Automated QA & Test Harness (`tests/` & `tools/`):**
  - Unit tests for backward compatibility, tensor math, GGUF loader, Q6_K, tokenizer, and diagnostics.
  - Inlined fast FP16-to-FP32 conversion and 2x unrolled dual-accumulator dot product loops.

### Changed
- **Build Toolchain (`language/build/buildvc_x64.bat`, `buildvcw_x64.bat`, `buildvc.bat`, `buildvcw.bat`):**
  - Incorporated `ring_tensor.c`, `ring_gguf.c`, `ring_tokenizer.c`, `ring_inference.c`, `ggml.c`, `vmcgoto.c`, `ring_diagnostics.c`, and their respective object files into core compilation, DLL linkage (`ring.dll`), and static library archive (`ringstatic.lib`).
- **Master Include Hierarchy (`language/include/ring.h`):**
  - Included `ggml.h`, `ring_tensor.h`, `ring_gguf.h`, `ring_tokenizer.h`, `ring_inference.h`, and `ring_diagnostics.h` in the master build pipeline before `ritem.h`.

### Fixed
- **For-In Loop Algorithmic Optimization on Expressions (`language/src/stmt.c`):**
  - Implemented single-evaluation hoisting for anonymous container expressions (e.g., `for x in 1:N`, `for x in [1, 2, 3]`, or function call returns) into an ephemeral container register (`cStrSource`) prior to loop entry.
  - Eliminated the severe $O(N^2)$ compiler bottleneck where the iterable expression was re-evaluated twice on every iteration (40,000 heap range allocations for $N = 20,000$).
  - Reduced execution time from 2+ minutes (CPU thrashing/hanging) to ~15 milliseconds with $O(1)$ indexing and zero redundant GC pressure.
- **For-In Large String & Collection Zero-Copy References (`language/src/stmt.c`):**
  - Restored and hardened the `lFastLen` compiler optimization for variable containers (e.g., `for l in str`, `for item in aList`).
  - Suppressed `ICO_PUSHV` duplication and routed indexing directly into the container variable, yielding direct pointer references (`RING_OBJTYPE_SUBSTRING`) and zero memory cloning on large buffers.
  - Eliminated over 240 GB of temporary allocations on large strings, bringing execution time of `forinandstr.ring` down to ~400ms.
- **VM Function Invocation & Parameter Type Validation Safety (`language/src/vmfuncs.c`, `language/src/vmjump.c`, `language/src/stmt.c`):**
  - Guarded parameter count and signature validation in `ring_vm_newfunc` and `ring_vm_checkarg` against uninitialized bytecode registers when calling 0-argument functions.
  - Eliminated false R19 runtime errors (`Calling function with less number of parameters`) on callbacks/methods like `ToString = func() {}`.
- **Windows 11 SDK Header Detection Bug (`language/build/locatevc.bat`):**
  - Added `:FixWindowsSdk` subroutine to resolve Microsoft's `VsDevCmd.bat` failure to find Universal C Runtime (`ucrt\stdio.h`) with SDK 10.0.26100.0+.
- **Libcurl WebSocket Header Missing (`extensions/libdepwin/.../websockets.h`):**
  - Created standard `websockets.h` with definitions for `struct curl_ws_frame`, `curl_ws_send`, `curl_ws_recv`, `curl_ws_meta`, and all `CURLWS_*` flags including `CURLWS_RAW_MODE`.
- **GPT-2 & Qwen Byte-Level BPE Multilingual Tokenization (`language/src/ring_tokenizer.c`):**
  - Implemented complete reversible GPT-2 `bytes_to_unicode` mapping (256 bytes to safe Unicode code points).
  - Fixed tokenization of non-ASCII and Arabic scripts.
- **Qwen2 / Qwen2.5 GGUF Metadata & Tensor Resolution (`language/src/ring_inference.c` & `language/src/ring_gguf.c`):**
  - Added multi-type integer & float metadata readers handling `UINT64`, `INT32`, and `UINT32` formats from standard Hugging Face/llama.cpp GGUF exports.
  - Added tensor name fallback lookups supporting standard Hugging Face tensor naming conventions.
  - Resolved OOP property shadowing in `QwenModel` class when initializing with model path parameter.

---

## Versioning Policy
- **Major (X.0.0):** Breaking architectural changes to runtime or language specification.
- **Minor (0.X.0):** New features, GGML operators, VM optimizations, or new standard modules.
- **Patch (0.0.X):** Bug fixes, memory leak resolutions, or build pipeline improvements.
