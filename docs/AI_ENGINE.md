# Madar AI Engine & Inference Architecture

## 1. Overview
The **Madar AI Engine** is an ultra-lightweight, hardware-accelerated LLM and Tensor runtime implemented directly in pure ANSI C / C99 with SIMD intrinsics. Designed specifically for local execution on commodity CPUs, it achieves high-throughput autoregressive inference without heavy dependencies (such as PyTorch, CUDA, or libtorch).

---

## 2. Hardware Acceleration: AVX2 & FMA SIMD Kernels

Matrix-vector multiplication ($Y = W \cdot X$) dominates over 90% of the execution time during LLM token generation. Madar embeds custom 256-bit AVX2 SIMD routines inside `language/src/ring_inference.c`:

### A. Q4_0 Quantized Dot-Product (`dot_q4_0`)
- **Block Layout**: Each block contains 32 weights stored as 16 bytes (`qs[16]`) alongside a 16-bit half-precision scale factor (`d`).
- **SIMD Unpacking Pipeline**:
  1. `_mm_loadu_si128` loads 16 bytes (32 nibbles) in a single instruction.
  2. Lower 4 bits (`low`) and upper 4 bits (`high`) are isolated with bitwise masks (`0x0F`) and 16-bit shifts.
  3. The quantization bias (8) is subtracted using `_mm_sub_epi8`.
  4. The 8-bit integers are widened to 32-bit floats across 4 AVX2 256-bit vector registers (`__m256`) via `_mm256_cvtepi8_epi32` and `_mm256_cvtepi32_ps`.
  5. The uncompressed weights are multiplied by the activation vector $X$ using 256-bit vector multiply-accumulate operations.
  6. The scalar horizontal sum is multiplied by the block scale factor `d`.
- **Throughput Benefit**: Replaces 32 sequential scalar iterations with 4 parallel 256-bit SIMD registers, yielding a **4x to 8x speedup** on modern CPUs.

### B. Q8_0 Quantized Dot-Product (`dot_q8_0`)
- Primarily used for `output.weight` (the final projection layer to the vocabulary logits).
- Ingests 32 signed 8-bit weights directly into vector registers, skipping bit-shifting and executing fast signed integer sign-extension and float conversion.

### C. F16 & F32 Vector Operations
- **`dot_f16`**: Leverages hardware `_mm256_cvtph_ps` (F16C instruction set) to convert half-precision weights to full single-precision floats on-the-fly.
- **`dot_f32` & Cosine Similarity**: Employs loop unrolling and horizontal vector reductions across 8 floats per SIMD lane.

---

## 3. High-Performance Mean Pooling & Embeddings

Modern embedding models (such as `Qwen2-Embedding` and `bge-base`) represent text semantics via the mean-pooled vector of the final Transformer layer's hidden states:

$$\vec{E} = \frac{1}{N - 1} \sum_{i=1}^{N-1} \vec{h}_i$$

### Attention-Sink Token 0 Suppression
- Transformer architectures with causal attention concentrate disproportionate attention mass into the initial prompt token (index 0).
- If included in mean pooling, token 0 dominates the vector direction, creating severe directional bias (anisotropy) and reducing semantic separation.
- Madar automatically skips token 0 during mean aggregation, producing normalized, isotropic embedding vectors with cosine separation across disparate topics.

---

## 4. VectorStore & RAG Engine (`libraries/madar_ai/rag.ring`)

The `VectorStore` class provides a native Ring storage and semantic retrieval engine:
- **Zero-Copy Ingestion**: Accepts text chunks and computes embeddings directly via native C models.
- **Binary Disk Caching (`saveBinary` / `loadBinary`)**:
  - Dumps normalized floating-point embeddings and text payloads directly to binary files.
  - Skips redundant inference upon restart: reloads thousands of chunks in under **10 ms**!
- **Cosine Similarity Engine**: Native vector dot product normalized by $L_2$ norm.

---

## 5. AlQalam (القلم) AI & C++17 Integration

