# Changelog

All notable changes to RingTensor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.3.4] - 2026-05-07

### Added

- `ring_tensor_set_arena_size` - Configures arena allocation size (GB)
- `ring_tensor_rmsnorm` - RMS Norm (LLM specific)
- `ring_tensor_rope` - RoPE embeddings (LLM specific)
- `ring_tensor_silu` - SiLU activation (LLM specific)
- `ring_tensor_dot_row_vec` - Efficient row vector dot product

### Changed

- Updated C++ API documentation
- Added optimization notes for arena memory usage


---

## [1.3.3] - 2026-01-30

### Added
- Added mug.txt file
- Added mug_gpu_demo.ring file
- Added tensor_to_list() function
- Added tensor_from_list() function

### Changed
- Updated README.md with clearer installation instructions

### Fixed
- Minor typos in documentation
- Consistency in version numbering across files

---

## [1.3.2] - 2026-01-26

### Added
- Enhanced documentation structure with professional standards
- Comprehensive CONTRIBUTING.md guide
- Detailed API reference documentation
- Performance benchmarking examples
- Advanced usage tutorials

### Changed
- Updated README.md with clearer installation instructions
- Improved code comments and inline documentation
- Refined build scripts for better cross-platform support

### Fixed
- Minor typos in documentation
- Consistency in version numbering across files

---

## [1.3.1] - 2026-01-25

### Added
- **GPU Acceleration (OpenCL)**: Native support for Intel HD, NVIDIA, and AMD GPUs
  - Automatic GPU offloading for heavy matrix operations (`MatMul`, `Transpose`, `GELU`)
  - Smart dispatcher that chooses CPU or GPU based on workload size
  - GPU threshold configuration via `tensor_set_gpu_threshold()`
- **Binary Persistence**: 
  - `tensor_save()` and `tensor_load()` for Double-64bit format
  - `tensor_save_fp32()` and `tensor_load_fp32()` for Float-32bit format (50% smaller)
- **Advanced NLP Kernels**:
  - GELU activation function (GPT standard)
  - Batch Attention processing
  - Causal Masking for autoregressive models
- **Data Slicing Operations**:
  - `tensor_select_columns()` and `tensor_insert_columns()`
  - `tensor_slice_rows()` and `tensor_insert_rows()`
  - Ultra-fast `memcpy`-based implementations
- **Memory Optimization**:
  - Improved `tensor_copy()` using direct memory operations
  - Enhanced `tensor_set_from_list()` to eliminate Ring interpreter overhead

### Changed
- Refactored GPU initialization to support multiple platforms
- Optimized memory allocation patterns
- Improved error handling in GPU operations

### Performance
- 10-50x speedup on large matrix operations with GPU
- Reduced memory overhead in batch operations
- Faster data loading with binary persistence

---

## [1.2.1] - 2026-01-18

### Added
- **Graph Engine Enhancements**:
  - `graph_run_buffered()` for memory-efficient training
  - Support for complex computational graphs
  - Automatic gradient accumulation
- **Optimizer Improvements**:
  - AdamW optimizer with weight decay
  - Configurable optimizer selection via `graph_set_optimizer()`
- **New Attention Mechanisms**:
  - Linear Causal Attention
  - Linear Global Attention
  - Multi-Head Attention with configurable heads
  - Backward pass implementations for all attention types

### Changed
- Unified architecture with single `ring_tensor.c` file
- Improved Link-Time Optimization (LTO) support
- Enhanced thread safety with atomic operations

### Fixed
- Memory leaks in graph engine
- Gradient accumulation bugs in complex graphs
- Thread safety issues in parallel operations

---

## [1.2.0] - 2026-01-15

### Added
- **Graph Engine**: Complete computational graph system
  - Forward and backward automatic differentiation
  - Support for 40+ operations (see OPCODES_REFERENCE.md)
  - Zero-overhead training loops
  - Optimizer state management (SGD, Adam)
- **Transformer Operations**:
  - Layer Normalization with learnable parameters
  - Embedding lookup and backward pass
  - Dropout with mask persistence
  - Attention mechanisms (standard and causal)
