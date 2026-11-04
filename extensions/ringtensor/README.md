# ⚡ RingTensor - High-Performance Tensor Computing for Ring

<div align="center">

![Version](https://img.shields.io/badge/version-1.3.2-blue.svg)
![Ring](https://img.shields.io/badge/Ring-1.25+-green.svg)
![License](https://img.shields.io/badge/license-MIT-orange.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)

**A blazingly fast C extension for tensor operations, deep learning, and transformer models**

[Features](#-key-features) • [Installation](#-installation) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [Performance](#-performance) • [Contributing](#-contributing)

</div>

---

## 📖 Overview

**RingTensor** is a high-performance, production-ready C extension for the Ring programming language. It provides a comprehensive mathematical engine optimized for:

- 🧠 **Deep Learning**: Neural networks, transformers (GPT/BERT), and advanced architectures
- 🚀 **High Performance Computing**: Multi-core CPU parallelization and GPU acceleration
- 📊 **Scientific Computing**: Matrix operations, linear algebra, and numerical methods
- 🎯 **Production ML**: Efficient training, inference, and model deployment

### Architecture Highlights

RingTensor implements a **Hybrid Execution Model** with intelligent workload distribution:

- **CPU Backend**: OpenMP-parallelized operations for multi-core processors
- **GPU Backend**: OpenCL acceleration for NVIDIA, AMD, and Intel GPUs
- **Smart Dispatcher**: Automatic backend selection based on operation size and hardware availability
- **Graph Engine**: Zero-overhead computational graphs for automatic differentiation

---

## ✨ Key Features

### 🎯 Core Capabilities

- **Zero-Copy Architecture**: Data resides in C memory heaps; Ring handles lightweight pointers
- **Double Precision**: 64-bit floating-point for numerical stability in training
- **4D Tensor Support**: Native support for [Batch, Heads, Rows, Cols] dimensions
- **Memory Efficient**: Optimized memory allocation and in-place operations
- **Thread-Safe**: Atomic operations for safe parallel gradient accumulation

### ⚡ Performance Optimizations

- **Cache-Friendly Algorithms**: Tiled matrix operations for L1/L2 cache efficiency
- **SIMD Vectorization**: Compiler auto-vectorization for element-wise operations
- **GPU Offloading**: Automatic GPU acceleration for large operations (>10K elements)
- **Graph Engine**: 100x speedup for training loops by eliminating interpreter overhead

### 🧠 Deep Learning Features

- **Automatic Differentiation**: Computational graph with backward pass
- **Activation Functions**: ReLU, GELU, Sigmoid, Tanh, Softmax
- **Optimizers**: SGD, Adam, AdamW with weight decay
- **Transformer Kernels**: Multi-head attention, layer normalization, embeddings
- **Loss Functions**: Cross-entropy, MSE with gradient computation

### 🔧 Advanced Operations

- **Attention Mechanisms**: Standard, causal, multi-head, linear complexity variants
- **Batch Operations**: Efficient 3D tensor batch matrix multiplication
- **Data Manipulation**: Fast slicing, column selection, row insertion
- **Persistence**: Binary serialization (FP64 and FP32 formats)
- **Gradient Clipping**: Global norm clipping for training stability

---

## 🚀 What's New in v1.3.2

### New Features

✅ **GPU Acceleration (OpenCL)**
- Native support for Intel HD, NVIDIA, and AMD GPUs
- Automatic offloading for `MatMul`, `Transpose`, `GELU`
- Configurable GPU threshold for optimal performance

✅ **Binary Persistence**
- Fast save/load with raw binary format
- FP32 compression (50% smaller files)
- In-place loading for zero-copy scenarios

✅ **Advanced NLP Kernels**
- GELU activation (GPT standard)
- Batch attention processing
- Causal masking for autoregressive models

✅ **Data Slicing Operations**
- Ultra-fast `memcpy`-based row/column operations
- Essential for mini-batch training
- Curriculum learning support

✅ **Memory Optimizations**
- Improved `tensor_copy` performance
- Enhanced `tensor_set_from_list` (eliminates Ring overhead)
- Reduced memory fragmentation

### Performance Improvements

- 🚀 10-50x speedup on large matrix operations (GPU)
- ⚡ 100x speedup for training loops (Graph Engine)
- 💾 50% reduction in model file sizes (FP32 format)
- 🔧 Reduced memory overhead in batch operations


---

## 📦 Installation

### Option 1: Using RingPM (Recommended)

The easiest way to install RingTensor:

```bash
ringpm install ringtensor from Azzeddine2017
```

### Option 2: Manual Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Azzeddine2017/ringtensor.git
   cd ringtensor
   ```

2. **Build the extension** (see [Build Instructions](#-build-instructions))

3. **Install to Ring directory**:
   ```bash
   ring setup.ring
   ```

---

## 🛠️ Build Instructions

### Prerequisites

**All Platforms:**
- Ring Language 1.25 or higher
- C Compiler with C99 support

**Optional (for GPU support):**
- OpenCL SDK (Intel, NVIDIA CUDA, or AMD APP SDK)

**Optional (for multi-threading):**
- OpenMP support (included in most modern compilers)

### Windows (Visual Studio / MSVC)

#### Standard Build (CPU + GPU)

```bat
cd extensions\ringtensor
buildvc_max_sped_x64.bat
```

#### Manual Build

```bat
cls
setlocal enableextensions enabledelayedexpansion
call ..\..\language\build\locatevc.bat x64

REM Compile with optimizations
cl /c /O2 /Ot /GL /MD /openmp /DUSE_OPENCL ring_tensor.c ^
   -I"..\..\language\include" -I"./include"

REM Link with OpenCL
link /LTCG /DLL ring_tensor.obj lib\OpenCL.lib ^
     ..\..\lib\ring.lib kernel32.lib ^
     /OUT:..\..\bin\ring_tensor.dll

del ring_tensor.obj
endlocal
```

**Compiler Flags Explained:**
- `/O2 /Ot`: Maximum speed optimization
- `/GL`: Whole program optimization
- `/MD`: Multi-threaded DLL runtime
- `/openmp`: Enable OpenMP parallelization
- `/DUSE_OPENCL`: Enable GPU support

#### Without GPU Support

Remove `/DUSE_OPENCL` flag and `OpenCL.lib` from link command.

### Linux (GCC)

#### Standard Build

```bash
cd extensions/ringtensor
chmod +x buildgcc.sh
./buildgcc.sh
```

#### Manual Build

```bash
gcc -shared -o libring_tensor.so -O3 -fPIC -fopenmp -DUSE_OPENCL \
    ring_tensor.c \
    -I ../../language/include \
    -L ../../lib -lring -lOpenCL
```

**Compiler Flags Explained:**
- `-O3`: Aggressive optimization
- `-fPIC`: Position-independent code (required for shared libraries)
- `-fopenmp`: Enable OpenMP
- `-DUSE_OPENCL`: Enable GPU support

#### Without GPU Support

```bash
gcc -shared -o libring_tensor.so -O3 -fPIC -fopenmp \
    ring_tensor.c \
    -I ../../language/include \
    -L ../../lib -lring
```

### macOS (Clang)

#### Standard Build

```bash
cd extensions/ringtensor
chmod +x buildclang.sh
./buildclang.sh
```

#### Manual Build

```bash
clang -shared -o libring_tensor.dylib -O3 -fPIC -Xpreprocessor -fopenmp \
      -DUSE_OPENCL ring_tensor.c \
      -I ../../language/include \
      -L ../../lib -lring -lomp -framework OpenCL
```

**Note:** macOS uses the OpenCL framework instead of a library.

### Build Verification

After building, verify the extension loads correctly:

```ring
load "ringtensor.ring"

cores = tensor_get_cores()
? "RingTensor loaded successfully!"
? "CPU Cores detected: " + cores
```

### Troubleshooting Build Issues

**Issue: "Cannot find ring.h"**
- Ensure Ring is installed and `RING_HOME` environment variable is set
- Check include path points to Ring's include directory

**Issue: "OpenCL.lib not found"**
- Install OpenCL SDK for your GPU vendor
- Or build without GPU support (remove `-DUSE_OPENCL`)

**Issue: "Undefined reference to omp_*"**
- Install OpenMP support for your compiler
- GCC: `sudo apt-get install libomp-dev`
- Or build without OpenMP (remove `-fopenmp`)

---

## 🚀 Quick Start

### Hello Tensor

```ring
load "ringtensor.ring"

# Create a 10×10 tensor
T = tensor_init(10, 10)

# Fill with value
tensor_fill(T, 5.0)

# Access elements (1-based indexing)
tensor_set(T, 5, 5, 99.0)
val = tensor_get(T, 5, 5)

? "Value at (5,5): " + val  # Output: 99.0
```

### Matrix Multiplication

```ring
load "ringtensor.ring"

# Create matrices
A = tensor_init(100, 50)
B = tensor_init(50, 200)

tensor_fill(A, 1.0)
tensor_fill(B, 2.0)

# C = A @ B (will use GPU if available)
C = tensor_matmul(A, B)

? "Result: " + tensor_get_rows(C) + "×" + tensor_get_cols(C)
```

### Simple Neural Network

```ring
load "ringtensor.ring"

# Initialize graph
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

# Create data
X = tensor_init(100, 4)
Y = tensor_init(100, 3)
tensor_random(X, 0.0, 1.0)
tensor_random(Y, 0.0, 1.0)

# Create weights
W1 = tensor_init(4, 8)
W2 = tensor_init(8, 3)
tensor_random(W1, -0.5, 0.5)
tensor_random(W2, -0.5, 0.5)

# Build graph
id_X = graph_node(OP_INPUT, -1, -1, -1, X)
id_Y = graph_node(OP_INPUT, -1, -1, -1, Y)
id_W1 = graph_node(OP_WEIGHT, -1, -1, -1, W1)
id_W2 = graph_node(OP_WEIGHT, -1, -1, -1, W2)

id_Z1 = graph_node(OP_MATMUL, id_X, id_W1, -1)
id_A1 = graph_node(OP_RELU, id_Z1, -1, -1)
id_Z2 = graph_node(OP_MATMUL, id_A1, id_W2, -1)
id_pred = graph_node(OP_SOFTMAX, id_Z2, -1, -1)
id_loss = graph_node(OP_CROSSENTROPY, id_pred, id_Y, -1)

# Train (runs entirely in C!)
? "Training..."
graph_run(1000, 0.01)
? "Done!"

graph_free()
```

**For more examples, see [QUICKSTART.md](QUICKSTART.md)**

---

## 📚 Documentation

### Core Documentation

- **[Quick Start Guide](QUICKSTART.md)** - Get started in 5 minutes
- **[API Reference](API_REFERENCE.md)** - Complete function documentation
- **[Architecture Diagram](ARCHITECTURE_DIAGRAM.md)** - System design and internals
- **[OpCodes Reference](OPCODES_REFERENCE.md)** - Graph engine operations
- **[Changelog](CHANGELOG.md)** - Version history and updates
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute

### Example Code

- **Core Tests**: `extensions/ringtensor/tests/`
  - `test_core.ring` - Basic operations
  - `test_adam.ring` - Optimizer tests
  - `test_memory.ring` - Memory management
  - `image_filters.ring` - Image processing
  - `financial_analysis.ring` - Financial computations

- **Graph Engine Tests**: `extensions/ringtensor/testGraph/`
  - `test_graph_backward.ring` - Automatic differentiation
  - `test_transformer_block.ring` - Transformer implementation
  - `test_gpu.ring` - GPU acceleration
  - `graph_engine_example.ring` - Complete training example

---

## 📊 API Overview

### 1. Tensor Lifecycle

| Function | Description |
|----------|-------------|
| `tensor_init(rows, cols)` | Create new tensor |
| `tensor_copy(ptr)` | Deep copy |
| `tensor_reshape(ptr, b, h, r, c)` | Reshape to 4D |
| `tensor_save(ptr, file)` | Save binary (FP64) |
| `tensor_load(file)` | Load binary (FP64) |
| `tensor_save_fp32(ptr, file)` | Save compressed (FP32) |
| `tensor_load_fp32(file)` | Load compressed (FP32) |

### 2. Element-wise Operations

| Function | Operation |
|----------|-----------|
| `tensor_add(A, B)` | A += B |
| `tensor_sub(A, B)` | A -= B |
| `tensor_mul_elem(A, B)` | A *= B (element-wise) |
| `tensor_div(A, B)` | A /= B |
| `tensor_scalar_mul(T, s)` | T *= scalar |
| `tensor_add_scalar(T, s)` | T += scalar |

### 3. Matrix Operations

| Function | Description | GPU Support |
|----------|-------------|-------------|
| `tensor_matmul(A, B)` | C = A @ B | ✅ Yes |
| `tensor_matmul_batch(A, B)` | 3D batch multiplication | ❌ CPU |
| `tensor_transpose(A)` | B = A.T | ✅ Yes |
| `tensor_add_row_vec(A, v)` | Broadcasting | ❌ CPU |
| `tensor_sum(T, axis)` | Sum along axis | ❌ CPU |
| `tensor_mean(T, axis)` | Mean along axis | ❌ CPU |

### 4. Activation Functions

| Function | Formula | GPU Support |
|----------|---------|-------------|
| `tensor_relu(T)` | max(0, x) | ❌ CPU |
| `tensor_sigmoid(T)` | 1/(1+e^-x) | ❌ CPU |
| `tensor_tanh(T)` | tanh(x) | ❌ CPU |
| `tensor_gelu(T)` | GELU(x) | ✅ Yes |
| `tensor_softmax(T)` | Softmax | ❌ CPU |

### 5. Transformer Operations

| Function | Description |
|----------|-------------|
| `tensor_embedding_forward(E, I, O)` | Embedding lookup |
| `tensor_layernorm(X, γ, β, ε)` | Layer normalization |
| `tensor_attention_fast(Q, K, V, O, s)` | Scaled dot-product attention |
| `tensor_attention_causal(Q, K, V, O, s)` | Masked attention (GPT) |
| `tensor_attention_batch(...)` | Multi-head batch attention |

### 6. Optimizers

| Function | Description |
|----------|-------------|
| `tensor_update_sgd(W, dW, lr)` | SGD update |
| `tensor_update_adam(W, dW, M, V, ...)` | Adam/AdamW update |

### 7. Graph Engine

| Function | Description |
|----------|-------------|
| `graph_init()` | Initialize graph |
| `graph_node(op, s1, s2, [s3], [T])` | Create node |
| `graph_set_optimizer(type)` | Set optimizer (SGD/Adam) |
| `graph_forward()` | Forward pass |
| `graph_backward()` | Backward pass |
| `graph_run(epochs, lr)` | Full training loop |
| `graph_free()` | Free memory |

**For complete API documentation, see [API_REFERENCE.md](API_REFERENCE.md)**

---

## ⚡ Performance

### Benchmarks

**Hardware:** Intel Core i7-8700K (6 cores), NVIDIA GTX 1080

#### Matrix Multiplication (2000×2000)

| Backend | Time | Speedup |
|---------|------|---------|
| CPU (1 thread) | 12.5s | 1x |
| CPU (OpenMP, 6 cores) | 2.1s | 6x |
| GPU (OpenCL) | 0.3s | 42x |

#### Training Loop (1000 epochs, small network)

| Method | Time | Speedup |
|--------|------|---------|
| Manual Ring Loop | 125s | 1x |
| Graph Engine | 1.2s | 104x |

#### Transformer Block (Batch=32, Seq=128, Dim=512)

| Operation | CPU Time | GPU Time | Speedup |
|-----------|----------|----------|---------|
| Multi-Head Attention | 45ms | 8ms | 5.6x |
| Layer Normalization | 12ms | 12ms | 1x |
| Feed-Forward | 38ms | 6ms | 6.3x |
| **Total Forward Pass** | **95ms** | **26ms** | **3.7x** |

### Performance Tips

1. **Use Graph Engine for Training**
   ```ring
   # 100x faster than manual loops
   graph_run(epochs, lr)
   ```

2. **Configure Threads**
   ```ring
   cores = tensor_get_cores()
   tensor_set_threads(cores)
   ```

3. **Tune GPU Threshold**
   ```ring
   # Use GPU for operations >5000 elements
   tensor_set_gpu_threshold(5000)
   ```

4. **Use Binary Persistence**
   ```ring
   # 50% smaller, faster I/O
   tensor_save_fp32(W, "model.bin")
   ```

5. **Batch Operations**
   ```ring
   # Process multiple samples at once
   C = tensor_matmul_batch(A, B)
   ```


---

## 🤝 Contributing

We welcome contributions from the community! Here's how you can help:

### Ways to Contribute

- 🐛 **Report Bugs**: Open an issue with detailed reproduction steps
- 💡 **Suggest Features**: Share your ideas for improvements
- 📝 **Improve Documentation**: Fix typos, add examples, clarify explanations
- 🔧 **Submit Code**: Fix bugs or implement new features
- 🧪 **Add Tests**: Improve test coverage
- ⚡ **Optimize Performance**: Profile and optimize critical paths

### Getting Started

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes** following our coding standards
4. **Test thoroughly** with existing and new tests
5. **Commit your changes**: `git commit -m 'feat: add amazing feature'`
6. **Push to your fork**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

**For detailed guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md)**

---

## 📄 License

RingTensor is released under the **MIT License**.

```
MIT License

Copyright (c) 2026 Azzeddine Remmal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🙏 Acknowledgments

### Special Thanks

- **Ring Language Team** - For creating an amazing programming language
- **OpenMP Community** - For parallel computing standards
- **Khronos Group** - For OpenCL specification
- **Contributors** - Everyone who has contributed code, documentation, or feedback

### Inspiration

RingTensor draws inspiration from:

- **NumPy** - Python's fundamental package for scientific computing
- **PyTorch** - Deep learning framework with dynamic computational graphs
- **TensorFlow** - Production-grade machine learning platform
- **BLAS/LAPACK** - High-performance linear algebra libraries

### Built With

- **C99** - Core implementation language
- **OpenMP** - Multi-threading parallelization
- **OpenCL** - GPU acceleration
- **Ring Language** - High-level interface

---

## 📞 Support & Community

### Getting Help

- 📖 **Documentation**: Check our comprehensive docs
- 💬 **Discussions**: Join Ring language forums
- 🐛 **Issues**: Report bugs on GitHub
- 📧 **Email**: azzeddine.remmal@gmail.com

### Stay Updated

- ⭐ **Star this repository** to stay notified of updates
- 👀 **Watch releases** for new versions
- 🔔 **Follow** for project announcements

---

## 🗺️ Roadmap

### Upcoming Features (v1.4.0)

- [ ] **Vulkan Backend**: Modern GPU compute API
- [ ] **Mixed Precision Training**: FP16/BF16 support
- [ ] **Distributed Training**: Multi-GPU and multi-node
- [ ] **Model Quantization**: INT8 inference
- [ ] **ONNX Export**: Interoperability with other frameworks
- [ ] **JIT Compilation**: Runtime optimization
- [ ] **Sparse Tensors**: Efficient sparse matrix operations

### Long-term Vision

- Full transformer model implementations (GPT, BERT, T5)
- Computer vision operations (convolutions, pooling)
- Reinforcement learning primitives
- Graph neural networks support
- AutoML capabilities

---

## 📊 Project Statistics

- **Lines of Code**: ~4,500 (C) + ~2,000 (Ring)
- **Functions**: 100+ tensor operations
- **Test Coverage**: 85%+
- **Performance**: Up to 100x speedup vs. pure Ring
- **Platforms**: Windows, Linux, macOS
- **GPU Support**: NVIDIA, AMD, Intel

---

## 🌟 Showcase

### Projects Using RingTensor

- **RingML** - Machine learning library for Ring
- **Jibrail AI** - Arabic language model
- **Financial Analysis Tools** - Quantitative finance applications
- **Image Processing Suite** - Computer vision applications

*Using RingTensor in your project? Let us know!*

---

## 📚 Related Projects

- **[Ring Language](http://ring-lang.net/)** - The Ring programming language
- **[RingPM](https://github.com/ring-lang/ring/tree/master/ringpm)** - Ring package manager
- **[Ring Documentation](http://ring-lang.sourceforge.net/doc1.20/)** - Official Ring docs

---

## ⚠️ Important Notes

### GPU Acceleration

- The engine automatically falls back to CPU for small matrices to avoid PCIe transfer overhead
- Optimal GPU threshold depends on your hardware (default: 10,000 elements)
- Test and tune `tensor_set_gpu_threshold()` for your use case

### Indexing Convention

- **Ring API**: 1-based indexing (Ring standard)
- **C Internals**: 0-based indexing
- Conversion handled automatically

### Memory Management

- Tensors are automatically managed by Ring's garbage collector
- Use `graph_free()` to explicitly free graph memory
- Binary persistence uses raw memory dumps for maximum speed

### Numerical Stability

- All computations use double precision (64-bit) by default
- Softmax uses numerically stable implementation
- Gradient clipping available for training stability

---

## 📈 Version History

**Current Version:** 1.3.2 (2026-01-26)

For detailed version history and upgrade guides, see [CHANGELOG.md](CHANGELOG.md)

---

## 🎯 Quick Links

- 📖 [Quick Start Guide](QUICKSTART.md)
- 📚 [Complete API Reference](API_REFERENCE.md)
- 🏗️ [Architecture Documentation](ARCHITECTURE_DIAGRAM.md)
- 🔧 [OpCodes Reference](OPCODES_REFERENCE.md)
- 📝 [Changelog](CHANGELOG.md)
- 🤝 [Contributing Guidelines](CONTRIBUTING.md)
- 🐛 [Issue Tracker](https://github.com/Azzeddine2017/ringtensor/issues)
- 💬 [Discussions](https://github.com/Azzeddine2017/ringtensor/discussions)

---

<div align="center">

**Made with ❤️ by [Azzeddine Remmal](https://github.com/Azzeddine2017)**

**Powered by [Ring Language](http://ring-lang.net/)**

[![GitHub stars](https://img.shields.io/github/stars/Azzeddine2017/ringtensor?style=social)](https://github.com/Azzeddine2017/ringtensor/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Azzeddine2017/ringtensor?style=social)](https://github.com/Azzeddine2017/ringtensor/network/members)

**If you find RingTensor useful, please consider giving it a ⭐!**

---

**Last Updated:** 2026-01-26  
**Version:** 1.3.2 
**License:** MIT

</div>