Madar seamlessly integrates with the **AlQalam** library to form an enterprise-grade document search pipeline:

```text
+-----------------------+     +------------------------+
|      PDF Document     | --> | QalamReader (pdftotxt) |
+-----------------------+     +------------------------+
                                           |
                                  Extracted Text
                                           |
            +------------------------------+------------------------------+
            |                                                             |
            v                                                             v
+------------------------+                                   +-------------------------+
|   Qwen-Embedding Core  |                                   |  QalamIndex (Inverted)  |
|  (Dense Vector Search) |                                   |   (O(1) Lexical Search) |
+------------------------+                                   +-------------------------+
            |                                                             |
       Vector Score (70%)                                            Lexical Score (30%)
            \                                                             /
             +----------------------------+------------------------------+
                                          |
                                          v
                              Hybrid Ranked Context
                                          |
                                          v
                              +-----------------------+
                              |   Qwen Instruct LLM   |
                              |   (GGUF C Inference)  |
                              +-----------------------+
```

1. **PDF Text Extraction**: Uses `QalamReader` and bundled `pdftotext.exe` to parse Arabic, English, and multilingual technical documentation without external dependencies.
2. **Hybrid Search**: Combines deep semantic similarity (70% weight) with exact keyword lexical matching (30% weight via `QalamIndex`) to eliminate hallucination.
3. **QalamInk Memory Buffers**: Builds LLM prompts dynamically with zero memory reallocation fragmentation.
4. **QalamChronos**: High-resolution nanosecond timer profiling embedding extraction, indexing, and token generation speed.

---

## 6. FP16 Compressed KV-Cache & 2048 Context Window

To allow extensive conversational memory and lengthy document retrieval without out-of-memory crashes, the Key and Value attention caches are compressed to 16-bit half-precision (`ggml_fp16_t`):
- **Memory Footprint**: Halved compared to standard 32-bit floats.
- **Context Capacity**: Scaled from 512 to **2048 tokens** (`nMaxSeq = 2048`).
- **Dynamic Attention Buffer**: Replaced fixed stack allocation with a heap-backed scratch buffer (`pAttScores`) sized to `nMaxSeq`.
- **Anti-Looping Filter**: Implements dynamic repetition penalty (`1.25x` over a 64-token window and `1.55x` for consecutive duplicates) to prevent generative infinite loops.

---

## 7. Autonomous Function Calling & AI Agents (`libraries/madar_ai/agent.ring`)

The `AIAgent` class enables the LLM to interface with the host environment and execute native code dynamically:
1. **Schema Generation**: Automatically renders registered tools and parameter signatures into the system prompt.
2. **Tool Invocation Protocol**: Detects `<tool_call>` syntax emitted by the model:
   ```text
   <tool_call>
   name: calc
   args: 1450 * 32 + 890
   </tool_call>
   ```
3. **Execution & Feedback Loop**: Executes the corresponding Ring function, encapsulates output into `<tool_response>`, and prompts the model to deliver the final factual response.
4. **Built-in Core Tools**:
   - `calc(expr)`: Exact mathematical evaluation.
   - `get_time()`: Real-time clock and date.
   - `read_file(path)`: Direct filesystem access.
   - `sys_info()`: Operating system runtime telemetry.

---

## 8. High-Performance Madar DataFrame (`libraries/madar_ai/dataframe.ring`)

Designed for memory-bound tabular data analysis:
- **Direct C-Tensor Binding**: Numeric columns are converted to contiguous `RingTensor` (Float32) structures, enabling microsecond matrix reductions (`mean`, `sum`, `min`, `max`, `std`).
- **Pandas-like Workflow**:
  - Ingestion: `df = read_csv("data.csv")`
  - Relational Filtering: `dfHigh = df.filter("salary", ">", 4500)`
  - Summary Analytics: `df.describe()` outputs full tabular statistics.
  - Zero Python Dependency: Executes entirely within the lightweight Madar VM and C core.
