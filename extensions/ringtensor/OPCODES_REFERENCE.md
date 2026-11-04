# Graph Engine OpCodes Reference

This document provides a comprehensive list of operations supported by the RingTensor Graph Engine.

---

## 📋 OpCode Categories

### 1. Node Types

| OpCode | Value | Description | Usage |
|--------|-------|-------------|-------|
| `OP_NONE` | 0 | No operation | Internal use |
| `OP_INPUT` | 1 | Input placeholder | `graph_node(OP_INPUT, -1, -1, tensor)` |
| `OP_WEIGHT` | 2 | Trainable parameter | `graph_node(OP_WEIGHT, -1, -1, tensor)` |

---

### 2. Element-Wise Math

| OpCode | Description | Formula | Parents |
|--------|-------------|---------|---------|
| `OP_ADD` | Element-wise addition | `C = A + B` | 2 |
| `OP_SUB` | Element-wise subtraction | `C = A - B` | 2 |
| `OP_MUL` | Element-wise multiplication | `C = A * B` | 2 |
| `OP_DIV` | Element-wise division | `C = A / B` | 2 |
| `OP_SCALAR_MUL` | Scalar multiplication | `C = A * scalar` | 1 |
| `OP_ADD_SCALAR` | Add scalar | `C = A + scalar` | 1 |

---

### 3. Matrix Operations

| OpCode | Description | Formula | Shape |
|--------|-------------|---------|-------|
| `OP_MATMUL` | Matrix multiplication | `C = A @ B` | `(m,n) @ (n,p) -> (m,p)` |
| `OP_TRANSPOSE` | Matrix transpose | `B = A.T` | `(m,n) -> (n,m)` |

---

### 4. Activation Functions

| OpCode | Description | Formula | Derivative |
|--------|-------------|---------|------------|
| `OP_RELU` | ReLU activation | `max(0, x)` | `OP_RELU_PRIME` |
| `OP_SIGMOID` | Sigmoid activation | `1 / (1 + e^-x)` | `OP_SIGMOID_PRIME` |
| `OP_TANH` | Tanh activation | `tanh(x)` | `OP_TANH_PRIME` |
| `OP_GELU` | GELU activation | `x * Φ(x)` | `OP_GELU_PRIME` |
| `OP_SOFTMAX` | Softmax (row-wise) | `e^xi / Σe^xj` | - |

---

### 5. Loss Functions

| OpCode | Description | Use Case |
|--------|-------------|----------|
| `OP_MSE` | Mean Squared Error | Regression |
| `OP_CROSSENTROPY` | Cross-Entropy Loss | Classification |

---

### 6. Advanced Transformer Operations

| OpCode | Description | Parameters |
|--------|-------------|------------|
| `OP_LAYERNORM` | Layer Normalization | `src1`: Input, `src2`: Gamma |
| `OP_DROPOUT` | Dropout regularization | `src1`: Input (Mask stored in `node->m`) |
| `OP_EMBEDDING` | Embedding lookup | `src1`: Weights, `src2`: Indices |

---

## 🔧 Optimizer Selection

The Graph Engine supports multiple optimizers. Use `graph_set_optimizer(type)` to switch.

| Constant | Value | Description |
|----------|-------|-------------|
| `OPTIMIZER_SGD` | 0 | Standard Stochastic Gradient Descent (Default) |
| `OPTIMIZER_ADAM` | 1 | Adam Optimizer (Recommended for Transformers) |

**Example:**
```ring
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)
# ... build nodes ...
graph_run(100, 0.001)
```

---

## 📝 Technical Notes

### Memory Management
- **Intermediate Tensors**: The graph engine automatically manages memory for intermediate operation results.
- **Gradients**: Gradients are accumulated during `graph_backward` and cleared at the start of each epoch in `graph_run`.
- **Optimizer States**: Adam moments (`m` and `v`) are automatically allocated for trainable nodes when Adam is selected.

### Performance
- **Zero Overhead**: Once the graph is built, the training loop runs entirely in C.
- **OpenMP**: All kernels are parallelized using OpenMP where beneficial.

---

**Last Updated: 2026-01-18**
