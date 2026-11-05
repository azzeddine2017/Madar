# Native LoRA Fine-Tuning & Standalone GGUF Export Engine

## 1. Overview & Architecture

Madar features a **100% native, dependency-free LoRA (Low-Rank Adaptation) fine-tuning and weight fusion engine** built entirely within the Ring language and the Madar C core. Engineered for zero dependency on heavy frameworks (no PyTorch, no HuggingFace, no CUDA toolkits, and zero Node.js), Madar allows developers to:

1. **Fine-tune quantized LLMs** on specialized programming syntax (e.g. Ring language documentation and idioms).
2. **Dynamically fuse LoRA adapter weights** into active inference graphs with **Zero-Copy Native C execution**.
3. **Export permanently fused standalone `.gguf` models** in seconds, ready for deployment in Madar, Ollama, LM Studio, or llama.cpp.

```text
+-------------------------------------------------------------------------------+
|                       Madar Native LoRA Architecture                          |
+-------------------------------------------------------------------------------+
|                                                                               |
|  [Base GGUF Model] ---------------------------------------+                   |
|  (e.g., qwen2.5-0.5b-instruct-q4_0.gguf)                  |                   |
|                                                           v                   |
|  [LoRA Adapters A & B] ----> [Zero-Copy Fusion] ---> [Active In-Memory Graph] |
|  (Rank=16, Alpha=32)         matvec_multiply()       y = (W + scale*B*A) x    |
|                                                           |                   |
|                                                           v                   |
|  [Fast Q4_0 Re-Quantizer] -------------------------> [Standalone GGUF File]   |
|  quantize_row_q4_0_fast()                            (Zero LoRA Loading!)     |
|                                                                               |
+-------------------------------------------------------------------------------+
```

---

## 2. Mathematical Foundations & Zero-Copy Fusion

### A. Low-Rank Weight Adaptation
Given a projection weight matrix $W_0 \in \mathbb{R}^{d_{\text{out}} \times d_{\text{in}}}$, standard LoRA decomposes the weight update $\Delta W$ into two low-rank matrices:

$$\Delta W = \frac{\alpha}{r} (B \cdot A)$$

Where:
- $A \in \mathbb{R}^{r \times d_{\text{in}}}$: Down-projection matrix initialized with Gaussian distribution.
- $B \in \mathbb{R}^{d_{\text{out}} \times r}$: Up-projection matrix initialized to zeros.
- $r$: Rank (e.g., $r = 16$).
- $\alpha$: Scaling hyperparameter (e.g., $\alpha = 32.0$).
- $\text{scale} = \alpha / r$.

### B. Zero-Copy Inference Fusion (`matvec_multiply`)
Rather than allocating full uncompressed floating-point weight matrices for the entire model, Madar computes the adapter contribution on-the-fly during matrix-vector multiplication in `language/src/ring_inference.c`:

$$y = W_0 \cdot x + \text{scale} \cdot \Big(B \cdot (A \cdot x)\Big)$$

1. **Step 1 (Down-projection)**: Computes intermediate scratch vector $h = A \cdot x$ ($r \times 1$).
2. **Step 2 (Up-projection & Accumulation)**: Adds $\text{scale} \cdot (B \cdot h)$ directly to activation vector $y$.

This eliminates all memory overhead during inference, allowing quantized models (Q4_0) to remain memory-mapped while behaving as fully adapted models.

### C. True Semantic Token Transition Gradients
During training, rather than using arbitrary constant fills (which disrupt the Softmax attention distribution), Madar extracts the **actual continuous embedding vectors** of context tokens from the model's embedding table (`token_embd.weight`).

For a target syntax transition $(Token_{t-1} \to Token_t)$:
1. $X = \text{Embedding}(Token_{t-1}) \in \mathbb{R}^{d_{\text{in}}}$
2. $Y = \text{Embedding}(Token_t) \in \mathbb{R}^{d_{\text{in}}}$
3. The displacement gradient vector is mean-centered to eliminate DC logit offsets:

$$\Delta_d = (Y_d - X_d) - \frac{1}{d_{\text{in}}} \sum_{k=1}^{d_{\text{in}}} (Y_k - X_k)$$

$$\nabla Y = \Delta \cdot \text{LossMagnitude} \cdot 0.05$$

Ensuring $\sum_d \nabla Y_d = 0$, which preserves numerical stability across the Multi-Head Attention Softmax layers.

---

## 3. Core Engine Implementation (C & Ring API)

### A. Native C Lifecycle Functions (`language/src/ring_inference.c`)

