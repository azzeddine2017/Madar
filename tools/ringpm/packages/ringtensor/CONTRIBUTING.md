# Contributing to RingTensor

Thank you for your interest in contributing to **RingTensor**! This document provides guidelines and instructions for contributing to the project.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)

---

## 🤝 Code of Conduct

We are committed to providing a welcoming and inclusive environment for all contributors. Please be respectful and professional in all interactions.

### Our Standards

- **Be Respectful**: Treat everyone with respect and kindness
- **Be Collaborative**: Work together to achieve common goals
- **Be Professional**: Maintain professional conduct in all communications
- **Be Inclusive**: Welcome contributors from all backgrounds

---

## 🚀 Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Ring Language** (version 1.25 or higher)
- **C Compiler**:
  - Windows: Visual Studio 2019+ or MSVC
  - Linux/macOS: GCC 7+ or Clang 10+
- **OpenMP** support (for multi-threading)
- **OpenCL SDK** (optional, for GPU acceleration)
- **Git** for version control

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ringtensor.git
   cd ringtensor
   ```
3. Add the upstream remote:
   ```bash
   git remote add upstream https://github.com/Azzeddine2017/ringtensor.git
   ```

---

## 🛠️ Development Setup

### Building the Extension

#### Windows (MSVC)

```bat
cd extensions\ringtensor
buildvc_max_sped_x64.bat
```

#### Linux/macOS (GCC)

```bash
cd extensions/ringtensor
chmod +x buildgcc.sh
./buildgcc.sh
```

### Running Tests

```bash
# Core functionality tests
ring extensions/ringtensor/tests/test_core.ring

# Graph engine tests
ring extensions/ringtensor/testGraph/test_graph_backward.ring

# GPU tests (requires OpenCL)
ring extensions/ringtensor/testGraph/test_gpu.ring
```

---

## 💡 How to Contribute

### Types of Contributions

We welcome various types of contributions:

1. **Bug Fixes**: Fix existing issues
2. **New Features**: Add new tensor operations or optimizations
3. **Documentation**: Improve or add documentation
4. **Tests**: Add or improve test coverage
5. **Performance**: Optimize existing code
6. **Examples**: Create usage examples

### Contribution Workflow

1. **Create a Branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Changes**: Implement your changes following our coding standards

3. **Test Your Changes**: Ensure all tests pass

4. **Commit Your Changes**:
   ```bash
   git add .
   git commit -m "feat: add new tensor operation"
   ```

5. **Push to Your Fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request**: Open a PR on GitHub

---

## 📝 Coding Standards

### C Code Style

#### Naming Conventions

- **Functions**: Use `snake_case`
  - Public API: `ring_tensor_operation`
  - Internal kernels: `internal_operation`
  
- **Variables**: Use `snake_case`
  ```c
  int row_count;
  double learning_rate;
  ```

- **Constants**: Use `UPPER_SNAKE_CASE`
  ```c
  #define TILE_SIZE 32
  #define MAX_NODES 1024
  ```

- **Structs**: Use `snake_case` with `_t` suffix
  ```c
  typedef struct {
      double *data;
      int rows;
      int cols;
  } tensor_t;
  ```

#### Code Formatting

- **Indentation**: 4 spaces (no tabs)
- **Braces**: K&R style
  ```c
  void function_name(int param) {
      if (condition) {
          // code
      } else {
          // code
      }
  }
  ```

- **Line Length**: Maximum 100 characters
- **Comments**: Use `/* */` for multi-line, `//` for single-line

#### Memory Management

- Always check for `NULL` after allocation
- Free all allocated memory
- Use `memcpy` for bulk data operations
- Avoid memory leaks

```c
tensor_t *t = (tensor_t *)malloc(sizeof(tensor_t));
if (!t) {
    return NULL; // Handle allocation failure
}

t->data = (double *)calloc(rows * cols, sizeof(double));
if (!t->data) {
    free(t);
    return NULL;
}
```

#### OpenMP Guidelines

- Use `#pragma omp parallel for` for parallelizable loops
- Ensure thread safety with `atomic` or `critical` sections
- Specify private variables explicitly

```c
#pragma omp parallel for private(i, j)
for (i = 0; i < rows; i++) {
    for (j = 0; j < cols; j++) {
        // computation
    }
}
```

