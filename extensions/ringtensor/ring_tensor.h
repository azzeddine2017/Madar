/*
** RingTensor Extension - Header (Refactored Architecture)
** Architecture: Core/Shell Separation + Graph Engine Support
*/

#ifndef RING_TENSOR_H
#define RING_TENSOR_H

#include "ring.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>
#include <time.h> 

#ifdef _OPENMP
#include <omp.h>
#endif

#ifdef _WIN32
#define RING_EXPORT __declspec(dllexport)
#else
#define RING_EXPORT extern
#endif

/* ========================================================================== */
/* PART 1: TENSOR STRUCTURE (Unchanged)                                      */
/* ========================================================================== */

/* 
** The Tensor Structure (N-Dimensional Capable)
** We allow up to 4 Dimensions: [Batch, Heads, Rows, Cols]
** For 2D Tensors: Batch=1, Heads=1
*/
typedef struct {
    double *data;
    
    // Physical Dimensions
    int shape[4]; // [0]=Batch, [1]=Heads, [2]=Rows, [3]=Cols
    int ndim;     // Current active dimensions (2, 3, or 4)
    
    // Quick Aliases for Legacy Code (Pointing to shape[2] and shape[3])
    int rows; 
    int cols;
    
    int size;     // Total Elements
    int is_owner; // 1 if we own the data pointer (free it), 0 otherwise
} tensor_t;

/* --- Internal Attention Kernels --- */
void internal_attention_linear_causal(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale, int batch);
void internal_attention_linear_optimized(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale, int batch);
void internal_attention_linear_backward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *G, tensor_t *dQ, tensor_t *dK, tensor_t *dV, double scale, int batch);
void internal_attention_linear_global_backward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *dOut, tensor_t *dQ, tensor_t *dK, tensor_t *dV, double scale, int batch);
void internal_attention_multihead(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale, int batch, int seq, int heads, int is_causal);
void internal_attention_multihead_backward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *dOut, tensor_t *dQ, tensor_t *dK, tensor_t *dV, double scale, int batch, int seq, int heads, int is_causal);

#define RING_VM_POINTER_TENSOR "tensor_t"

/* ========================================================================== */
/* PART 2: GRAPH ENGINE DEFINITIONS                                          */
/* ========================================================================== */

/* OpCodes for Computational Graph */
enum OpCode {
    OP_NONE = 0,
    OP_INPUT,       // Placeholder (Input Data)
    OP_WEIGHT,      // Trainable Parameter
    
    // Element-Wise Math
    OP_ADD, OP_SUB, OP_TENSOR_MUL, OP_TENSOR_DIV,
    OP_SCALAR_MUL, OP_ADD_SCALAR, OP_SUB_SCALAR,
    
    // Matrix Operations
    OP_MATMUL, OP_TRANSPOSE,
    
    // Activations
    OP_RELU, OP_SIGMOID, OP_TANH, OP_GELU, OP_SOFTMAX,
    OP_RELU_PRIME, OP_SIGMOID_PRIME, OP_TANH_PRIME, OP_GELU_PRIME,
    
    // Transformations
    OP_SQUARE, OP_SQRT, OP_EXP,
    
    // Reductions
    OP_SUM, OP_MEAN, OP_ARGMAX,
    
    // Loss Functions
    OP_MSE, OP_CROSSENTROPY,
    
    // Advanced
    OP_LAYERNORM, OP_DROPOUT, OP_EMBEDDING,
    
    // New
    OP_ADD_ROW_VEC, OP_ATTENTION, OP_REPEAT_ROWS
};

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

#define RING_VM_POINTER_GRAPHNODE "GraphNode"

/* Library Entry Point */
RING_EXPORT void ringlib_init(RingState *pRingState);

/* ========================================================================== */
/* PART 3: INTERNAL KERNELS (Pure C - No Ring API Dependency)                */
/* ========================================================================== */

