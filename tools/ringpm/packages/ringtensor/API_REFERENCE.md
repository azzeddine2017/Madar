# RingTensor API Reference

**Version:** 1.3.4  
**Last Updated:** 2026-05-07

This document provides a comprehensive reference for all RingTensor functions, organized by category.

---

## 📋 Table of Contents

1. [Tensor Lifecycle](#1-tensor-lifecycle)
2. [Shape and Properties](#2-shape-and-properties)
3. [Element-wise Operations](#3-element-wise-operations)
4. [Matrix Operations](#4-matrix-operations)
5. [Activation Functions](#5-activation-functions)
6. [Loss Functions](#6-loss-functions)
7. [Transformer Operations](#7-transformer-operations)
8. [Attention Mechanisms](#8-attention-mechanisms)
9. [Optimizers](#9-optimizers)
10. [Data Manipulation](#10-data-manipulation)
11. [Persistence](#11-persistence)
12. [Graph Engine](#12-graph-engine)
13. [Utilities](#13-utilities)
14. [GPU Configuration](#14-gpu-configuration)

---

## 1. Tensor Lifecycle

### `tensor_init(rows, cols)`

Creates a new tensor initialized to zero.

**Parameters:**
- `rows` (int): Number of rows
- `cols` (int): Number of columns

**Returns:**
- Pointer to newly allocated tensor

**Example:**
```ring
load "ringtensor.ring"

# Create a 100x50 tensor
T = tensor_init(100, 50)
```

**Memory:**
- Allocates `rows * cols * sizeof(double)` bytes
- Automatically managed by Ring's garbage collector

---

### `tensor_copy(ptr)`

Creates a deep copy of a tensor.

**Parameters:**
- `ptr` (tensor_t*): Source tensor pointer

**Returns:**
- Pointer to new tensor with copied data

**Example:**
```ring
A = tensor_init(10, 10)
tensor_fill(A, 5.0)

# Create independent copy
B = tensor_copy(A)
```

**Performance:**
- Uses `memcpy` for maximum throughput
- O(n) where n = total elements

---

### `tensor_reshape(ptr, batch, heads, rows, cols)`

Logically reshapes a tensor to 4D dimensions.

**Parameters:**
- `ptr` (tensor_t*): Tensor pointer
- `batch` (int): Batch dimension (use 1 if unused)
- `heads` (int): Heads dimension (use 1 if unused)
- `rows` (int): Rows dimension
- `cols` (int): Columns dimension

**Constraints:**
- `batch * heads * rows * cols` must equal total tensor size

**Example:**
```ring
# Create 1D tensor of 1200 elements
T = tensor_init(1200, 1)

# Reshape to [10 batches, 3 heads, 5 rows, 8 cols]
tensor_reshape(T, 10, 3, 5, 8)
```

---

## 2. Shape and Properties

### `tensor_get_rows(ptr)`

Returns the number of rows.

**Parameters:**
- `ptr` (tensor_t*): Tensor pointer

**Returns:**
- Number of rows (int)

**Example:**
```ring
T = tensor_init(100, 50)
rows = tensor_get_rows(T)  # Returns 100
```

---

### `tensor_get_cols(ptr)`

Returns the number of columns.

**Parameters:**
- `ptr` (tensor_t*): Tensor pointer

**Returns:**
- Number of columns (int)

**Example:**
```ring
T = tensor_init(100, 50)
cols = tensor_get_cols(T)  # Returns 50
```

---

### `tensor_get(ptr, row, col)`

Gets value at specific position.

**Parameters:**
- `ptr` (tensor_t*): Tensor pointer
- `row` (int): Row index (1-based)
- `col` (int): Column index (1-based)

**Returns:**
- Value at position (double)

**Example:**
```ring
T = tensor_init(10, 10)
tensor_set(T, 5, 5, 42.0)
val = tensor_get(T, 5, 5)  # Returns 42.0
```

---

### `tensor_set(ptr, row, col, value)`

Sets value at specific position.

**Parameters:**
- `ptr` (tensor_t*): Tensor pointer
- `row` (int): Row index (1-based)
- `col` (int): Column index (1-based)
- `value` (double): Value to set

**Example:**
```ring
T = tensor_init(10, 10)
tensor_set(T, 3, 7, 99.5)
```

---

## 3. Element-wise Operations

All element-wise operations are **in-place** and **parallelized** with OpenMP.

### `tensor_add(A, B)`

Element-wise addition: `A += B`

**Parameters:**
- `A` (tensor_t*): Destination tensor (modified in-place)
- `B` (tensor_t*): Source tensor

**Constraints:**
- A and B must have same dimensions

**Example:**
```ring
A = tensor_init(100, 100)
B = tensor_init(100, 100)
tensor_fill(A, 1.0)
tensor_fill(B, 2.0)

tensor_add(A, B)  # A now contains 3.0
```

**Performance:**
- O(n) where n = total elements
- Parallelized across CPU cores

---

### `tensor_sub(A, B)`

Element-wise subtraction: `A -= B`

**Parameters:**
- `A` (tensor_t*): Destination tensor (modified in-place)
- `B` (tensor_t*): Source tensor

**Example:**
```ring
A = tensor_init(100, 100)
B = tensor_init(100, 100)
tensor_fill(A, 5.0)
tensor_fill(B, 2.0)

tensor_sub(A, B)  # A now contains 3.0
```

---

### `tensor_mul_elem(A, B)`

Element-wise multiplication: `A *= B`

**Parameters:**
- `A` (tensor_t*): Destination tensor (modified in-place)
- `B` (tensor_t*): Source tensor

**Example:**
```ring
A = tensor_init(100, 100)
B = tensor_init(100, 100)
tensor_fill(A, 3.0)
tensor_fill(B, 4.0)

tensor_mul_elem(A, B)  # A now contains 12.0
```

---

### `tensor_div(A, B)`

Element-wise division: `A /= B`

**Parameters:**
- `A` (tensor_t*): Destination tensor (modified in-place)
- `B` (tensor_t*): Source tensor

**Warning:**
- No division by zero check for performance
- Ensure B contains no zeros

**Example:**
```ring
A = tensor_init(100, 100)
B = tensor_init(100, 100)
tensor_fill(A, 12.0)
tensor_fill(B, 3.0)

tensor_div(A, B)  # A now contains 4.0
```

---

### `tensor_scalar_mul(T, scalar)`

Scalar multiplication: `T *= scalar`

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `scalar` (double): Scalar value

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 2.0)

tensor_scalar_mul(T, 3.5)  # T now contains 7.0
```

---

### `tensor_add_scalar(T, scalar)`

Add scalar: `T += scalar`

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `scalar` (double): Scalar value

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 10.0)

tensor_add_scalar(T, 5.0)  # T now contains 15.0
```

---

### `tensor_sub_scalar(T, scalar)`

Subtract scalar: `T -= scalar`

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `scalar` (double): Scalar value

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 10.0)

tensor_sub_scalar(T, 3.0)  # T now contains 7.0
```

---

## 4. Matrix Operations

### `tensor_matmul(A, B)`

Matrix multiplication: `C = A @ B`

**Parameters:**
- `A` (tensor_t*): Left matrix (M × K)
- `B` (tensor_t*): Right matrix (K × N)

**Returns:**
- New tensor C (M × N)

**Constraints:**
- `A.cols` must equal `B.rows`

**Example:**
```ring
A = tensor_init(100, 50)
B = tensor_init(50, 200)
tensor_fill(A, 1.0)
tensor_fill(B, 2.0)

C = tensor_matmul(A, B)  # C is 100×200
```

**Performance:**
- Cache-friendly tiled implementation
- GPU acceleration for large matrices (>10,000 elements)
- O(M × N × K) complexity

**GPU Offloading:**
- Automatically uses GPU if:
  - OpenCL is available
  - Total elements > GPU threshold
  - GPU initialization succeeded

---

### `tensor_matmul_batch(A, B)`

Batch matrix multiplication for 3D tensors.

**Parameters:**
- `A` (tensor_t*): Shape [Batch, M, K]
- `B` (tensor_t*): Shape [Batch, K, N]

**Returns:**
- New tensor C with shape [Batch, M, N]

**Constraints:**
- A and B must have same batch size
- `A.shape[2]` must equal `B.shape[1]`

**Example:**
```ring
# Create batch of 10 matrices
A = tensor_init(10 * 20 * 30, 1)
tensor_reshape(A, 10, 1, 20, 30)

B = tensor_init(10 * 30 * 40, 1)
tensor_reshape(B, 10, 1, 30, 40)

C = tensor_matmul_batch(A, B)  # Shape: [10, 20, 40]
```

**Performance:**
- Parallelized across batches with OpenMP
- Each batch processed independently

---

### `tensor_transpose(A)`

Matrix transpose: `B = A.T`

**Parameters:**
- `A` (tensor_t*): Input matrix (M × N)

**Returns:**
- New tensor B (N × M)

**Example:**
```ring
A = tensor_init(100, 50)
tensor_fill(A, 5.0)

B = tensor_transpose(A)  # B is 50×100
```

**Performance:**
- GPU acceleration for large matrices
- Cache-friendly implementation

---

### `tensor_add_row_vec(A, vec)`

Broadcasting: Add row vector to all rows.

**Parameters:**
- `A` (tensor_t*): Matrix (M × N) - modified in-place
- `vec` (tensor_t*): Row vector (1 × N)

**Constraints:**
- `vec.cols` must equal `A.cols`

**Example:**
```ring
A = tensor_init(100, 50)
vec = tensor_init(1, 50)

tensor_fill(A, 1.0)
tensor_fill(vec, 0.5)

tensor_add_row_vec(A, vec)  # Each row of A += vec
```

**Use Case:**
- Adding bias in neural networks

---

### `tensor_sum(T, axis)`

Sum along specified axis.

**Parameters:**
- `T` (tensor_t*): Input tensor
- `axis` (int): 0 for column-wise, 1 for row-wise

**Returns:**
- New tensor with summed values

**Example:**
```ring
T = tensor_init(100, 50)
tensor_fill(T, 2.0)

# Sum each column (result: 1×50)
col_sum = tensor_sum(T, 0)

# Sum each row (result: 100×1)
row_sum = tensor_sum(T, 1)
```

---

### `tensor_mean(T, axis)`

Mean along specified axis.

**Parameters:**
- `T` (tensor_t*): Input tensor
- `axis` (int): 0 for column-wise, 1 for row-wise

**Returns:**
- New tensor with mean values

**Example:**
```ring
T = tensor_init(100, 50)
tensor_fill(T, 10.0)

# Mean of each column
col_mean = tensor_mean(T, 0)
```

---

### `tensor_argmax(T)`

Returns index of maximum value (global).

**Parameters:**
- `T` (tensor_t*): Input tensor

**Returns:**
- Index of maximum value (int, 0-based)

**Example:**
```ring
T = tensor_init(10, 10)
tensor_fill(T, 1.0)
tensor_set(T, 5, 5, 99.0)

idx = tensor_argmax(T)  # Returns 44 (row 4, col 4 in 0-based)
```

---

## 5. Activation Functions

All activation functions are **in-place** and **parallelized**.

### `tensor_relu(T)`

ReLU activation: `T = max(0, T)`

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, -5.0)
tensor_relu(T)  # T now contains 0.0
```

**Formula:**
```
f(x) = max(0, x)
```

---

### `tensor_relu_prime(T)`

ReLU derivative: `T = (T > 0) ? 1 : 0`

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)

**Use Case:**
- Backward pass in neural networks

**Formula:**
```
f'(x) = 1 if x > 0, else 0
```

---

### `tensor_sigmoid(T)`

Sigmoid activation: `T = 1 / (1 + exp(-T))`

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 0.0)
tensor_sigmoid(T)  # T now contains 0.5
```

**Formula:**
```
f(x) = 1 / (1 + e^(-x))
```

**Range:** (0, 1)

---

### `tensor_sigmoid_prime(T)`

Sigmoid derivative: `T = sigmoid(T) * (1 - sigmoid(T))`

**Parameters:**
- `T` (tensor_t*): Tensor containing sigmoid outputs (modified in-place)

**Formula:**
```
f'(x) = f(x) * (1 - f(x))
```

---

### `tensor_tanh(T)`

Hyperbolic tangent: `T = tanh(T)`

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 0.0)
tensor_tanh(T)  # T now contains 0.0
```

**Formula:**
```
f(x) = (e^x - e^(-x)) / (e^x + e^(-x))
```

**Range:** (-1, 1)

---

### `tensor_tanh_prime(T)`

Tanh derivative: `T = 1 - tanh²(T)`

**Parameters:**
- `T` (tensor_t*): Tensor containing tanh outputs (modified in-place)

**Formula:**
```
f'(x) = 1 - f(x)²
```

---

### `tensor_gelu(T)`

GELU activation (Gaussian Error Linear Unit).

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)

**Example:**
```ring
T = tensor_init(1000, 1000)
tensor_random(T, -1.0, 1.0)
tensor_gelu(T)
```

**Formula:**
```
f(x) = 0.5 * x * (1 + tanh(√(2/π) * (x + 0.044715 * x³)))
```

**Performance:**
- GPU accelerated for large tensors
- Standard activation in GPT models

---

### `tensor_gelu_prime(T)`

GELU derivative.

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)

**Use Case:**
- Backward pass in transformer models

---

### `tensor_softmax(T)`

Softmax activation (row-wise).

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)

**Example:**
```ring
T = tensor_init(10, 100)
tensor_random(T, -1.0, 1.0)
tensor_softmax(T)  # Each row sums to 1.0
```

**Formula:**
```
f(x_i) = e^(x_i - max(x)) / Σ e^(x_j - max(x))
```

**Features:**
- Numerically stable (subtracts max before exp)
- Row-wise normalization

---

## 6. Loss Functions

### `tensor_crossentropy_loss(pred, target)`

Cross-entropy loss for classification.

**Parameters:**
- `pred` (tensor_t*): Predictions (after softmax)
- `target` (tensor_t*): One-hot encoded targets

**Returns:**
- Loss value (double)

**Example:**
```ring
pred = tensor_init(10, 5)     # 10 samples, 5 classes
target = tensor_init(10, 5)

# ... fill with data ...
tensor_softmax(pred)

loss = tensor_crossentropy_loss(pred, target)
```

**Formula:**
```
L = -Σ target * log(pred)
```

---

### `tensor_crossentropy_backward(pred, target, grad)`

Cross-entropy backward pass.

**Parameters:**
- `pred` (tensor_t*): Predictions (after softmax)
- `target` (tensor_t*): One-hot encoded targets
- `grad` (tensor_t*): Gradient output (same shape as pred)

**Example:**
```ring
grad = tensor_init(10, 5)
tensor_crossentropy_backward(pred, target, grad)
```

**Formula:**
```
∂L/∂pred = pred - target
```

---

## 7. Transformer Operations

### `tensor_embedding_forward(emb, indices, out)`

Embedding lookup.

**Parameters:**
- `emb` (tensor_t*): Embedding matrix (vocab_size × embed_dim)
- `indices` (tensor_t*): Token indices (batch × seq_len)
- `out` (tensor_t*): Output embeddings (batch × seq_len × embed_dim)

**Example:**
```ring
vocab_size = 10000
embed_dim = 512
batch = 32
seq_len = 128

emb = tensor_init(vocab_size, embed_dim)
indices = tensor_init(batch, seq_len)
out = tensor_init(batch * seq_len, embed_dim)

tensor_embedding_forward(emb, indices, out)
```

**Performance:**
- O(batch × seq_len) lookups
- Cache-friendly memory access

---

### `tensor_embedding_backward(dOut, indices, dEmb)`

Embedding backward pass.

**Parameters:**
- `dOut` (tensor_t*): Gradient from next layer
- `indices` (tensor_t*): Token indices
- `dEmb` (tensor_t*): Embedding gradient (accumulated)

**Example:**
```ring
dEmb = tensor_init(vocab_size, embed_dim)
tensor_fill(dEmb, 0.0)

tensor_embedding_backward(dOut, indices, dEmb)
```

**Features:**
- Thread-safe gradient accumulation
- Uses atomic operations

---

### `tensor_layernorm(X, gamma, beta, eps)`

Layer Normalization.

**Parameters:**
- `X` (tensor_t*): Input (modified in-place)
- `gamma` (tensor_t*): Scale parameter (1 × features)
- `beta` (tensor_t*): Shift parameter (1 × features)
- `eps` (double): Epsilon for numerical stability (e.g., 1e-5)

**Example:**
```ring
X = tensor_init(32, 512)      # batch × features
gamma = tensor_init(1, 512)
beta = tensor_init(1, 512)

tensor_fill(gamma, 1.0)
tensor_fill(beta, 0.0)

tensor_layernorm(X, gamma, beta, 1e-5)
```

**Formula:**
```
y = γ * (x - μ) / √(σ² + ε) + β
```

where μ and σ² are computed per sample.

---

### `tensor_dropout(T, rate, training)`

Dropout regularization.

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `rate` (double): Dropout rate (0.0 to 1.0)
- `training` (int): 1 for training mode, 0 for inference

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 1.0)

# Training: randomly zero out 20% of elements
tensor_dropout(T, 0.2, 1)

# Inference: no dropout
tensor_dropout(T, 0.2, 0)
```

**Features:**
- Inverted dropout (scales remaining values)
- Deterministic in inference mode

---

## 8. Attention Mechanisms

### `tensor_attention_fast(Q, K, V, Out, scale)`

Standard scaled dot-product attention.

**Parameters:**
- `Q` (tensor_t*): Query matrix (seq_len × d_k)
- `K` (tensor_t*): Key matrix (seq_len × d_k)
- `V` (tensor_t*): Value matrix (seq_len × d_v)
- `Out` (tensor_t*): Output matrix (seq_len × d_v)
- `scale` (double): Scaling factor (typically 1/√d_k)

**Example:**
```ring
seq_len = 128
d_k = 64
d_v = 64

Q = tensor_init(seq_len, d_k)
K = tensor_init(seq_len, d_k)
V = tensor_init(seq_len, d_v)
Out = tensor_init(seq_len, d_v)

scale = 1.0 / sqrt(d_k)
tensor_attention_fast(Q, K, V, Out, scale)
```

**Formula:**
```
Attention(Q,K,V) = softmax(Q·K^T / √d_k) · V
```

---

### `tensor_attention_causal(Q, K, V, Out, scale)`

Causal (masked) attention for autoregressive models.

**Parameters:**
- Same as `tensor_attention_fast`

**Example:**
```ring
# For GPT-style models
tensor_attention_causal(Q, K, V, Out, scale)
```

**Features:**
- Prevents attending to future tokens
- Applies upper triangular mask before softmax

**Formula:**
```
mask[i,j] = -∞ if j > i, else 0
Attention(Q,K,V) = softmax((Q·K^T + mask) / √d_k) · V
```

---

### `tensor_attention_batch(Q, K, V, Out, scale, batch, seq, heads, causal)`

Multi-head batch attention.

**Parameters:**
- `Q, K, V` (tensor_t*): Shape [batch × heads × seq × d_k]
- `Out` (tensor_t*): Output [batch × heads × seq × d_v]
- `scale` (double): Scaling factor
- `batch` (int): Batch size
- `seq` (int): Sequence length
- `heads` (int): Number of attention heads
- `causal` (int): 1 for causal masking, 0 otherwise

**Example:**
```ring
batch = 32
heads = 8
seq = 128
d_k = 64

total_size = batch * heads * seq * d_k

Q = tensor_init(total_size, 1)
K = tensor_init(total_size, 1)
V = tensor_init(total_size, 1)
Out = tensor_init(total_size, 1)

tensor_reshape(Q, batch, heads, seq, d_k)
# ... same for K, V, Out ...

scale = 1.0 / sqrt(d_k)
tensor_attention_batch(Q, K, V, Out, scale, batch, seq, heads, 1)
```

**Performance:**
- Parallelized across batches and heads
- Optimized for transformer architectures

---

### `tensor_attention_linear_causal(Q, K, V, Out, scale, batch)`

Linear complexity causal attention.

**Parameters:**
- `Q, K, V` (tensor_t*): Input matrices
- `Out` (tensor_t*): Output matrix
- `scale` (double): Scaling factor
- `batch` (int): Batch size

**Performance:**
- O(n) complexity instead of O(n²)
- Suitable for long sequences

---

### `tensor_attention_multihead(Q, K, V, Out, scale, batch, seq, heads, is_causal)`

Optimized multi-head attention.

**Parameters:**
- Similar to `tensor_attention_batch`
- `is_causal` (int): 1 for causal, 0 for bidirectional

**Features:**
- Fused operations for better performance
- Reduced memory allocations

---

## 9. Optimizers

### `tensor_update_sgd(W, dW, lr)`

Stochastic Gradient Descent update.

**Parameters:**
- `W` (tensor_t*): Weights (modified in-place)
- `dW` (tensor_t*): Gradients
- `lr` (double): Learning rate

**Example:**
```ring
W = tensor_init(100, 50)
dW = tensor_init(100, 50)

# ... compute gradients ...

lr = 0.01
tensor_update_sgd(W, dW, lr)
```

**Formula:**
```
W = W - lr * dW
```

---

### `tensor_update_adam(W, dW, M, V, lr, beta1, beta2, eps, t, wd)`

Adam optimizer with weight decay (AdamW).

**Parameters:**
- `W` (tensor_t*): Weights (modified in-place)
- `dW` (tensor_t*): Gradients
- `M` (tensor_t*): First moment estimate (modified in-place)
- `V` (tensor_t*): Second moment estimate (modified in-place)
- `lr` (double): Learning rate
- `beta1` (double): First moment decay (typically 0.9)
- `beta2` (double): Second moment decay (typically 0.999)
- `eps` (double): Epsilon for numerical stability (typically 1e-8)
- `t` (int): Time step (iteration number)
- `wd` (double): Weight decay coefficient

**Example:**
```ring
W = tensor_init(100, 50)
dW = tensor_init(100, 50)
M = tensor_init(100, 50)
V = tensor_init(100, 50)

tensor_fill(M, 0.0)
tensor_fill(V, 0.0)

lr = 0.001
beta1 = 0.9
beta2 = 0.999
eps = 1e-8
t = 1
wd = 0.01

tensor_update_adam(W, dW, M, V, lr, beta1, beta2, eps, t, wd)
```

**Formula:**
```
m_t = β₁ * m_{t-1} + (1 - β₁) * g_t
v_t = β₂ * v_{t-1} + (1 - β₂) * g_t²
m̂_t = m_t / (1 - β₁^t)
v̂_t = v_t / (1 - β₂^t)
W_t = W_{t-1} - lr * (m̂_t / (√v̂_t + ε) + wd * W_{t-1})
```

---

## 10. Data Manipulation

### `tensor_fill(T, value)`

Fill tensor with a constant value.

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `value` (double): Fill value

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 3.14159)
```

---

### `tensor_random(T, min, max)`

Fill tensor with uniform random values.

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `min` (double): Minimum value
- `max` (double): Maximum value

**Example:**
```ring
T = tensor_init(100, 100)
tensor_random(T, -0.1, 0.1)  # Xavier-style initialization
```

**Distribution:**
- Uniform distribution in [min, max]

---

### `tensor_set_from_list(T, list)`

Fast bulk data loading from Ring list.

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `list` (Ring List): List of numbers

**Example:**
```ring
T = tensor_init(2, 3)
data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]

tensor_set_from_list(T, data)
```

**Performance:**
- Single C pass through Ring list
- Eliminates interpreter overhead

---

### `tensor_set_one_hot(T, indices, value)`

Set specific indices to a value (scatter operation).

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `indices` (Ring List): List of linear indices (1-based)
- `value` (double): Value to set

**Example:**
```ring
T = tensor_init(10, 10)
tensor_fill(T, 0.0)

indices = [5, 15, 25, 35]
tensor_set_one_hot(T, indices, 1.0)
```

**Use Case:**
- Creating one-hot encoded targets

---

### `tensor_select_columns(Src, indices, Dest)`

Copy specific columns to a new tensor.

**Parameters:**
- `Src` (tensor_t*): Source tensor
- `indices` (tensor_t*): Column indices (1-based)
- `Dest` (tensor_t*): Destination tensor

**Example:**
```ring
Src = tensor_init(100, 50)
indices = tensor_init(1, 10)  # Select 10 columns
Dest = tensor_init(100, 10)

# ... fill indices with column numbers ...

tensor_select_columns(Src, indices, Dest)
```

**Performance:**
- Uses `memcpy` for each column
- O(rows × selected_cols)

---

### `tensor_insert_columns(Dest, Src, indices)`

Insert columns into a tensor.

**Parameters:**
- `Dest` (tensor_t*): Destination tensor (modified in-place)
- `Src` (tensor_t*): Source tensor
- `indices` (tensor_t*): Column indices where to insert (1-based)

**Example:**
```ring
Dest = tensor_init(100, 50)
Src = tensor_init(100, 10)
indices = tensor_init(1, 10)

tensor_insert_columns(Dest, Src, indices)
```

---

### `tensor_slice_rows(Src, Dest, start_row, count)`

Copy a range of rows.

**Parameters:**
- `Src` (tensor_t*): Source tensor
- `Dest` (tensor_t*): Destination tensor
- `start_row` (int): Starting row (1-based)
- `count` (int): Number of rows to copy

**Example:**
```ring
Src = tensor_init(1000, 50)
Dest = tensor_init(32, 50)  # Batch size 32

# Extract rows 1-32
tensor_slice_rows(Src, Dest, 1, 32)
```

**Use Case:**
- Mini-batch extraction for training

---

### `tensor_insert_rows(Dest, Src, start_row)`

Insert rows into a tensor.

**Parameters:**
- `Dest` (tensor_t*): Destination tensor (modified in-place)
- `Src` (tensor_t*): Source tensor
- `start_row` (int): Starting row in destination (1-based)

**Example:**
```ring
Dest = tensor_init(1000, 50)
Src = tensor_init(32, 50)

# Insert at row 100
tensor_insert_rows(Dest, Src, 100)
```

---

### `tensor_repeat_rows(Src, Dest, repeat_count)`

Repeat rows multiple times.

**Parameters:**
- `Src` (tensor_t*): Source tensor (M × N)
- `Dest` (tensor_t*): Destination tensor (M × repeat_count × N)
- `repeat_count` (int): Number of times to repeat

**Example:**
```ring
Src = tensor_init(10, 50)
Dest = tensor_init(10, 150)  # 50 * 3

tensor_repeat_rows(Src, Dest, 3)
```

---

## 11. Persistence

### `tensor_save(ptr, filename)`

Save tensor in binary format (Double 64-bit).

**Parameters:**
- `ptr` (tensor_t*): Tensor to save
- `filename` (string): Output file path

**Example:**
```ring
T = tensor_init(1000, 1000)
tensor_random(T, -1.0, 1.0)

tensor_save(T, "model_weights.bin")
```

**File Format:**
- Header: rows (int), cols (int)
- Data: raw double array

---

### `tensor_load(filename)`

Load tensor from binary format (Double 64-bit).

**Parameters:**
- `filename` (string): Input file path

**Returns:**
- Loaded tensor pointer

**Example:**
```ring
T = tensor_load("model_weights.bin")
```

---

### `tensor_save_fp32(ptr, filename)`

Save tensor in compressed format (Float 32-bit).

**Parameters:**
- `ptr` (tensor_t*): Tensor to save
- `filename` (string): Output file path

**Example:**
```ring
T = tensor_init(1000, 1000)
tensor_save_fp32(T, "model_weights_compressed.bin")
```

**Benefits:**
- 50% smaller file size
- Faster I/O
- Suitable for deployment

---

### `tensor_load_fp32(filename)`

Load tensor from compressed format (Float 32-bit).

**Parameters:**
- `filename` (string): Input file path

**Returns:**
- Loaded tensor pointer (converted to double)

**Example:**
```ring
T = tensor_load_fp32("model_weights_compressed.bin")
```

---

### `tensor_load_inplace(ptr, filename)`

Load tensor data into existing tensor (Double 64-bit).

**Parameters:**
- `ptr` (tensor_t*): Existing tensor (must match file dimensions)
- `filename` (string): Input file path

**Example:**
```ring
T = tensor_init(1000, 1000)
tensor_load_inplace(T, "model_weights.bin")
```

**Benefits:**
- Avoids memory reallocation
- Faster for repeated loading

---

### `tensor_load_fp32_inplace(ptr, filename)`

Load compressed tensor data into existing tensor.

**Parameters:**
- `ptr` (tensor_t*): Existing tensor
- `filename` (string): Input file path

---

## 12. Graph Engine

The Graph Engine enables building computational graphs for automatic differentiation and efficient training.

### `graph_init()`

Initialize or reset the computational graph.

**Example:**
```ring
load "ringtensor.ring"

graph_init()
```

**Effect:**
- Clears all existing nodes
- Resets optimizer state
- Prepares for new graph construction

---

### `graph_node(opcode, src1, src2, [src3], [tensor])`

Create a new graph node.

**Parameters:**
- `opcode` (int): Operation code (see OPCODES_REFERENCE.md)
- `src1` (int): First parent node ID (-1 if none)
- `src2` (int): Second parent node ID (-1 if none)
- `src3` (int): Third parent node ID (optional, -1 if none)
- `tensor` (tensor_t*): Optional tensor for INPUT/WEIGHT nodes

**Returns:**
- Node ID (int)

**Example:**
```ring
# Create input node
id_X = graph_node(OP_INPUT, -1, -1, -1, X)

# Create weight node
id_W = graph_node(OP_WEIGHT, -1, -1, -1, W)

# Create matmul node
id_Z = graph_node(OP_MATMUL, id_X, id_W, -1)

# Create activation
id_A = graph_node(OP_RELU, id_Z, -1, -1)
```

---

### `graph_set_optimizer(type)`

Set the optimizer type.

**Parameters:**
- `type` (int): `OPTIMIZER_SGD` (0) or `OPTIMIZER_ADAM` (1)

**Example:**
```ring
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)
```

**Effect:**
- Allocates optimizer state (M, V) for Adam
- Configures update rules

---

### `graph_forward()`

Execute forward pass through the graph.

**Example:**
```ring
graph_forward()
```

**Effect:**
- Computes all node values in topological order
- Stores intermediate results

---

### `graph_backward()`

Execute backward pass (compute gradients).

**Example:**
```ring
graph_backward()
```

**Effect:**
- Computes gradients for all nodes
- Accumulates gradients for trainable parameters

---

### `graph_run(epochs, learning_rate)`

Run complete training loop.

**Parameters:**
- `epochs` (int): Number of training iterations
- `learning_rate` (double): Learning rate

**Example:**
```ring
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

# ... build graph ...

graph_run(1000, 0.001)
```

**Effect:**
- Runs epochs iterations of:
  1. Forward pass
  2. Backward pass
  3. Parameter update
- Entirely in C (zero Ring overhead)

**Performance:**
- Up to 100x faster than manual loops
- Optimized for transformer models

---

### `graph_run_buffered(epochs, learning_rate, batch_size)`

Memory-efficient training with batching.

**Parameters:**
- `epochs` (int): Number of epochs
- `learning_rate` (double): Learning rate
- `batch_size` (int): Mini-batch size

**Example:**
```ring
graph_run_buffered(100, 0.001, 32)
```

**Benefits:**
- Reduced memory usage
- Better for large datasets

---

### `graph_set_input(node_id, tensor)`

Update input data for a node.

**Parameters:**
- `node_id` (int): Node ID
- `tensor` (tensor_t*): New input data

**Example:**
```ring
id_X = graph_node(OP_INPUT, -1, -1, -1, X_train)

# Later, update with validation data
graph_set_input(id_X, X_val)
graph_forward()
```

---

### `graph_get_output(node_id)`

Retrieve output from a node.

**Parameters:**
- `node_id` (int): Node ID

**Returns:**
- Tensor pointer

**Example:**
```ring
id_output = graph_node(OP_SOFTMAX, id_Z, -1, -1)
graph_forward()

predictions = graph_get_output(id_output)
```

---

### `graph_bind_memory(node_id, tensor)`

Bind external memory to a node's value.

**Parameters:**
- `node_id` (int): Node ID
- `tensor` (tensor_t*): External tensor

**Use Case:**
- Sharing memory between Ring and Graph Engine
- Avoiding data copies

---

### `graph_bind_grad(node_id, tensor)`

Bind external memory to a node's gradient.

**Parameters:**
- `node_id` (int): Node ID
- `tensor` (tensor_t*): External tensor for gradient

---

### `graph_free()`

Free all graph memory.

**Example:**
```ring
graph_free()
```

**Effect:**
- Deallocates all nodes
- Frees optimizer state
- Releases tensors

---

## 13. Utilities

### `tensor_get_cores()`

Get number of CPU cores.

**Returns:**
- Number of cores (int)

**Example:**
```ring
cores = tensor_get_cores()
? "CPU Cores: " + cores
```

---

### `tensor_set_threads(count)`

Set number of OpenMP threads.

**Parameters:**
- `count` (int): Thread count

**Example:**
```ring
# Use 4 threads
tensor_set_threads(4)

# Use all cores
cores = tensor_get_cores()
tensor_set_threads(cores)
```

**Recommendation:**
- For CPU-bound tasks: use all cores
- For I/O-bound tasks: use fewer threads

---

### `tensor_clip_tensor(T, min_val, max_val)`

Clip tensor values to range.

**Parameters:**
- `T` (tensor_t*): Tensor (modified in-place)
- `min_val` (double): Minimum value
- `max_val` (double): Maximum value

**Example:**
```ring
T = tensor_init(100, 100)
tensor_random(T, -10.0, 10.0)

tensor_clip_tensor(T, -1.0, 1.0)
```

---

### `tensor_clip_global_norm(tensors, max_norm)`

Clip gradients by global norm.

**Parameters:**
- `tensors` (Ring List): List of tensor pointers
- `max_norm` (double): Maximum norm

**Example:**
```ring
gradients = [dW1, dW2, dW3]
tensor_clip_global_norm(gradients, 1.0)
```

**Formula:**
```
global_norm = √(Σ ||g_i||²)
if global_norm > max_norm:
    g_i = g_i * (max_norm / global_norm)
```

**Use Case:**
- Preventing exploding gradients

---

### `tensor_sum_squares(T)`

Compute sum of squared elements.

**Parameters:**
- `T` (tensor_t*): Tensor

**Returns:**
- Sum of squares (double)

**Example:**
```ring
T = tensor_init(100, 100)
tensor_fill(T, 2.0)

ss = tensor_sum_squares(T)  # Returns 40000.0
```

**Use Case:**
- Computing L2 norm
- Regularization

---

### `tensor_print_stats(T)`

Print tensor statistics.

**Parameters:**
- `T` (tensor_t*): Tensor

**Example:**
```ring
T = tensor_init(100, 100)
tensor_random(T, -1.0, 1.0)

tensor_print_stats(T)
```

**Output:**
```
Tensor Stats:
  Shape: 100 × 100
  Size: 10000 elements
  Min: -0.9987
  Max: 0.9991
  Mean: 0.0012
```

---

## 14. GPU Configuration

### `tensor_set_gpu_threshold(threshold)`

Set GPU offloading threshold.

**Parameters:**
- `threshold` (int): Minimum total elements to use GPU

**Example:**
```ring
# Use GPU for matrices with >5000 elements
tensor_set_gpu_threshold(5000)
```

**Default:** 10,000 elements

**Tuning:**
- Lower threshold: More GPU usage (may increase overhead for small ops)
- Higher threshold: More CPU usage (may underutilize GPU)

**Recommendation:**
- Test with your specific hardware
- Consider PCIe transfer overhead

---

## OpCode Constants

For use with Graph Engine:

### Node Types
- `OP_NONE = 0`
- `OP_INPUT = 1`
- `OP_WEIGHT = 2`

### Element-wise Operations
- `OP_ADD`, `OP_SUB`, `OP_TENSOR_MUL`, `OP_TENSOR_DIV`
- `OP_SCALAR_MUL`, `OP_ADD_SCALAR`, `OP_SUB_SCALAR`

### Matrix Operations
- `OP_MATMUL`, `OP_TRANSPOSE`

### Activations
- `OP_RELU`, `OP_SIGMOID`, `OP_TANH`, `OP_GELU`, `OP_SOFTMAX`
- `OP_RELU_PRIME`, `OP_SIGMOID_PRIME`, `OP_TANH_PRIME`, `OP_GELU_PRIME`

### Transformations
- `OP_SQUARE`, `OP_SQRT`, `OP_EXP`

### Reductions
- `OP_SUM`, `OP_MEAN`, `OP_ARGMAX`

### Loss Functions
- `OP_MSE`, `OP_CROSSENTROPY`

### Advanced
- `OP_LAYERNORM`, `OP_DROPOUT`, `OP_EMBEDDING`
- `OP_ADD_ROW_VEC`, `OP_ATTENTION`, `OP_REPEAT_ROWS`

### Optimizer Types
- `OPTIMIZER_SGD = 0`
- `OPTIMIZER_ADAM = 1`

---

## Performance Tips

1. **Use Graph Engine for Training**
   - 100x speedup for complex models
   - Eliminates Ring interpreter overhead

2. **Enable GPU for Large Operations**
   - Tune threshold based on hardware
   - Monitor GPU utilization

3. **Optimize Thread Count**
   - Use `tensor_get_cores()` to detect cores
   - Adjust with `tensor_set_threads()`

4. **Use Binary Persistence**
   - Faster than text formats
   - Use FP32 for deployment (50% smaller)

5. **Batch Operations**
   - Use `tensor_matmul_batch()` for 3D tensors
   - Leverage parallel batch processing

6. **Memory Efficiency**
   - Use in-place operations when possible
   - Reuse tensors to avoid allocations
   - Use `graph_run_buffered()` for large datasets

7. **Gradient Clipping**
   - Prevent exploding gradients
   - Use `tensor_clip_global_norm()`

---

## Error Handling

Most functions perform basic parameter validation:

- **Dimension Mismatch**: Error if tensor dimensions incompatible
- **NULL Pointers**: Error if tensor pointer is NULL
- **Invalid Parameters**: Error if parameters out of range

**Example Error Messages:**
```
Error: Matrix dimensions incompatible for multiplication
Error: Tensor pointer is NULL
Error: Invalid axis (must be 0 or 1)
```

---

## Memory Management

- **Automatic**: Tensors managed by Ring's garbage collector
- **Manual**: Use `graph_free()` to explicitly free graph memory
- **Ownership**: Tensors created by RingTensor own their data
- **Borrowed**: Use `tensor_from_memory()` for external data

---

## Thread Safety

- **Read Operations**: Thread-safe
- **Write Operations**: Not thread-safe (use external synchronization)
- **Graph Engine**: Thread-safe gradient accumulation (uses atomic operations)
- **OpenMP**: Automatic parallelization in internal kernels

---

## Platform Support

- **Windows**: MSVC 2019+
- **Linux**: GCC 7+, Clang 10+
- **macOS**: Clang 10+

**Dependencies:**
- OpenMP (optional, for multi-threading)
- OpenCL (optional, for GPU acceleration)

---

## Version Compatibility

- **Ring Language**: 1.26+
- **RingTensor**: 1.3.4

**Backward Compatibility:**
- Version 1.3.x is fully compatible with 1.2.x and 1.1.x
- No breaking API changes

---

**For more information, see:**
- [README.md](README.md) - Project overview
- [ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md) - System architecture
- [OPCODES_REFERENCE.md](OPCODES_REFERENCE.md) - Graph engine opcodes
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines

---

**Last Updated:** 2026-05-07  
**Version:** 1.3.4
**Author:** Azzeddine Remmal