### Ring Code Style

- **Indentation**: 4 spaces or 1 tab
- **Naming**: Use `camelCase` for variables, `PascalCase` for classes
- **Comments**: Use `#` for single-line comments

```ring
# Load the extension
load "ringtensor.ring"

# Create a tensor
myTensor = new Tensor(100, 100)
myTensor.fill(0.5)
```

---

## 🧪 Testing Guidelines

### Writing Tests

- Create test files in `extensions/ringtensor/tests/` or `extensions/ringtensor/testGraph/`
- Name test files with `test_` prefix
- Include both positive and negative test cases
- Test edge cases (empty tensors, single element, large sizes)

### Test Structure

```ring
load "ringtensor.ring"

# Test: Matrix Multiplication
func testMatMul()
    A = new Tensor(2, 3)
    B = new Tensor(3, 2)
    
    A.fill(1.0)
    B.fill(2.0)
    
    C = A.matmul(B)
    
    # Verify result
    if C.get(1, 1) = 6.0
        ? "✓ MatMul test passed"
    else
        ? "✗ MatMul test failed"
    ok
```

### Performance Testing

- Benchmark critical operations
- Compare CPU vs GPU performance
- Test with various tensor sizes
- Document performance characteristics

---

## 🔄 Pull Request Process

### Before Submitting

1. ✅ Ensure all tests pass
2. ✅ Update documentation if needed
3. ✅ Add tests for new features
4. ✅ Follow coding standards
5. ✅ Update CHANGELOG.md

### PR Title Format

Use conventional commits format:

- `feat: add new tensor operation`
- `fix: resolve memory leak in matmul`
- `docs: update API reference`
- `perf: optimize GELU activation`
- `test: add graph engine tests`
- `refactor: restructure internal kernels`

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Performance improvement
- [ ] Documentation update
- [ ] Code refactoring

## Testing
Describe testing performed

## Checklist
- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] All tests pass
- [ ] No breaking changes (or documented)
```

### Review Process

1. Maintainers will review your PR
2. Address any feedback or requested changes
3. Once approved, your PR will be merged
4. Your contribution will be credited in CHANGELOG.md

---

## 🐛 Reporting Bugs

### Before Reporting

1. Check if the issue already exists
2. Verify you're using the latest version
3. Test with a minimal reproducible example

### Bug Report Template

```markdown
**Description**
Clear description of the bug

**To Reproduce**
Steps to reproduce the behavior:
1. Create tensor with '...'
2. Call function '...'
3. Observe error

**Expected Behavior**
What you expected to happen

**Actual Behavior**
What actually happened

**Environment**
- OS: [e.g., Windows 10, Ubuntu 20.04]
- Ring Version: [e.g., 1.25]
- RingTensor Version: [e.g., 1.3.2]
- Compiler: [e.g., MSVC 2019, GCC 9.3]

**Additional Context**
Any other relevant information
```

---

## 💡 Feature Requests

We welcome feature requests! Please provide:

1. **Use Case**: Describe the problem you're trying to solve
2. **Proposed Solution**: Your suggested implementation
3. **Alternatives**: Other solutions you've considered
4. **Additional Context**: Any relevant information

### Feature Request Template

```markdown
**Feature Description**
Clear description of the feature

**Use Case**
Why is this feature needed?

**Proposed API**
How should the API look?

**Implementation Ideas**
Any thoughts on implementation?

**Additional Context**
Any other relevant information
```

---

## 📚 Documentation Contributions

Documentation is crucial! You can help by:

- Fixing typos and grammar
- Adding examples
- Improving clarity
- Translating documentation
- Creating tutorials

### Documentation Standards

- Use clear, concise language
- Include code examples
- Add diagrams where helpful
- Keep formatting consistent
- Test all code examples

---

## 🏆 Recognition

Contributors will be:

- Listed in CHANGELOG.md
- Credited in release notes
- Acknowledged in the project README

---

## 📞 Getting Help

If you need help:

- Open a GitHub Discussion
- Check existing documentation
- Review closed issues and PRs
- Contact maintainers

---

## 📄 License

By contributing to RingTensor, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for contributing to RingTensor! Your efforts help make this project better for everyone.** 🎉