/* --- 3.1: Element-Wise Math Kernels --- */
void internal_add(tensor_t *A, tensor_t *B);                    // A += B (in-place)
void internal_sub(tensor_t *A, tensor_t *B);                    // A -= B (in-place)
void internal_mul_elem(tensor_t *A, tensor_t *B);                    // A *= B (element-wise, in-place)
void internal_div(tensor_t *A, tensor_t *B);                    // A /= B (in-place)
void internal_scalar_mul(tensor_t *T, double scalar);           // T *= scalar
void internal_add_scalar(tensor_t *T, double scalar);           // T += scalar
void internal_sub_scalar(tensor_t *T, double scalar);           // T -= scalar

/* --- 3.2: Matrix Operations Kernels --- */
void internal_matmul(tensor_t *A, tensor_t *B, tensor_t *C);    // C = A * B
void internal_transpose(tensor_t *A, tensor_t *R);              // R = A.T
void internal_add_row_vec(tensor_t *A, tensor_t *B);            // Broadcasting: A += B (row vector)

/* --- 3.3: Activation Kernels --- */
void internal_relu(tensor_t *T);                                // ReLU (in-place)
void internal_relu_prime(tensor_t *T);                          // ReLU derivative
void internal_sigmoid(tensor_t *T);                             // Sigmoid (in-place)
void internal_sigmoid_prime(tensor_t *T);                       // Sigmoid derivative
void internal_tanh_activation(tensor_t *T);                     // Tanh (in-place)
void internal_tanh_prime(tensor_t *T);                          // Tanh derivative
void internal_gelu(tensor_t *T);                                // GELU (in-place)
void internal_gelu_prime(tensor_t *T);                          // GELU derivative
void internal_softmax(tensor_t *T);                             // Softmax (in-place)

/* --- 3.4: Transformation Kernels --- */
void internal_square(tensor_t *T);                              // T = T^2
void internal_sqrt_tensor(tensor_t *T);                         // T = sqrt(T)
void internal_exp(tensor_t *T);                                 // T = exp(T)
void internal_fill(tensor_t *T, double value);                  // Fill with value
void internal_random(tensor_t *T, double min, double max);      // Random uniform
void internal_repeat_rows(tensor_t *Src, tensor_t *Dest, int nTimes);

/* --- 3.5: Reduction Kernels --- */
void internal_sum(tensor_t *T, int axis, tensor_t *R);          // Sum along axis
void internal_mean(tensor_t *T, int axis, tensor_t *R);         // Mean along axis
double internal_mean_global(tensor_t *T);                       // Mean of all elements
int internal_argmax(tensor_t *T);                               // Argmax (returns index)
void internal_argmax_rowwise(tensor_t *T, tensor_t *R);         // Argmax per row

/* --- 3.6: Advanced Kernels --- */
void internal_layernorm(tensor_t *X, tensor_t *G, tensor_t *B, double eps);
void internal_dropout(tensor_t *T, double rate, int training);
void internal_embedding_forward(tensor_t *Emb, tensor_t *Ind, tensor_t *Out);
void internal_embedding_backward(tensor_t *dOut, tensor_t *Ind, tensor_t *dEmb);

/* --- 3.7: Loss Kernels --- */
double internal_mse_loss(tensor_t *Pred, tensor_t *Target);
void internal_mse_backward(tensor_t *Pred, tensor_t *Target, tensor_t *Grad);
double internal_crossentropy_loss(tensor_t *Pred, tensor_t *Target);
void internal_crossentropy_backward(tensor_t *Pred, tensor_t *Target, tensor_t *Grad);

/* --- 3.8: Optimizer Kernels --- */
void internal_sgd_update(tensor_t *W, tensor_t *dW, double lr);
void internal_adam_update(tensor_t *W, tensor_t *dW, tensor_t *m, tensor_t *v, 
                          double lr, double beta1, double beta2, double eps, int t);

