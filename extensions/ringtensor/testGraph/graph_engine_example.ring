/*
** Example: Simple Neural Network using Graph Engine
** 
** Network Architecture:
** Input (784) -> Dense(128) -> ReLU -> Dense(10) -> Softmax
*/

load "ringtensor.ring"

// ========== Configuration ==========
INPUT_SIZE = 784
HIDDEN_SIZE = 128
OUTPUT_SIZE = 10
BATCH_SIZE = 32
EPOCHS = 100
LEARNING_RATE = 0.01

// ========== Initialize Tensors ==========
? "Initializing tensors..."

// Input and Target
X = tensor_init(BATCH_SIZE, INPUT_SIZE)
Y = tensor_init(BATCH_SIZE, OUTPUT_SIZE)

// Layer 1: Input -> Hidden
W1 = tensor_init(INPUT_SIZE, HIDDEN_SIZE)
B1 = tensor_init(1, HIDDEN_SIZE)

// Layer 2: Hidden -> Output
W2 = tensor_init(HIDDEN_SIZE, OUTPUT_SIZE)
B2 = tensor_init(1, OUTPUT_SIZE)

// Initialize weights with random values
tensor_random(W1, -0.1, 0.1)
tensor_random(W2, -0.1, 0.1)
tensor_fill(B1, 0.0)
tensor_fill(B2, 0.0)

? "Tensors initialized!"

// ========== Build Computational Graph ==========
? "Building computational graph..."

graph_init()

// Create Input Nodes
input_id = graph_node(OP_INPUT, -1, -1, X)
target_id = graph_node(OP_INPUT, -1, -1, Y)

// Create Weight Nodes (Trainable)
w1_id = graph_node(OP_WEIGHT, -1, -1, W1)
b1_id = graph_node(OP_WEIGHT, -1, -1, B1)
w2_id = graph_node(OP_WEIGHT, -1, -1, W2)
b2_id = graph_node(OP_WEIGHT, -1, -1, B2)

// Layer 1: Z1 = X @ W1
z1_id = graph_node(OP_MATMUL, input_id, w1_id)

// Layer 1: Z1 = Z1 + B1 (Broadcasting)
z1_bias_id = graph_node(OP_ADD, z1_id, b1_id)

// Layer 1: A1 = ReLU(Z1)
a1_id = graph_node(OP_RELU, z1_bias_id, -1)

// Layer 2: Z2 = A1 @ W2
z2_id = graph_node(OP_MATMUL, a1_id, w2_id)

// Layer 2: Z2 = Z2 + B2
z2_bias_id = graph_node(OP_ADD, z2_id, b2_id)

// Output: Softmax(Z2)
output_id = graph_node(OP_SOFTMAX, z2_bias_id, -1)

// Loss: CrossEntropy(Output, Target)
loss_id = graph_node(OP_CROSSENTROPY, output_id, target_id)

? "Graph built successfully!"
? "Total nodes: " + output_id + 1

// ========== Training (Traditional Way - For Comparison) ==========
? ""
? "========== TRADITIONAL TRAINING (Ring Loop) =========="
? "Training for " + EPOCHS + " epochs..."

start_time = clock()

for epoch = 1 to EPOCHS
    // Generate dummy data (in real scenario, load from dataset)
    tensor_random(X, 0, 1)
    tensor_fill(Y, 0)
    // Set one-hot targets (simplified)
    
    // Forward Pass
    Z1 = tensor_init(BATCH_SIZE, HIDDEN_SIZE)
    tensor_matmul(X, W1, Z1)
    tensor_add_row_vec(Z1, B1)
    
    A1 = tensor_copy(Z1)
    tensor_relu(A1)
    
    Z2 = tensor_init(BATCH_SIZE, OUTPUT_SIZE)
    tensor_matmul(A1, W2, Z2)
    tensor_add_row_vec(Z2, B2)
    
    Output = tensor_copy(Z2)
    tensor_softmax(Output)
    
    // Backward Pass (Simplified - Not implemented here)
    // ...
    
    // Update Weights (SGD)
    // tensor_update_sgd(W1, dW1, LEARNING_RATE)
    // ...
    
    if epoch % 10 = 0
        ? "Epoch " + epoch + " completed"
    ok
next

end_time = clock()
traditional_time = (end_time - start_time) / clockspersecond()

? "Traditional training completed in " + traditional_time + " seconds"

// ========== Training (Graph Engine - Fast!) ==========
? ""
? "========== GRAPH ENGINE TRAINING (C Loop) =========="
? "Training for " + EPOCHS + " epochs..."

start_time = clock()

// Run entire training loop in C!
graph_run(EPOCHS, LEARNING_RATE, 5.0)

end_time = clock()
graph_time = (end_time - start_time) / clockspersecond()

? "Graph engine training completed in " + graph_time + " seconds"

// ========== Results ==========
? ""
? "========== PERFORMANCE COMPARISON =========="
? "Traditional Method: " + traditional_time + " seconds"
? "Graph Engine:       " + graph_time + " seconds"
? "Speedup:            " + traditional_time / graph_time + "x"

// ========== Get Final Output ==========
final_output = graph_get_output(output_id)
? ""
? "Final output shape: " + tensor_get_rows(final_output) + " x " + tensor_get_cols(final_output)

// ========== Cleanup ==========
graph_free()
? ""
? "Done!"
