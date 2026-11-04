# RingTensor Quick Start Guide

Welcome to **RingTensor**! This guide will help you get started quickly with the most common operations.

---

## 📦 Installation

### Using RingPM (Recommended)

```bash
ringpm install ringtensor from Azzeddine2017
```

### Manual Installation

1. Clone the repository
2. Build the extension (see [Building](#building))
3. Copy files to Ring installation directory

---

## 🔨 Building

### Windows (MSVC)

```bat
cd extensions\ringtensor
OpenCL_buildvc_x64.bat
```

### Linux/macOS (GCC)

```bash
cd extensions/ringtensor
chmod +x buildgcc.sh
./buildgcc.sh
```

---

## 🚀 Your First Tensor

```ring
load "ringtensor.ring"

# Create a 10×10 tensor
T = tensor_init(10, 10)

# Fill with value
tensor_fill(T, 5.0)

# Get dimensions
rows = tensor_get_rows(T)  # 10
cols = tensor_get_cols(T)  # 10

# Access elements (1-based indexing)
tensor_set(T, 5, 5, 99.0)
val = tensor_get(T, 5, 5)  # 99.0

? "Created tensor: " + rows + "×" + cols
? "Value at (5,5): " + val
```

**Output:**
```
Created tensor: 10×10
Value at (5,5): 99.0
```

---

## 🧮 Basic Operations

### Element-wise Operations

```ring
load "ringtensor.ring"

# Create two tensors
A = tensor_init(100, 100)
B = tensor_init(100, 100)

tensor_fill(A, 3.0)
tensor_fill(B, 2.0)

# Addition (in-place)
tensor_add(A, B)  # A = A + B = 5.0

# Subtraction
tensor_sub(A, B)  # A = A - B = 3.0

# Multiplication
tensor_mul_elem(A, B)  # A = A * B = 6.0

# Division
tensor_div(A, B)  # A = A / B = 3.0

# Scalar operations
tensor_scalar_mul(A, 2.0)  # A = A * 2 = 6.0
tensor_add_scalar(A, 10.0)  # A = A + 10 = 16.0
```

---

## 🔢 Matrix Operations

### Matrix Multiplication

```ring
load "ringtensor.ring"

# Create matrices
A = tensor_init(100, 50)   # 100×50
B = tensor_init(50, 200)   # 50×200

tensor_fill(A, 1.0)
tensor_fill(B, 2.0)

# Matrix multiplication: C = A @ B
C = tensor_matmul(A, B)    # 100×200

? "Result shape: " + tensor_get_rows(C) + "×" + tensor_get_cols(C)
? "Sample value: " + tensor_get(C, 1, 1)  # 100.0 (50 * 1.0 * 2.0)
```

### Matrix Transpose

```ring
A = tensor_init(100, 50)
tensor_fill(A, 5.0)

B = tensor_transpose(A)  # 50×100

? "Original: " + tensor_get_rows(A) + "×" + tensor_get_cols(A)
? "Transposed: " + tensor_get_rows(B) + "×" + tensor_get_cols(B)
```

---

## 🎯 Activation Functions

```ring
load "ringtensor.ring"

T = tensor_init(5, 5)
tensor_random(T, -2.0, 2.0)

? "Original values:"
tensor_print_stats(T)

# ReLU: max(0, x)
tensor_relu(T)
? "\nAfter ReLU:"
tensor_print_stats(T)

# Sigmoid: 1 / (1 + e^-x)
tensor_random(T, -2.0, 2.0)
tensor_sigmoid(T)
? "\nAfter Sigmoid (values in 0-1):"
tensor_print_stats(T)

# Tanh: (-1, 1)
tensor_random(T, -2.0, 2.0)
tensor_tanh(T)
? "\nAfter Tanh (values in -1 to 1):"
tensor_print_stats(T)

# GELU (for transformers)
tensor_random(T, -2.0, 2.0)
tensor_gelu(T)
? "\nAfter GELU:"
tensor_print_stats(T)

# Softmax (row-wise normalization)
tensor_random(T, -2.0, 2.0)
tensor_softmax(T)
? "\nAfter Softmax (each row sums to 1):"
tensor_print_stats(T)
```

---

## 🤖 Simple Neural Network (Manual)

```ring
load "ringtensor.ring"

# Network: Input(4) -> Hidden(8) -> Output(3)

# Initialize weights
W1 = tensor_init(4, 8)
W2 = tensor_init(8, 3)

tensor_random(W1, -0.5, 0.5)
tensor_random(W2, -0.5, 0.5)

# Input data (batch of 10 samples)
X = tensor_init(10, 4)
tensor_random(X, 0.0, 1.0)

# Forward pass
# Layer 1
Z1 = tensor_matmul(X, W1)     # 10×8
tensor_relu(Z1)               # Activation

# Layer 2
Z2 = tensor_matmul(Z1, W2)    # 10×3
tensor_softmax(Z2)            # Output probabilities

? "Network output shape: " + tensor_get_rows(Z2) + "×" + tensor_get_cols(Z2)
? "Sample prediction (row 1):"
? "  Class 0: " + tensor_get(Z2, 1, 1)
? "  Class 1: " + tensor_get(Z2, 1, 2)
? "  Class 2: " + tensor_get(Z2, 1, 3)
```

---

## ⚡ Graph Engine (Automatic Training)

The Graph Engine runs training loops entirely in C for 100x speedup!

```ring
load "ringtensor.ring"

# Initialize graph
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

# Prepare data
X_train = tensor_init(100, 4)   # 100 samples, 4 features
Y_train = tensor_init(100, 3)   # 100 samples, 3 classes

tensor_random(X_train, 0.0, 1.0)
tensor_random(Y_train, 0.0, 1.0)
tensor_softmax(Y_train)  # Normalize targets

# Create weights
W1 = tensor_init(4, 8)
W2 = tensor_init(8, 3)

tensor_random(W1, -0.5, 0.5)
tensor_random(W2, -0.5, 0.5)

# Build computational graph
id_X = graph_node(OP_INPUT, -1, -1, -1, X_train)
id_Y = graph_node(OP_INPUT, -1, -1, -1, Y_train)

id_W1 = graph_node(OP_WEIGHT, -1, -1, -1, W1)
id_W2 = graph_node(OP_WEIGHT, -1, -1, -1, W2)

# Forward: X @ W1
id_Z1 = graph_node(OP_MATMUL, id_X, id_W1, -1)

# ReLU activation
id_A1 = graph_node(OP_RELU, id_Z1, -1, -1)

# Z1 @ W2
id_Z2 = graph_node(OP_MATMUL, id_A1, id_W2, -1)

# Softmax
id_pred = graph_node(OP_SOFTMAX, id_Z2, -1, -1)

# Loss
id_loss = graph_node(OP_CROSSENTROPY, id_pred, id_Y, -1)

# Train for 1000 epochs
? "Training started..."
t1 = clock()

graph_run(1000, 0.01)  # 1000 epochs, lr=0.01

elapsed = (clock() - t1) / clockspersecond()
? "Training completed in " + elapsed + " seconds"

# Get predictions
graph_forward()
predictions = graph_get_output(id_pred)

? "Final predictions (first sample):"
? "  Class 0: " + tensor_get(predictions, 1, 1)
? "  Class 1: " + tensor_get(predictions, 1, 2)
? "  Class 2: " + tensor_get(predictions, 1, 3)

# Cleanup
graph_free()
```

---

## 💾 Saving and Loading

### Binary Format (Double Precision)

```ring
load "ringtensor.ring"

# Create and save
W = tensor_init(1000, 1000)
tensor_random(W, -1.0, 1.0)

tensor_save(W, "weights.bin")
? "Saved 1000×1000 tensor"

# Load
W_loaded = tensor_load("weights.bin")
? "Loaded tensor: " + tensor_get_rows(W_loaded) + "×" + tensor_get_cols(W_loaded)
```

### Compressed Format (Float 32-bit)

```ring
# Save compressed (50% smaller)
tensor_save_fp32(W, "weights_compressed.bin")
? "Saved compressed tensor"

# Load compressed
W_loaded = tensor_load_fp32("weights_compressed.bin")
? "Loaded compressed tensor"
```

---

## 🎮 GPU Acceleration

RingTensor automatically uses GPU for large operations!

```ring
load "ringtensor.ring"

# Check CPU cores
cores = tensor_get_cores()
? "CPU Cores: " + cores

# Configure threads
tensor_set_threads(cores)

# Set GPU threshold (use GPU for >5000 elements)
tensor_set_gpu_threshold(5000)

# Large matrix multiplication (will use GPU if available)
A = tensor_init(2000, 2000)
B = tensor_init(2000, 2000)

tensor_fill(A, 1.5)
tensor_fill(B, 2.5)

? "Running large MatMul (GPU accelerated)..."
t1 = clock()

C = tensor_matmul(A, B)

elapsed = (clock() - t1) / clockspersecond()
? "Completed in " + elapsed + " seconds"
? "Result sample: " + tensor_get(C, 1, 1)
```

---

## 🔍 Data Manipulation

### Slicing Rows (Mini-batches)

```ring
load "ringtensor.ring"

# Full dataset
dataset = tensor_init(1000, 50)
tensor_random(dataset, 0.0, 1.0)

# Extract mini-batch (rows 1-32)
batch = tensor_init(32, 50)
tensor_slice_rows(dataset, batch, 1, 32)

? "Extracted batch: " + tensor_get_rows(batch) + "×" + tensor_get_cols(batch)
```

### Selecting Columns

```ring
# Select specific columns
src = tensor_init(100, 50)
tensor_random(src, 0.0, 1.0)

# Select columns 1, 5, 10, 15, 20
indices = tensor_init(1, 5)
tensor_set(indices, 1, 1, 1.0)
tensor_set(indices, 1, 2, 5.0)
tensor_set(indices, 1, 3, 10.0)
tensor_set(indices, 1, 4, 15.0)
tensor_set(indices, 1, 5, 20.0)

dest = tensor_init(100, 5)
tensor_select_columns(src, indices, dest)

? "Selected 5 columns from 50"
```

---

## 🧠 Transformer Operations

### Layer Normalization

```ring
load "ringtensor.ring"

# Input: batch of 32 samples, 512 features each
X = tensor_init(32, 512)
tensor_random(X, -1.0, 1.0)

# Learnable parameters
gamma = tensor_init(1, 512)
beta = tensor_init(1, 512)

tensor_fill(gamma, 1.0)
tensor_fill(beta, 0.0)

# Apply layer normalization
tensor_layernorm(X, gamma, beta, 1e-5)

? "Applied LayerNorm"
tensor_print_stats(X)
```

### Embedding Lookup

```ring
# Vocabulary size: 10000, embedding dimension: 512
embeddings = tensor_init(10000, 512)
tensor_random(embeddings, -0.1, 0.1)

# Token indices (batch=32, sequence=128)
indices = tensor_init(32, 128)
# ... fill with token IDs ...

# Output embeddings
output = tensor_init(32 * 128, 512)

tensor_embedding_forward(embeddings, indices, output)

? "Embedded " + (32*128) + " tokens"
```

### Attention Mechanism

```ring
# Sequence length: 128, dimension: 64
seq_len = 128
d_k = 64

Q = tensor_init(seq_len, d_k)
K = tensor_init(seq_len, d_k)
V = tensor_init(seq_len, d_k)
Out = tensor_init(seq_len, d_k)

tensor_random(Q, -0.1, 0.1)
tensor_random(K, -0.1, 0.1)
tensor_random(V, -0.1, 0.1)

# Scaled dot-product attention
scale = 1.0 / sqrt(d_k)
tensor_attention_fast(Q, K, V, Out, scale)

? "Applied attention mechanism"

# For autoregressive models (GPT), use causal attention
tensor_attention_causal(Q, K, V, Out, scale)
? "Applied causal attention (masked)"
```

---

## 🎓 Training Tips

### 1. Use Graph Engine for Training

**Bad (Slow):**
```ring
# Manual loop in Ring (slow due to interpreter overhead)
for epoch = 1 to 1000
    Z1 = tensor_matmul(X, W1)
    tensor_relu(Z1)
    Z2 = tensor_matmul(Z1, W2)
    # ... backward pass ...
    # ... optimizer update ...
end
```

**Good (Fast):**
```ring
# Graph engine (100x faster)
graph_init()
# ... build graph ...
graph_run(1000, 0.01)  # Runs entirely in C!
```

### 2. Configure Threads

```ring
# Detect and use all cores
cores = tensor_get_cores()
tensor_set_threads(cores)
```

### 3. Use Binary Persistence

```ring
# Save models in binary format
tensor_save_fp32(W, "model.bin")  # 50% smaller

# Load quickly
W = tensor_load_fp32("model.bin")
```

### 4. Batch Your Data

```ring
batch_size = 32
for i = 1 to num_samples step batch_size
    batch = tensor_init(batch_size, features)
    tensor_slice_rows(dataset, batch, i, batch_size)
    # ... train on batch ...
end
```

### 5. Gradient Clipping

```ring
# Prevent exploding gradients
gradients = [dW1, dW2, dW3]
tensor_clip_global_norm(gradients, 1.0)
```

---

## 📊 Performance Benchmarks

### Matrix Multiplication (2000×2000)

| Backend | Time | Speedup |
|---------|------|---------|
| CPU (Single-threaded) | 12.5s | 1x |
| CPU (OpenMP, 8 cores) | 2.1s | 6x |
| GPU (OpenCL) | 0.3s | 42x |

### Training Loop (1000 epochs)

| Method | Time | Speedup |
|--------|------|---------|
| Manual Ring Loop | 125s | 1x |
| Graph Engine | 1.2s | 104x |

---

## 🐛 Common Issues

### Issue: "Cannot find ringtensor.ring"

**Solution:**
```ring
# Use absolute path or ensure package is installed
load "C:/Ring/extensions/ringtensor/ringtensor.ring"
```

### Issue: "Dimension mismatch"

**Solution:**
```ring
# Check dimensions before operations
? "A: " + tensor_get_rows(A) + "×" + tensor_get_cols(A)
? "B: " + tensor_get_rows(B) + "×" + tensor_get_cols(B)

# For matmul: A.cols must equal B.rows
```

### Issue: "Slow performance"

**Solutions:**
1. Use Graph Engine for training loops
2. Enable all CPU cores: `tensor_set_threads(tensor_get_cores())`
3. Use GPU for large operations: `tensor_set_gpu_threshold(5000)`
4. Rebuild with optimizations enabled

---

## 📚 Next Steps

1. **Read the API Reference**: [API_REFERENCE.md](API_REFERENCE.md)
2. **Explore Examples**: Check `extensions/ringtensor/tests/` and `testGraph/`
3. **Study Architecture**: [ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)
4. **Learn Graph Engine**: [OPCODES_REFERENCE.md](OPCODES_REFERENCE.md)
5. **Contribute**: [CONTRIBUTING.md](CONTRIBUTING.md)

---

## 🎯 Example Projects

### 1. Linear Regression

See: `extensions/ringtensor/tests/test_core.ring`

### 2. Image Processing

See: `extensions/ringtensor/tests/image_filters.ring`

### 3. Financial Analysis

See: `extensions/ringtensor/tests/financial_analysis.ring`

### 4. Transformer Block

See: `extensions/ringtensor/testGraph/test_transformer_block.ring`

### 5. GPU Acceleration

See: `extensions/ringtensor/testGraph/test_gpu.ring`

---

## 💬 Getting Help

- **Documentation**: Check README.md and API_REFERENCE.md
- **Examples**: Browse test files in `tests/` and `testGraph/`
- **Issues**: Report bugs on GitHub
- **Community**: Join Ring language forums

---

**Happy Coding with RingTensor! 🚀**