/* --- 3.9: Utility Kernels --- */
void internal_clip_tensor(tensor_t *T, double min_val, double max_val);
double internal_sum_squares(tensor_t *T);
void internal_clip_global_norm(tensor_t **tensors, int count, double max_norm);

/* --- 3.10: Row/Column Operations --- */
void internal_select_columns(tensor_t *Src, tensor_t *Ind, tensor_t *Dest);
void internal_insert_columns(tensor_t *Dest, tensor_t *Src, tensor_t *Ind);
void internal_slice_rows(tensor_t *Src, tensor_t *Dest, int start_row, int count);
void internal_insert_rows(tensor_t *Dest, tensor_t *Src, int start_row);
void internal_repeat_rows(tensor_t *Src, tensor_t *Dest, int repeat_count);

/* --- 3.11: Set Operations --- */
void internal_set_from_list(tensor_t *T, double *values, int count);
void internal_set_one_hot(tensor_t *T, int *indices, int count, double value);

/* --- 3.12: Attention Mechanisms --- */
void internal_attention_forward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale);
void internal_attention_causal(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale);

/* Forward Declarations for Kernels used in Graph */
void internal_layernorm_backward(tensor_t *dY, tensor_t *X, tensor_t *G, tensor_t *B, tensor_t *dX, tensor_t *dG, tensor_t *dB, double eps);
void internal_dropout_backward(tensor_t *dY, tensor_t *dX, tensor_t *Mask, double rate);
void internal_adam_update(tensor_t *W, tensor_t *dW, tensor_t *m, tensor_t *v, double lr, double beta1, double beta2, double eps, int t);


/* ========================================================================== */
/* PART 4: GRAPH ENGINE API                                                  */
/* ========================================================================== */

RING_FUNC(ring_graph_init);           // Initialize/Reset Graph
RING_FUNC(ring_graph_node);           // Create a new node: graph_node(opcode, src1, src2)
RING_FUNC(ring_graph_set_input);      // Set input data for a node
RING_FUNC(ring_graph_get_output);     // Get output from a node
RING_FUNC(ring_graph_forward);        // Run forward pass
RING_FUNC(ring_graph_backward);       // Run backward pass
RING_FUNC(ring_graph_set_optimizer);  // Set optimizer type
RING_FUNC(ring_graph_run);            // Run full training loop (epochs)
RING_FUNC(ring_graph_bind_memory);    // Bind memory to graph node
RING_FUNC(ring_graph_bind_grad);      // Bind gradient memory to graph node
RING_FUNC(ring_graph_free);           // Free graph memory

/* ========================================================================== */
/* PART 5: RING API WRAPPERS (Legacy Support)                                */
/* ========================================================================== */

/* Lifecycle */
RING_FUNC(ring_tensor_init);
RING_FUNC(ring_tensor_reshape); 
RING_FUNC(ring_tensor_copy);

RING_FUNC(ring_tensor_print_stats);
RING_FUNC(ring_tensor_get_data_ptr);
 
/* Batch Operations */
RING_FUNC(ring_tensor_matmul_batch); 

RING_FUNC(ring_tensor_set);     
RING_FUNC(ring_tensor_get);     

/* Properties */
RING_FUNC(ring_tensor_get_rows);
RING_FUNC(ring_tensor_get_cols);
RING_FUNC(ring_tensor_dot_row_vec);

/* 2. Element-Wise Math (In-Place / Parallelized) */
RING_FUNC(ring_tensor_add);
RING_FUNC(ring_tensor_sub);
RING_FUNC(ring_tensor_mul_elem);
RING_FUNC(ring_tensor_div);
RING_FUNC(ring_tensor_scalar_mul);
RING_FUNC(ring_tensor_add_scalar);
RING_FUNC(ring_tensor_sub_scalar); 

