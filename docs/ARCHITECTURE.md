# Madar Technical Architecture & Design Specification

This document details the architectural blueprints, memory models, and subsystem designs powering the **Madar** (مدار) AI-Native runtime.

---

## 1. System Overview

Madar transforms the lightweight Ring Core engine into an AI-first runtime through a layered, modular architecture written in standard ANSI C (C99):

```text
+-------------------------------------------------------------+
|                     Madar Script Layer                      |
|         (ChatML Pipelines, Matrix Ops, Native Tensors)      |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                  Ring VM & Dispatch Engine                  |
|    - Direct Threading (Computed Gotos) / Fast Dispatch      |
|    - RefCount GC & Item System (ITEMTYPE_TENSOR = 6)        |
|    - Operator Overloading for Tensors (+, -, *, /)          |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                 Native Tensor Engine Core                   |
|    - Zero-Copy View & Slicing Subsystem (Strided Layout)    |
|    - Contiguous Buffer Allocator & Lifecycle Tracking       |
|    - Precision Types: Float32, Float16, Int8, Int32, Float64|
|    - Vectorized Math: GEMM (IKJ blocked), Activations       |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|            In-Core GGUF & Transformer Engine                |
|    - Memory-Mapped GGUF (v2/v3) Binary Reader               |
|    - AVX2 & FMA SIMD MatVec Kernels (Q4_0, Q8_0, F16, F32) |
|    - Quantized MatVec: Q4_0, Q8_0, F16, and Q6_K SuperBlocks|
|    - Multi-Threaded Event-Driven Worker Pool                |
|    - Dual Architectures: Causal Decoder (Qwen/DeepSeek) &   |
|      Bidirectional Transformer Encoder (BGE-M3 / BERT)      |
|    - Dual Tokenizers: GPT-2 / Qwen BPE & SentencePiece (SPM)|
|    - KV-Cache Engine & Prefill Logits Optimization          |
|    - CLS & Mean Pooling L2-Normalized Embedding Engine      |
|    - See docs/AI_ENGINE.md for deep SIMD details            |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|            OpenCL GPU Acceleration Layer                    |
|    - Dynamic LoadLibrary("OpenCL.dll") — Zero SDK deps      |
|    - Zero-Copy CL_MEM_USE_HOST_PTR for all FFN weights      |
|    - Vectorized float4 kernels: Q4_0, Q8_0, Q6_K           |
|    - Work-Group 64 tuned for Intel HD Graphics SIMD-16      |
|    - Hybrid CPU+GPU: GPU = FFN + LM Head, CPU = Attention   |
|    - Runtime toggle: /gpu on|off  or  model.setGPU(1/0)    |
+-------------------------------------------------------------+
```

---

## 2. Zero-Copy Tensor Memory Model

### Separation of Storage and Descriptor
To allow zero-copy views, slicing, and reshaping, Madar separates raw memory storage from the tensor's geometrical view:

```text
[RingTensor View A] -----\
  - shape: [2, 4]         \
  - offset: 0              +---> [RingTensorStorage]
  - strides: [4, 1]       /        - pData: 0x1000 (raw memory)
                         /         - nBytes: 32 bytes
[RingTensor View B] ----/          - nRefCount: 2
  - shape: [4, 2]                  - lOwnsData: 1
  - offset: 0
  - strides: [2, 1]
```

### Strided Coordinate Resolution Formula
For any $N$-dimensional coordinate $(i_0, i_1, \dots, i_{N-1})$, the exact byte location within `pStorage->pData` is computed deterministically in $O(1)$:

$$\text{ByteAddress} = \text{pData} + \text{nOffset} + \left( \sum_{d=0}^{N-1} i_d \times \text{aStrides}[d] \right) \times \text{element\_size}$$

### Slicing & Reshaping Rules
- **Slicing (`ring_tensor_slice`):** Increments `nRefCount` on the existing `pStorage`, advances `nOffset` to the slice starting element, multiplies the stride by `nStep`, and leaves raw data untouched.
- **Reshaping (`ring_tensor_reshape`):** Requires `lContiguous == 1`. When contiguous, shape transformation is an instantaneous $O(1)$ metadata operation with zero reallocations.

