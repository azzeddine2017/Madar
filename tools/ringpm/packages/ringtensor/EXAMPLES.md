# RingTensor Advanced Examples

This document contains advanced examples and use cases for RingTensor.

---

## 📋 Table of Contents

1. [Linear Regression](#1-linear-regression)
2. [Logistic Regression](#2-logistic-regression)
3. [Multi-Layer Neural Network](#3-multi-layer-neural-network)
4. [Mini-Batch Training](#4-mini-batch-training)
5. [Transformer Attention Block](#5-transformer-attention-block)
6. [Image Convolution](#6-image-convolution)
7. [Time Series Prediction](#7-time-series-prediction)
8. [Gradient Descent Variants](#8-gradient-descent-variants)
9. [Custom Loss Functions](#9-custom-loss-functions)
10. [Model Persistence](#10-model-persistence)

---

## 1. Linear Regression

Simple linear regression using Graph Engine.

```ring
load "ringtensor.ring"

# Generate synthetic data: y = 2x + 3 + noise
func generateData(n)
    X = tensor_init(n, 1)
    Y = tensor_init(n, 1)
    
    for i = 1 to n
        x_val = (i / n) * 10.0  # 0 to 10
        y_val = 2.0 * x_val + 3.0 + (random(100) / 100.0 - 0.5)
        
        tensor_set(X, i, 1, x_val)
        tensor_set(Y, i, 1, y_val)
    next
    
    return [X, Y]

# Main
n_samples = 100
data = generateData(n_samples)
X_train = data[1]
Y_train = data[2]

# Initialize parameters
W = tensor_init(1, 1)
b = tensor_init(1, 1)
tensor_random(W, -0.1, 0.1)
tensor_fill(b, 0.0)

# Build graph
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

id_X = graph_node(OP_INPUT, -1, -1, -1, X_train)
id_Y = graph_node(OP_INPUT, -1, -1, -1, Y_train)
id_W = graph_node(OP_WEIGHT, -1, -1, -1, W)
id_b = graph_node(OP_WEIGHT, -1, -1, -1, b)

# Forward: pred = X @ W + b
id_pred = graph_node(OP_MATMUL, id_X, id_W, -1)
id_pred = graph_node(OP_ADD, id_pred, id_b, -1)

# Loss: MSE
id_loss = graph_node(OP_MSE, id_pred, id_Y, -1)

# Train
? "Training Linear Regression..."
graph_run(1000, 0.01)

# Get learned parameters
? "Learned W: " + tensor_get(W, 1, 1)  # Should be ~2.0
? "Learned b: " + tensor_get(b, 1, 1)  # Should be ~3.0

graph_free()
```

---

## 2. Logistic Regression

Binary classification with sigmoid activation.

```ring
load "ringtensor.ring"

# Generate binary classification data
func generateBinaryData(n)
    X = tensor_init(n, 2)
    Y = tensor_init(n, 1)
    
    for i = 1 to n
        x1 = random(100) / 50.0 - 1.0  # -1 to 1
        x2 = random(100) / 50.0 - 1.0
        
        # Decision boundary: y = 1 if x1 + x2 > 0
        label = 0.0
        if x1 + x2 > 0
            label = 1.0
        ok
        
        tensor_set(X, i, 1, x1)
        tensor_set(X, i, 2, x2)
        tensor_set(Y, i, 1, label)
    next
    
    return [X, Y]

# Main
n_samples = 200
data = generateBinaryData(n_samples)
X_train = data[1]
Y_train = data[2]

# Initialize weights
W = tensor_init(2, 1)
b = tensor_init(1, 1)
tensor_random(W, -0.5, 0.5)
tensor_fill(b, 0.0)

# Build graph
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

id_X = graph_node(OP_INPUT, -1, -1, -1, X_train)
id_Y = graph_node(OP_INPUT, -1, -1, -1, Y_train)
id_W = graph_node(OP_WEIGHT, -1, -1, -1, W)
id_b = graph_node(OP_WEIGHT, -1, -1, -1, b)

# Forward: sigmoid(X @ W + b)
id_z = graph_node(OP_MATMUL, id_X, id_W, -1)
id_z = graph_node(OP_ADD, id_z, id_b, -1)
id_pred = graph_node(OP_SIGMOID, id_z, -1, -1)

# Binary cross-entropy loss
id_loss = graph_node(OP_CROSSENTROPY, id_pred, id_Y, -1)

# Train
? "Training Logistic Regression..."
graph_run(500, 0.1)

# Test accuracy
graph_forward()
predictions = graph_get_output(id_pred)

correct = 0
for i = 1 to n_samples
    pred = tensor_get(predictions, i, 1)
    actual = tensor_get(Y_train, i, 1)
    
    pred_class = 0.0
    if pred > 0.5
        pred_class = 1.0
    ok
    
    if pred_class = actual
        correct++
    ok
next

accuracy = (correct / n_samples) * 100.0
? "Accuracy: " + accuracy + "%"

graph_free()
```

---

## 3. Multi-Layer Neural Network

Deep neural network with multiple hidden layers.

```ring
load "ringtensor.ring"

# XOR problem (non-linearly separable)
func createXORData()
    X = tensor_init(4, 2)
    Y = tensor_init(4, 1)
    
    # XOR truth table
    tensor_set(X, 1, 1, 0.0)  # [0, 0] -> 0
    tensor_set(X, 1, 2, 0.0)
    tensor_set(Y, 1, 1, 0.0)
    
    tensor_set(X, 2, 1, 0.0)  # [0, 1] -> 1
    tensor_set(X, 2, 2, 1.0)
    tensor_set(Y, 2, 1, 1.0)
    
    tensor_set(X, 3, 1, 1.0)  # [1, 0] -> 1
    tensor_set(X, 3, 2, 0.0)
    tensor_set(Y, 3, 1, 1.0)
    
    tensor_set(X, 4, 1, 1.0)  # [1, 1] -> 0
    tensor_set(X, 4, 2, 1.0)
    tensor_set(Y, 4, 1, 0.0)
    
    return [X, Y]

# Main
data = createXORData()
X_train = data[1]
Y_train = data[2]

# Network: 2 -> 8 -> 4 -> 1
W1 = tensor_init(2, 8)
W2 = tensor_init(8, 4)
W3 = tensor_init(4, 1)

tensor_random(W1, -1.0, 1.0)
tensor_random(W2, -1.0, 1.0)
tensor_random(W3, -1.0, 1.0)

# Build graph
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

id_X = graph_node(OP_INPUT, -1, -1, -1, X_train)
id_Y = graph_node(OP_INPUT, -1, -1, -1, Y_train)

id_W1 = graph_node(OP_WEIGHT, -1, -1, -1, W1)
id_W2 = graph_node(OP_WEIGHT, -1, -1, -1, W2)
id_W3 = graph_node(OP_WEIGHT, -1, -1, -1, W3)

# Layer 1
id_z1 = graph_node(OP_MATMUL, id_X, id_W1, -1)
id_a1 = graph_node(OP_TANH, id_z1, -1, -1)

# Layer 2
id_z2 = graph_node(OP_MATMUL, id_a1, id_W2, -1)
id_a2 = graph_node(OP_TANH, id_z2, -1, -1)

# Layer 3 (output)
id_z3 = graph_node(OP_MATMUL, id_a2, id_W3, -1)
id_pred = graph_node(OP_SIGMOID, id_z3, -1, -1)

# Loss
id_loss = graph_node(OP_MSE, id_pred, id_Y, -1)

# Train
? "Training XOR Network..."
graph_run(5000, 0.1)

# Test
? "\nXOR Results:"
graph_forward()
predictions = graph_get_output(id_pred)

for i = 1 to 4
    x1 = tensor_get(X_train, i, 1)
    x2 = tensor_get(X_train, i, 2)
    pred = tensor_get(predictions, i, 1)
    actual = tensor_get(Y_train, i, 1)
    
    ? "Input: [" + x1 + ", " + x2 + "] -> Pred: " + pred + " (Actual: " + actual + ")"
next

graph_free()
```

---

## 4. Mini-Batch Training

Efficient training with mini-batches.

```ring
load "ringtensor.ring"

# Generate large dataset
func generateLargeDataset(n, features, classes)
    X = tensor_init(n, features)
    Y = tensor_init(n, classes)
    
    tensor_random(X, -1.0, 1.0)
    tensor_random(Y, 0.0, 1.0)
    tensor_softmax(Y)  # Normalize
    
    return [X, Y]

# Main
n_samples = 1000
n_features = 20
n_classes = 5
batch_size = 32

data = generateLargeDataset(n_samples, n_features, n_classes)
X_full = data[1]
Y_full = data[2]

# Model
W = tensor_init(n_features, n_classes)
tensor_random(W, -0.1, 0.1)

# Training loop with mini-batches
epochs = 10
learning_rate = 0.01

for epoch = 1 to epochs
    ? "Epoch " + epoch
    
    # Shuffle and batch
    for batch_start = 1 to n_samples step batch_size
        batch_end = batch_start + batch_size - 1
        if batch_end > n_samples
            batch_end = n_samples
        ok
        
        actual_batch_size = batch_end - batch_start + 1
        
        # Extract batch
        X_batch = tensor_init(actual_batch_size, n_features)
        Y_batch = tensor_init(actual_batch_size, n_classes)
        
        tensor_slice_rows(X_full, X_batch, batch_start, actual_batch_size)
        tensor_slice_rows(Y_full, Y_batch, batch_start, actual_batch_size)
        
        # Build graph for this batch
        graph_init()
        graph_set_optimizer(OPTIMIZER_ADAM)
        
        id_X = graph_node(OP_INPUT, -1, -1, -1, X_batch)
        id_Y = graph_node(OP_INPUT, -1, -1, -1, Y_batch)
        id_W = graph_node(OP_WEIGHT, -1, -1, -1, W)
        
        id_z = graph_node(OP_MATMUL, id_X, id_W, -1)
        id_pred = graph_node(OP_SOFTMAX, id_z, -1, -1)
        id_loss = graph_node(OP_CROSSENTROPY, id_pred, id_Y, -1)
        
        # Train on batch
        graph_run(1, learning_rate)
        
        graph_free()
    next
next

? "Training complete!"
```

---

## 5. Transformer Attention Block

Self-attention mechanism for sequence processing.

```ring
load "ringtensor.ring"

# Hyperparameters
batch = 4
seq_len = 16
d_model = 64
n_heads = 4
d_k = d_model / n_heads  # 16

# Input sequence
X = tensor_init(batch * seq_len, d_model)
tensor_random(X, -0.1, 0.1)

# Query, Key, Value projections
W_Q = tensor_init(d_model, d_model)
W_K = tensor_init(d_model, d_model)
W_V = tensor_init(d_model, d_model)

tensor_random(W_Q, -0.1, 0.1)
tensor_random(W_K, -0.1, 0.1)
tensor_random(W_V, -0.1, 0.1)

# Project to Q, K, V
Q = tensor_matmul(X, W_Q)
K = tensor_matmul(X, W_K)
V = tensor_matmul(X, W_V)

# Reshape for multi-head attention
tensor_reshape(Q, batch, n_heads, seq_len, d_k)
tensor_reshape(K, batch, n_heads, seq_len, d_k)
tensor_reshape(V, batch, n_heads, seq_len, d_k)

# Multi-head attention
Out = tensor_init(batch * n_heads * seq_len, d_k)
tensor_reshape(Out, batch, n_heads, seq_len, d_k)

scale = 1.0 / sqrt(d_k)

? "Computing Multi-Head Attention..."
tensor_attention_batch(Q, K, V, Out, scale, batch, seq_len, n_heads, 1)  # Causal

? "Attention computed successfully!"
? "Output shape: [" + batch + ", " + n_heads + ", " + seq_len + ", " + d_k + "]"
```

---

## 6. Image Convolution

Simple image filtering using tensor operations.

```ring
load "ringtensor.ring"

# Create a simple image (8x8)
func createImage()
    img = tensor_init(8, 8)
    
    # Create a simple pattern
    for i = 1 to 8
        for j = 1 to 8
            if i = j or i + j = 9
                tensor_set(img, i, j, 1.0)
            else
                tensor_set(img, i, j, 0.0)
            ok
        next
    next
    
    return img

# Edge detection kernel (Sobel X)
func createSobelX()
    kernel = tensor_init(3, 3)
    
    tensor_set(kernel, 1, 1, -1.0)
    tensor_set(kernel, 1, 2, 0.0)
    tensor_set(kernel, 1, 3, 1.0)
    
    tensor_set(kernel, 2, 1, -2.0)
    tensor_set(kernel, 2, 2, 0.0)
    tensor_set(kernel, 2, 3, 2.0)
    
    tensor_set(kernel, 3, 1, -1.0)
    tensor_set(kernel, 3, 2, 0.0)
    tensor_set(kernel, 3, 3, 1.0)
    
    return kernel

# Manual convolution (for demonstration)
func convolve(img, kernel)
    img_rows = tensor_get_rows(img)
    img_cols = tensor_get_cols(img)
    
    result = tensor_init(img_rows - 2, img_cols - 2)
    
    for i = 2 to img_rows - 1
        for j = 2 to img_cols - 1
            sum = 0.0
            
            for ki = 1 to 3
                for kj = 1 to 3
                    img_val = tensor_get(img, i + ki - 2, j + kj - 2)
                    kernel_val = tensor_get(kernel, ki, kj)
                    sum += img_val * kernel_val
                next
            next
            
            tensor_set(result, i - 1, j - 1, sum)
        next
    next
    
    return result

# Main
? "Creating image..."
img = createImage()

? "Creating Sobel kernel..."
kernel = createSobelX()

? "Applying convolution..."
filtered = convolve(img, kernel)

? "Convolution complete!"
? "Output size: " + tensor_get_rows(filtered) + "x" + tensor_get_cols(filtered)
```

---

## 7. Time Series Prediction

Predicting future values from historical data.

```ring
load "ringtensor.ring"

# Generate sine wave data
func generateTimeSeries(n)
    data = tensor_init(n, 1)
    
    for i = 1 to n
        val = sin((i / 10.0) * 3.14159)
        tensor_set(data, i, 1, val)
    next
    
    return data

# Create sequences (sliding window)
func createSequences(data, seq_len)
    n = tensor_get_rows(data)
    n_sequences = n - seq_len
    
    X = tensor_init(n_sequences, seq_len)
    Y = tensor_init(n_sequences, 1)
    
    for i = 1 to n_sequences
        # Input: seq_len values
        for j = 1 to seq_len
            val = tensor_get(data, i + j - 1, 1)
            tensor_set(X, i, j, val)
        next
        
        # Target: next value
        target = tensor_get(data, i + seq_len, 1)
        tensor_set(Y, i, 1, target)
    next
    
    return [X, Y]

# Main
n_points = 200
seq_len = 10

? "Generating time series..."
data = generateTimeSeries(n_points)

? "Creating sequences..."
sequences = createSequences(data, seq_len)
X_train = sequences[1]
Y_train = sequences[2]

# Simple RNN-like model
W = tensor_init(seq_len, 1)
tensor_random(W, -0.1, 0.1)

# Build graph
graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

id_X = graph_node(OP_INPUT, -1, -1, -1, X_train)
id_Y = graph_node(OP_INPUT, -1, -1, -1, Y_train)
id_W = graph_node(OP_WEIGHT, -1, -1, -1, W)

id_pred = graph_node(OP_MATMUL, id_X, id_W, -1)
id_loss = graph_node(OP_MSE, id_pred, id_Y, -1)

? "Training..."
graph_run(500, 0.01)

? "Training complete!"

graph_free()
```

---

## 8. Gradient Descent Variants

Comparing different optimization algorithms.

```ring
load "ringtensor.ring"

# Simple quadratic function: f(x) = x^2
func testOptimizer(optimizer_type, name)
    ? "\nTesting " + name + "..."
    
    # Parameter to optimize
    x = tensor_init(1, 1)
    tensor_set(x, 1, 1, 5.0)  # Start at x=5
    
    # Build graph
    graph_init()
    graph_set_optimizer(optimizer_type)
    
    id_x = graph_node(OP_WEIGHT, -1, -1, -1, x)
    
    # f(x) = x^2
    id_x_squared = graph_node(OP_SQUARE, id_x, -1, -1)
    
    # Train (minimize x^2, should converge to x=0)
    graph_run(100, 0.1)
    
    final_x = tensor_get(x, 1, 1)
    ? name + " final x: " + final_x + " (should be ~0)"
    
    graph_free()

# Main
testOptimizer(OPTIMIZER_SGD, "SGD")
testOptimizer(OPTIMIZER_ADAM, "Adam")
```

---

## 9. Custom Loss Functions

Implementing custom loss using graph operations.

```ring
load "ringtensor.ring"

# Huber Loss (robust to outliers)
func buildHuberLoss(id_pred, id_target, delta)
    # error = pred - target
    id_error = graph_node(OP_SUB, id_pred, id_target, -1)
    
    # abs_error = |error|
    id_abs_error = graph_node(OP_SQUARE, id_error, -1, -1)
    id_abs_error = graph_node(OP_SQRT, id_abs_error, -1, -1)
    
    # For simplicity, use MSE (full Huber requires conditionals)
    # In practice, you'd implement this in C
    id_loss = graph_node(OP_SQUARE, id_error, -1, -1)
    id_loss = graph_node(OP_MEAN, id_loss, -1, -1)
    
    return id_loss

# Example usage
X = tensor_init(100, 1)
Y = tensor_init(100, 1)
W = tensor_init(1, 1)

tensor_random(X, 0.0, 10.0)
tensor_random(Y, 0.0, 10.0)
tensor_random(W, -1.0, 1.0)

graph_init()
graph_set_optimizer(OPTIMIZER_ADAM)

id_X = graph_node(OP_INPUT, -1, -1, -1, X)
id_Y = graph_node(OP_INPUT, -1, -1, -1, Y)
id_W = graph_node(OP_WEIGHT, -1, -1, -1, W)

id_pred = graph_node(OP_MATMUL, id_X, id_W, -1)
id_loss = buildHuberLoss(id_pred, id_Y, 1.0)

? "Training with custom loss..."
graph_run(100, 0.01)

graph_free()
```

---

## 10. Model Persistence

Saving and loading trained models.

```ring
load "ringtensor.ring"

# Train a model
func trainModel()
    ? "Training model..."
    
    X = tensor_init(100, 10)
    Y = tensor_init(100, 3)
    W = tensor_init(10, 3)
    
    tensor_random(X, -1.0, 1.0)
    tensor_random(Y, 0.0, 1.0)
    tensor_random(W, -0.5, 0.5)
    
    graph_init()
    graph_set_optimizer(OPTIMIZER_ADAM)
    
    id_X = graph_node(OP_INPUT, -1, -1, -1, X)
    id_Y = graph_node(OP_INPUT, -1, -1, -1, Y)
    id_W = graph_node(OP_WEIGHT, -1, -1, -1, W)
    
    id_pred = graph_node(OP_MATMUL, id_X, id_W, -1)
    id_pred = graph_node(OP_SOFTMAX, id_pred, -1, -1)
    id_loss = graph_node(OP_CROSSENTROPY, id_pred, id_Y, -1)
    
    graph_run(500, 0.01)
    
    graph_free()
    
    return W

# Save model
func saveModel(W, filename)
    ? "Saving model to " + filename + "..."
    tensor_save_fp32(W, filename)  # Compressed format
    ? "Model saved!"

# Load model
func loadModel(filename)
    ? "Loading model from " + filename + "..."
    W = tensor_load_fp32(filename)
    ? "Model loaded!"
    return W

# Main
W_trained = trainModel()

# Save
saveModel(W_trained, "my_model.bin")

# Load
W_loaded = loadModel("my_model.bin")

# Verify
? "\nVerifying loaded model..."
? "Original W[1,1]: " + tensor_get(W_trained, 1, 1)
? "Loaded W[1,1]: " + tensor_get(W_loaded, 1, 1)
```

---

## 🎯 More Examples

For more examples, check:

- `extensions/ringtensor/tests/` - Core functionality tests
- `extensions/ringtensor/testGraph/` - Graph engine examples
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- [API_REFERENCE.md](API_REFERENCE.md) - Complete API documentation

---

**Happy Coding with RingTensor! 🚀**
