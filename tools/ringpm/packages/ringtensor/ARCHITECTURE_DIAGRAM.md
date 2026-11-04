# RingTensor Architecture Diagram (v2.1)

## 🏗️ Unified Architecture Overview

RingTensor has evolved from a collection of separate files into a unified, high-performance C extension. All logic is now consolidated into `ring_tensor.c` to maximize compiler optimizations and simplify the build process.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                         RING LANGUAGE LAYER                                 │
│                         (User Application)                                  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  # Graph Engine Usage (Optimized for Training)                        │  │
│  │  graph_init()                                                         │  │
│  │  graph_set_optimizer(OPTIMIZER_ADAM)                                  │  │
│  │  id_emb = graph_node(OP_EMBEDDING, id_w, id_in)                       │  │
│  │  graph_run(epochs, lr, clipNorm)  ──► Runs entirely in C!             │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                    RING API WRAPPERS (The Shell Layer)                      │
│                         ring_tensor.c (Unified)                             │
│                                                                             │
│  • Handles Ring API (Managed Pointers, Parameter Checking)                  │
│  • Converts Ring 1-based indexing to C 0-based indexing                     │
│  • Calls Internal Kernels for actual computation                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                   GRAPH ENGINE (The Orchestration Layer)                    │
│                         ring_tensor.c (Unified)                             │
│                                                                             │
│  • Manages Computational Graph (Nodes, Edges, Gradients)                    │
│  • Performs Reverse Topological Traversal for Backward Pass                 │
│  • Manages Optimizer States (Adam/SGD)                                      │
│  • Direct Calls to Kernels (Zero Ring Overhead)                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                  INTERNAL KERNELS (The Core Engine)                         │
│                         ring_tensor.c (Unified)                             │
│                                                                             │
│  • Pure C Logic - No Ring Dependency                                        │
│  • Multi-Core Parallelization (OpenMP)                                      │
│  • Cache-Friendly Tiled Operations                                          │
│  • Atomic Updates for Thread-Safe Gradient Accumulation                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Data Flow: Graph Engine vs. Traditional

### Traditional Method
Each operation incurs a "Context Switch" between the Ring Interpreter and the C Extension.
`Ring -> C (Op1) -> Ring -> C (Op2) -> Ring ...`
**Overhead:** High for small operations in a loop.

### Graph Engine Method
The entire training loop is offloaded to C.
`Ring -> C (Build Graph) -> C (Loop 1000 Epochs) -> Ring`
**Overhead:** Near Zero.
**Performance Gain:** Up to 100x for complex models like Transformers.

---

## 📊 Memory Layout: GraphNode

The `GraphNode` structure is the heart of the Graph Engine, storing values, gradients, and optimizer states.

```c
/* Graph Node Structure */
typedef struct GraphNode {
    int id;
    int opcode;
    int src1_id;    // Index of parent node 1 (-1 if none)
    int src2_id;    // Index of parent node 2 (-1 if none)
    int src3_id;    // Index of parent node 3 (-1 if none)
    
    tensor_t *val;  // Forward Value
    tensor_t *grad; // Backward Gradient
    
    int trainable;  // 1 if this is a trainable parameter
    
    // Optimizer State (for Adam)
    tensor_t *m;    // First moment
    tensor_t *v;    // Second moment
    
    // Parameters (Scalars)
    double params[4];    // For operations that require a scalar parameter
    int heads;      // For Multi-Head Attention
    int causal;     // For Causal Masking
    int batch;      // For Attention
    int seq;        // For Attention
    int attn_type;  // 0: Standard, 1: Linear Causal, 2: Linear Global
} GraphNode;
```

---

## 🛠️ Design Principles

1. **Unified Source**: Single `ring_tensor.c` for maximum Link-Time Optimization (LTO).
2. **Zero-Copy**: Tensors are allocated in C heap and shared between nodes.
3. **Thread-Safety**: Use of `omp atomic` for gradient accumulation in parallel loops.
4. **Transformer-First**: Specialized kernels for Embedding, LayerNorm, and Attention are first-class citizens.

---
  
**Last Updated: 2026-01-18**