---

## 3. Core VM Integration & The 3-Bit Item Optimization

In Ring, every fundamental value on the evaluation stack and inside lists is represented by `struct Item`.

### The Bitfield Discovery
In `language/include/ritem.h`:
```c
typedef struct Item {
    union { ... } data;
    unsigned int nType : 3;
    ...
} Item;
```
A 3-bit unsigned bitfield represents integers from `0` to `7`. Upstream Ring defined only types `0` through `5`:
- `0`: `ITEMTYPE_NOTHING`
- `1`: `ITEMTYPE_STRING`
- `2`: `ITEMTYPE_NUMBER`
- `3`: `ITEMTYPE_POINTER`
- `4`: `ITEMTYPE_LIST`
- `5`: `ITEMTYPE_FUNCPOINTER`

Madar assigns:
```c
#define ITEMTYPE_TENSOR 6
```
Because `6` fits cleanly inside the existing 3 bits, **the memory footprint of `Item` is not increased by a single byte**, guaranteeing 100% binary structure alignment with all existing Ring libraries.

---

## 4. GGUF & Quantization Architecture

### 1. Memory-Mapped GGUF Binary Parser (`ring_gguf.c`)
- Direct Windows file mapping (`CreateFileMapping` / `MapViewOfFile`) allows multi-gigabyte models to be accessed with virtual addresses without copying data into RAM.
- Instant initialization times: models mount in under 0.35 seconds.

### 2. Quantization Kernels Supported

| Format | Block Size | Struct Size | Packing & Dequantization Details | GPU OpenCL Kernel |
| :--- | :--- | :--- | :--- | :--- |
| **F32** | 1 | 4 bytes | Standard IEEE 754 float | — |
| **F16** | 1 | 2 bytes | Half-precision float converted via table/bit shifts | — |
| **Q4_0** | 32 | 18 bytes | 16-bit scale + 16 bytes (32 x 4-bit nibbles - 8) | `matvec_q4_0_kernel` ✅ |
| **Q8_0** | 32 | 34 bytes | 16-bit scale + 32 x 8-bit signed quants | `matvec_q8_0_kernel` ✅ |
| **Q6_K** | 256 | 210 bytes | 128B lower 4 bits (`ql`) + 64B upper 2 bits (`qh`) + 16B 8-bit sub-block scales + FP16 super-block scale | `matvec_q6_k_kernel` ✅ |

### 3. Dynamic Heap Buffer Architecture
To support arbitrary LLM architectures (from 0.5B to 14B+) without risk of C runtime stack exhaustion:
- Model activations for Attention Projections (`pActAttnProj`) and Feed-Forward Networks (`pActFFNOut`) are allocated on the heap during model initialization.
- Re-used across forward passes with zero dynamic allocation overhead during inference.

---

## 5. Modern Language Syntax Roadmap (Python-Like Extensions)

Madar is extending Ring's grammar to incorporate high-productivity constructs while preserving 100% backward compatibility:

1. **`f-strings`**: Direct literal interpolation `f"Value: {x + 1}"` compiled into fast concatenation bytecode.
2. **Default Arguments**: `def my_func(a, b = 10)` with runtime parameter count validation.
3. **Multiple Assignments & Destructuring**: `a, b = b, a` and `first, *rest = list`.
4. **Chained Comparisons**: `10 <= x <= 100` evaluated without re-evaluating intermediate expressions.
5. **List Comprehensions**: `[x * x for x in items if x > 2]` compiled into optimized inline builder loops.
6. **Resource Management (`with ... as`)**: Automatic resource cleanup blocks using Ring's unreserved `with` construct.
7. **High-Performance Loop & Iterator Engine**:
   - **Anonymous Expression Hoisting**: Temporary iterable expressions (such as range literals `for x in 1:N`, list literals `for x in [1, 2, 3]`, or generator functions) are evaluated strictly **once** before entering loop bytecode, assigning to an internal register `cStrSource`. This eliminates the $2 \times N$ redundant heap allocations ($O(N^2)$ algorithmic bottleneck) of legacy bytecode generators.
   - **`lFastLen` Zero-Copy Container Traversal**: Variables (`for l in str`, `for x in aList`) bypass value duplication and connect directly to internal memory pointers via `RING_OBJTYPE_SUBSTRING` and `RING_OBJTYPE_LISTITEM` references, achieving zero allocation and C-speed string mutation.