| Function | Signature | Purpose |
| :--- | :--- | :--- |
| `ring_model_load_lora` | `(RingModel *pModel, const char *cAdapterDir)` | Loads adapter tensors ($A$ and $B$) from directory. |
| `ring_model_enable_lora`| `(RingModel *pModel, int bEnable)` | Toggles adapter fusion on or off at runtime. |
| `ring_model_set_lora_scale` | `(RingModel *pModel, float fScale)` | Sets adapter perturbation scaling factor. |
| `ring_model_export_merged_gguf` | `(RingModel *pModel, const char *cOutGGUFPath)` | Permanently fuses LoRA weights into a standalone `.gguf`. |
| `madar_trainer_fill_batch` | `(hModel, pX, pdY, aTokens, aIndices, fScale)` | High-speed C kernel populating real token embeddings. |
| `madar_model_forward` | `(hModel, nToken, nPos)` | Evaluates Transformer layers and LM Head on GPU. |

### B. High-Level Ring OOP Scripting API (`libraries/madar_ai/madar_ai.ring`)

```ring
load "madar_ai.ring"

# 1. Open Base Quantized Model
oModel = model_open("models/qwen2.5-0.5b-instruct-q4_0.gguf")
oModel.setGPU(true)

# 2. Attach LoRA Adapter
oModel.loadLoRA("adapters/ring_lora_cloud/final")
oModel.setLoRAScale(0.005)

# 3. Generate with Fine-Tuned Weights Active
cPrompt = oModel.formatChatPrompt("Write a Ring example to reverse a string.")
? oModel.generate(cPrompt, 128)

# 4. Permanently Export to Standalone GGUF
oModel.exportMergedGGUF("models/qwen2.5-0.5b-ring-instruct.gguf")
oModel.close()
```

---

## 4. Standalone GGUF Model Exporter

Madar provides a specialized fast exporter in `language/src/ring_inference.c`:

1. **Header & Metadata Streaming**: Streams the binary header and metadata table from byte 0 to `nDataOffset` verbatim from memory-mapped storage.
2. **Zero-Copy Non-Adapted Tensors**: Directly copies unadapted layers (FFN weights, Norm weights, Embeddings) using memory-mapped block transfers.
3. **Q4_0 Dequantization & Re-Quantization**:
   - For attention projection tensors (`attn_q.weight`, `attn_output.weight`), dequantizes Q4_0 blocks to 32-bit floats.
   - Computes low-rank delta: $W_{\text{f32}}[row, col] += \text{scale} \cdot \sum_k B[row, k] \cdot A[k, col]$.
   - Re-quantizes using `quantize_row_q4_0_fast`:
     - Finds peak block amplitude $\text{amax} = \max(|x_0|, \dots, |x_{31}|)$.
     - Computes FP16 scale factor $d = \text{amax} / -8.0f$.
     - Packs pairs of 4-bit nibbles into 16 bytes.
   - Writes back into output file at the identical byte alignment.

### Execution Speed
Exporting a complete 500M parameter model (~350 MB, 291 tensors) takes **under 4 seconds** on standard NVMe / SSD drives.

---

## 5. Google Colab Cloud Training Pipeline

For large-scale training across all 730 synthesized Ring instruction pairs, Madar provides an interactive cloud environment:

- **Notebook**: [`notebooks/Madar_LoRA_Studio.ipynb`](../notebooks/Madar_LoRA_Studio.ipynb)
- **Target Hardware**: NVIDIA Tesla T4 GPU (16 GB VRAM)
- **Pipeline Steps**:
  1. **Step 1–3**: Environment setup, OpenCL package install, and complete Linux build (`tools/build_linux.sh`).
  2. **Step 4**: Verification of 730 instruction pairs in `data/ring_instruct_dataset.jsonl`.
  3. **Step 5–6**: Registration of interactive `%%madar` cell magic and baseline evaluation.
  4. **Step 7**: Launch 3 full training epochs (2,190 steps) with OpenCL GPU acceleration.
  5. **Step 8–9**: Training loss visualization and adapter zip packaging.
  6. **Step 10**: Direct one-click standalone GGUF model export and download.

---

## 6. End-to-End Comparative Verification

To verify that the model correctly transitions from generic Python code generation to authentic Ring language code, run:

```bash
ring examples/ai/test_lora_merge_inference.ring
```

### Benchmark Results:
- **Baseline Model (Before LoRA)**:
  ```python
  def is_palindrome(s):
      reversed_s = ''.join(reversed(list(s)))
      ...
  ```
- **Merged Model (After LoRA)**:
  ```ring
  // Reverse string and check if it is palindrome in Ring
  cStr = "madam"
  cRev = reverse(cStr)
  if cStr = cRev
      see "The string is a palindrome!" + nl
  ok
  ```
- **Standalone Export Tool**:
  ```bash
  ring tools/export_merged_gguf.ring
  ```