- **Advanced Matrix Operations**:
  - Batch matrix multiplication
  - Tiled matrix multiplication for cache efficiency
  - Optimized transpose operations

### Performance
- 100x speedup for complex models using Graph Engine
- Reduced Ring interpreter overhead to near-zero
- Cache-friendly tiled operations

---

## [1.1.0] - 2026-01-10

### Added
- **OpenMP Parallelization**: Multi-core CPU support
  - Configurable thread count via `tensor_set_threads()`
  - Automatic core detection with `tensor_get_cores()`
  - Parallel implementations for all major operations
- **Activation Functions**:
  - ReLU and ReLU derivative
  - Sigmoid and Sigmoid derivative
  - Tanh and Tanh derivative
  - Softmax with numerical stability
- **Loss Functions**:
  - Mean Squared Error (MSE)
  - Cross-Entropy Loss
  - Backward pass implementations
- **Optimizer Kernels**:
  - SGD update rule
  - Adam optimizer with momentum

### Changed
- Refactored internal kernel architecture
- Separated Ring API wrappers from core logic
- Improved memory management

---

## [1.0.0] - 2026-01-05

### Added
- Initial release of RingTensor
- **Core Tensor Operations**:
  - Tensor creation and initialization
  - Element-wise operations (add, subtract, multiply, divide)
  - Scalar operations
  - Matrix multiplication (basic implementation)
  - Matrix transpose
- **Memory Management**:
  - Automatic memory allocation and deallocation
  - Deep copy support
  - Reshape functionality
- **Utility Functions**:
  - Fill tensor with values
  - Random initialization
  - Get/Set individual elements
  - Sum and mean operations
- **4D Tensor Support**:
  - Shape: [Batch, Heads, Rows, Cols]
  - Flexible dimension management
- **Ring Language Integration**:
  - Managed pointer system
  - Ring API wrappers
  - Error handling

### Performance
- Optimized matrix multiplication with tiling
- Cache-friendly memory access patterns
- Efficient memory allocation

---

## Version Numbering Scheme

RingTensor follows Semantic Versioning (SemVer):

- **MAJOR** version: Incompatible API changes
- **MINOR** version: New functionality in a backward-compatible manner
- **PATCH** version: Backward-compatible bug fixes

---

## Upgrade Guide

### From 1.2.x to 1.3.x

**New Features:**
- GPU acceleration is now available. To enable:
  ```ring
  # Check GPU availability
  cores = tensor_get_cores()
  
  # Set GPU threshold (default: 10000 elements)
  tensor_set_gpu_threshold(5000)
  ```

**Breaking Changes:**
- None. Version 1.3.x is fully backward compatible.

**Recommendations:**
- Update build scripts to include OpenCL libraries for GPU support
- Test GPU operations with your specific hardware
- Adjust GPU threshold based on your use case

### From 1.1.x to 1.2.x

**New Features:**
- Graph Engine is now available for training:
  ```ring
  graph_init()
  graph_set_optimizer(OPTIMIZER_ADAM)
  # Build graph...
  graph_run(epochs, learning_rate)
  ```

**Breaking Changes:**
- None. Version 1.2.x is fully backward compatible.

**Recommendations:**
- Migrate training loops to Graph Engine for 100x speedup
- Use `graph_run_buffered()` for large models

### From 1.0.x to 1.1.x

**New Features:**
- OpenMP support for multi-threading
- New activation and loss functions

**Breaking Changes:**
- None. Version 1.1.x is fully backward compatible.

**Recommendations:**
- Rebuild extension with OpenMP support (`/openmp` flag for MSVC, `-fopenmp` for GCC)
- Configure thread count for optimal performance

---

## Contributors

We thank all contributors who have helped make RingTensor better:

- **Azzeddine Remmal** - Project Creator and Lead Developer
- Community contributors (see GitHub contributors page)

---

## Links

- **Repository**: https://github.com/Azzeddine2017/ringtensor
- **Documentation**: See README.md and docs/
- **Issues**: https://github.com/Azzeddine2017/ringtensor/issues
- **Ring Language**: http://ring-lang.net/

---

## License

RingTensor is released under the MIT License. See LICENSE file for details.
