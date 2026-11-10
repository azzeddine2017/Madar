# Native LoRA Fine-Tuning, Multi-Layer Adaptation & Standalone GGUF Engine

## 1. Overview & Architecture

Madar features a **100% native, dependency-free LoRA (Low-Rank Adaptation) fine-tuning and weight fusion engine** built entirely within the Ring language and the Madar C core (`language/src/ring_inference.c`). Engineered for zero dependency on heavy Python frameworks (no PyTorch, no HuggingFace, no CUDA toolkits, and zero Node.js), Madar allows developers to:

1. **Fine-tune quantized LLMs** (e.g. Qwen2.5-Coder-1.5B/3B, DeepSeek-R1-1.5B) natively on custom syntax and instruction datasets.
2. **Backpropagate stable gradients across all transformer layers** with mathematical Zero-Sum Cross-Entropy normalization and depth-aware residual scaling.
3. **Dynamically fuse LoRA adapter weights** into active inference graphs with **Zero-Copy Native C execution**.
4. **Export permanently fused standalone `.gguf` models** in seconds, fully deployable in Madar, Ollama, LM Studio, or llama.cpp.

```text
+-------------------------------------------------------------------------------+
|                       Madar Native LoRA Architecture                          |
+-------------------------------------------------------------------------------+
|                                                                               |
|  [Base GGUF Model] ---------------------------------------+                   |
|  (e.g., qwen2.5-coder-1.5b-instruct-q4_0.gguf)            |                   |
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

## 2. Mathematical Foundations & Training Stability

### A. The Zero-Sum Invariant in Cross-Entropy Backpropagation
In Causal Language Modeling, given logits $z \in \mathbb{R}^V$ and target token $y$, the Cross-Entropy loss is:

$$\mathcal{L} = -\log P(y) = -\log \left( \frac{e^{z_y}}{\sum_{j=1}^V e^{z_j}} \right)$$

The derivative of $\mathcal{L}$ with respect to the pre-softmax logit $z_i$ is:

$$\frac{\partial \mathcal{L}}{\partial z_i} = P_i - \delta_{iy}$$

Because the probabilities sum to unity ($\sum_{i=1}^V P_i = 1.0$) and $\sum_{i=1}^V \delta_{iy} = 1.0$, the sum of all scalar gradients across the entire vocabulary $V$ is **strictly and identically zero**:

$$\sum_{i=1}^V \frac{\partial \mathcal{L}}{\partial z_i} = \sum_{i=1}^V (P_i - \delta_{iy}) = 1.0 - 1.0 \equiv \mathbf{0.0}$$

#### The Instability Problem of Truncated Competitors
When computing the backpropagated gradient on the final hidden state $h \in \mathbb{R}^{d}$:

$$\frac{\partial \mathcal{L}}{\partial h} = \sum_{i=1}^V (P_i - \delta_{iy}) W_{out}[i, :]$$

If one only accumulates the target token and a few top competitor tokens (e.g., top 8) without normalization, the omitted $150,000+$ vocabulary tokens create a massive negative scalar imbalance:

$$(P_{target} - 1.0) + \sum_{k=1}^K P_k \approx -0.7 \text{ to } -0.9 \ne 0$$

Over hundreds of training steps, this negative bias acts as a continuous DC drift on hidden activations, eventually pushing vectors off the manifold and triggering violent loss explosions (the "seizing patient" phenomenon).

#### Madar's Conservative Subspace Normalization
Madar solves this by re-normalizing probabilities over the active subspace $\{y, c_1, \ldots, c_K\}$:

$$S = P(y) + \sum_{k=1}^K P(c_k)$$

$$\tilde{P}_y = \frac{P(y)}{S}, \quad \tilde{P}_{c_k} = \frac{P(c_k)}{S}$$

$$\text{coeff}_{target} = (\tilde{P}_y - 1.0) \cdot (1.0 - P(y))$$

$$\text{coeff}_{c_k} = \tilde{P}_{c_k} \cdot (1.0 - P(y))$$

This mathematically guarantees:

$$\text{coeff}_{target} + \sum_{k=1}^K \text{coeff}_{c_k} \equiv \mathbf{0.0}$$

The target token is pulled toward its embedding vector, the active competitors push back proportionally, the omitted tail produces **zero DC drift**, and well-predicted tokens ($P(y) \to 1.0$) smoothly decay their gradient contribution to zero.

---

### B. Depth-Aware Residual Stream Backpropagation
In deep Transformers (e.g. 28 layers in Qwen2.5-1.5B), the residual stream carries activations forward:

$$x_{l+1} = x_l + \text{attnOut}_l + \text{ffnOut}_l$$

Because $\text{attnOut}_l$ is added directly into the residual stream, the gradient of the loss with respect to the attention output projection satisfies:

$$\frac{\partial \mathcal{L}}{\partial \text{attnOut}_l} = \frac{\partial \mathcal{L}}{\partial x_{\text{final}}} \cdot \frac{\partial x_{\text{final}}}{\partial \text{attnOut}_l} \approx pGradH$$

To account for intermediate layer norm Jacobians and maintain gradient stability across deep hierarchies, Madar applies depth-aware attenuation:

$$\text{scale}_l = \text{scale} \cdot \left(0.5 + 0.5 \cdot \frac{l + 1}{L}\right)$$

Deeper layers near the LM head receive high-fidelity updates, while earlier layers are protected from gradient oversaturation.

---

### C. Standard AdamW with Step-Based Bias Correction
Madar implements textbook AdamW with true optimizer step tracking ($t = nOptimizerSteps$):

$$m_t = \beta_1 m_{t-1} + (1 - \beta_1) g_t$$

$$v_t = \beta_2 v_{t-1} + (1 - \beta_2) g_t^2$$

$$\hat{m}_t = \frac{m_t}{1 - \beta_1^t}, \quad \hat{v}_t = \frac{v_t}{1 - \beta_2^t}$$

$$W_t = W_{t-1} - \eta \left( \frac{\hat{m}_t}{\sqrt{\hat{v}_t} + \epsilon} + \lambda W_{t-1} \right)$$

- Gradients $g_t$ are normalized by the number of accumulated response tokens per sample ($1 / N_{\text{tokens}}$).
- LoRA weight matrices are bounded within dynamic range $[-0.50, +0.50]$, preventing weight saturation.

---

## 3. Core Engine Implementation (C & Ring API)

### A. Native C Lifecycle Functions (`language/src/ring_inference.c`)

| Function | Signature | Purpose |
| :--- | :--- | :--- |
| `ring_model_init_lora` | `(pModel, nRank, fAlpha)` | Allocates low-rank adapter buffers across all model layers. |
| `ring_model_train_token` | `(pModel, nTargetToken)` | Computes Zero-Sum Cross-Entropy gradient and backpropagates into all layers. |
| `ring_model_train_sequence` | `(pModel, tokens, mask, nSeqLen, nRespStart, nTrainEnd, bUseBatch)` | High-throughput Teacher Forcing sequence training using chunked GPU forward passes. |
| `ring_model_optimizer_step` | `(pModel, fLR, fWeightDecay)` | Executes AdamW parameter update with sequence-normalized gradients. |
| `ring_model_save_lora` | `(pModel, cFolder)` | Exports raw binary LoRA adapter tensors ($A$ and $B$). |
| `ring_model_load_lora` | `(pModel, cFolder)` | Loads trained LoRA adapter tensors into active model memory. |
| `ring_model_export_merged_gguf` | `(pModel, cOutGGUFPath)` | Permanently fuses LoRA weights and re-quantizes to standalone GGUF. |

---

### B. High-Level Ring OOP Scripting API (`libraries/madar_ai/trainer/trainer.ring`)

```ring
load "stdlibcore.ring"
load "madar_ai.ring"
load "madar_trainer.ring"