---

## 6. Scripting API Reference

### Tensor Operations
| Function | Signature | Description |
| :--- | :--- | :--- |
| `tensor` / `tensor_new` | `tensor(shape, [type])` | Allocates a new zero-initialized tensor. |
| `tensor_from_list` | `tensor_from_list(list, [type])` | Converts a Ring numerical list to a contiguous C tensor. |
| `tensor_to_list` | `tensor_to_list(tensor)` | Converts a tensor to a Ring list. |
| `tensor_shape` | `tensor_shape(tensor)` | Returns a list of dimension lengths `[d1, d2, ...]`. |
| `tensor_dims` | `tensor_dims(tensor)` | Returns the tensor rank (number of dimensions). |
| `tensor_elements` | `tensor_elements(tensor)` | Returns total element count. |
| `tensor_type` | `tensor_type(tensor)` | Returns data type name string (`"Float32"`, `"Int8"`, etc.). |
| `tensor_slice` | `tensor_slice(tensor, dim, start, length)` | Returns a zero-copy slice view. |
| `tensor_reshape` | `tensor_reshape(tensor, new_shape)` | Returns a zero-copy reshaped view. |
| `tensor_matmul` | `tensor_matmul(t1, t2)` | Cache-blocked matrix multiplication. |
| `istensor` | `istensor(variable)` | Returns `1` if the variable is a Tensor, `0` otherwise. |

### GGUF & Model APIs
| Function | Signature | Description |
| :--- | :--- | :--- |
| `gguf_open` | `gguf_open(path)` | Opens a GGUF file with zero-copy memory mapping. |
| `gguf_close` | `gguf_close(handle)` | Closes and unmaps the GGUF file. |
| `madar_model_open` | `madar_model_open(path)` | Initializes transformer inference runtime from GGUF. |
| `madar_model_set_threads` | `madar_model_set_threads(h, n)` | Sets active CPU worker thread count. |
| `madar_model_set_gpu` | `madar_model_set_gpu(h, bEnable)` | Enables (1) or disables (0) OpenCL GPU acceleration at runtime. |
| `madar_model_generate` | `madar_model_generate(h, prompt, maxTokens, temp)` | Executes autoregressive text generation. |
| `madar_model_generate_stream`| `madar_model_generate_stream(h, prompt, maxTokens, temp, stream)` | Streams generated tokens to terminal in real time. |
| `madar_model_embedding`| `madar_model_embedding(h, text)` | Computes normalized L2 dense vector embedding (`RingTensor`). |

### Madar AI Suite APIs
| Class / Function | Module | Description |
| :--- | :--- | :--- |
| `BgeModel` | `madar_ai/madar_ai.ring` | High-accuracy BGE-M3 bidirectional embedding model wrapper. |
| `QwenModel` / `DeepSeekModel` | `madar_ai/madar_ai.ring` | Generative autoregressive instruction LLM wrappers. |
| `AIAgent` | `madar_ai/agent.ring` | Autonomous agent orchestrating function and tool calling. |
| `registerTool` | `madar_ai/agent.ring` | Registers local Ring functions for autonomous model execution. |
| `DataFrame` / `read_csv`| `madar_ai/dataframe.ring` | High-performance C-Tensor continuous table analytics. |
| `VectorStore` | `madar_ai/rag.ring` | Persistent dense vector database with binary disk caching. |
| `RAGPipeline` | `madar_ai/rag.ring` | Contextual question-answering retrieval pipeline. |