/* 3. Transformations & Activations (In-Place / Parallelized) */
RING_FUNC(ring_tensor_fill);
RING_FUNC(ring_tensor_random);
RING_FUNC(ring_tensor_square);
RING_FUNC(ring_tensor_sqrt);
RING_FUNC(ring_tensor_exp);
RING_FUNC(ring_tensor_sigmoid);
RING_FUNC(ring_tensor_sigmoid_prime);
RING_FUNC(ring_tensor_tanh);
RING_FUNC(ring_tensor_tanh_prime);
RING_FUNC(ring_tensor_relu);
RING_FUNC(ring_tensor_relu_prime);
RING_FUNC(ring_tensor_softmax);

/* 4. Matrix Operations (Heavily Optimized) */
RING_FUNC(ring_tensor_matmul);      
RING_FUNC(ring_tensor_transpose);   
RING_FUNC(ring_tensor_sum);         
RING_FUNC(ring_tensor_mean);
RING_FUNC(ring_tensor_argmax);
RING_FUNC(ring_tensor_add_row_vec); 

/* 5. NLP & Transformer Kernels (Advanced) */
RING_FUNC(ring_tensor_embedding_forward);
RING_FUNC(ring_tensor_embedding_backward);

RING_FUNC(ring_tensor_layernorm);
RING_FUNC(ring_tensor_rmsnorm);
RING_FUNC(ring_tensor_rope);
RING_FUNC(ring_tensor_silu);

RING_FUNC(ring_tensor_attention_fast);   
RING_FUNC(ring_tensor_attention_causal); 
RING_FUNC(ring_tensor_mha_backward_fast);
RING_FUNC(ring_tensor_attention_batch);

RING_FUNC(ring_tensor_select_columns);   
RING_FUNC(ring_tensor_insert_columns);   

RING_FUNC(ring_tensor_slice_rows);
RING_FUNC(ring_tensor_insert_rows);

/* 6. Optimizers (Fused Kernels) */
RING_FUNC(ring_tensor_update_sgd);
RING_FUNC(ring_tensor_update_adam);
RING_FUNC(ring_tensor_dropout);

RING_FUNC(ring_tensor_crossentropy_loss);
RING_FUNC(ring_tensor_crossentropy_backward);

/* 7. Utilities */
RING_FUNC(ring_tensor_get_cores);
RING_FUNC(ring_tensor_set_threads);
RING_FUNC(ring_tensor_set_gpu_threshold);
RING_FUNC(ring_tensor_set_arena_size);


RING_FUNC(ring_tensor_set_from_list);
RING_FUNC(ring_tensor_set_one_hot);

/* Persistence (Binary & Quantized) */
RING_FUNC(ring_tensor_save);
RING_FUNC(ring_tensor_load);
RING_FUNC(ring_tensor_save_fp32);
RING_FUNC(ring_tensor_load_fp32);
RING_FUNC(ring_tensor_load_inplace);
RING_FUNC(ring_tensor_load_fp32_inplace);

RING_FUNC(ring_tensor_clip_global_norm);
RING_FUNC(ring_tensor_clip_tensor);

RING_FUNC(ring_tensor_gelu);
RING_FUNC(ring_tensor_gelu_prime);

RING_FUNC(ring_tensor_sum_squares);
RING_FUNC(ring_tensor_repeat_rows);
RING_FUNC(ring_tensor_from_memory);

RING_FUNC(ring_tensor_attention_linear_causal);
RING_FUNC(ring_tensor_attention_linear_optimized);
RING_FUNC(ring_tensor_attention_linear_backward);
RING_FUNC(ring_tensor_attention_linear_global_backward);

RING_FUNC(ring_tensor_attention_multihead);
RING_FUNC(ring_tensor_attention_multihead_backward);

RING_FUNC(ring_tensor_set_one_hot_ptr);
RING_FUNC(ring_graph_run_buffered);

RING_FUNC(ring_tensor_to_list);

#endif