# 1. Open Quantized Base Model
oModel = model_open("models/qwen2.5-coder-1.5b-instruct-q4_0.gguf")
oModel.setThreads(4)

# 2. Ingest Bilingual Ring Instruction Dataset
oDataset = new MadarInstructDataset("data/ring_instruct_bilingual.jsonl", "chatml")

# 3. Initialize LoRA Trainer (Rank 16, Alpha 32.0, LR 0.0002)
oTrainer = new MadarLoRATrainer(oModel, oDataset, 16, 32.0, 0.0002) {
    nLogInterval  = 10
    nSaveInterval = 50
    cOutputDir    = "adapters/ring_lora_cloud"
}

# 4. Train 3 Epochs
oTrainer.train(3)

# 5. Export Permanently Fused Standalone GGUF
oModel.exportMergedGGUF("models/qwen2.5-coder-1.5b-ring-standalone.gguf")
```

---

## 4. Benchmark & Hugging Face Ground-Truth Baseline

To establish an absolute empirical ground-truth baseline, a full 3-epoch training run was executed on Google Colab (Tesla T4 GPU) using Hugging Face SFTTrainer and PEFT:

- **Base Model**: `Qwen/Qwen2.5-Coder-1.5B-Instruct` (BitsAndBytes 4-bit NF4)
- **Dataset**: `data/ring_instruct_bilingual.jsonl` (1,460 pairs: 730 English, 730 Arabic)
- **Parameters**: Rank = 16, Alpha = 32, Batch Size = 2, Gradient Accumulation = 4
- **Training Trajectory**: 549 optimizer steps across 3 epochs.

### Empirical Convergence Curve:
- **Step 10**: Loss = 3.0076
- **Step 100**: Loss = 1.7601
- **Step 250**: Loss = 1.5997
- **Step 540**: Loss = 1.3444

The merged FP16 weights were converted to 4-bit GGUF (`models/qwen2.5-coder-1.5b-ring-hf-q4_0.gguf`, 891.6 MB) and verified natively in Madar using `tools/test_qwen_coder_gguf.ring`, confirming 100% accurate Ring syntax generation in both Arabic and English.

---

## 5. High-Throughput Teacher Forcing & Full GPU Acceleration (v0.4.3)

In release **0.4.3-alpha**, Madar addresses the fundamental throughput difference between sequential autoregressive inference and dense sequence-level training:

```text
+---------------------------------------------------------------------------------+
|               Teacher Forcing Chunked Training Pipeline (v0.4.3)                |
+---------------------------------------------------------------------------------+
|                                                                                 |
|  [Shuffled Dataset] -----> [Sequence Prefill (Chunk=64)]                        |
|  (Fisher-Yates)            Populates KV Cache via GPU Chunks                    |
|                                     |                                           |
|                                     v                                           |
|                           [Response Training Chunk]                             |
|                           ring_model_train_chunk()                              |
|                           (Chunks of up to 64 tokens)                           |
|                                     |                                           |
|          +--------------------------+--------------------------+                |
|          |                                                     |                |
|          v                                                     v                |
|   [Phase A: Attention]                                  [Phase B: Fused FFN]    |
|   Q, K, V, Out Projections on GPU                       madar_gpu_ffn_fused_    |
|   Caches actBatchAttOut[l][t] in memory                 batch() across all B=64 |
|          |                                                     |                |
|          +--------------------------+--------------------------+                |
|                                     |                                           |
|                                     v                                           |
|                    [Parallel Masked Cross-Entropy Loss]                         |
|                    GPU LM Head -> Softmax -> pGradH                             |
|                                     |                                           |
|                                     v                                           |
|                    [Vectorized Multi-Layer LoRA Backward]                       |
|                    ΔB_out += scale * (pGradH * u^T)                             |
|                    ΔA_out += g_u * att_out^T                                    |
|                                                                                 |
+---------------------------------------------------------------------------------+
```

### A. Full GPU Layer Weight Residency
Rather than restricting GPU acceleration to FFN projections and the LM Head, Madar v0.4.3 extends zero-copy OpenCL mapping to **all attention projection matrices** ($Q, K, V, \text{Out}$) across all 28 layers.
- Every tensor in the model maintains an optional `pGPUBuf` pointer within `RingGGUFTensorInfo`.
- At model load time, 100% of dense weight matrices are resident in GPU VRAM (totaling ~850 MB for Qwen2.5-1.5B, leaving ~15 GB free on a Tesla T4).
- The host CPU performs zero matrix multiplication during active GPU training.

### B. Teacher Forcing Sequence Chunking (`ring_model_train_chunk`)
In training (unlike inference), the entire target sequence is known in advance (Teacher Forcing). Instead of dispatching $200 \times 28$ individual forward-backward passes:
1. The response sequence is divided into contiguous chunks of up to 64 tokens.
2. In each chunk, all 28 Transformer layers process all tokens concurrently via OpenCL 2D NDRange kernels (`gemv_batch_q4_0_kernel` with $B \le 64$).
3. The exact attention outputs $\text{attOut}_l[t]$ entering LoRA adapters are cached in a contiguous buffer `actBatchAttOut`.
4. Logits for masked target tokens are evaluated on the GPU LM head in single microsecond calls, followed by vectorized backpropagation across all layers.
5. **Impact**: Host-device command submissions are slashed by $66\times$ (from ~5,600 down to ~84 per sample), reducing sample latency from 15s to under 0.3s on a Tesla T4 GPU.

### C. Fisher-Yates Dataset Shuffling
To eliminate dataset bias caused by localized thematic clusters (e.g., 200 consecutive Arabic documentation texts causing temporary spikes in instantaneous loss):
- `MadarInstructDataset.shuffle()` performs an in-memory random permutation of instruction pairs before each epoch.
- Blends simple syntax examples, complex algorithms, English instructions, and Arabic explanations uniformly.
- Ensures smooth, monotonic loss decay across all training epochs matching production PyTorch benchmarks.
