/*
** RingTensor Extension Implementation
** Optimized for Dual-Core / Hyper-threaded CPUs
** Fixed for MSVC C3015 Error & High Overhead
*/

#include "ring_tensor.h"

#include <stdio.h>

/* ====================================================================
** AVX2 SIMD Intrinsics (Upgrade 2)
** Provides _mm256_*_pd functions to process 4 doubles per clock cycle.
** Broadwell i3-5005U supports AVX2 natively.
** ==================================================================== */
#ifdef __AVX2__
#include <immintrin.h>
#endif

/* ====================================================================
** Memory Arena / Pool (Upgrade 3)
** Pre-allocated contiguous block to eliminate per-tensor calloc overhead
** during graph forward/backward passes.
** Pool Size: 256MB (sufficient for most training workloads on 8GB RAM)
** ==================================================================== */
static size_t ARENA_SIZE  = (512 * 1024 * 1024); /* Default: 512 MB */

static char   *arena_memory  = NULL;    /* Base pointer to the arena block   */
static size_t  arena_offset  = 0;       /* Current allocation offset (bump)  */
static int     arena_active  = 0;       /* 1 when graph owns the arena       */
/* ==================================================================== */
/* --- GPU ACCELERATION (OpenCL) -------------------------------------- */
/* ==================================================================== */

// Uncomment this line to enable GPU, or define it in compiler flags
#define USE_OPENCL 1 

#ifdef USE_OPENCL
#include "opencl_stub.h"

// Default threshold: 5 Million operations
// If matrix ops > this, use GPU. Else use CPU.
static long long GPU_THRESHOLD = 5000000;

static cl_context       clContext = NULL;
static cl_command_queue clQueue   = NULL;
static cl_kernel        clMatMulKernel = NULL;
static cl_kernel        clTransposeKernel = NULL; 
static cl_kernel        clGeluKernel = NULL; 
static int              gpu_ready = 0;

// OpenCL Kernels (Float32) - Corrected & Formatted
const char *clSource = 
// 1. MatMul Kernel
"__kernel void matmul(__global const float* A, __global const float* B, __global float* C, int M, int K, int N) {\n"
"   int row = get_global_id(0);\n"
"   int col = get_global_id(1);\n"
"   if(row < M && col < N) {\n"
"       float sum = 0.0f;\n"
"       for(int k=0; k<K; k++) {\n"
"           sum += A[row*K + k] * B[k*N + col];\n"
"       }\n"
"       C[row*N + col] = sum;\n"
"   }\n"
"}\n"

// 2. Transpose Kernel
"__kernel void transpose(__global const float* A, __global float* B, int Rows, int Cols) {\n"
"   int r = get_global_id(0);\n"
"   int c = get_global_id(1);\n"
"   if(r < Rows && c < Cols) {\n"
"       // Output(c, r) = Input(r, c)\n"
"       B[c * Rows + r] = A[r * Cols + c];\n"
"   }\n"
"}\n"

// 3. GELU Kernel
"__kernel void gelu(__global float* A, int Size) {\n"
"   int i = get_global_id(0);\n"
"   if(i < Size) {\n"
"       float x = A[i];\n"
"       float cube = x * x * x;\n"
"       float inner = 0.7978845608f * (x + 0.044715f * cube);\n"
"       A[i] = 0.5f * x * (1.0f + tanh(inner));\n"
"   }\n"
"}\n"
"__kernel void sat_anneal(__global float* Field, __global float* Momentum, __global const float* Clauses, __global float* Weights, int nVars, int nClauses, int lits_per_clause, int nPasses, float fLR, float fMomDecay) {\n"
"   int d = get_global_id(0);\n"
"   int nDims = get_global_size(0);\n"
"\n"
"   for(int pass=0; pass < nPasses; pass++) {\n"
"       float curLR = fLR * (1.0f - ((float)pass / (float)nPasses));\n"
"       for(int c=0; c < nClauses; c++) {\n"
"           float maxVal = -9999.0f;\n"
"           for(int k=0; k < lits_per_clause; k++) {\n"
"               int lit = (int)Clauses[c * lits_per_clause + k];\n"
"               if(lit == 0) break;\n"
"               int varIdx = abs(lit) - 1;\n"
"               float v = Field[varIdx * nDims + d];\n"
"               if(lit < 0) v = -v;\n"
"               if(v > maxVal) maxVal = v;\n"
"           }\n"
"           \n"
"           if(maxVal < 1.0f) {\n"
"               // 🚀 THE TSUNAMI ACCUMULATION: If clause is unsatisfied, increase its frustration weight\n"
"               float w = Weights[c * nDims + d];\n"
"               w += 0.1f;\n" // Aggressive accumulation
"               Weights[c * nDims + d] = w;\n"
"               \n"
"               float push = (1.0f - maxVal) * curLR * w;\n"
"               for(int k=0; k < lits_per_clause; k++) {\n"
"                   int lit = (int)Clauses[c * lits_per_clause + k];\n"
"                   if(lit == 0) break;\n"
"                   int varIdx = abs(lit) - 1;\n"
"                   float sign = (lit < 0) ? -1.0f : 1.0f;\n"
"                   float force = push * sign;\n"
"                   float m = Momentum[varIdx * nDims + d] * fMomDecay + force;\n"
"                   Momentum[varIdx * nDims + d] = m;\n"
"                   Field[varIdx * nDims + d] += m;\n"
"               }\n"
"           } else {\n"
"               // Optional: Slowly forget frustration if currently satisfied\n"
"               Weights[c * nDims + d] *= 0.999f;\n"
"           }\n"
"       }\n"
"       \n"
"       if ((pass % 100) == 0) {\n"
"           for(int v=0; v < nVars; v++) {\n"
"               Field[v * nDims + d] *= 0.99f;\n"
"           }\n"
"       }\n"
"   }\n"
"}\n";

static cl_kernel clSatKernel = NULL;

void init_opencl() {
    //printf("\n[GPU] Attempting to initialize OpenCL...\n");

    cl_platform_id platform_id = NULL;
    cl_device_id device_id = NULL;
    cl_uint ret_num_devices;
    cl_uint ret_num_platforms;
    cl_int ret;

    // 1. Get Platform
    ret = clGetPlatformIDs(1, &platform_id, &ret_num_platforms);
    if (ret != CL_SUCCESS) {
        printf("[GPU] Error: Could not get Platform ID. Error Code: %d\n", ret);
        return;
    }
    //printf("[GPU] Platform Found.\n");

    // 2. Get Device (Try GPU first)
    ret = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_GPU, 1, &device_id, &ret_num_devices);
    if (ret != CL_SUCCESS) {
         printf("[GPU] Warning: No GPU Device found. Trying CPU...\n");
         ret = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_CPU, 1, &device_id, &ret_num_devices);
    }
    
    if (ret != CL_SUCCESS) {
        printf("[GPU] Error: No OpenCL Device found at all. Error Code: %d\n", ret);
        return; 
    }

    // Print Device Name
    char devName[128];
    clGetDeviceInfo(device_id, CL_DEVICE_NAME, 128, devName, NULL);
    printf("[GPU] Device Found: %s\n", devName);

    // 3. Create Context
    clContext = clCreateContext(NULL, 1, &device_id, NULL, NULL, &ret);
    if (ret != CL_SUCCESS) {
        printf("[GPU] Error: Create Context Failed. Error Code: %d\n", ret);
        return;
    }

    // 4. Create Queue
    // OpenCL 2.0 deprecated clCreateCommandQueue, but we use it for compatibility.
    // If it fails, try clCreateCommandQueueWithProperties (if available in header)
    clQueue = clCreateCommandQueue(clContext, device_id, 0, &ret);
    if (ret != CL_SUCCESS) {
        printf("[GPU] Error: Create Command Queue Failed. Error Code: %d\n", ret);
        return;
    }

    // 5. Build Kernel (The Critical Part)
    cl_program program = clCreateProgramWithSource(clContext, 1, (const char **)&clSource, NULL, &ret);
    ret = clBuildProgram(program, 1, &device_id, NULL, NULL, NULL);
    
    if (ret != CL_SUCCESS) {
        printf("[GPU] Error: Kernel Compilation Failed! Error Code: %d\n", ret);
        
        // Get Build Log to see WHY
        size_t len;
        clGetProgramBuildInfo(program, device_id, CL_PROGRAM_BUILD_LOG, 0, NULL, &len);
        char *buffer = (char *)malloc(len);
        clGetProgramBuildInfo(program, device_id, CL_PROGRAM_BUILD_LOG, len, buffer, NULL);
        printf("[GPU] Build Log:\n%s\n", buffer);
        free(buffer);
        
        return;
    }
    
    clMatMulKernel = clCreateKernel(program, "matmul", &ret);
    if (ret != CL_SUCCESS) {
        printf("[GPU] Error: Create Kernel Failed.\n");
        return;
    }

    clTransposeKernel = clCreateKernel(program, "transpose", &ret);
    if (ret != CL_SUCCESS) printf("[GPU] Error creating Transpose kernel\n");

    clGeluKernel = clCreateKernel(program, "gelu", &ret);
    if (ret != CL_SUCCESS) printf("[GPU] Error creating GELU kernel\n");

    clSatKernel = clCreateKernel(program, "sat_anneal", &ret);
    if (ret != CL_SUCCESS) printf("[GPU] Error creating SAT kernel\n");

    gpu_ready = 1;
    printf("[RingTensor] GPU Acceleration Enabled.\n");
}

/* ====================================================================
** Upgrade 1: OpenCL Zero-Copy MatMul for Integrated GPUs
** ====================================================================
** BEFORE: CL_MEM_COPY_HOST_PTR — OpenCL allocates a SEPARATE device
**         buffer and deep-copies from the host buffer into it.
**         On iGPU (shared RAM), this is a pointless memcpy within the
**         same physical memory. 3x alloc + 3x deep copy = bottleneck.
**
** AFTER:  CL_MEM_USE_HOST_PTR — OpenCL uses the host buffer DIRECTLY.
**         On Intel HD 5500 (iGPU sharing DDR3L with CPU), the driver
**         recognizes it's the same physical RAM and avoids any copy.
**         The GPU kernel reads/writes the host pointer in-place.
**
** We still need host-side malloc for the double→float conversion
** (can't avoid that — tensors are double, GPU works in float).
** But the key change is: NO device-side allocation, NO deep copy.
** ==================================================================== */
int gpu_matmul(tensor_t *A, tensor_t *B, tensor_t *C) {
    if (!gpu_ready) return 0;

    int M = A->rows;
    int K = A->cols; 
    int N = B->cols;
    
    size_t num_elements_A = (size_t)A->size;
    size_t num_elements_B = (size_t)B->size;
    size_t num_elements_C = (size_t)C->size;
    
    size_t szA_bytes = num_elements_A * sizeof(float);
    size_t szB_bytes = num_elements_B * sizeof(float);
    size_t szC_bytes = num_elements_C * sizeof(float);
    
    cl_int ret;
    int i; 
    int limit; 

    /* Step 1: Allocate host-side float buffers for double→float conversion.
    ** These are the ONLY mallocs — they hold the converted float data. */
    float *fA = (float *)malloc(szA_bytes);
    float *fB = (float *)malloc(szB_bytes);
    float *fC = (float *)malloc(szC_bytes);
    
    if (!fA || !fB || !fC) {
        if(fA) free(fA); if(fB) free(fB); if(fC) free(fC);
        return 0;
    }

    /* Step 2: Convert Double → Float into host buffers */
    limit = (int)num_elements_A;
    #pragma omp parallel for private(i)
    for(i=0; i<limit; i++) fA[i] = (float)A->data[i];
    
    limit = (int)num_elements_B;
    #pragma omp parallel for private(i)
    for(i=0; i<limit; i++) fB[i] = (float)B->data[i];

    /* Step 3: Create CL buffers with CL_MEM_USE_HOST_PTR.
    ** This tells OpenCL: "Don't allocate device memory. Use THIS pointer."
    ** On iGPU (shared RAM), the GPU accesses fA/fB/fC directly — zero copy.
    ** On discrete GPU, the driver would still need to transfer, but on
    ** Intel HD 5500 it's the same physical DDR3L — true zero copy. */
    cl_mem bufA = clCreateBuffer(clContext, CL_MEM_READ_ONLY  | CL_MEM_USE_HOST_PTR, szA_bytes, fA, &ret);
    if (ret != CL_SUCCESS) { free(fA); free(fB); free(fC); return 0; }
    
    cl_mem bufB = clCreateBuffer(clContext, CL_MEM_READ_ONLY  | CL_MEM_USE_HOST_PTR, szB_bytes, fB, &ret);
    if (ret != CL_SUCCESS) { clReleaseMemObject(bufA); free(fA); free(fB); free(fC); return 0; }
    
    cl_mem bufC = clCreateBuffer(clContext, CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR, szC_bytes, fC, &ret);
    if (ret != CL_SUCCESS) { clReleaseMemObject(bufA); clReleaseMemObject(bufB); free(fA); free(fB); free(fC); return 0; }

    /* Step 4: Set kernel args and execute — standard path */
    clSetKernelArg(clMatMulKernel, 0, sizeof(cl_mem), (void *)&bufA);
    clSetKernelArg(clMatMulKernel, 1, sizeof(cl_mem), (void *)&bufB);
    clSetKernelArg(clMatMulKernel, 2, sizeof(cl_mem), (void *)&bufC);
    clSetKernelArg(clMatMulKernel, 3, sizeof(int), &M);
    clSetKernelArg(clMatMulKernel, 4, sizeof(int), &K);
    clSetKernelArg(clMatMulKernel, 5, sizeof(int), &N);

    size_t global_item_size[2] = { (size_t)M, (size_t)N };
    ret = clEnqueueNDRangeKernel(clQueue, clMatMulKernel, 2, NULL, global_item_size, NULL, 0, NULL, NULL);

    /* Step 5: Read results back. With CL_MEM_USE_HOST_PTR on iGPU,
    ** this is essentially a synchronization barrier — the data is
    ** already in fC (same physical memory), but we need the blocking
    ** read to ensure the kernel has completed before we access fC. */
    if (ret == CL_SUCCESS) {
        ret = clEnqueueReadBuffer(clQueue, bufC, CL_TRUE, 0, szC_bytes, fC, 0, NULL, NULL);
    }

    /* Step 6: Convert Float → Double */
    if (ret == CL_SUCCESS) {
        limit = (int)num_elements_C;
        #pragma omp parallel for private(i)
        for(i=0; i<limit; i++) C->data[i] = (double)fC[i];
    }

    /* Step 7: Cleanup */
    clReleaseMemObject(bufA); clReleaseMemObject(bufB); clReleaseMemObject(bufC);
    free(fA); free(fB); free(fC);
    
    return (ret == CL_SUCCESS);
}

int gpu_transpose(tensor_t *A, tensor_t *C) {
    if (!gpu_ready) return 0;
    
    int Rows = A->rows;
    int Cols = A->cols;
    size_t num_elements = (size_t)A->size;
    size_t sz_bytes = num_elements * sizeof(float);
    cl_int ret;
    int i, limit; 

    float *fA = (float *)malloc(sz_bytes);
    if (!fA) return 0;
    
    limit = (int)num_elements;
    #pragma omp parallel for private(i)
    for(i=0; i<limit; i++) fA[i] = (float)A->data[i];

    cl_mem bufA = clCreateBuffer(clContext, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, sz_bytes, fA, &ret);
    cl_mem bufC = clCreateBuffer(clContext, CL_MEM_WRITE_ONLY, sz_bytes, NULL, &ret);

    if (ret != CL_SUCCESS) { free(fA); return 0; }

    clSetKernelArg(clTransposeKernel, 0, sizeof(cl_mem), (void *)&bufA);
    clSetKernelArg(clTransposeKernel, 1, sizeof(cl_mem), (void *)&bufC);
    clSetKernelArg(clTransposeKernel, 2, sizeof(int), &Rows);
    clSetKernelArg(clTransposeKernel, 3, sizeof(int), &Cols);

    size_t global_item_size[2] = { (size_t)Rows, (size_t)Cols };
    ret = clEnqueueNDRangeKernel(clQueue, clTransposeKernel, 2, NULL, global_item_size, NULL, 0, NULL, NULL);

    float *fC = (float *)malloc(sz_bytes);
    if (ret == CL_SUCCESS && fC) {
        ret = clEnqueueReadBuffer(clQueue, bufC, CL_TRUE, 0, sz_bytes, fC, 0, NULL, NULL);
        if (ret == CL_SUCCESS) {
            limit = (int)num_elements;
            #pragma omp parallel for private(i)
            for(i=0; i<limit; i++) C->data[i] = (double)fC[i];
        }
    }

    clReleaseMemObject(bufA); clReleaseMemObject(bufC);
    free(fA); if (fC) free(fC);

    return (ret == CL_SUCCESS);
}

int gpu_gelu(tensor_t *T) {
    if (!gpu_ready) return 0;
    
    size_t num_elements = (size_t)T->size;
    size_t sz_bytes = num_elements * sizeof(float);
    cl_int ret;
    int i, limit;

    float *fT = (float *)malloc(sz_bytes);
    if (!fT) return 0;
    
    limit = (int)num_elements;
    #pragma omp parallel for private(i)
    for(i=0; i<limit; i++) fT[i] = (float)T->data[i];

    cl_mem bufT = clCreateBuffer(clContext, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR, sz_bytes, fT, &ret);
    if (ret != CL_SUCCESS) { free(fT); return 0; }

    int Size = (int)num_elements;
    clSetKernelArg(clGeluKernel, 0, sizeof(cl_mem), (void *)&bufT);
    clSetKernelArg(clGeluKernel, 1, sizeof(int), &Size);
    
    size_t global_size = num_elements;
    ret = clEnqueueNDRangeKernel(clQueue, clGeluKernel, 1, NULL, &global_size, NULL, 0, NULL, NULL);

    if (ret == CL_SUCCESS) {
        ret = clEnqueueReadBuffer(clQueue, bufT, CL_TRUE, 0, sz_bytes, fT, 0, NULL, NULL);
        if (ret == CL_SUCCESS) {
            limit = (int)num_elements;
            #pragma omp parallel for private(i)
            for(i=0; i<limit; i++) T->data[i] = (double)fT[i];
        }
    }

    clReleaseMemObject(bufT);
    free(fT);
    return (ret == CL_SUCCESS);
}

#endif

/* 
** Cache Block Size
** 32 doubles * 8 bytes = 256 bytes (Fits easily in L1 Cache) 
*/
#define TILE_SIZE 32

/* 
** TUNING:
** Threshold raised to 10,000 to prevent overhead on small matrices.
** On i3-5005U, small tasks are faster in serial mode.
*/
#define PARALLEL_THRESHOLD 50000

/* ========================================================================== */
/* GRAPH STATE                                                                */
/* ========================================================================== */

#define MAX_NODES 2048

static GraphNode* GRAPH[MAX_NODES];
static int GRAPH_SIZE = 0;
static int GRAPH_OPTIMIZER = 0; // 0: SGD, 1: ADAM

/* ========================================================================== */
/* HELPER FUNCTIONS                                                           */
/* ========================================================================== */

/* ====================================================================
** Upgrade 3: Memory Arena / Pool Allocator
** ====================================================================
** BEFORE: ensure_tensor_memory called calloc() for EVERY intermediate
**         tensor during forward/backward pass. On a 10-layer network
**         with 100 epochs, that's ~2000 calloc+free cycles per epoch.
**         Each calloc involves an OS kernel call (expensive on Windows).
**
** AFTER:  A single 256MB block is allocated once in ring_graph_init.
**         ensure_tensor_memory returns a pointer from this block via a
**         simple offset bump — O(1), no syscall, no fragmentation.
**         The arena resets (offset=0) when the graph is freed.
**
** arena_alloc(): Thread-safe bump allocator with 64-byte alignment
** (matches cache line size on Broadwell to prevent false sharing).
** ==================================================================== */
static void* arena_alloc(size_t bytes) {
    /* Align to 64-byte boundary (L1 cache line on Broadwell) */
    size_t aligned = (bytes + 63) & ~((size_t)63);
    
    if (!arena_active || !arena_memory) {
        /* Fallback: arena not initialized (standalone tensor usage) */
        return calloc(1, bytes);
    }
    
    if (arena_offset + aligned > ARENA_SIZE) {
        /* Arena exhausted — fall back to system allocator.
        ** This should rarely happen; increase ARENA_SIZE if it does. */
        printf("[RingTensor] WARNING: Arena exhausted (%zu / %zu bytes). Falling back to malloc.\n",
               arena_offset + aligned, ARENA_SIZE);
        return calloc(1, bytes);
    }
    
    void *ptr = arena_memory + arena_offset;
    arena_offset += aligned;
    
    /* Zero the allocation (matches calloc behavior) */
    memset(ptr, 0, bytes);
    return ptr;
}

/* Allocate memory for the Tensor if it doesn't already exist.
** Upgrade 3: Uses arena pool when graph is active, calloc otherwise. */
static void ensure_tensor_memory(tensor_t **t, int rows, int cols) {
    if (*t == NULL) {
        /* The struct itself is always heap-allocated (small, ~80 bytes) */
        *t = (tensor_t*)malloc(sizeof(tensor_t));
        (*t)->rows = rows;
        (*t)->cols = cols;
        (*t)->size = rows * cols;
        (*t)->ndim = 2;
        (*t)->shape[0] = 1;
        (*t)->shape[1] = 1;
        (*t)->shape[2] = rows;
        (*t)->shape[3] = cols;
        
        /* Data buffer: served from arena pool during graph execution,
        ** or from system allocator for standalone tensor operations. */
        if (arena_active) {
            (*t)->data = (double*)arena_alloc((size_t)rows * cols * sizeof(double));
            (*t)->is_owner = 0;  /* Arena owns this memory, not the tensor */
        } else {
            (*t)->data = (double*)calloc(rows * cols, sizeof(double));
            (*t)->is_owner = 1;
        }
    }
}

static void ensure_temp_memory(tensor_t **t, int rows, int cols) {
    if (*t == NULL) {
        *t = (tensor_t*)malloc(sizeof(tensor_t));
        (*t)->rows = rows;
        (*t)->cols = cols;
        (*t)->size = rows * cols;
        (*t)->ndim = 2;
        (*t)->shape[0] = 1; (*t)->shape[1] = 1;
        (*t)->shape[2] = rows; (*t)->shape[3] = cols;
        (*t)->data = (double*)calloc(rows * cols, sizeof(double));
        (*t)->is_owner = 1;
    }
}

static void copy_tensor(tensor_t *src, tensor_t *dst) {
    int i;
    if (dst->size != src->size) return;
    
    #pragma omp parallel for if(src->size > 50000)
    for(i=0; i<src->size; i++) {
        dst->data[i] = src->data[i];
    }
}

/*Gradient Accumulation
static void accumulate_grad(GraphNode *node, tensor_t *grad_to_add) {
    if (!node) return;
    ensure_tensor_memory(&node->grad, grad_to_add->rows, grad_to_add->cols);
    internal_add(node->grad, grad_to_add);
}
 */
/* --- Memory Management --- */
void ring_tensor_free(void *pState, void *pPointer) {
    tensor_t *t = (tensor_t *)pPointer;
    if (t != NULL) {
        if (t->is_owner && t->data != NULL) free(t->data);
        free(t);
    }
}

/*
** Destructor for Borrowed Memory
** Frees the struct ONLY, not the data (owned by AlQalam/C++)
*/
void ring_tensor_free_struct_only(void *pState, void *pPointer) {
    tensor_t *t = (tensor_t *)pPointer;
    if (t != NULL) {
        // DO NOT FREE t->data!
        free(t);
    }
}

/* ==================================================================== */
/* --- 1. LIFECYCLE --------------------------------------------------- */
/* ==================================================================== */

RING_FUNC(ring_tensor_init) {
    int rows, cols;
    tensor_t *t;

    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }

    rows = (int)RING_API_GETNUMBER(1);
    cols = (int)RING_API_GETNUMBER(2);
    
    if (rows <= 0 || cols <= 0) { RING_API_ERROR("Invalid Dims"); return; }

    t = (tensor_t *)malloc(sizeof(tensor_t));
    if(!t) { RING_API_ERROR("Malloc Fail"); return; }
    
    // Default to 2D
    t->ndim = 2;
    t->shape[0] = 1; // Batch
    t->shape[1] = 1; // Heads
    t->shape[2] = rows;
    t->shape[3] = cols;
    
    // Legacy Aliases
    t->rows = rows;
    t->cols = cols;
    t->size = rows * cols;
    t->is_owner = 1;
    
    t->data = (double *)calloc(t->size, sizeof(double));
    if (!t->data) { free(t); RING_API_ERROR("Malloc Data Fail"); return; }
    
    RING_API_RETMANAGEDCPOINTER(t, RING_VM_POINTER_TENSOR, ring_tensor_free);
}

/*
** Reshape Tensor
** Usage: tensor_reshape(pTensor, Batch, Heads, Rows, Cols)
** Pass 1 for unused dimensions. Product must equal total size.
*/
RING_FUNC(ring_tensor_reshape) {
    tensor_t *t;
    int b, h, r, c;
    int new_size;

    if (RING_API_PARACOUNT != 5) {
        RING_API_ERROR("Reshape requires 4 dims (Batch, Heads, Rows, Cols). Use 1 for unused.");
        return;
    }

    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    b = (int)RING_API_GETNUMBER(2);
    h = (int)RING_API_GETNUMBER(3);
    r = (int)RING_API_GETNUMBER(4);
    c = (int)RING_API_GETNUMBER(5);
    
    new_size = b * h * r * c;
    
    if (new_size != t->size) {
        RING_API_ERROR("Reshape Error: Total size cannot change.");
        return;
    }
    
    // Update Logical Shape
    t->shape[0] = b;
    t->shape[1] = h;
    t->shape[2] = r;
    t->shape[3] = c;
    
    // Determine ndim for internal logic
    if (b > 1) t->ndim = (h > 1) ? 4 : 3;
    else t->ndim = 2;
    
    // Update legacy aliases (Always points to last two dims)
    t->rows = r;
    t->cols = c;
}

/*
** Copy Tensor (Deep Copy)
** Creates a new independent tensor with the same data and shape.
** Optimization: Uses memcpy for maximum throughput.
*/
RING_FUNC(ring_tensor_copy) {
    tensor_t *Src, *Dest;
    size_t bytes;
    int i;

    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }

    Src = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);

    // 1. Allocate Struct
    Dest = (tensor_t *)malloc(sizeof(tensor_t));
    if (!Dest) {
        RING_API_ERROR("Malloc Failed (Struct)");
        return;
    }

    // 2. Copy Metadata (Dimensions)
    Dest->rows = Src->rows;
    Dest->cols = Src->cols;
    Dest->size = Src->size;
    Dest->ndim = Src->ndim;
    
    Dest->is_owner = 1;
    for(i=0; i<4; i++) Dest->shape[i] = Src->shape[i];

    // 3. Allocate Data
    Dest->data = (double *)malloc(Dest->size * sizeof(double));
    if (!Dest->data) {
        free(Dest);
        RING_API_ERROR("Malloc Failed (Data)");
        return;
    }

    // 4. Copy Data (Memcpy is highly optimized by CPU)
    bytes = Dest->size * sizeof(double);
    memcpy(Dest->data, Src->data, bytes);

    // 5. Return Managed Pointer
    RING_API_RETMANAGEDCPOINTER(Dest, RING_VM_POINTER_TENSOR, ring_tensor_free);
}

/*
** Batch Matrix Multiplication (3D)
** A: (Batch, RowsA, ColsA)
** B: (Batch, RowsB, ColsB) -> ColsA must equal RowsB
** C: (Batch, RowsA, ColsB)
*/
RING_FUNC(ring_tensor_matmul_batch) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *C = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    
    int batch = A->shape[0];
    int rA = A->rows; int cA = A->cols; int cB = B->cols;
    int strideA = rA * cA; int strideB = cA * cB; int strideC = rA * cB;
    
    int b_idx, i, j, k, ii, jj, kk;
    int i_max, j_max, k_max;
    double *ptrA, *ptrB, *ptrC, *rowC, *rowA;

    if (B->shape[0] != batch) { RING_API_ERROR("BMM Mismatch"); return; }

    // Parallelize Batches
    #pragma omp parallel for private(b_idx, ptrA, ptrB, ptrC, i, j, k, ii, jj, kk, i_max, j_max, k_max, rowC, rowA)
    for (b_idx = 0; b_idx < batch; b_idx++) {
        
        ptrA = &A->data[b_idx * strideA];
        ptrB = &B->data[b_idx * strideB];
        ptrC = &C->data[b_idx * strideC];
        
        // Zero out Batch C
        memset(ptrC, 0, strideC * sizeof(double));
        
        // Tiled MatMul for this Batch
        for (ii = 0; ii < rA; ii += TILE_SIZE) {
            i_max = (ii + TILE_SIZE > rA) ? rA : ii + TILE_SIZE;

            for (kk = 0; kk < cA; kk += TILE_SIZE) {
                k_max = (kk + TILE_SIZE > cA) ? cA : kk + TILE_SIZE;

                for (jj = 0; jj < cB; jj += TILE_SIZE) {
                    j_max = (jj + TILE_SIZE > cB) ? cB : jj + TILE_SIZE;

                    for (i = ii; i < i_max; i++) {
                        rowC = &ptrC[i * cB];
                        rowA = &ptrA[i * cA];
                        
                        for (k = kk; k < k_max; k++) {
                            double valA = rowA[k];
                            if (valA == 0.0) continue;
                            
                            double *rowB = &ptrB[k * cB];
                            for (j = jj; j < j_max; j++) {
                                rowC[j] += valA * rowB[j];
                            }
                        }
                    }
                }
            }
        }
    }
}

RING_FUNC(ring_tensor_set) {
    tensor_t *t;
    int r, c;
    double val;

    if (RING_API_PARACOUNT != 4) return;
    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    r = (int)RING_API_GETNUMBER(2);
    c = (int)RING_API_GETNUMBER(3);
    val = RING_API_GETNUMBER(4);
    
    // Bounds check
    if (r < 1 || r > t->rows || c < 1 || c > t->cols) return;
    t->data[(r-1) * t->cols + (c-1)] = val;
}

RING_FUNC(ring_tensor_get) {
    tensor_t *t;
    int r, c;

    if (RING_API_PARACOUNT != 3) return;
    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    r = (int)RING_API_GETNUMBER(2);
    c = (int)RING_API_GETNUMBER(3);
    
    if (r < 1 || r > t->rows || c < 1 || c > t->cols) {
        RING_API_RETNUMBER(0.0);
        return;
    }
    RING_API_RETNUMBER(t->data[(r-1) * t->cols + (c-1)]);
}

/* ==================================================================== */
/* --- 2. ELEMENT-WISE MATH (OPTIMIZED) ------------------------------- */
/* ==================================================================== */

/* ====================================================================
** Upgrade 2: AVX2 SIMD Intrinsics for Element-Wise Math
** ====================================================================
** BEFORE: Scalar loop processing 1 double per cycle.
** AFTER:  _mm256_*_pd processes 4 doubles per cycle (256-bit registers).
**
** Broadwell i3-5005U has full AVX2 support with 2x 256-bit FMA units.
** Combined with OpenMP, this gives us: 4 (SIMD) × 4 (threads via HT) = 16x
** theoretical throughput for element-wise ops.
**
** Tail Handling: When size % 4 != 0, the remaining 1-3 elements are
** processed with standard scalar operations (safe, no buffer overread).
** ==================================================================== */

void internal_add(tensor_t *A, tensor_t *B) {
    int i;
    int size = A->size;
#ifdef __AVX2__
    int simd_end = size - (size % 4);  /* Process in chunks of 4 doubles */
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<simd_end; i+=4) {
        __m256d va = _mm256_loadu_pd(&A->data[i]);
        __m256d vb = _mm256_loadu_pd(&B->data[i]);
        _mm256_storeu_pd(&A->data[i], _mm256_add_pd(va, vb));
    }
    /* Scalar tail: handle remaining elements */
    for(i=simd_end; i<size; i++) A->data[i] += B->data[i];
#else
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) A->data[i] += B->data[i];
#endif
}

void internal_sub(tensor_t *A, tensor_t *B) {
    int i;
    int size = A->size;
#ifdef __AVX2__
    int simd_end = size - (size % 4);
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<simd_end; i+=4) {
        __m256d va = _mm256_loadu_pd(&A->data[i]);
        __m256d vb = _mm256_loadu_pd(&B->data[i]);
        _mm256_storeu_pd(&A->data[i], _mm256_sub_pd(va, vb));
    }
    for(i=simd_end; i<size; i++) A->data[i] -= B->data[i];
#else
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) A->data[i] -= B->data[i];
#endif
}

void internal_mul_elem(tensor_t *A, tensor_t *B) {
    int i;
    int size = A->size;
#ifdef __AVX2__
    int simd_end = size - (size % 4);
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<simd_end; i+=4) {
        __m256d va = _mm256_loadu_pd(&A->data[i]);
        __m256d vb = _mm256_loadu_pd(&B->data[i]);
        _mm256_storeu_pd(&A->data[i], _mm256_mul_pd(va, vb));
    }
    for(i=simd_end; i<size; i++) A->data[i] *= B->data[i];
#else
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) A->data[i] *= B->data[i];
#endif
}

void internal_div(tensor_t *A, tensor_t *B) {
    int i;
    /* Division keeps scalar path due to zero-check branching.
    ** AVX2 division with masking is possible but not worth the
    ** complexity for a rarely-bottlenecked operation. */
    #pragma omp parallel for if(A->size > PARALLEL_THRESHOLD)
    for(i=0; i<A->size; i++) {
        A->data[i] = (B->data[i] != 0) ? A->data[i] / B->data[i] : 0.0;
    }
}

void internal_scalar_mul(tensor_t *T, double scalar) {
    int i;
    int size = T->size;
#ifdef __AVX2__
    /* Broadcast scalar to all 4 lanes of the 256-bit register */
    __m256d vs = _mm256_set1_pd(scalar);
    int simd_end = size - (size % 4);
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<simd_end; i+=4) {
        __m256d vt = _mm256_loadu_pd(&T->data[i]);
        _mm256_storeu_pd(&T->data[i], _mm256_mul_pd(vt, vs));
    }
    for(i=simd_end; i<size; i++) T->data[i] *= scalar;
#else
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) T->data[i] *= scalar;
#endif
}

void internal_add_scalar(tensor_t *T, double scalar) {
    int i;
    int size = T->size;
#ifdef __AVX2__
    __m256d vs = _mm256_set1_pd(scalar);
    int simd_end = size - (size % 4);
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<simd_end; i+=4) {
        __m256d vt = _mm256_loadu_pd(&T->data[i]);
        _mm256_storeu_pd(&T->data[i], _mm256_add_pd(vt, vs));
    }
    for(i=simd_end; i<size; i++) T->data[i] += scalar;
#else
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) T->data[i] += scalar;
#endif
}

void internal_sub_scalar(tensor_t *T, double scalar) {
    int i;
    int size = T->size;
#ifdef __AVX2__
    __m256d vs = _mm256_set1_pd(scalar);
    int simd_end = size - (size % 4);
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<simd_end; i+=4) {
        __m256d vt = _mm256_loadu_pd(&T->data[i]);
        _mm256_storeu_pd(&T->data[i], _mm256_sub_pd(vt, vs));
    }
    for(i=simd_end; i<size; i++) T->data[i] -= scalar;
#else
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) T->data[i] -= scalar;
#endif
}

/* Ring API Wrappers */
RING_FUNC(ring_tensor_add) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    if (A->size != B->size) { RING_API_ERROR("Tensor Size Mismatch"); return; }
    internal_add(A, B);
}

RING_FUNC(ring_tensor_sub) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    if (A->size != B->size) { RING_API_ERROR("Tensor Size Mismatch"); return; }
    internal_sub(A, B);
}

RING_FUNC(ring_tensor_mul_elem) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    if (A->size != B->size) { RING_API_ERROR("Tensor Size Mismatch"); return; }
    internal_mul_elem(A, B);
}

RING_FUNC(ring_tensor_div) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    if (A->size != B->size) { RING_API_ERROR("Tensor Size Mismatch"); return; }
    internal_div(A, B);
}

RING_FUNC(ring_tensor_scalar_mul) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    double v = RING_API_GETNUMBER(2);
    internal_scalar_mul(T, v);
}

RING_FUNC(ring_tensor_add_scalar) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    double v = RING_API_GETNUMBER(2);
    internal_add_scalar(T, v);
}

RING_FUNC(ring_tensor_sub_scalar) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    double v = RING_API_GETNUMBER(2);
    internal_sub_scalar(T, v);
}

/* ==================================================================== */
/* --- 3. TRANSFORMS & ACTIVATIONS ------------------------------------ */
/* ==================================================================== */

/* Internal Kernels */
void internal_fill(tensor_t *T, double value) {
    int i;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD)
    for(i=0; i<T->size; i++) T->data[i] = value;
}

void internal_random(tensor_t *T, double min, double max) {
    int i;
    double range = max - min;
    for(i=0; i<T->size; i++) {
        T->data[i] = min + ((double)rand() / RAND_MAX) * range;
    }
}

void internal_square(tensor_t *T) {
    int i;
    double v;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(v)
    for(i=0; i<T->size; i++) {
        v = T->data[i];
        T->data[i] = v * v;
    }
}

void internal_sqrt_tensor(tensor_t *T) {
    int i;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD)
    for(i=0; i<T->size; i++) T->data[i] = sqrt(T->data[i]);
}

void internal_exp(tensor_t *T) {
    int i;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD)
    for(i=0; i<T->size; i++) T->data[i] = exp(T->data[i]);
}

void internal_sigmoid(tensor_t *T) {
    int i;
    double v;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(v)
    for(i=0; i<T->size; i++) {
        v = T->data[i];
        T->data[i] = 1.0 / (1.0 + exp(-v));
    }
}

void internal_sigmoid_prime(tensor_t *T) {
    int i;
    double v;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(v)
    for(i=0; i<T->size; i++) {
        v = T->data[i];
        T->data[i] = v * (1.0 - v);
    }
}

void internal_tanh_activation(tensor_t *T) {
    int i;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD)
    for(i=0; i<T->size; i++) T->data[i] = tanh(T->data[i]);
}

void internal_tanh_prime(tensor_t *T) {
    int i;
    double v;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(v)
    for(i=0; i<T->size; i++) {
        v = T->data[i];
        T->data[i] = 1.0 - (v * v);
    }
}

void internal_relu(tensor_t *T) {
    int i;
    double v;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(v)
    for(i=0; i<T->size; i++) {
        v = T->data[i];
        T->data[i] = (v > 0) ? v : 0;
    }
}

void internal_relu_prime(tensor_t *T) {
    int i;
    double v;
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(v)
    for(i=0; i<T->size; i++) {
        v = T->data[i];
        T->data[i] = (v > 0) ? 1.0 : 0.0;
    }
}

/* Ring API Wrappers */
RING_FUNC(ring_tensor_fill) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    double v = RING_API_GETNUMBER(2);
    internal_fill(T, v);
}

RING_FUNC(ring_tensor_random) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    internal_random(T, 0.0, 1.0);
}

RING_FUNC(ring_tensor_square)        { internal_square((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_sqrt)          { internal_sqrt_tensor((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_exp)           { internal_exp((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_sigmoid)       { internal_sigmoid((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_sigmoid_prime) { internal_sigmoid_prime((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_tanh)          { internal_tanh_activation((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_tanh_prime)    { internal_tanh_prime((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_relu)          { internal_relu((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }
RING_FUNC(ring_tensor_relu_prime)    { internal_relu_prime((tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR)); }

void internal_softmax_backward(tensor_t *Y, tensor_t *dY, tensor_t *dX) {
    int r, c, rows = Y->rows, cols = Y->cols;
    
    #pragma omp parallel for if(rows > 32) private(c)
    for(r = 0; r < rows; r++) {
        double sum_dy_y = 0.0;
        int offset = r * cols;
        for(c = 0; c < cols; c++) sum_dy_y += dY->data[offset + c] * Y->data[offset + c];
        for(c = 0; c < cols; c++) {
            dX->data[offset + c] = Y->data[offset + c] * (dY->data[offset + c] - sum_dy_y);
        }
    }
}

void internal_softmax(tensor_t *T) {
    int r, c;
    
    #pragma omp parallel for if(T->rows > 64) private(c)
    for(r=0; r<T->rows; r++) {
        double maxVal = -DBL_MAX;
        int offset = r * T->cols;
        
        // Find Max
        for(c=0; c<T->cols; c++) {
            if(T->data[offset+c] > maxVal) maxVal = T->data[offset+c];
        }
        
        // Safety: If maxVal is still very small (masked row), force zero output
        if (maxVal < -1e8) {
             for(c=0; c<T->cols; c++) T->data[offset+c] = 0.0;
             continue;
        }

        double sum = 0.0;
        for(c=0; c<T->cols; c++) {
            T->data[offset+c] = exp(T->data[offset+c] - maxVal);
            sum += T->data[offset+c];
        }
        
        double invSum = (sum > 1e-9) ? (1.0/sum) : 0.0;
        for(c=0; c<T->cols; c++) T->data[offset+c] *= invSum;
    }
}

RING_FUNC(ring_tensor_softmax) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    internal_softmax(T);
}

/* ==================================================================== */
/* --- 4. MATRIX OPS (OPTIMIZED MATMUL) ------------------------------- */
/* ==================================================================== */

/* ====================================================================
** Upgrade 4: Cache-Friendly MatMul via B-Transpose + Memory Packing
** ====================================================================
** BEFORE: Inner loop reads B by columns — B->data[k*cB + j].
**         Column access is stride-cB, causing heavy L1/L2 cache misses.
**         On i3-5005U with 3MB L3, matrices > 512x512 thrash badly.
**
** AFTER:  We explicitly transpose B into B_T before the multiply.
**         The dot product now reads both A rows and B_T rows
**         contiguously — sequential memory access, full cache line utilization.
**
**         A row:   A[i*cA + 0], A[i*cA + 1], ... A[i*cA + cA-1]  (contiguous)
**         B_T row: B_T[j*cA + 0], B_T[j*cA + 1], ... B_T[j*cA + cA-1]  (contiguous)
**         Result:  C[i*cB + j] = dot(A_row_i, B_T_row_j)
**
** The transpose cost is O(cA*cB) which is negligible compared to
** the O(rA*cA*cB) multiply, especially for large matrices.
** Tiling is applied on top for L1 temporal locality.
** ==================================================================== */
void internal_matmul(tensor_t *A, tensor_t *B, tensor_t *C) {

    int rA = A->rows; int cA = A->cols; int cB = B->cols;
    int i, j, k, ii, jj, kk;
    int i_max, j_max, k_max;
    double *rowC, *rowA, *rowBT;
    double sum;

    /* --- GPU Smart Switch (unchanged) --- */
    long operations = (long)rA * cA * cB;

    #ifdef USE_OPENCL
    if (gpu_ready && operations > GPU_THRESHOLD) {
        if (gpu_matmul(A, B, C)) {
            return;  /* Done by GPU */
        }
    }
    #endif

    memset(C->data, 0, (size_t)rA * cB * sizeof(double));

    /* --- Step 1: Transpose B into B_T (column-major -> row-major) ---
    ** B  is (cA x cB) stored row-major: B[k][j] = B->data[k*cB + j]
    ** B_T is (cB x cA) stored row-major: B_T[j][k] = B_T[j*cA + k]
    ** After transpose, iterating over k for a fixed j is contiguous. */
    double *B_T = (double *)malloc((size_t)cA * cB * sizeof(double));
    if (B_T == NULL) {
        /* Fallback: if malloc fails, use original (slower) path */
        #pragma omp parallel for schedule(static) private(ii, jj, kk, i, j, k, i_max, j_max, k_max, rowC, rowA)
        for (ii = 0; ii < rA; ii += TILE_SIZE) {
            i_max = (ii + TILE_SIZE > rA) ? rA : ii + TILE_SIZE;
            for (kk = 0; kk < cA; kk += TILE_SIZE) {
                k_max = (kk + TILE_SIZE > cA) ? cA : kk + TILE_SIZE;
                for (jj = 0; jj < cB; jj += TILE_SIZE) {
                    j_max = (jj + TILE_SIZE > cB) ? cB : jj + TILE_SIZE;
                    for (i = ii; i < i_max; i++) {
                        rowC = &C->data[i * cB];
                        rowA = &A->data[i * cA];
                        for (k = kk; k < k_max; k++) {
                            double valA = rowA[k];
                            if (valA == 0.0) continue;
                            double *rowB = &B->data[k * cB];
                            for (j = jj; j < j_max; j++) {
                                rowC[j] += valA * rowB[j];
                            }
                        }
                    }
                }
            }
        }
        return;
    }

    /* Transpose B -> B_T (parallelized for large matrices) */
    #pragma omp parallel for if(cA * cB > PARALLEL_THRESHOLD) private(k)
    for (j = 0; j < cB; j++) {
        for (k = 0; k < cA; k++) {
            B_T[j * cA + k] = B->data[k * cB + j];
        }
    }

    /* --- Step 2: Tiled MatMul with transposed B ---
    ** The inner dot product now reads A[i] and B_T[j] both contiguously.
    ** Both rows fit in L1 cache (32 doubles * 8 bytes = 256 bytes each).
    ** This turns random column-strided accesses into sequential reads. */
    #pragma omp parallel for schedule(static) private(ii, jj, kk, i, j, k, i_max, j_max, k_max, rowC, rowA, rowBT, sum)
    for (ii = 0; ii < rA; ii += TILE_SIZE) {
        i_max = (ii + TILE_SIZE > rA) ? rA : ii + TILE_SIZE;
        for (jj = 0; jj < cB; jj += TILE_SIZE) {
            j_max = (jj + TILE_SIZE > cB) ? cB : jj + TILE_SIZE;
            for (i = ii; i < i_max; i++) {
                rowC = &C->data[i * cB];
                rowA = &A->data[i * cA];
                for (j = jj; j < j_max; j++) {
                    rowBT = &B_T[j * cA];
                    sum = 0.0;
                    /* Tiled inner K loop for L1 cache reuse */
                    for (kk = 0; kk < cA; kk += TILE_SIZE) {
                        k_max = (kk + TILE_SIZE > cA) ? cA : kk + TILE_SIZE;
                        for (k = kk; k < k_max; k++) {
                            sum += rowA[k] * rowBT[k];
                        }
                    }
                    rowC[j] = sum;
                }
            }
        }
    }

    free(B_T);
}

RING_FUNC(ring_tensor_matmul) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *C = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    if (A->cols != B->rows) { RING_API_ERROR("MatMul Dims Mismatch"); return; }
    internal_matmul(A, B, C);
}

RING_FUNC(ring_tensor_transpose) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *C = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    if (A->rows != C->cols || A->cols != C->rows) { RING_API_ERROR("Transpose Dims Mismatch"); return; }
    internal_transpose(A, C);
}

/* Internal Kernel - Transpose */
void internal_transpose(tensor_t *A, tensor_t *R) {

    int rA = A->rows; 
    int cA = A->cols;
    int i, j, ii, jj;
    int i_max, j_max;

    #ifdef USE_OPENCL
    // Rotation requires significant memory movement; the GPU is excellent here.
    if (gpu_ready && A->size > GPU_THRESHOLD) { 
        if (gpu_transpose(A, R)) return;
    }
    #endif

    #pragma omp parallel for schedule(static) private(ii, jj, i, j, i_max, j_max)
    for (ii = 0; ii < rA; ii += TILE_SIZE) {
        i_max = (ii + TILE_SIZE > rA) ? rA : ii + TILE_SIZE;
        for (jj = 0; jj < cA; jj += TILE_SIZE) {
            j_max = (jj + TILE_SIZE > cA) ? cA : jj + TILE_SIZE;
            for (j = jj; j < j_max; j++) {
                for (i = ii; i < i_max; i++) {
                    R->data[j * rA + i] = A->data[i * cA + j];
                }
            }
        }
    }
}

/* Internal Kernel - Sum */
void internal_sum(tensor_t *T, int axis, tensor_t *R) {
    int r, c;
    double s;
    double *ptr, *src, *dst, *rowPtr;
    
    memset(R->data, 0, R->size * sizeof(double));
    
    if (axis == 1) {
        #pragma omp parallel for if(T->rows > 64) private(c, s, ptr)
        for(r=0; r<T->rows; r++) {
            s = 0;
            ptr = &T->data[r * T->cols];
            for(c=0; c<T->cols; c++) {
                s += ptr[c];
            }
            R->data[r] = s;
        }
    } else {
        src = T->data;
        dst = R->data;
        for(r=0; r<T->rows; r++) {
            rowPtr = &src[r * T->cols];
            for(c=0; c<T->cols; c++) {
                dst[c] += rowPtr[c];
            }
        }
    }
}

/* Internal Kernel - Dot Product of a Row Vector with a Matrix */
void internal_dot_row_vec(tensor_t *A, tensor_t *B, tensor_t *R) {
    int i, j;
    int rows = A->rows;
    int cols = A->cols;
    
    #pragma omp parallel for private(j) schedule(static)
    for(i=0; i<rows; i++) {
        double dot = 0.0;
        double *rowA = &A->data[i * cols];
        double *vecB = B->data;
        for(j=0; j<cols; j++) {
            dot += rowA[j] * vecB[j];
        }
        R->data[i] = dot; 
    }
}

RING_FUNC(ring_tensor_dot_row_vec) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *R = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    internal_dot_row_vec(A, B, R);
}

RING_FUNC(ring_tensor_sum) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    int axis = (int)RING_API_GETNUMBER(2);
    tensor_t *R = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    internal_sum(T, axis, R);
}

/* Internal Kernel - Add Row Vector */
void internal_add_row_vec(tensor_t *A, tensor_t *B) {
    int i, j;
    double *rowA, *rowB;
    
    #pragma omp parallel for if(A->rows > 32) private(j, rowA, rowB)
    for(i=0; i<A->rows; i++) {
        rowA = &A->data[i * A->cols];
        rowB = B->data;
        for(j=0; j<A->cols; j++) {
            rowA[j] += rowB[j];
        }
    }
}

RING_FUNC(ring_tensor_add_row_vec) {
    tensor_t *A = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    if (A->cols != B->cols) { RING_API_ERROR("Dim Mismatch"); return; }
    internal_add_row_vec(A, B);
}

/* Internal Kernel - Mean */
void internal_mean(tensor_t *T, int axis, tensor_t *R) {
    internal_sum(T, axis, R);
    int divisor = (axis == 1) ? T->cols : T->rows;
    internal_scalar_mul(R, 1.0 / divisor);
}

RING_FUNC(ring_tensor_mean) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    RING_API_RETNUMBER(internal_mean_global(T));
}

/* Internal Kernel - Argmax */
int internal_argmax(tensor_t *T) {
    int i;
    int max_idx = 0;
    double max_val = T->data[0];
    for(i=1; i<T->size; i++) {
        if (T->data[i] > max_val) {
            max_val = T->data[i];
            max_idx = i;
        }
    }
    return max_idx;
}

RING_FUNC(ring_tensor_argmax) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    int nBestID = internal_argmax(T);
    RING_API_RETNUMBER(nBestID);
}

/*
** Slice Rows (Extraction)
** Copies 'count' rows starting from 'start_row' in Src to Dest.
** Optimization: Uses single memcpy because rows are contiguous in memory.
*/
RING_FUNC(ring_tensor_slice_rows) {
    tensor_t *Src, *Dest;
    int start_row, count;
    
    if (RING_API_PARACOUNT != 4) {
        RING_API_ERROR(RING_API_MISS4PARA);
        return;
    }

    Src = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    Dest = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    start_row = (int)RING_API_GETNUMBER(3);
    count = (int)RING_API_GETNUMBER(4);

    if (start_row < 1 || start_row + count - 1 > Src->rows) {
        RING_API_ERROR("Slice Rows: Index out of bounds");
        return;
    }
    if (Dest->cols != Src->cols || Dest->rows != count) {
        RING_API_ERROR("Slice Rows: Destination Dims Mismatch");
        return;
    }

    internal_slice_rows(Src, Dest, start_row, count);
}

/*
** Insert Rows (Injection)
** Copies all rows from Src into Dest starting at 'start_row'.
*/
RING_FUNC(ring_tensor_insert_rows) {
    tensor_t *Dest, *Src;
    int start_row;

    if (RING_API_PARACOUNT != 3) {
        RING_API_ERROR(RING_API_MISS3PARA);
        return;
    }

    Dest = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    Src = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    start_row = (int)RING_API_GETNUMBER(3);

    if (start_row < 1 || start_row + Src->rows - 1 > Dest->rows) {
        RING_API_ERROR("Insert Rows: Index out of bounds");
        return;
    }
    if (Dest->cols != Src->cols) {
        RING_API_ERROR("Insert Rows: Column count mismatch");
        return;
    }

    internal_insert_rows(Dest, Src, start_row);
}

/* ==================================================================== */
/* --- 5. NLP & TRANSFORMER KERNELS (OpenMP Optimized) ---------------- */
/* ==================================================================== */

RING_FUNC(ring_tensor_embedding_forward) {
    tensor_t *Ind = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *W   = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *Out = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    internal_embedding_forward(W, Ind, Out);
}

RING_FUNC(ring_tensor_copy_data) {
    // Usage: copy_data(Dest, Src)
    tensor_t *Dest = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *Src  = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    
    if (Dest->size != Src->size) {
        printf("ERROR: Copy Size Mismatch! Dest=%d, Src=%d\n", Dest->size, Src->size);
        RING_API_ERROR("Size Mismatch");
        return;
    }

    memcpy(Dest->data, Src->data, Dest->size * sizeof(double));
}

RING_FUNC(ring_tensor_embedding_backward) {
    tensor_t *GOut = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *Ind = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *GW = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    internal_embedding_backward(GOut, Ind, GW);
}

RING_FUNC(ring_tensor_layernorm) {
    tensor_t *X = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *G = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *B = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Y = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    double eps = RING_API_GETNUMBER(5);
    
    copy_tensor(X, Y);
    internal_layernorm(Y, G, B, eps);
}

RING_FUNC(ring_tensor_attention_fast) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Out = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    double scale = RING_API_GETNUMBER(5);
    internal_attention_forward(Q, K, V, Out, scale);
}

RING_FUNC(ring_tensor_attention_causal) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Out = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    double scale = RING_API_GETNUMBER(5);
    internal_attention_causal(Q, K, V, Out, scale);
}

RING_FUNC(ring_tensor_select_columns) {
    tensor_t *Src = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *Dest = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    int start = (int)RING_API_GETNUMBER(3);
    int count = (int)RING_API_GETNUMBER(4);
    int r;
    int src_off;
    size_t bytes;
    
    if (start < 1 || start + count - 1 > Src->cols) { RING_API_ERROR("Bounds"); return; }
    
    src_off = start - 1;
    bytes = count * sizeof(double);
    
    #pragma omp parallel for if(Src->rows > 64)
    for(r=0; r<Src->rows; r++) {
        memcpy(&Dest->data[r*Dest->cols], &Src->data[r*Src->cols + src_off], bytes);
    }
}

RING_FUNC(ring_tensor_insert_columns) {
    tensor_t *Dest = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *Src = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    int start = (int)RING_API_GETNUMBER(3);
    int r;
    int dest_off;
    size_t bytes;
    
    if (start < 1 || start + Src->cols - 1 > Dest->cols) { RING_API_ERROR("Bounds"); return; }
    
    dest_off = start - 1;
    bytes = Src->cols * sizeof(double);
    
    #pragma omp parallel for if(Dest->rows > 64)
    for(r=0; r<Dest->rows; r++) {
        memcpy(&Dest->data[r*Dest->cols + dest_off], &Src->data[r*Src->cols], bytes);
    }
}

/*
** Fused Batch Attention (Fast & Causal)
** Handles [Batch, Seq, Dim] in one go using OpenMP.
** 
** Params: 
** 1. Q, 2. K, 3. V, 4. Out (All Flattened: Batch*Seq*Dim)
** 5. Scale, 6. BatchSize, 7. SeqLen, 8. Dim, 9. IsCausal (1=Yes, 0=No)
*/
RING_FUNC(ring_tensor_attention_batch) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Out = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    
    double scale  = RING_API_GETNUMBER(5);
    int batch     = (int)RING_API_GETNUMBER(6);
    int seq       = (int)RING_API_GETNUMBER(7);
    int dim       = (int)RING_API_GETNUMBER(8);
    int is_causal = (int)RING_API_GETNUMBER(9);
    
    int b, i, j, k;
    int stride = seq * dim; // Size of one sentence block
    
    // Parallelize over Batches (The most efficient way)
    #pragma omp parallel for private(b, i, j, k)
    for (b = 0; b < batch; b++) {
        
        // Pointers to the start of the current batch
        double *q_base = &Q->data[b * stride];
        double *k_base = &K->data[b * stride];
        double *v_base = &V->data[b * stride];
        double *o_base = &Out->data[b * stride];
        
        // Temp scores buffer (per thread/batch)
        double *scores = (double *)malloc(seq * sizeof(double));
        
        if (scores) {
            // Loop over Sequence (Rows)
            for(i = 0; i < seq; i++) {
                double *q_row = &q_base[i * dim];
                double *o_row = &o_base[i * dim];
                
                // 1. Q . K^T
                for(j = 0; j < seq; j++) {
                    // Causal Masking Logic
                    if (is_causal && j > i) {
                        scores[j] = -1e9;
                        continue;
                    }
                    
                    double *k_row = &k_base[j * dim];
                    double dot = 0.0;
                    for(k = 0; k < dim; k++) {
                        dot += q_row[k] * k_row[k];
                    }
                    scores[j] = dot * scale;
                }
                
                // 2. Softmax
                double maxVal = -1e9;
                for(j=0; j<seq; j++) if(scores[j] > maxVal) maxVal = scores[j];
                
                double sum = 0.0;
                for(j=0; j<seq; j++) {
                    scores[j] = exp(scores[j] - maxVal);
                    sum += scores[j];
                }
                
                double invSum = 1.0 / sum;
                for(j=0; j<seq; j++) scores[j] *= invSum;
                
                // 3. Scores . V
                memset(o_row, 0, dim * sizeof(double));
                for(j=0; j<seq; j++) {
                    double s = scores[j];
                    if (s < 1e-9) continue; // Optimization
                    
                    double *v_row = &v_base[j * dim];
                    for(k=0; k<dim; k++) {
                        o_row[k] += s * v_row[k];
                    }
                }
            }
            free(scores);
        }
    }
}

/* ==================================================================== */
/* --- 6. OPTIMIZERS -------------------------------------------------- */
/* ==================================================================== */

RING_FUNC(ring_tensor_update_adam) {
    tensor_t *W = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *G = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *M = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    
    double lr = RING_API_GETNUMBER(5);
    double b1 = RING_API_GETNUMBER(6);
    double b2 = RING_API_GETNUMBER(7);
    double eps= RING_API_GETNUMBER(8);
    int t = (int)RING_API_GETNUMBER(9);
    double weight_decay = RING_API_GETNUMBER(10);
    
    double corr1 = 1.0 - pow(b1, t);
    double corr2 = 1.0 - pow(b2, t);
    if(corr1 < 1e-9) corr1 = 1e-9;
    if(corr2 < 1e-9) corr2 = 1e-9;
    
    int i;
    int size = W->size;
    
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) {
        double g = G->data[i];
        
        // Update momentum
        M->data[i] = (b1 * M->data[i]) + ((1.0 - b1) * g);
        V->data[i] = (b2 * V->data[i]) + ((1.0 - b2) * g * g);
        
        double m_hat = M->data[i] / corr1;
        double v_hat = V->data[i] / corr2;
        if(v_hat < 0) v_hat = 0;
        
        // Update Adam
        W->data[i] -= (lr * m_hat) / (sqrt(v_hat) + eps);
        
        // Apply Weight Decay directly (AdamW)
        W->data[i] -= lr * weight_decay * W->data[i];
    }
}

RING_FUNC(ring_tensor_update_sgd) {
    tensor_t *W = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *G = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    double lr = RING_API_GETNUMBER(3);
    int i;
    int size = W->size;
    
    #pragma omp parallel for if(size > PARALLEL_THRESHOLD)
    for(i=0; i<size; i++) W->data[i] -= (lr * G->data[i]);
}

RING_FUNC(ring_tensor_dropout) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    double rate = RING_API_GETNUMBER(2);
    internal_dropout(T, rate, 1);
}

/* ==================================================================== */
/* --- 7. UTILS ------------------------------------------------------- */
/* ==================================================================== */

RING_FUNC(ring_tensor_get_cores) {
    int cores = 1;
    #ifdef _OPENMP
    cores = omp_get_num_procs();
    #endif
    RING_API_RETNUMBER(cores);
}

RING_FUNC(ring_tensor_set_threads) {
    int n = (int)RING_API_GETNUMBER(1);
    #ifdef _OPENMP
    omp_set_num_threads(n);
    #endif
}

/*
** Set GPU Switch Threshold
** Input: Number (Operations count, e.g. 1000000)
*/
RING_FUNC(ring_tensor_set_gpu_threshold) {
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    
    double val = RING_API_GETNUMBER(1);
    
    // Safety check
    if (val < 0) val = 0;
    
    GPU_THRESHOLD = (long long)val;
}

/*
** Set Memory Arena Size (in MB)
** Usage: tensor_set_arena_size(1024) -> sets to 1GB
** Note: Must be called BEFORE graph_init() to take effect.
*/
RING_FUNC(ring_tensor_set_arena_size) {
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    
    double mb = RING_API_GETNUMBER(1);
    if (mb < 1) mb = 1; // Minimum 1MB
    
    ARENA_SIZE = (size_t)(mb * 1024 * 1024);
    
    // If arena is already active, we warn the user
    if (arena_active) {
        printf("[RingTensor] WARNING: Arena size changed while active. Call graph_free() then graph_init() to apply.\n");
    }
}

/*
** ====================================================================
** --- CROSS ENTROPY KERNELS (FUSED) ----------------------------------
** ====================================================================
*/

/*
** Optimized CrossEntropy Loss (Fused Kernel)
** Logic: -Sum(Target * Log(Pred)) / ActiveSamples
** Features: Auto-Masking (Ignores zero targets), Safety Clamp (No NaN)
*/
RING_FUNC(ring_tensor_crossentropy_loss) {
    tensor_t *Probs   = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *Targets = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    
    double total_loss = 0.0;
    int active_samples = 0;
    double eps = 1e-7; // Safety Clamp

    int rows = Probs->rows;
    int cols = Probs->cols;
    int r, c;

    // Parallel Reduction for Speed
    #pragma omp parallel for reduction(+:total_loss, active_samples) private(c)
    for (r = 0; r < rows; r++) {
        int target_idx = -1;
        double *row_t = &Targets->data[r * cols];
        
        // Find Target Class (One-Hot)
        for (c = 0; c < cols; c++) {
            if (row_t[c] > 0.5) {
                target_idx = c;
                break;
            }
        }
        
        // If Target exists (Not Padding)
        if (target_idx != -1) {
            double p = Probs->data[r * cols + target_idx];
            
            // --- Safety Clamp (Same as your Ring code) ---
            if (p < eps) p = eps;
            if (p > 1.0) p = 1.0;
            // ---------------------------------------------
            
            total_loss += -log(p);
            active_samples++;
        }
    }

    if (active_samples == 0) {
        RING_API_RETNUMBER(0.0);
    } else {
        RING_API_RETNUMBER(total_loss / active_samples);
    }
}

/*
** Optimized Backward (Fused Kernel)
** Logic: (Probs - Targets) / ActiveSamples
** Features: Auto-Masking (Zeros out gradients for padding)
*/
RING_FUNC(ring_tensor_crossentropy_backward) {
    tensor_t *Probs   = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *Targets = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *Grad    = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);

    int rows = Probs->rows;
    int cols = Probs->cols;
    int active_samples = 0;
    int r, c;

    // 1. Count Active Samples First (For Scaling)
    for (r = 0; r < rows; r++) {
        double *row_t = &Targets->data[r * cols];
        for (c = 0; c < cols; c++) {
            if (row_t[c] > 0.5) {
                active_samples++;
                break;
            }
        }
    }
    
    double scale = (active_samples > 0) ? (1.0 / active_samples) : 0.0;

    // 2. Compute Gradients
    #pragma omp parallel for private(c)
    for (r = 0; r < rows; r++) {
        double *p_row = &Probs->data[r * cols];
        double *t_row = &Targets->data[r * cols];
        double *g_row = &Grad->data[r * cols];
        
        // Check mask
        int is_active = 0;
        for(c=0; c<cols; c++) if(t_row[c] > 0.5) { is_active=1; break; }

        if (is_active) {
            // Apply Gradient: (P - T) * Scale
            for (c = 0; c < cols; c++) {
                g_row[c] = (p_row[c] - t_row[c]) * scale;
            }
        } else {
            // Masking: Force Zero
            memset(g_row, 0, cols * sizeof(double));
        }
    }
}


/*
** Bulk Set from List (Turbo Loading)
** Copies a Ring List directly into Tensor Memory.
** Eliminates the overhead of calling setVal() thousands of times.
*/
RING_FUNC(ring_tensor_set_from_list) {
    tensor_t *T;
    List *pList;
    int i, nSize, nLimit;

    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }

    // 1. Get Tensor
    T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    
    // 2. Get List
    if (!RING_API_ISLIST(2)) {
        RING_API_ERROR(RING_API_BADPARATYPE);
        return;
    }
    pList = RING_API_GETLIST(2);
    
    // 3. Determine safe copy limit
    nSize = ring_list_getsize(pList);
    nLimit = T->size;
    if (nSize < nLimit) nLimit = nSize;

    // 4. Turbo Copy Loop (Inside C)
    for(i = 1; i <= nLimit; i++) {
        if (ring_list_isnumber(pList, i)) {
            T->data[i-1] = ring_list_getdouble(pList, i);
        } else {
            T->data[i-1] = 0.0; // Default for non-numbers
        }
    }
}

/*
** Set One-Hot (Scatter)
** Takes a List of Indices and sets T[row, index] = value.
** Assumes Tensor is already zeroed (or overwrites).
** 1-based Indexing for both List and Values.
*/
RING_FUNC(ring_tensor_set_one_hot) {
    tensor_t *T;
    List *pList;
    double val;
    int i, nListSize, nMaxRows;

    if (RING_API_PARACOUNT != 3) {
        RING_API_ERROR(RING_API_MISS3PARA);
        return;
    }

    T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    
    if (!RING_API_ISLIST(2)) {
        RING_API_ERROR("Param 2 must be a List of Indices");
        return;
    }
    pList = RING_API_GETLIST(2);
    val = RING_API_GETNUMBER(3);

    nListSize = ring_list_getsize(pList);
    nMaxRows = T->rows;
    
    if (nListSize > nMaxRows) nListSize = nMaxRows;

    // Parallel scatter
    #pragma omp parallel for if(nListSize > 5000)
    for(i = 1; i <= nListSize; i++) {
        if (ring_list_isnumber(pList, i)) {
            int col_idx = (int)ring_list_getdouble(pList, i);
            
            // ignore 0 (padding marker) و 1 (PAD token)
            if (col_idx <= 1) continue;
            
            // Validate bounds
            if (col_idx >= 2 && col_idx <= T->cols) {
                T->data[(i-1) * T->cols + (col_idx-1)] = val;
            }
        }
    }
}

/* ==================================================================== */
/* --- 8. PERSISTENCE (BINARY & QUANTIZATION) ------------------------- */
/* ==================================================================== */

/*
** Save Tensor (Raw Binary - Double Precision 64-bit)
** Format: [Rows (int)][Cols (int)][Data (double...)]
*/
RING_FUNC(ring_tensor_save) {
    tensor_t *t;
    const char *cFile;
    FILE *fp;
    
    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }

    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    cFile = RING_API_GETSTRING(2);

    fp = fopen(cFile, "wb");
    if (!fp) {
        RING_API_ERROR("Could not open file for writing");
        return;
    }

    // 1. Write Header (Rows, Cols)
    fwrite(&t->rows, sizeof(int), 1, fp);
    fwrite(&t->cols, sizeof(int), 1, fp);

    // 2. Write Data Block (Fastest way)
    fwrite(t->data, sizeof(double), t->size, fp);

    fclose(fp);
}

/*
** Load Tensor (Raw Binary - Double Precision)
** Returns: New Tensor Pointer
*/
RING_FUNC(ring_tensor_load) {
    const char *cFile;
    FILE *fp;
    int rows, cols;
    tensor_t *t;

    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }

    cFile = RING_API_GETSTRING(1);
    fp = fopen(cFile, "rb");
    if (!fp) {
        RING_API_ERROR("Could not open file for reading");
        return;
    }

    // 1. Read Header
    if (fread(&rows, sizeof(int), 1, fp) != 1 ||
        fread(&cols, sizeof(int), 1, fp) != 1) {
        fclose(fp);
        RING_API_ERROR("Invalid Tensor File (Header)");
        return;
    }

    // 2. Allocate Tensor
    t = (tensor_t *)malloc(sizeof(tensor_t));
    t->rows = rows;
    t->cols = cols;
    t->size = rows * cols;
    t->ndim = 2; // Default
    t->shape[0]=1; t->shape[1]=1; t->shape[2]=rows; t->shape[3]=cols;

    t->data = (double *)malloc(t->size * sizeof(double));
    if (!t->data) {
        fclose(fp);
        free(t);
        RING_API_ERROR("Malloc Failed");
        return;
    }

    // 3. Read Data Block
    if (fread(t->data, sizeof(double), t->size, fp) != t->size) {
        fclose(fp);
        free(t->data);
        free(t);
        RING_API_ERROR("File truncated or corrupted");
        return;
    }

    fclose(fp);
    RING_API_RETMANAGEDCPOINTER(t, RING_VM_POINTER_TENSOR, ring_tensor_free);
}

/*
** Save Tensor Quantized (FP32 - 32-bit Float)
** Reduces size by 50%.
*/
RING_FUNC(ring_tensor_save_fp32) {
    tensor_t *t;
    const char *cFile;
    FILE *fp;
    int i;
    float val; // 32-bit buffer

    if (RING_API_PARACOUNT != 2) return;

    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    cFile = RING_API_GETSTRING(2);

    fp = fopen(cFile, "wb");
    if (!fp) return;

    // Header
    fwrite(&t->rows, sizeof(int), 1, fp);
    fwrite(&t->cols, sizeof(int), 1, fp);

    // Write Data (Cast Double -> Float)
    // Optimization: We could use a buffer block, but loop is simple for now
    for (i = 0; i < t->size; i++) {
        val = (float)t->data[i];
        fwrite(&val, sizeof(float), 1, fp);
    }

    fclose(fp);
}

/*
** Load Tensor Quantized (FP32 -> Double)
*/
RING_FUNC(ring_tensor_load_fp32) {
    const char *cFile;
    FILE *fp;
    int rows, cols, i;
    tensor_t *t;
    float val;

    if (RING_API_PARACOUNT != 1) return;

    cFile = RING_API_GETSTRING(1);
    fp = fopen(cFile, "rb");
    if (!fp) return;

    fread(&rows, sizeof(int), 1, fp);
    fread(&cols, sizeof(int), 1, fp);

    t = (tensor_t *)malloc(sizeof(tensor_t));
    t->rows = rows; t->cols = cols; t->size = rows * cols;
    t->ndim = 2; t->shape[0]=1; t->shape[1]=1; t->shape[2]=rows; t->shape[3]=cols;
    t->data = (double *)malloc(t->size * sizeof(double));

    // Read Data (Float -> Double)
    for (i = 0; i < t->size; i++) {
        fread(&val, sizeof(float), 1, fp);
        t->data[i] = (double)val;
    }

    fclose(fp);
    RING_API_RETMANAGEDCPOINTER(t, RING_VM_POINTER_TENSOR, ring_tensor_free);
}

/*
** Load Tensor In-Place (Modifies existing tensor)
** Usage: tensor.loadFile(filename)
*/
RING_FUNC(ring_tensor_load_inplace) {
    tensor_t *t;
    const char *cFile;
    FILE *fp;
    int rows, cols, size;

    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }

    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    cFile = RING_API_GETSTRING(2);

    fp = fopen(cFile, "rb");
    if (!fp) {
        RING_API_ERROR("Could not open file for reading");
        return;
    }

    // Read header
    if (fread(&rows, sizeof(int), 1, fp) != 1 ||
        fread(&cols, sizeof(int), 1, fp) != 1) {
        fclose(fp);
        RING_API_ERROR("Invalid file header");
        return;
    }

    size = rows * cols;

    // Free old data if size changed
    if (t->size != size) {
        if (t->data) {
            free(t->data);
        }
        t->data = (double *)malloc(size * sizeof(double));
        if (!t->data) {
            fclose(fp);
            RING_API_ERROR("Memory allocation failed");
            return;
        }
    }

    // Update dimensions
    t->rows = rows;
    t->cols = cols;
    t->size = size;
    t->ndim = 2;
    t->shape[0] = 1;
    t->shape[1] = 1;
    t->shape[2] = rows;
    t->shape[3] = cols;

    // Read data
    if (fread(t->data, sizeof(double), t->size, fp) != t->size) {
        fclose(fp);
        RING_API_ERROR("File read error");
        return;
    }

    fclose(fp);
    
    // No return - modified in place
}

/*
** Load Quantized Tensor In-Place (FP32 -> Double)
*/
RING_FUNC(ring_tensor_load_fp32_inplace) {
    tensor_t *t;
    const char *cFile;
    FILE *fp;
    int rows, cols, size, i;
    float val;

    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }

    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    cFile = RING_API_GETSTRING(2);

    fp = fopen(cFile, "rb");
    if (!fp) {
        RING_API_ERROR("Could not open file");
        return;
    }

    // Read header
    fread(&rows, sizeof(int), 1, fp);
    fread(&cols, sizeof(int), 1, fp);
    size = rows * cols;

    // Reallocate if needed
    if (t->size != size) {
        if (t->data) free(t->data);
        t->data = (double *)malloc(size * sizeof(double));
    }

    // Update dimensions
    t->rows = rows;
    t->cols = cols;
    t->size = size;
    t->ndim = 2;
    t->shape[0] = 1;
    t->shape[1] = 1;
    t->shape[2] = rows;
    t->shape[3] = cols;

    // Read data (float -> double)
    for (i = 0; i < t->size; i++) {
        fread(&val, sizeof(float), 1, fp);
        t->data[i] = (double)val;
    }

    fclose(fp);
}
/*
** Get Tensor Dimensions (For Syncing with Ring)
*/
RING_FUNC(ring_tensor_get_rows) {
    tensor_t *t;
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    RING_API_RETNUMBER(t->rows);
}

/*
** Get Tensor Columns
*/
RING_FUNC(ring_tensor_get_cols) {
    tensor_t *t;
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    RING_API_RETNUMBER(t->cols);
}

/*
** Global Gradient Clipping (Fixed Logic)
** Applies the same "Pointer OR Number" check to sub-lists.
*/
RING_FUNC(ring_tensor_clip_global_norm) {
    List *pList, *pSubList;
    double max_norm, total_norm_sq = 0.0;
    int i, k, nItems;
    tensor_t *t;

    if (RING_API_PARACOUNT != 2) {
        RING_API_ERROR(RING_API_MISS2PARA);
        return;
    }

    if (!RING_API_ISLIST(1)) {
        RING_API_ERROR("Param 1 must be a List");
        return;
    }

    pList = RING_API_GETLIST(1);
    max_norm = RING_API_GETNUMBER(2);
    nItems = ring_list_getsize(pList);

    // ═══════════════════════════════════════════════
    // STEP 1: Calculate Global Norm
    // ═══════════════════════════════════════════════
    int valid_tensors = 0;  
    
    for (i = 1; i <= nItems; i++) {
        t = NULL;

        if (ring_list_islist(pList, i)) {
            pSubList = ring_list_getlist(pList, i);
            if (ring_list_getsize(pSubList) > 0) {
                if (ring_list_ispointer(pSubList, 1)) {
                    t = (tensor_t *)ring_list_getpointer(pSubList, 1);
                } 
                else if (ring_list_isnumber(pSubList, 1)) {
                    t = (tensor_t *)(size_t)ring_list_getdouble(pSubList, 1);
                }
            }
        } 
        else if (ring_list_ispointer(pList, i)) {
            t = (tensor_t *)ring_list_getpointer(pList, i);
        }
        else if (ring_list_isnumber(pList, i)) {
            t = (tensor_t *)(size_t)ring_list_getdouble(pList, i);
        }

        if (t == NULL) continue;
        
        valid_tensors++;  

        double t_sum = 0.0;
        int size = t->size;
        double *data = t->data;
        
        #pragma omp parallel for reduction(+:t_sum) if(size > 5000)
        for (k = 0; k < size; k++) {
            t_sum += (data[k] * data[k]);
        }
        total_norm_sq += t_sum;
    }

    // ═══════════════════════════════════════════════
    // STEP 2: Calculate Scale and Clip
    // ═══════════════════════════════════════════════
    double total_norm = sqrt(total_norm_sq);
    double scale = 1.0;
    int clipped = 0;  
    
    if (total_norm > max_norm) {
        scale = max_norm / (total_norm + 1e-9);
        clipped = 1;
        
        // Apply scale to all tensors
        for (i = 1; i <= nItems; i++) {
            t = NULL;
            
            if (ring_list_islist(pList, i)) {
                pSubList = ring_list_getlist(pList, i);
                if (ring_list_getsize(pSubList) > 0) {
                    if (ring_list_ispointer(pSubList, 1)) {
                        t = (tensor_t *)ring_list_getpointer(pSubList, 1);
                    } 
                    else if (ring_list_isnumber(pSubList, 1)) {
                        t = (tensor_t *)(size_t)ring_list_getdouble(pSubList, 1);
                    }
                }
            }
            else if (ring_list_ispointer(pList, i)) {
                t = (tensor_t *)ring_list_getpointer(pList, i);
            }
            else if (ring_list_isnumber(pList, i)) {
                t = (tensor_t *)(size_t)ring_list_getdouble(pList, i);
            }

            if (t != NULL) {
                int size = t->size;
                double *data = t->data;
                
                #pragma omp parallel for if(size > 5000)
                for (k = 0; k < size; k++) {
                    data[k] *= scale;
                }
            }
        }
    }
    
    //  Debug output
    //if (clipped) {
    //    printf("[CLIP] Norm %.2f > %.2f → scaled by %.4f (tensors: %d)\n", 
    //           total_norm, max_norm, scale, valid_tensors);
    //}
    
    RING_API_RETNUMBER(total_norm);
}

/*
** GELU Activation (Gaussian Error Linear Unit)
** Used in GPT/BERT. Smooth non-linearity.
** Approximation: 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715 * x^3)))
*/
RING_FUNC(ring_tensor_gelu) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);

    #ifdef USE_OPENCL
    if (gpu_ready && T->size > GPU_THRESHOLD) {
        if (gpu_gelu(T)) return;
    }
    #endif

    int i;
    int size = T->size;
    double x, cube, inner;
    
    // Constants
    const double SQRT_2_OVER_PI = 0.7978845608;
    const double COEF = 0.044715;

    #pragma omp parallel for if(size > 2000) private(x, cube, inner)
    for(i=0; i<size; i++) {
        x = T->data[i];
        cube = x * x * x;
        inner = SQRT_2_OVER_PI * (x + COEF * cube);
        T->data[i] = 0.5 * x * (1.0 + tanh(inner));
    }
}

/*
** GELU Derivative (Gradient)
** Backward pass for GELU.
** Formula is complex, essentially: 0.5 [1 + tanh(y) + x * (1 - tanh(y)^2) * dy/dx]
*/
RING_FUNC(ring_tensor_gelu_prime) {
    tensor_t *T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    int i;
    int size = T->size;
    double x, x3, inner, tanh_inner, sech2;
    
    const double SQRT_2_OVER_PI = 0.7978845608;
    const double COEF = 0.044715;

    #pragma omp parallel for if(size > 2000) private(x, x3, inner, tanh_inner, sech2)
    for(i=0; i<size; i++) {
        x = T->data[i];
        x3 = x * x * x;
        inner = SQRT_2_OVER_PI * (x + COEF * x3);
        tanh_inner = tanh(inner);
        
        // Sech^2(x) = 1 - tanh^2(x)
        sech2 = 1.0 - (tanh_inner * tanh_inner);
        
        // Derivative logic
        double term1 = 0.5 * (1.0 + tanh_inner);
        double term2 = 0.5 * x * sech2 * SQRT_2_OVER_PI * (1.0 + 3.0 * COEF * x * x);
        
        T->data[i] = term1 + term2;
    }
}

/*
** Sum of Squares (Helper for L2 Norm Calculation)
** Returns: Sum(x^2)
*/
RING_FUNC(ring_tensor_sum_squares) {
    tensor_t *T;
    if (RING_API_PARACOUNT != 1) { RING_API_ERROR(RING_API_MISS1PARA); return; }
    T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    RING_API_RETNUMBER(internal_sum_squares(T));
}

/*
** Clip Tensor Values (In-place)
** Clips all values in tensor to [-max_val, +max_val]
*/
RING_FUNC(ring_tensor_clip_tensor) {
    tensor_t *T;
    double max_val;
    if (RING_API_PARACOUNT != 2) { RING_API_ERROR(RING_API_MISS2PARA); return; }
    T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    max_val = RING_API_GETNUMBER(2);
    internal_clip_tensor(T, -max_val, max_val);
}

/*
** Simplified Multi-Head Attention Backward
** Fast approximation that just redistributes gradients with proper scaling
*/
RING_FUNC(ring_tensor_mha_backward_fast) {
    tensor_t *grad_concat, *grad_input;
    int num_heads;
    double clip_norm;
    int i;
    
    if (RING_API_PARACOUNT != 4) {
        RING_API_ERROR("Usage: mha_backward_fast(grad_concat, grad_input, num_heads, clip_norm)");
        return;
    }
    
    grad_concat = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    grad_input  = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    num_heads   = (int)RING_API_GETNUMBER(3);
    clip_norm   = RING_API_GETNUMBER(4);
    
    // ════════════════════════════════════════════════
    // STEP 1: Clip concat gradient
    // ════════════════════════════════════════════════
    double norm_sq = 0.0;
    
    #pragma omp parallel for reduction(+:norm_sq)
    for(i = 0; i < grad_concat->size; i++) {
        norm_sq += grad_concat->data[i] * grad_concat->data[i];
    }
    
    double norm = sqrt(norm_sq);
    
    if (norm > clip_norm) {
        double scale = clip_norm / (norm + 1e-8);
        #pragma omp parallel for
        for(i = 0; i < grad_concat->size; i++) {
            grad_concat->data[i] *= scale;
        }
    }
    
    // ════════════════════════════════════════════════
    // STEP 2: Simple gradient redistribution
    // Scale by 1/sqrt(num_heads * 3) and copy
    // ════════════════════════════════════════════════
    double dist_scale = 1.0 / sqrt((double)(num_heads * 3));
    
    // Assuming grad_input and grad_concat have same size (simplified)
    // In practice, there's a projection but we approximate here
    
    int min_size = (grad_concat->size < grad_input->size) ? 
                   grad_concat->size : grad_input->size;
    
    #pragma omp parallel for
    for(i = 0; i < min_size; i++) {
        // Distribute to input (approximating Q, K, V backward)
        grad_input->data[i] = grad_concat->data[i] * dist_scale * 3.0;
    }
    
    // ════════════════════════════════════════════════
    // STEP 3: Clip output gradient
    // ════════════════════════════════════════════════
    norm_sq = 0.0;
    
    #pragma omp parallel for reduction(+:norm_sq)
    for(i = 0; i < grad_input->size; i++) {
        norm_sq += grad_input->data[i] * grad_input->data[i];
    }
    
    norm = sqrt(norm_sq);
    
    if (norm > clip_norm) {
        double scale = clip_norm / (norm + 1e-8);
        #pragma omp parallel for
        for(i = 0; i < grad_input->size; i++) {
            grad_input->data[i] *= scale;
        }
    }
    
    // Return final norm for monitoring
    RING_API_RETNUMBER(norm);
}

/*
** Repeat Tensor Rows (Tiling/Broadcasting)
** Copies the entire Src tensor content 'nTimes' into Dest.
** Used for Positional Embeddings Broadcasting.
** Optimization: Uses Block Memcpy.
*/
void internal_repeat_rows(tensor_t *Src, tensor_t *Dest, int nTimes) {
    size_t chunk_bytes = Src->size * sizeof(double);
    int i;
    #pragma omp parallel for if(nTimes > 4)
    for (i = 0; i < nTimes; i++) {
        memcpy(&Dest->data[i * Src->size], Src->data, chunk_bytes);
    }
}

RING_FUNC(ring_tensor_repeat_rows) {
    tensor_t *Src, *Dest;
    int nTimes;

    if (RING_API_PARACOUNT != 3) {
        RING_API_ERROR(RING_API_MISS3PARA);
        return;
    }

    Src = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    Dest = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    nTimes = (int)RING_API_GETNUMBER(3);

    // Validation
    if (Dest->size != Src->size * nTimes) {
        RING_API_ERROR("Repeat Rows: Destination size mismatch");
        return;
    }

    internal_repeat_rows(Src, Dest, nTimes);
}

/*
** Create Tensor from Raw Memory Address
** Usage: tensor_from_memory(nAddress, nRows, nCols)
*/
RING_FUNC(ring_tensor_from_memory) {
    if (RING_API_PARACOUNT != 3) {
        RING_API_ERROR(RING_API_MISS3PARA);
        return;
    }

    // 1. Get Address as Number (size_t)
    size_t address = (size_t)RING_API_GETNUMBER(1);
    int rows = (int)RING_API_GETNUMBER(2);
    int cols = (int)RING_API_GETNUMBER(3);

    // 2. Allocate Struct Wrapper
    tensor_t *t = (tensor_t *)malloc(sizeof(tensor_t));
    if (!t) { RING_API_ERROR("Malloc Fail"); return; }

    // 3. Point to External Memory
    t->data = (double *)address;
    t->rows = rows;
    t->cols = cols;
    t->size = rows * cols;
    t->is_owner = 0; // Important: we don't own this memory

    RING_API_RETCPOINTER(t, RING_VM_POINTER_TENSOR);
}

void internal_attention_linear_causal(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale, int batch) {
    int seq_len = Q->rows / batch;
    int dim = Q->cols;
    int b, t, i, j;
    #pragma omp parallel for private(b, t, i, j)
    for (b = 0; b < batch; b++) {
        int offset = b * seq_len * dim;
        double *S = (double *)calloc(dim * dim, sizeof(double));
        double *Z = (double *)calloc(dim, sizeof(double));
        if (!S || !Z) continue;
        for (t = 0; t < seq_len; t++) {
            double *qt = &Q->data[offset + t*dim];
            double *kt = &K->data[offset + t*dim];
            double *vt = &V->data[offset + t*dim];
            double *ot = &Out->data[offset + t*dim];
            for (i = 0; i < dim; i++) {
                double k_val = kt[i];
                Z[i] += k_val;
                for (j = 0; j < dim; j++) S[i * dim + j] += k_val * vt[j];
            }
            double den = 0.0;
            for (i = 0; i < dim; i++) den += qt[i] * Z[i];
            if (den < 1e-6) den = 1e-6;
            for (j = 0; j < dim; j++) {
                double num = 0.0;
                for (i = 0; i < dim; i++) num += qt[i] * S[i * dim + j];
                ot[j] = (num / den) * scale;
            }
        }
        free(S); free(Z);
    }
}

void internal_attention_linear_optimized(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale, int batch) {
    int seq = Q->rows / batch;
    int dim = Q->cols;
    int b, i, j, k, ii, jj, kk;
    #pragma omp parallel for private(b, i, j, k, ii, jj, kk)
    for (b = 0; b < batch; b++) {
        double *Context = (double *)calloc(dim * dim, sizeof(double));
        double *qb = &Q->data[b * seq * dim];
        double *kb = &K->data[b * seq * dim];
        double *vb = &V->data[b * seq * dim];
        double *ob = &Out->data[b * seq * dim];
        for (ii = 0; ii < dim; ii += TILE_SIZE) {
            for (kk = 0; kk < seq; kk += TILE_SIZE) {
                for (jj = 0; jj < dim; jj += TILE_SIZE) {
                    int i_lim = (ii + TILE_SIZE < dim) ? ii + TILE_SIZE : dim;
                    int k_lim = (kk + TILE_SIZE < seq) ? kk + TILE_SIZE : seq;
                    int j_lim = (jj + TILE_SIZE < dim) ? jj + TILE_SIZE : dim;
                    for (i = ii; i < i_lim; i++) {
                        for (k = kk; k < k_lim; k++) {
                            double k_val = kb[k * dim + i];
                            for (j = jj; j < j_lim; j++) Context[i * dim + j] += k_val * vb[k * dim + j];
                        }
                    }
                }
            }
        }
        for (ii = 0; ii < seq; ii += TILE_SIZE) {
            for (kk = 0; kk < dim; kk += TILE_SIZE) {
                for (jj = 0; jj < dim; jj += TILE_SIZE) {
                    int i_lim = (ii + TILE_SIZE < seq) ? ii + TILE_SIZE : seq;
                    int k_lim = (kk + TILE_SIZE < dim) ? kk + TILE_SIZE : dim;
                    int j_lim = (jj + TILE_SIZE < dim) ? jj + TILE_SIZE : dim;
                    for (i = ii; i < i_lim; i++) {
                        for (k = kk; k < k_lim; k++) {
                            double q_val = qb[i * dim + k];
                            for (j = jj; j < j_lim; j++) ob[i * dim + j] += q_val * Context[k * dim + j] * scale;
                        }
                    }
                }
            }
        }
        free(Context);
    }
}

void internal_attention_linear_backward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *G, tensor_t *dQ, tensor_t *dK, tensor_t *dV, double scale, int batch) {
    int dim = Q->cols;
    int seq = Q->rows / batch;
    int b, t, i, j;
    #pragma omp parallel for private(b, t, i, j)
    for (b = 0; b < batch; b++) {
        int offset = b * seq * dim;
        double *S_History = (double *)malloc(seq * dim * dim * sizeof(double));
        double *S = (double *)calloc(dim * dim, sizeof(double));
        for (t = 0; t < seq; t++) {
            double *kt = &K->data[offset + t*dim];
            double *vt = &V->data[offset + t*dim];
            for (i = 0; i < dim; i++) {
                for (j = 0; j < dim; j++) S[i*dim + j] += kt[i] * vt[j];
            }
            memcpy(&S_History[t*dim*dim], S, dim*dim*sizeof(double));
        }
        free(S);
        double *dS = (double *)calloc(dim * dim, sizeof(double));
        for (t = seq - 1; t >= 0; t--) {
            double *qt  = &Q->data[offset + t*dim];
            double *kt  = &K->data[offset + t*dim];
            double *vt  = &V->data[offset + t*dim];
            double *gt  = &G->data[offset + t*dim];
            double *dqt = &dQ->data[offset + t*dim];
            double *dkt = &dK->data[offset + t*dim];
            double *dvt = &dV->data[offset + t*dim];
            double *St = &S_History[t*dim*dim];
            for (i = 0; i < dim; i++) {
                double val = 0.0;
                for (j = 0; j < dim; j++) val += gt[j] * St[i*dim + j];
                dqt[i] = val * scale;
            }
            for (i = 0; i < dim; i++) {
                for (j = 0; j < dim; j++) dS[i*dim + j] += qt[i] * gt[j];
            }
            for (i = 0; i < dim; i++) {
                double val = 0.0;
                for (j = 0; j < dim; j++) val += dS[i*dim + j] * vt[j];
                dkt[i] = val * scale;
            }
            for (i = 0; i < dim; i++) {
                double val = 0.0;
                for (j = 0; j < dim; j++) val += dS[j*dim + i] * kt[j];
                dvt[i] = val * scale;
            }
        }
        free(S_History); free(dS);
    }
}

void internal_attention_linear_global_backward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *dOut, tensor_t *dQ, tensor_t *dK, tensor_t *dV, double scale, int batch) {
    int seq = Q->rows / batch;
    int dim = Q->cols;
    int b, t, i, j;
    #pragma omp parallel for private(b, t, i, j)
    for (b = 0; b < batch; b++) {
        int offset = b * seq * dim;
        double *C_mat  = (double *)calloc(dim * dim, sizeof(double));
        double *dC_mat = (double *)calloc(dim * dim, sizeof(double));
        if (!C_mat || !dC_mat) continue;
        for (t = 0; t < seq; t++) {
            double *kt = &K->data[offset + t*dim];
            double *vt = &V->data[offset + t*dim];
            double *qt = &Q->data[offset + t*dim];
            double *gt = &dOut->data[offset + t*dim];
            for (i = 0; i < dim; i++) {
                for (j = 0; j < dim; j++) {
                    C_mat[i*dim + j] += kt[i] * vt[j];
                    dC_mat[i*dim + j] += qt[i] * gt[j];
                }
            }
        }
        for (t = 0; t < seq; t++) {
            double *dqt = &dQ->data[offset + t*dim];
            double *dkt = &dK->data[offset + t*dim];
            double *dvt = &dV->data[offset + t*dim];
            double *vt = &V->data[offset + t*dim];
            double *kt = &K->data[offset + t*dim];
            double *gt = &dOut->data[offset + t*dim];
            for (i = 0; i < dim; i++) {
                double sum_dq = 0.0;
                for (j = 0; j < dim; j++) sum_dq += gt[j] * C_mat[j*dim + i];
                dqt[i] = sum_dq * scale;
                double sum_dk = 0.0;
                for (j = 0; j < dim; j++) sum_dk += vt[j] * dC_mat[j*dim + i];
                dkt[i] = sum_dk * scale;
                double sum_dv = 0.0;
                for (j = 0; j < dim; j++) sum_dv += kt[j] * dC_mat[i*dim + j];
                dvt[i] = sum_dv * scale;
            }
        }
        free(C_mat); free(dC_mat);
    }
}

RING_FUNC(ring_tensor_attention_linear_causal) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Out = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    double scale = 1.0; if (RING_API_PARACOUNT >= 5) scale = RING_API_GETNUMBER(5);
    int batch = 1; if (RING_API_PARACOUNT >= 6) batch = (int)RING_API_GETNUMBER(6);
    internal_attention_linear_causal(Q, K, V, Out, scale, batch);
}

RING_FUNC(ring_tensor_attention_linear_optimized) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Out = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    double scale = RING_API_GETNUMBER(5);
    int batch = (int)RING_API_GETNUMBER(6);
    internal_attention_linear_optimized(Q, K, V, Out, scale, batch);
}

RING_FUNC(ring_tensor_attention_linear_backward) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *G = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    tensor_t *dQ = (tensor_t *)RING_API_GETCPOINTER(5, RING_VM_POINTER_TENSOR);
    tensor_t *dK = (tensor_t *)RING_API_GETCPOINTER(6, RING_VM_POINTER_TENSOR);
    tensor_t *dV = (tensor_t *)RING_API_GETCPOINTER(7, RING_VM_POINTER_TENSOR);
    double scale = RING_API_GETNUMBER(8);
    int batch = (int)RING_API_GETNUMBER(9);
    internal_attention_linear_backward(Q, K, V, G, dQ, dK, dV, scale, batch);
}

RING_FUNC(ring_tensor_attention_linear_global_backward) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *dOut = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    tensor_t *dQ = (tensor_t *)RING_API_GETCPOINTER(5, RING_VM_POINTER_TENSOR);
    tensor_t *dK = (tensor_t *)RING_API_GETCPOINTER(6, RING_VM_POINTER_TENSOR);
    tensor_t *dV = (tensor_t *)RING_API_GETCPOINTER(7, RING_VM_POINTER_TENSOR);
    double scale = RING_API_GETNUMBER(8);
    int batch = (int)RING_API_GETNUMBER(9);
    internal_attention_linear_global_backward(Q, K, V, dOut, dQ, dK, dV, scale, batch);
}

/** Performs: Split Heads -> Attention -> Merge Heads
*/
void internal_attention_multihead(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale, int batch, int seq, int heads, int is_causal) {
    int dim = Q->cols; 
    int head_dim = dim / heads;
    int task, b, h, i, j, k;
    int total_tasks = batch * heads;
    
    #pragma omp parallel for private(task, b, h, i, j, k)
    for (task = 0; task < total_tasks; task++) {
        b = task / heads;
        h = task % heads;
        
        double scores_stack[256];
        double *scores = (seq <= 256) ? scores_stack : (double *)malloc(seq * sizeof(double));
        if (scores) {
            int batch_offset = b * seq * dim;
            int head_offset  = h * head_dim; 
            
            for (i = 0; i < seq; i++) {
                double *qi = &Q->data[batch_offset + (i * dim) + head_offset];
                double *oi = &Out->data[batch_offset + (i * dim) + head_offset];
                
                // 1. Score
                for (j = 0; j < seq; j++) {
                    if (is_causal && j > i) {
                        scores[j] = -1e9;
                        continue;
                    }
                    
                    double *kj = &K->data[batch_offset + (j * dim) + head_offset];
                    double dot = 0.0;
                    for (k = 0; k < head_dim; k++) dot += qi[k] * kj[k];
                    scores[j] = dot * scale;
                }
                
                // 2. Softmax
                double maxVal = -1e9;
                for(j=0; j<seq; j++) if(scores[j] > maxVal) maxVal = scores[j];
                
                double sum = 0.0;
                for(j=0; j<seq; j++) {
                    scores[j] = exp(scores[j] - maxVal);
                    sum += scores[j];
                }
                double invSum = 1.0 / (sum + 1e-9);
                for(j=0; j<seq; j++) scores[j] *= invSum;
                
                // 3. Output
                for (k = 0; k < head_dim; k++) oi[k] = 0.0;
                
                for (j = 0; j < seq; j++) {
                    double s = scores[j];
                    if (s < 1e-9) continue;
                    
                    double *vj = &V->data[batch_offset + (j * dim) + head_offset];
                    for (k = 0; k < head_dim; k++) {
                        oi[k] += s * vj[k];
                    }
                }
            }
            if (seq > 256) free(scores);
        }
    }
}

void internal_attention_multihead_backward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *dOut, tensor_t *dQ, tensor_t *dK, tensor_t *dV, double scale, int batch, int seq, int heads, int is_causal) {
    int dim = Q->cols;
    int head_dim = dim / heads;
    int task, b, h, i, j, k;
    int total_tasks = batch * heads;

    #pragma omp parallel for private(task, b, h, i, j, k)
    for (task = 0; task < total_tasks; task++) {
        b = task / heads;
        h = task % heads;
        
        int offset = b * seq * dim;
        int head_off = h * head_dim;
        
        double *S  = (double *)malloc(seq * seq * sizeof(double));
        double *dS = (double *)malloc(seq * seq * sizeof(double));
        
        if (S && dS) {
            // --- 1. Recompute Forward ---
            for (i = 0; i < seq; i++) {
                double *qi = &Q->data[offset + i*dim + head_off];
                
                for (j = 0; j < seq; j++) {
                    double *kj = &K->data[offset + j*dim + head_off];
                    double dot = 0.0;
                    
                    if (is_causal && j > i) {
                        S[i*seq + j] = 0.0;
                        continue; 
                    }

                    for (k = 0; k < head_dim; k++) dot += qi[k] * kj[k];
                    S[i*seq + j] = dot * scale;
                }
                
                double maxVal = -1e9;
                for (j = 0; j <= (is_causal ? i : seq-1); j++) {
                    if (S[i*seq + j] > maxVal) maxVal = S[i*seq + j];
                }
                
                double sum = 0.0;
                for (j = 0; j <= (is_causal ? i : seq-1); j++) {
                    S[i*seq + j] = exp(S[i*seq + j] - maxVal);
                    sum += S[i*seq + j];
                }
                double invSum = 1.0 / (sum + 1e-9);
                for (j = 0; j <= (is_causal ? i : seq-1); j++) {
                    S[i*seq + j] *= invSum;
                }
            }

            // --- 2. Calculate dV ---
            for (j = 0; j < seq; j++) {
                double *dvj = &dV->data[offset + j*dim + head_off];
                for (k = 0; k < head_dim; k++) dvj[k] = 0.0;

                for (i = 0; i < seq; i++) {
                    if (is_causal && j > i) continue;
                    
                    double s_val = S[i*seq + j];
                    double *doi = &dOut->data[offset + i*dim + head_off];
                    
                    for (k = 0; k < head_dim; k++) {
                        dvj[k] += s_val * doi[k];
                    }
                }
            }

            // --- 3. Calculate dS ---
            for (i = 0; i < seq; i++) {
                double *doi = &dOut->data[offset + i*dim + head_off];
                double dp_sum = 0.0;
                
                for (j = 0; j < seq; j++) {
                    if (is_causal && j > i) { dS[i*seq+j] = 0; continue; }
                    
                    double *vj = &V->data[offset + j*dim + head_off];
                    double dot = 0.0;
                    for (k = 0; k < head_dim; k++) dot += doi[k] * vj[k];
                    
                    dS[i*seq + j] = dot;
                    dp_sum += dot * S[i*seq + j];
                }
                
                for (j = 0; j < seq; j++) {
                    if (is_causal && j > i) continue;
                    double s_val = S[i*seq + j];
                    dS[i*seq + j] = s_val * (dS[i*seq + j] - dp_sum) * scale;
                }
            }

            // --- 4. Calculate dQ and dK ---
            for (i = 0; i < seq; i++) {
                double *dqi = &dQ->data[offset + i*dim + head_off];
                for (k = 0; k < head_dim; k++) dqi[k] = 0.0;

                for (j = 0; j < seq; j++) {
                    if (is_causal && j > i) continue;
                    
                    double ds_val = dS[i*seq + j];
                    double *kj = &K->data[offset + j*dim + head_off];
                    
                    for (k = 0; k < head_dim; k++) {
                        dqi[k] += ds_val * kj[k];
                    }
                }
            }

            for (j = 0; j < seq; j++) {
                double *dkj = &dK->data[offset + j*dim + head_off];
                for (k = 0; k < head_dim; k++) dkj[k] = 0.0;

                for (i = 0; i < seq; i++) {
                    if (is_causal && j > i) continue;
                    
                    double ds_val = dS[i*seq + j];
                    double *qi = &Q->data[offset + i*dim + head_off];
                    
                    for (k = 0; k < head_dim; k++) {
                        dkj[k] += ds_val * qi[k];
                    }
                }
            }
            
            free(S); free(dS);
        }
    }
}

RING_FUNC(ring_tensor_attention_multihead) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Out = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    
    double scale = RING_API_GETNUMBER(5);
    int batch    = (int)RING_API_GETNUMBER(6);
    int seq      = (int)RING_API_GETNUMBER(7);
    int heads    = (int)RING_API_GETNUMBER(8);
    int is_causal= (int)RING_API_GETNUMBER(9);
    
    internal_attention_multihead(Q, K, V, Out, scale, batch, seq, heads, is_causal);
}

RING_FUNC(ring_tensor_attention_multihead_backward) {
    tensor_t *Q = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *V = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *dOut = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    
    tensor_t *dQ = (tensor_t *)RING_API_GETCPOINTER(5, RING_VM_POINTER_TENSOR);
    tensor_t *dK = (tensor_t *)RING_API_GETCPOINTER(6, RING_VM_POINTER_TENSOR);
    tensor_t *dV = (tensor_t *)RING_API_GETCPOINTER(7, RING_VM_POINTER_TENSOR);
    
    double scale = RING_API_GETNUMBER(8);
    int batch    = (int)RING_API_GETNUMBER(9);
    int seq      = (int)RING_API_GETNUMBER(10);
    int heads    = (int)RING_API_GETNUMBER(11);
    int is_causal= (int)RING_API_GETNUMBER(12);
    
    internal_attention_multihead_backward(Q, K, V, dOut, dQ, dK, dV, scale, batch, seq, heads, is_causal);
}

/* Linear Global Attention Backward moved to internal kernel */

/*
** Set One-Hot from Raw Pointer (Turbo Scatter)
** Reads indices directly from AlQalam memory (C++ vector<double>) 
** and sets T[row, col] = val.
** Params: 1:Tensor, 2:RawPtrAddress, 3:Count, 4:Value
*/
RING_FUNC(ring_tensor_set_one_hot_ptr) {
    tensor_t *T;
    double *pIndices;
    int nCount, i;
    double val;

    if (RING_API_PARACOUNT != 4) {
        RING_API_ERROR(RING_API_MISS4PARA);
        return;
    }

    T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    
    // Get the raw memory address passed from Ring (AlQalam.getRawPointer)
    size_t ptrAddr = (size_t)RING_API_GETNUMBER(2);
    pIndices = (double *)ptrAddr;
    
    nCount = (int)RING_API_GETNUMBER(3);
    val = RING_API_GETNUMBER(4);

    if (pIndices == NULL) return;
    
    // Limit to Tensor rows to prevent overflow
    // We assume the tensor is flattened (Batch*Seq, Vocab)
    if (nCount > T->rows) nCount = T->rows;

    // Parallel Scatter
    #pragma omp parallel for if(nCount > 5000)
    for(i = 0; i < nCount; i++) {
        // Read index directly from C++ memory
        int col_idx = (int)pIndices[i];
        
        // Validate Bounds (1-based index)
        if (col_idx >= 1 && col_idx <= T->cols) {
            // Row i, Col (col_idx-1)
            T->data[i * T->cols + (col_idx - 1)] = val;
        }
    }
}

/*
** Get Raw Data Pointer
** Returns the actual memory address of the array as a double number to be passed to AlQalam
*/
RING_FUNC(ring_tensor_get_data_ptr) {
    tensor_t *t;
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    if (t == NULL || t->data == NULL) {
        RING_API_RETNUMBER(0);
        return;
    }
    
    // Returns the actual memory address of the array as a double number
    RING_API_RETNUMBER((double)(size_t)t->data);
}




/* ========================================================================== */
/* GRAPH API IMPLEMENTATION                                                   */
/* ========================================================================== */


/* ====================================================================
** Upgrade 3: Arena-backed Graph Initialization
** ====================================================================
** On init, we allocate (or reset) the 256MB arena.
** All intermediate tensors during forward/backward are served from this
** pool, eliminating thousands of malloc/free calls per epoch.
** ==================================================================== */
RING_FUNC(ring_graph_init) {
    int i;
    
    /* --- Free existing nodes --- */
    for(i=0; i<GRAPH_SIZE; i++) {
        if (GRAPH[i] != NULL) {
            /* Free tensors if they were allocated by the graph.
            ** Upgrade 3: Only free data if the tensor owns it (is_owner == 1).
            ** Arena-backed tensors (is_owner == 0) are freed in bulk below. */
            if (GRAPH[i]->val != NULL && GRAPH[i]->opcode != OP_WEIGHT && GRAPH[i]->opcode != OP_INPUT) {
                if (GRAPH[i]->val->is_owner && GRAPH[i]->val->data != NULL)
                    free(GRAPH[i]->val->data);
                free(GRAPH[i]->val);
            }
            if (GRAPH[i]->grad != NULL) {
                if (GRAPH[i]->grad->is_owner && GRAPH[i]->grad->data != NULL)
                    free(GRAPH[i]->grad->data);
                free(GRAPH[i]->grad);
            }
            if (GRAPH[i]->m != NULL) {
                if (GRAPH[i]->m->is_owner && GRAPH[i]->m->data != NULL)
                    free(GRAPH[i]->m->data);
                free(GRAPH[i]->m);
            }
            if (GRAPH[i]->v != NULL) {
                if (GRAPH[i]->v->is_owner && GRAPH[i]->v->data != NULL)
                    free(GRAPH[i]->v->data);
                free(GRAPH[i]->v);
            }
            free(GRAPH[i]);
        }
    }
    
    GRAPH_SIZE = 0;
    
    /* --- Upgrade 3: Initialize (or reset) the Memory Arena ---
    ** First call: allocate the 256MB block.
    ** Subsequent calls (graph rebuild): just reset the offset to 0.
    ** The block is reused across training runs without reallocation. */
    if (arena_memory == NULL) {
        arena_memory = (char *)malloc(ARENA_SIZE);
        if (arena_memory) {
            printf("[RingTensor] Memory Arena: %zu MB allocated.\n", ARENA_SIZE / (1024 * 1024));
        } else {
            printf("[RingTensor] WARNING: Arena allocation failed! Using system malloc.\n");
        }
    }
    arena_offset = 0;   /* Reset the bump pointer */
    arena_active = 1;   /* Enable arena for ensure_tensor_memory */
}

RING_FUNC(ring_graph_node) {
    /*
    ** Usage: node_id = ring_graph_node(opcode, src1_id, src2_id [, tensor_ptr])
    ** opcode: من enum OpCode
    **src1_id, src2_id: Parent node IDs (-1 if none exists)
    ** tensor_ptr: Optional - for nodes of type OP_WEIGHT or OP_INPUT
    */
    
    if (GRAPH_SIZE >= MAX_NODES) {
        RING_API_ERROR("Graph size limit reached");
        return;
    }
    
    int opcode = (int)RING_API_GETNUMBER(1);
    int src1 = (int)RING_API_GETNUMBER(2);
    int src2 = (int)RING_API_GETNUMBER(3);
    // 2. Reading additional transactions (optional)
    int src3 = -1;
    double param = 0.0;
    int heads = 1;
    int causal = 0;
    int batch = 1;
    int seq = 1;
    
    if (RING_API_PARACOUNT >= 4) {
        if (RING_API_ISNUMBER(4)) src3 = (int)RING_API_GETNUMBER(4);
    }
    
    double input_param = 0.0;
    if (RING_API_PARACOUNT >= 5) {
        if (RING_API_ISNUMBER(5)) input_param = RING_API_GETNUMBER(5);
    }
    if (RING_API_PARACOUNT >= 6) {
        if (RING_API_ISNUMBER(6)) heads = (int)RING_API_GETNUMBER(6);
    }

    if (RING_API_PARACOUNT >= 7) {
        if (RING_API_ISNUMBER(7)) causal = (int)RING_API_GETNUMBER(7);
    }

    if (RING_API_PARACOUNT >= 8) {
        if (RING_API_ISNUMBER(8)) batch = (int)RING_API_GETNUMBER(8);
    }

    if (RING_API_PARACOUNT >= 9) {
        if (RING_API_ISNUMBER(9)) seq = (int)RING_API_GETNUMBER(9);
    }
    
    int attn_type = 0;
    if (RING_API_PARACOUNT >= 10) {
        if (RING_API_ISNUMBER(10)) attn_type = (int)RING_API_GETNUMBER(10);
    }

    GraphNode *node = (GraphNode*)calloc(1, sizeof(GraphNode));
    node->id = GRAPH_SIZE;
    node->opcode = opcode;
    node->src1_id = src1;
    node->src2_id = src2;
    node->src3_id = src3; 
    node->params[0] = input_param; // We put the value coming from Ring in box 0 (or as you use it).
    node->params[1] = 0.0;         // We use it for the time counter t in Adam
    node->params[2] = 0.0;
    node->params[3] = 0.0;  
    node->heads = heads;
    node->causal = causal;
    node->batch = batch;
    node->seq = seq;
    node->attn_type = attn_type;
    node->val = NULL;
    node->grad = NULL;
    node->m = NULL;
    node->v = NULL;
    node->trainable = 0;

    if (opcode == OP_WEIGHT) {
        node->trainable = 1; // This is a weight, therefore it is always trainable.
    } else {
        node->trainable = 0;
    }

    // If the node is of type WEIGHT or INPUT, we take the pointer from Ring.
    if (opcode == OP_WEIGHT || opcode == OP_INPUT) {
        if (RING_API_PARACOUNT >= 4 && RING_API_ISCPOINTER(4)) {
            node->val = (tensor_t*)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
            if (opcode == OP_WEIGHT) node->trainable = 1;
            
            // Allocating memory for gradient and optimizer states
            ensure_tensor_memory(&node->grad, node->val->rows, node->val->cols);
            ensure_tensor_memory(&node->m, node->val->rows, node->val->cols);
            ensure_tensor_memory(&node->v, node->val->rows, node->val->cols);
        }
    }
    
    GRAPH[GRAPH_SIZE++] = node;
    RING_API_RETNUMBER(node->id);
}

RING_FUNC(ring_graph_set_input) {
    /*
    ** Usage: ring_graph_set_input(node_id, tensor_ptr)
    ** Assigning input data to a specific node
    */
    
    int node_id = (int)RING_API_GETNUMBER(1);
    tensor_t *data = (tensor_t*)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    
    if (node_id < 0 || node_id >= GRAPH_SIZE) {
        RING_API_ERROR("Invalid node ID");
        return;
    }
    
    GRAPH[node_id]->val = data;
}

RING_FUNC(ring_graph_get_output) {
    /*
    ** Usage: tensor_ptr = ring_graph_get_output(node_id)
    ** Obtaining the output of a specific node
    */
    
    int node_id = (int)RING_API_GETNUMBER(1);
    
    if (node_id < 0 || node_id >= GRAPH_SIZE) {
        RING_API_ERROR("Invalid node ID");
        return;
    }
    
    RING_API_RETCPOINTER(GRAPH[node_id]->val, RING_VM_POINTER_TENSOR);
}

void internal_graph_forward() {
    int i;
    GraphNode *node, *src1, *src2, *src3;
    
    for(i=0; i<GRAPH_SIZE; i++) {
        node = GRAPH[i];
        
        // Get parent nodes
        src1 = (node->src1_id >= 0) ? GRAPH[node->src1_id] : NULL;
        src2 = (node->src2_id >= 0) ? GRAPH[node->src2_id] : NULL;
        src3 = (node->src3_id >= 0) ? GRAPH[node->src3_id] : NULL;
        
        if (node->opcode == OP_INPUT || node->opcode == OP_WEIGHT) continue;
        
        switch(node->opcode) {
            case OP_ADD:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    if (src2 && src2->val) {
                        internal_add(node->val, src2->val);
                    }
                }
                break;
                
            case OP_SUB:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    if (src2 && src2->val) {
                        internal_sub(node->val, src2->val);
                    }
                }
                break;
                
            case OP_TENSOR_MUL:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    if (src2 && src2->val) {
                        internal_mul_elem(node->val, src2->val);
                    }
                }
                break;

            case OP_TENSOR_DIV:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    if (src2 && src2->val) {
                        internal_div(node->val, src2->val);
                    }
                }
                break;

            case OP_SCALAR_MUL:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_scalar_mul(node->val, node->params[0]);
                }
                break;

            case OP_ADD_SCALAR:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_add_scalar(node->val, node->params[0]);
                }
                break;

            case OP_SUB_SCALAR:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_sub_scalar(node->val, node->params[0]);
                }
                break;
                
            case OP_MATMUL:
                if (src1 && src2) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src2->val->cols);
                    internal_matmul(src1->val, src2->val, node->val);
                }
                break;
                
            case OP_RELU:
                if (src1) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_relu(node->val);
                }
                break;
                
            case OP_SIGMOID:
                if (src1) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_sigmoid(node->val);
                }
                break;
                
            case OP_TANH:
                if (src1) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_tanh_activation(node->val);
                }
                break;
                
            case OP_GELU:
                if (src1) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_gelu(node->val);
                }
                break;
                
            case OP_SOFTMAX:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_softmax(node->val);
                }
                break;

            case OP_SQUARE:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_square(node->val);
                }
                break;

            case OP_SQRT:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_sqrt_tensor(node->val);
                }
                break;

            case OP_EXP:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_exp(node->val);
                }
                break;
                
            case OP_TRANSPOSE:
                if (src1) {
                    ensure_tensor_memory(&node->val, src1->val->cols, src1->val->rows);
                    internal_transpose(src1->val, node->val);
                }
                break;
                
            case OP_MSE:
                if (src1 && src2) {
                    ensure_tensor_memory(&node->val, 1, 1);
                    double loss = internal_mse_loss(src1->val, src2->val);
                    node->val->data[0] = loss;
                }
                break;
                
            case OP_CROSSENTROPY:
                if (src1 && src2) {
                    ensure_tensor_memory(&node->val, 1, 1);
                    double loss = internal_crossentropy_loss(src1->val, src2->val);
                    node->val->data[0] = loss;
                }
                break;
                
            case OP_EMBEDDING:
                if (src1 && src1->val && src2 && src2->val) {
                    int batch = src2->val->rows;
                    int seq = src2->val->cols;
                    int dim = src1->val->cols;
                    ensure_tensor_memory(&node->val, batch * seq, dim);
                    node->val->rows = batch * seq; 
                    node->val->cols = dim; 
                    internal_embedding_forward(src1->val, src2->val, node->val);
                }
                break;
                
            case OP_LAYERNORM:
                if (src1 && src1->val && src2 && src2->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    double eps = node->params[0];
                    if (eps == 0.0) eps = 1e-5;
                    
                    tensor_t *beta_tensor = NULL;
                    int owns_beta = 0;
                    if (src3 && src3->val) {
                        beta_tensor = src3->val;
                    } else {
                        beta_tensor = (tensor_t*)calloc(1, sizeof(tensor_t));
                        beta_tensor->rows = 1; beta_tensor->cols = src1->val->cols; beta_tensor->size = src1->val->cols;
                        beta_tensor->data = (double*)calloc(beta_tensor->size, sizeof(double));
                        owns_beta = 1;
                    }
                    internal_layernorm(node->val, src2->val, beta_tensor, eps);
                    if (owns_beta) {
                        free(beta_tensor->data); free(beta_tensor);
                    }
                }
                break;
                
            case OP_DROPOUT:
                if (src1) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    ensure_tensor_memory(&node->m, src1->val->rows, src1->val->cols);
                    double rate = node->params[0];
                    if (rate < 0.0) rate = 0.0;
                    if (rate >= 1.0) rate = 0.9;
                    int i;
                    double scale = 1.0 / (1.0 - rate);
                    for(i=0; i<node->val->size; i++) {
                        double r = (double)rand() / RAND_MAX;
                        if (r < rate) {
                            node->val->data[i] = 0.0;
                            node->m->data[i] = 0.0;
                        } else {
                            node->val->data[i] *= scale;
                            node->m->data[i] = 1.0;
                        }
                    }
                }
                break;
                
            case OP_ADD_ROW_VEC:
                if (src1 && src2) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, node->val);
                    internal_add_row_vec(node->val, src2->val);
                }
                break;
                
            case OP_ATTENTION:
                if (src1 && src2 && src3) {
                    ensure_tensor_memory(&node->val, src1->val->rows, src1->val->cols);
                    if (node->attn_type == 1) { // Linear Causal
                        internal_attention_linear_causal(src1->val, src2->val, src3->val, node->val, node->params[0], node->batch);
                    } else if (node->attn_type == 2) { // Linear Global
                        internal_attention_linear_optimized(src1->val, src2->val, src3->val, node->val, node->params[0], node->batch);
                    } else { // Standard Multi-Head
                        internal_attention_multihead(
                            src1->val, src2->val, src3->val, node->val,
                            node->params[0], node->batch, node->seq, node->heads, node->causal
                        );
                    }
                }
                break;
                
            case OP_SUM:
                if (src1 && src1->val) {
                    int axis = (int)node->params[0];
                    int out_rows = (axis == 1) ? src1->val->rows : 1;
                    int out_cols = (axis == 0) ? src1->val->cols : 1;
                    ensure_tensor_memory(&node->val, out_rows, out_cols);
                    internal_sum(src1->val, axis, node->val);
                }
                break;

            case OP_MEAN:
                if (src1 && src1->val) {
                    int axis = (int)node->params[0];
                    int out_rows = (axis == 1) ? src1->val->rows : 1;
                    int out_cols = (axis == 0) ? src1->val->cols : 1;
                    ensure_tensor_memory(&node->val, out_rows, out_cols);
                    internal_mean(src1->val, axis, node->val);
                }
                break;

            case OP_ARGMAX:
                if (src1 && src1->val) {
                    ensure_tensor_memory(&node->val, src1->val->rows, 1);
                    internal_argmax_rowwise(src1->val, node->val);
                }
                break;

            case OP_REPEAT_ROWS:
                if (src1 && src1->val) {
                    int nTimes = (int)node->params[0];
                    ensure_tensor_memory(&node->val, src1->val->rows * nTimes, src1->val->cols);
                    internal_repeat_rows(src1->val, node->val, nTimes);
                }
                break;
                
            default:
                break;
        }
    }
}

RING_FUNC(ring_graph_forward) {
    internal_graph_forward();
}

/*
** Accumulate Gradient safely
** Adds 'src_grad' to 'node->grad'. Allocates memory if needed.
*/
void accumulate_grad(GraphNode *node, tensor_t *src_grad) {
    if (node == NULL || src_grad == NULL) return;

    // --- DEBUG SPY ---
   /* static int print_count = 0;
    if (print_count < 5) {     // We only print the first 5 transfers.
        double sum = 0;
        for(int k=0; k<src_grad->size; k++) sum += fabs(src_grad->data[k]);
        
        printf(">> ACCUMULATE: Node %d (Op %d) <- Grad Sum: %f\n", 
               node->id, node->opcode, sum);
               
        if (sum > 0) print_count++; 
    }*/
    // -----------------

    if (node->grad == NULL) {
        ensure_tensor_memory(&node->grad, src_grad->rows, src_grad->cols);
        size_t bytes = src_grad->size * sizeof(double);
        memcpy(node->grad->data, src_grad->data, bytes);
    } else {
        int i;
        if (node->grad->size != src_grad->size) {
            printf("ERROR: Grad Accumulate Size Mismatch Node %d\n", node->id);
            return; 
        }
        
        double *dst = node->grad->data;
        double *src = src_grad->data;
        
        #pragma omp parallel for if(src_grad->size > 2000)
        for(i=0; i<src_grad->size; i++) {
            dst[i] += src[i];
        }
    }
}

void internal_graph_backward() {
    int i;
    GraphNode *node, *src1, *src2, *src3;
    tensor_t *tmp1 = NULL, *tmp2 = NULL, *tmp3 = NULL;

    // 1. Zero out all existing gradients
    for(i=0; i<GRAPH_SIZE; i++) {
        if (GRAPH[i]->grad) {
            internal_fill(GRAPH[i]->grad, 0.0);
        }
    }

    // 2. Reverse Topological Traversal
    for(i=GRAPH_SIZE-1; i>=0; i--) {
        node = GRAPH[i];
        
        src1 = (node->src1_id >= 0) ? GRAPH[node->src1_id] : NULL;
        src2 = (node->src2_id >= 0) ? GRAPH[node->src2_id] : NULL;
        src3 = (node->src3_id >= 0) ? GRAPH[node->src3_id] : NULL;
        switch(node->opcode) {
            // --- Loss Functions ---
            case OP_MSE:
                if (src1 && src2) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    internal_mse_backward(src1->val, src2->val, tmp1);
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;

            case OP_CROSSENTROPY:
                if (src1 && src2) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    internal_crossentropy_backward(src1->val, src2->val, tmp1);
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;

            // --- Math Operations ---
            case OP_ADD:
                if (node->grad) {
                    if (src1) accumulate_grad(src1, node->grad);
                    if (src2) accumulate_grad(src2, node->grad);
                }
                break;

            case OP_SUB:
                if (node->grad) {
                    if (src1) accumulate_grad(src1, node->grad);
                    if (src2) {
                        ensure_temp_memory(&tmp1, node->grad->rows, node->grad->cols);
                        copy_tensor(node->grad, tmp1);
                        internal_scalar_mul(tmp1, -1.0);
                        accumulate_grad(src2, tmp1);
                        free(tmp1->data); free(tmp1); tmp1 = NULL;
                    }
                }
                break;

            case OP_TENSOR_MUL:
                if (node->grad) {
                    if (src1 && src2) {
                        ensure_temp_memory(&tmp1, node->grad->rows, node->grad->cols);
                        copy_tensor(node->grad, tmp1);
                        internal_mul_elem(tmp1, src2->val);
                        accumulate_grad(src1, tmp1);
                        copy_tensor(node->grad, tmp1);
                        internal_mul_elem(tmp1, src1->val);
                        accumulate_grad(src2, tmp1);
                        free(tmp1->data); free(tmp1); tmp1 = NULL;
                    } else if (src1) {
                        accumulate_grad(src1, node->grad);
                    }
                }
                break;

            case OP_MATMUL:
                if (src1 && src2) {
                    if (node->grad) {
                        ensure_temp_memory(&tmp1, src2->val->cols, src2->val->rows);
                        internal_transpose(src2->val, tmp1);
                        ensure_temp_memory(&tmp2, src1->val->rows, src1->val->cols);
                        internal_matmul(node->grad, tmp1, tmp2);
                        accumulate_grad(src1, tmp2);
                        free(tmp1->data); free(tmp1); tmp1 = NULL;
                        free(tmp2->data); free(tmp2); tmp2 = NULL;
                        ensure_temp_memory(&tmp1, src1->val->cols, src1->val->rows);
                        internal_transpose(src1->val, tmp1);
                        ensure_temp_memory(&tmp2, src2->val->rows, src2->val->cols);
                        internal_matmul(tmp1, node->grad, tmp2);
                        accumulate_grad(src2, tmp2);
                        free(tmp1->data); free(tmp1); tmp1 = NULL;
                        free(tmp2->data); free(tmp2); tmp2 = NULL;
                    }
                }
                break;
            
            case OP_SCALAR_MUL:
                // y = x * c  --> dy/dx = dy * c
                if (node->grad && src1) {
                    ensure_temp_memory(&tmp1, node->grad->rows, node->grad->cols);
                    copy_tensor(node->grad, tmp1);
                    internal_scalar_mul(tmp1, node->params[0]); // Multiply grad by scalar
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;

            case OP_ADD_SCALAR:
                // y = x + c --> dy/dx = dy
                if (node->grad && src1) {
                    accumulate_grad(src1, node->grad);
                }
                break;

            case OP_SUB_SCALAR:
                // y = x - c --> dy/dx = dy
                if (node->grad && src1) {
                    accumulate_grad(src1, node->grad);
                }
                break;

            case OP_TENSOR_DIV: // Tensor Div
                 // y = a / b
                 // da = dy / b
                 // db = -dy * a / b^2
                 // (Implementing just da for now as usually div is not used on weights directly in simple models)
                 // But for completeness:
                 if (node->grad && src1 && src2) {
                     // dSrc1
                     ensure_temp_memory(&tmp1, node->grad->rows, node->grad->cols);
                     copy_tensor(node->grad, tmp1);
                     internal_div(tmp1, src2->val); // grad / src2
                     accumulate_grad(src1, tmp1);
                     free(tmp1->data); free(tmp1); tmp1 = NULL;
                     
                     // dSrc2 (Complex, skipping for now unless needed)
                 }
                 break;

            case OP_TRANSPOSE:
                if (node->grad && src1) {
                    ensure_temp_memory(&tmp1, node->grad->cols, node->grad->rows);
                    internal_transpose(node->grad, tmp1);
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;

            // --- Activations ---
            case OP_RELU:
                if (node->grad && src1) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, tmp1);
                    internal_relu_prime(tmp1);
                    internal_mul_elem(tmp1, node->grad);
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
                
            case OP_SIGMOID:
                if (node->grad && src1) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, tmp1);
                    internal_sigmoid_prime(tmp1);
                    internal_mul_elem(tmp1, node->grad);
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
                
            case OP_TANH:
                if (node->grad && src1) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, tmp1);
                    internal_tanh_prime(tmp1);
                    internal_mul_elem(tmp1, node->grad);
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;

             case OP_GELU:
                if (src1) {
                    ensure_tensor_memory(&node->grad, src1->val->rows, src1->val->cols);
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    copy_tensor(src1->val, tmp1);
                    internal_gelu_prime(tmp1);
                    internal_mul_elem(tmp1, node->grad);
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
                
            case OP_SOFTMAX:
                if (node->grad && src1 && node->val) { 
                    // node->val contains the Softmax output (Y), which is what we need for the equation.
                    // node->grad is (dY)
                    // tmp1 will be (dX)
                    
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    
                    // Calling the correct kernel
                    internal_softmax_backward(node->val, node->grad, tmp1);
                    
                    //Derivatives aggregation
                    accumulate_grad(src1, tmp1);
                    
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
            
            case OP_EMBEDDING:
               // Order: (dOut, Ind, dEmb)
                // node->grad is the derivative coming from the next layer (dOut)
                // src1 is the indices
                // src2 is the weights matrix (Embeddings) whose derivative we want to update (dEmb)
                
                if (node->grad && src1 && src2) {
                    // If there is no room for derivatives in the weights, we reserve it.
                    if (!src2->grad) {
                        ensure_tensor_memory(&src2->grad, src2->val->rows, src2->val->cols);
                        internal_fill(src2->grad, 0.0);
                    }
                    
                    // Correct summons
                    internal_embedding_backward(node->grad, src1->val, src2->grad);
                }
                break;
                
            case OP_LAYERNORM:
                if (src1 && src2) {
                    ensure_tensor_memory(&node->grad, src1->val->rows, src1->val->cols);
                    double eps = node->params[0];
                    if (eps == 0.0) eps = 1e-5;
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols); // dX
                    if (!src2->grad) {
                        ensure_tensor_memory(&src2->grad, src2->val->rows, src2->val->cols);
                        internal_fill(src2->grad, 0.0);
                    }
                    tensor_t *beta_tensor = NULL;
                    tensor_t *dBeta_tensor = NULL;
                    if (src3 && src3->val) {
                        beta_tensor = src3->val;
                        if (!src3->grad) {
                            ensure_tensor_memory(&src3->grad, src3->val->rows, src3->val->cols);
                            internal_fill(src3->grad, 0.0);
                        }
                        dBeta_tensor = src3->grad;
                    } else {
                        beta_tensor = (tensor_t*)calloc(1, sizeof(tensor_t));
                        beta_tensor->rows = 1; beta_tensor->cols = src1->val->cols; beta_tensor->size = src1->val->cols;
                        beta_tensor->data = (double*)calloc(beta_tensor->size, sizeof(double));
                        dBeta_tensor = (tensor_t*)calloc(1, sizeof(tensor_t));
                        dBeta_tensor->rows = 1; dBeta_tensor->cols = src1->val->cols; dBeta_tensor->size = src1->val->cols;
                        dBeta_tensor->data = (double*)calloc(dBeta_tensor->size, sizeof(double));
                    }
                    internal_layernorm_backward(node->grad, src1->val, src2->val, beta_tensor, tmp1, src2->grad, dBeta_tensor, eps);
                    accumulate_grad(src1, tmp1);
                    if (!src3 || !src3->val) {
                        free(beta_tensor->data); free(beta_tensor);
                        free(dBeta_tensor->data); free(dBeta_tensor);
                    }
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
                
            case OP_REPEAT_ROWS:
                if (src1) {
                    ensure_tensor_memory(&node->grad, node->val->rows, node->val->cols);
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    internal_fill(tmp1, 0.0);
                    int nTimes = (int)node->params[0];
                    int r, c, t;
                    for (r = 0; r < src1->val->rows; r++) {
                        for (t = 0; t < nTimes; t++) {
                            for (c = 0; c < src1->val->cols; c++) {
                                tmp1->data[r * src1->val->cols + c] += node->grad->data[(r * nTimes + t) * src1->val->cols + c];
                            }
                        }
                    }
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
                
            case OP_ADD_ROW_VEC:
                if (src1 && src2) {
                    if (node->grad) {
                        accumulate_grad(src1, node->grad);
                        ensure_temp_memory(&tmp1, 1, src2->val->cols);
                        internal_sum(node->grad, 0, tmp1);
                        accumulate_grad(src2, tmp1);
                        free(tmp1->data); free(tmp1); tmp1 = NULL;
                    }
                }
                break;
                
            case OP_ATTENTION:
                if (node->grad && src1 && src2 && src3) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols); // dQ
                    ensure_temp_memory(&tmp2, src2->val->rows, src2->val->cols); // dK
                    ensure_temp_memory(&tmp3, src3->val->rows, src3->val->cols); // dV
                    internal_fill(tmp1, 0.0);
                    internal_fill(tmp2, 0.0);
                    internal_fill(tmp3, 0.0);
                    if (node->attn_type == 1) { // Linear Causal
                        internal_attention_linear_backward(src1->val, src2->val, src3->val, node->grad, tmp1, tmp2, tmp3, node->params[0], node->batch);
                    } else if (node->attn_type == 2) { // Linear Global
                        internal_attention_linear_global_backward(src1->val, src2->val, src3->val, node->grad, tmp1, tmp2, tmp3, node->params[0], node->batch);
                    } else { // Standard Multi-Head
                        internal_attention_multihead_backward(
                             src1->val, src2->val, src3->val,
                             node->grad,
                             tmp1, tmp2, tmp3,
                             node->params[0], node->batch, node->seq, node->heads, node->causal
                        );
                    }
                    accumulate_grad(src1, tmp1);
                    accumulate_grad(src2, tmp2);
                    accumulate_grad(src3, tmp3);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                    free(tmp2->data); free(tmp2); tmp2 = NULL;
                    free(tmp3->data); free(tmp3); tmp3 = NULL;
                }
                break;
                
            case OP_DROPOUT:
                if (node->grad && src1) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    internal_dropout_backward(node->grad, tmp1, node->m, node->params[0]); 
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
                
            case OP_SUM:
                if (node->grad && src1) {
                    ensure_temp_memory(&tmp1, src1->val->rows, src1->val->cols);
                    int axis = (int)node->params[0];
                    int r, c;
                    for(r=0; r<src1->val->rows; r++) {
                        for(c=0; c<src1->val->cols; c++) {
                            int grad_idx = (axis == 1) ? r : ((axis == 0) ? c : 0);
                            tmp1->data[r * src1->val->cols + c] = node->grad->data[grad_idx];
                        }
                    }
                    accumulate_grad(src1, tmp1);
                    free(tmp1->data); free(tmp1); tmp1 = NULL;
                }
                break;
        }
    }
}

RING_FUNC(ring_graph_backward) {
    internal_graph_backward();
}

RING_FUNC(ring_graph_set_optimizer) {
    /*
    ** Usage: graph_set_optimizer(type)
    ** type: 0 for SGD, 1 for ADAM
    */
    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }
    GRAPH_OPTIMIZER = (int)RING_API_GETNUMBER(1);
}

RING_FUNC(ring_graph_run) {
    int epochs = (int)RING_API_GETNUMBER(1);
    double lr = RING_API_GETNUMBER(2);
    double max_norm = (RING_API_PARACOUNT >= 3) ? RING_API_GETNUMBER(3) : 0.0;
    
    int e, i;
    
    for(e=0; e<epochs; e++) {
        // 0. Zero Gradients
        for(i=0; i<GRAPH_SIZE; i++) {
            if (GRAPH[i]->grad) internal_fill(GRAPH[i]->grad, 0.0);
        }

        // 1. Forward
        internal_graph_forward();
        
        // 2. Backward
        internal_graph_backward();
        
        // 2.5 Gradient Clipping
        if (max_norm > 0.0) {
            double total_norm = 0.0;
            for(i=0; i<GRAPH_SIZE; i++) {
                if (GRAPH[i]->grad) {
                    for(int k=0; k<GRAPH[i]->grad->size; k++) {
                        double g = GRAPH[i]->grad->data[k];
                        total_norm += g * g;
                    }
                }
            }
            total_norm = sqrt(total_norm);
            if (total_norm > max_norm) {
                double scale = max_norm / (total_norm + 1e-6);
                for(i=0; i<GRAPH_SIZE; i++) {
                    if (GRAPH[i]->trainable && GRAPH[i]->grad) {
                        for(int k=0; k<GRAPH[i]->grad->size; k++) {
                            GRAPH[i]->grad->data[k] *= scale;
                        }
                    }
                }
            }
        }
        
        // 3. Optimizer Step
        for(i=0; i<GRAPH_SIZE; i++) {
            if (GRAPH[i]->grad && (GRAPH[i]->trainable || GRAPH[i]->opcode == 1)) {
                GRAPH[i]->params[3] += 1.0; 
                int t = (int)GRAPH[i]->params[3];
                if (GRAPH_OPTIMIZER == 1) { // ADAM
                    if (!GRAPH[i]->m) ensure_tensor_memory(&GRAPH[i]->m, GRAPH[i]->val->rows, GRAPH[i]->val->cols);
                    if (!GRAPH[i]->v) ensure_tensor_memory(&GRAPH[i]->v, GRAPH[i]->val->rows, GRAPH[i]->val->cols);
                    internal_adam_update(GRAPH[i]->val, GRAPH[i]->grad, GRAPH[i]->m, GRAPH[i]->v, lr, 0.9, 0.999, 1e-8, t);
                } else { // SGD
                    internal_sgd_update(GRAPH[i]->val, GRAPH[i]->grad, lr);
                }
            }
        }
    }
}

RING_FUNC(ring_graph_run_buffered) {
    int input_id    = (int)RING_API_GETNUMBER(1);
    int target_id   = (int)RING_API_GETNUMBER(2);
    tensor_t *big_in = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *big_tg = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    int batch_size  = (int)RING_API_GETNUMBER(5);
    int epochs      = (int)RING_API_GETNUMBER(6);
    double lr       = RING_API_GETNUMBER(7);
    double max_norm = RING_API_GETNUMBER(8);

    if (!big_in || !big_tg || input_id < 0 || target_id < 0 || input_id >= GRAPH_SIZE || target_id >= GRAPH_SIZE) {
        RING_API_RETNUMBER(0.0);
        return;
    }
    if (!GRAPH[input_id] || !GRAPH[target_id]) {
        RING_API_RETNUMBER(0.0);
        return;
    }

    int total_samples = big_in->rows;
    int seq_len       = big_in->cols;
    
    if (batch_size > total_samples) batch_size = total_samples;
    if (batch_size <= 0) { RING_API_RETNUMBER(0.0); return; }

    int num_batches   = total_samples / batch_size;
    int i, b, k, e;
    double total_loss_accum = 0.0;
    int total_steps = 0;

    // Save original pointers
    double *orig_in_ptr = GRAPH[input_id]->val->data;
    double *orig_tg_ptr = GRAPH[target_id]->val->data;

    for(e=0; e < epochs; e++) {
        for(b=0; b < num_batches; b++) {
            // 1. Update Input/Target pointers
            GRAPH[input_id]->val->data  = big_in->data + (b * batch_size * seq_len);
            GRAPH[target_id]->val->data = big_tg->data + (b * batch_size * seq_len);

            // 2. Standard Graph Step
            for(i=0; i<GRAPH_SIZE; i++) if (GRAPH[i]->grad) internal_fill(GRAPH[i]->grad, 0.0);
            
            internal_graph_forward();
            internal_graph_backward();

            // Accumulate Loss (Last Node is always Loss)
            if (GRAPH_SIZE > 0) {
                total_loss_accum += GRAPH[GRAPH_SIZE-1]->val->data[0];
                total_steps++;
            }

            // Clipping
            if (max_norm > 0.0) {
                double total_norm = 0.0;
                for(i=0; i<GRAPH_SIZE; i++) {
                    if (GRAPH[i]->grad) {
                        for(k=0; k<GRAPH[i]->grad->size; k++) total_norm += GRAPH[i]->grad->data[k] * GRAPH[i]->grad->data[k];
                    }
                }
                total_norm = sqrt(total_norm);
                if (total_norm > max_norm) {
                    double scale = max_norm / (total_norm + 1e-6);
                    for(i=0; i<GRAPH_SIZE; i++) {
                        if (GRAPH[i]->trainable && GRAPH[i]->grad) {
                            for(k=0; k<GRAPH[i]->grad->size; k++) GRAPH[i]->grad->data[k] *= scale;
                        }
                    }
                }
            }

            // Optimizer
            for(i=0; i<GRAPH_SIZE; i++) {
                if (GRAPH[i]->grad && (GRAPH[i]->trainable || GRAPH[i]->opcode == 1)) {
                    GRAPH[i]->params[3] += 1.0;
                    int t = (int)GRAPH[i]->params[3];
                    if (GRAPH_OPTIMIZER == 1) {
                        if (!GRAPH[i]->m) ensure_tensor_memory(&GRAPH[i]->m, GRAPH[i]->val->rows, GRAPH[i]->val->cols);
                        if (!GRAPH[i]->v) ensure_tensor_memory(&GRAPH[i]->v, GRAPH[i]->val->rows, GRAPH[i]->val->cols);
                        internal_adam_update(GRAPH[i]->val, GRAPH[i]->grad, GRAPH[i]->m, GRAPH[i]->v, lr, 0.9, 0.999, 1e-8, t);
                    } else {
                        internal_sgd_update(GRAPH[i]->val, GRAPH[i]->grad, lr);
                    }
                }
            }
        }
    }

    // Restore original pointers
    GRAPH[input_id]->val->data  = orig_in_ptr;
    GRAPH[target_id]->val->data = orig_tg_ptr;

    // Return the average loss
    if (total_steps > 0) {
        RING_API_RETNUMBER(total_loss_accum / total_steps);
    } else {
        RING_API_RETNUMBER(0.0);
    }
}

RING_FUNC(ring_graph_update) {
    /*
    ** Usage: graph_update(lr)
    ** perform optimizer step
    */
    double lr = RING_API_GETNUMBER(1);
    int i;
    static int step_count = 0;
    step_count++;

    for(i=0; i<GRAPH_SIZE; i++) {
        if (GRAPH[i]->trainable && GRAPH[i]->grad != NULL) {
            if (GRAPH_OPTIMIZER == 1) {
                // Adam
                if (!GRAPH[i]->m) ensure_tensor_memory(&GRAPH[i]->m, GRAPH[i]->val->rows, GRAPH[i]->val->cols);
                if (!GRAPH[i]->v) ensure_tensor_memory(&GRAPH[i]->v, GRAPH[i]->val->rows, GRAPH[i]->val->cols);
                internal_adam_update(GRAPH[i]->val, GRAPH[i]->grad, GRAPH[i]->m, GRAPH[i]->v, 
                                     lr, 0.9, 0.999, 1e-8, step_count);
            } else {
                // SGD (Default)
                internal_sgd_update(GRAPH[i]->val, GRAPH[i]->grad, lr);
            }
        }
    }
}

RING_FUNC(ring_graph_bind_memory) {
    int node_id = (int)RING_API_GETNUMBER(1);
    tensor_t *pTensor = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    
    if (GRAPH && node_id >= 0 && node_id < GRAPH_SIZE) {
        GRAPH[node_id]->val = pTensor;
        
        if (GRAPH[node_id]->opcode == OP_WEIGHT) {
             GRAPH[node_id]->trainable = 1;
             // Ensure grad is allocated if not already
             ensure_tensor_memory(&GRAPH[node_id]->grad, pTensor->rows, pTensor->cols);
        }
    }
}

RING_FUNC(ring_graph_bind_grad) {
    // 1. Get Node ID
    int node_id = (int)RING_API_GETNUMBER(1);
    
    // 2. Get Tensor Pointer
    tensor_t *pTensor = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    
    // 3. Validation & Binding
    if (GRAPH && node_id < GRAPH_SIZE) {
        GRAPH[node_id]->grad = pTensor;
    } else {
        RING_API_ERROR("Graph Bind Grad: Invalid Node ID or Graph not init");
    }
}

/* ====================================================================
** Upgrade 3: Arena-aware Graph Cleanup
** ====================================================================
** ring_graph_free releases node structs (via ring_graph_init),
** then frees the arena block and disables arena mode.
** ==================================================================== */
RING_FUNC(ring_graph_free) {
    /*
    ** Usage: ring_graph_free()
    ** Frees all graph nodes, then releases the arena.
    */
    
    /* Clean up all graph nodes (reuses init logic) */
    ring_graph_init(pPointer);
    
    /* Release the arena block and disable pooling */
    if (arena_memory != NULL) {
        free(arena_memory);
        arena_memory = NULL;
    }
    arena_offset = 0;
    arena_active = 0;
}

/* --- Missing Kernels Implementation --- */

double internal_mse_loss(tensor_t *Pred, tensor_t *Target) {
    int i;
    double sum = 0.0;
    double diff;
    for(i=0; i<Pred->size; i++) {
        diff = Pred->data[i] - Target->data[i];
        sum += diff * diff;
    }
    return sum / Pred->size;
}

/*
** Fused CrossEntropy (Logits -> Softmax -> Loss)
** This is CRITICAL for numerical stability.
*/
double internal_crossentropy_loss(tensor_t *Pred, tensor_t *Target) {
    int r, c;
    double total_loss = 0.0;
    int batch_size = Pred->rows;
    int vocab_size = Pred->cols;
    
    // Buffer for probabilities (Softmax output)
    // We can use a small row buffer to save memory or act row-by-row
    
    #pragma omp parallel for reduction(+:total_loss) private(c)
    for(r=0; r<batch_size; r++) {
        
        // 1. Compute Softmax for this row ON THE FLY
        // ------------------------------------------
        double max_val = -DBL_MAX;
        double *logit_row = &Pred->data[r * vocab_size];
        
        for(c=0; c<vocab_size; c++) {
            if(logit_row[c] > max_val) max_val = logit_row[c];
        }
        
        double sum_exp = 0.0;
        // Note: We need exp values to calculate P. 
        // To avoid allocating a full row buffer, we might do 2 passes?
        // Or allocate small buffer on stack (vocab is usually small-ish, but dangerous)
        // Better: Just calculate P for the Target Index! 
        // We only need log(P_target).
        
        for(c=0; c<vocab_size; c++) {
            sum_exp += exp(logit_row[c] - max_val);
        }
        
        double log_sum_exp = log(sum_exp + 1e-9); // LogSumExp trick with safety
        
        // 2. Calculate Loss for Target
        // Loss = -log(P_target) 
        //      = -log( exp(logit_target - max) / sum_exp )
        //      = -( (logit_target - max) - log(sum_exp) )
        //      = -logit_target + max + log_sum_exp
        // ------------------------------------------
        
        double *target_row = &Target->data[r * vocab_size];
        
        for(c=0; c<vocab_size; c++) {
            if (target_row[c] > 0.5) { // Active Target
                double logit_t = logit_row[c];
                double loss = -logit_t + max_val + log_sum_exp;
                total_loss += loss;
                break; 
            }
        }
    }
    
    return total_loss / batch_size;
}

void internal_mse_backward(tensor_t *Pred, tensor_t *Target, tensor_t *Grad) {
    int i;
    double scale = 2.0 / Pred->size;
    #pragma omp parallel for if(Pred->size > PARALLEL_THRESHOLD)
    for(i=0; i<Pred->size; i++) {
        Grad->data[i] = scale * (Pred->data[i] - Target->data[i]);
    }
}

void internal_gelu(tensor_t *T) {

    #ifdef USE_OPENCL
    // The mathematical operations in GELU are heavy, so the threshold is lower.
    if (gpu_ready && T->size > GPU_THRESHOLD) { 
        if (gpu_gelu(T)) return;
    }
    #endif
    
    int i;
    double x, cdf;
    const double sqrt2 = 1.41421356237;
    
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(x, cdf)
    for(i=0; i<T->size; i++) {
        x = T->data[i];
        cdf = 0.5 * (1.0 + erf(x / sqrt2));
        T->data[i] = x * cdf;
    }
}

void internal_gelu_prime(tensor_t *T) {
    int i;
    double x, cdf, pdf;
    const double sqrt2 = 1.41421356237;
    const double sqrt2pi = 2.50662827463;
    
    #pragma omp parallel for if(T->size > PARALLEL_THRESHOLD) private(x, cdf, pdf)
    for(i=0; i<T->size; i++) {
        x = T->data[i];
        cdf = 0.5 * (1.0 + erf(x / sqrt2));
        pdf = exp(-0.5 * x * x) / sqrt2pi;
        T->data[i] = cdf + x * pdf;
    }
}

void internal_crossentropy_backward(tensor_t *Pred, tensor_t *Target, tensor_t *Grad) {
    int r, c;
    int rows = Pred->rows;
    int cols = Pred->cols;
    double scale = 1.0 / rows;
    
    #pragma omp parallel for if(rows > 32) private(c)
    for(r=0; r<rows; r++) {
        
        // 1. Calculating Softmax for this class (very important)
        // ------------------------------------------------
        double max_val = -DBL_MAX;
        double sum_exp = 0.0;
        double *logit_row = &Pred->data[r * cols];
        double *target_row = &Target->data[r * cols];
        double *grad_row = &Grad->data[r * cols];
        
        // Find Max
        for(c=0; c<cols; c++) if(logit_row[c] > max_val) max_val = logit_row[c];
        
        // Exponentiate & Sum
        // Optimization: We can store exps in grad_row temporarily to save memory
        for(c=0; c<cols; c++) {
            grad_row[c] = exp(logit_row[c] - max_val); // Temp storage
            sum_exp += grad_row[c];
        }
        
        double inv_sum = 1.0 / (sum_exp + 1e-9);
        
        // ------------------------------------------------
        
        // 2. Derivative calculation: (Prob - Target) * Scale
        // ------------------------------------------------
        int is_active = 0;
        for(c=0; c<cols; c++) if(target_row[c] > 0.5) { is_active = 1; break; }
        
        if (is_active) {
            for(c=0; c<cols; c++) {
                double prob = grad_row[c] * inv_sum; // Final Probability
                grad_row[c] = scale * (prob - target_row[c]);
            }
        } else {
            // Masking (Padding)
            memset(grad_row, 0, cols * sizeof(double));
        }
    }
}

void internal_layernorm_backward(tensor_t *dY, tensor_t *X, tensor_t *G, tensor_t *B, tensor_t *dX, tensor_t *dG, tensor_t *dB, double eps) {
    int r, c, rows = X->rows, cols = X->cols;
    
    // 1. Accumulate Gradients for Gamma/Beta (Reduction is safer/faster than Atomic inside loop)
    // Since rows are many and cols (dim) are few (e.g. 64), we can iterate differently?
    // No, standard loop with atomic is acceptable for now given current architecture complexity,
    // BUT let's ensure we are not reading garbage.
    
    // Ensure dG and dB are zeroed before accumulation in the main loop call?
    // Yes, internal_graph_backward zeros all grads first.
    
    #pragma omp parallel for if(rows > 32) private(c)
    for(r=0; r<rows; r++) {
        double mean = 0, var = 0;
        double *px = &X->data[r*cols];
        double *pdy = &dY->data[r*cols];
        double *pdx = &dX->data[r*cols];
        
        // Forward Re-calc
        for(c=0; c<cols; c++) mean += px[c];
        mean /= cols;
        
        for(c=0; c<cols; c++) { double d = px[c] - mean; var += d*d; }
        var /= cols;
        
        double invStd = 1.0 / sqrt(var + eps);

        // Temp accumulators for this row (to minimize atomic contention)
        // Note: For dG/dB, we must write to global memory. 
        // Atomic is the bottleneck here.
        // Optimization: Calculate dX parts that don't need dG sum first? No.
        
        double sum_dy = 0;
        double sum_dy_x_mu = 0;

        for(c=0; c<cols; c++) {
            double x_norm = (px[c] - mean) * invStd;
            double dy = pdy[c];
            
            // Accumulate global gradients
            #pragma omp atomic
            dG->data[c] += dy * x_norm;
            
            #pragma omp atomic
            dB->data[c] += dy;
            
            // Prepare for dX
            double g = G->data[c];
            sum_dy += dy * g;
            sum_dy_x_mu += dy * g * x_norm;
        }

        // Calculate dX
        double term1 = invStd;
        double term2 = invStd / cols; 
        
        for(c=0; c<cols; c++) {
            double x_norm = (px[c] - mean) * invStd;
            double g = G->data[c];
            double dy = pdy[c];
            
            // Exact formula for LayerNorm Backward
            pdx[c] = term1 * (dy * g - sum_dy / cols - x_norm * sum_dy_x_mu / cols);
        }
    }
}

void internal_dropout_backward(tensor_t *dY, tensor_t *dX, tensor_t *Mask, double rate) {
    int i;
    double scale = 1.0 / (1.0 - rate);
    
    #pragma omp parallel for if(dY->size > PARALLEL_THRESHOLD)
    for(i=0; i<dY->size; i++) {
        if (Mask->data[i] > 0.5) { // Active
             dX->data[i] = dY->data[i] * scale;
        } else { // Dropped
             dX->data[i] = 0.0;
        }
    }
}

/* --- Updated Optimizer --- */
void internal_sgd_update(tensor_t *W, tensor_t *dW, double lr) {
    int i;
    #pragma omp parallel for if(W->size > PARALLEL_THRESHOLD)
    for(i=0; i<W->size; i++) {
        W->data[i] -= lr * dW->data[i];
    }
}

void internal_adam_update(tensor_t *W, tensor_t *dW, tensor_t *m, tensor_t *v, 
                          double lr, double beta1, double beta2, double eps, int t) {
    int i;
    double m_hat, v_hat, beta1_t, beta2_t;
    
    beta1_t = pow(beta1, t);
    beta2_t = pow(beta2, t);
    
    #pragma omp parallel for if(W->size > PARALLEL_THRESHOLD) private(m_hat, v_hat)
    for(i=0; i<W->size; i++) {
        // Update biased first moment
        m->data[i] = beta1 * m->data[i] + (1.0 - beta1) * dW->data[i];
        
        // Update biased second moment
        v->data[i] = beta2 * v->data[i] + (1.0 - beta2) * dW->data[i] * dW->data[i];
        
        // Bias correction
        m_hat = m->data[i] / (1.0 - beta1_t);
        v_hat = v->data[i] / (1.0 - beta2_t);
        
        // Update weights
        if (v_hat < 0) v_hat = 0;
        W->data[i] -= lr * m_hat / (sqrt(v_hat) + eps);
    }
}

/* --- More Missing Kernels --- */

void internal_layernorm(tensor_t *X, tensor_t *G, tensor_t *B, double eps) {
    int r, c, rows = X->rows, cols = X->cols;
    
    #pragma omp parallel for if(rows > 32) private(c)
    for(r=0; r<rows; r++) {
        double mean = 0, var = 0;
        double *px = &X->data[r*cols];
        double invStd;
        
        // Calculate mean
        for(c=0; c<cols; c++) mean += px[c];
        mean /= cols;
        
        // Calculate variance
        for(c=0; c<cols; c++) var += (px[c]-mean)*(px[c]-mean);
        var /= cols;
        
        // Normalize
        invStd = 1.0 / sqrt(var + eps);
        for(c=0; c<cols; c++) {
            px[c] = ((px[c] - mean) * invStd * G->data[c]) + B->data[c];
        }
    }
}

void internal_slice_rows(tensor_t *Src, tensor_t *Dest, int start_row, int count) {
    int src_offset_idx = (start_row - 1) * Src->cols;
    size_t total_elements = (size_t)count * Src->cols;
    size_t bytes = total_elements * sizeof(double);
    memcpy(Dest->data, &Src->data[src_offset_idx], bytes);
}

void internal_insert_rows(tensor_t *Dest, tensor_t *Src, int start_row) {
    size_t offset_elems = (size_t)(start_row - 1) * Dest->cols;
    size_t copy_elems   = (size_t)Src->rows * Src->cols;
    size_t copy_bytes   = copy_elems * sizeof(double);
    memcpy(&Dest->data[offset_elems], Src->data, copy_bytes);
}

void internal_dropout(tensor_t *T, double rate, int training) {
    int i;
    double scale;
    
    if (!training || rate == 0.0) return;
    
    scale = 1.0 / (1.0 - rate);
    
    for(i=0; i<T->size; i++) {
        double r = (double)rand() / RAND_MAX;
        if (r < rate) {
            T->data[i] = 0.0;
        } else {
            T->data[i] *= scale;
        }
    }
}

void internal_attention_forward(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale) {
    int seq = Q->rows;
    int dim = Q->cols;
    int i, j, k;
    
    #pragma omp parallel private(i, j, k)
    {
        double *scores = (double *)malloc(seq * sizeof(double));
        if(scores) {
            #pragma omp for
            for(i=0; i<seq; i++) {
                double *q_row = &Q->data[i*dim];
                double *out_row = &Out->data[i*dim];
                double maxVal = -DBL_MAX;
                double sum = 0;
                
                for(j=0; j<seq; j++) {
                    double *k_row = &K->data[j*dim];
                    double dot = 0;
                    for(k=0; k<dim; k++) dot += q_row[k] * k_row[k];
                    scores[j] = dot * scale;
                }
                
                for(j=0; j<seq; j++) if(scores[j] > maxVal) maxVal = scores[j];
                for(j=0; j<seq; j++) {
                    scores[j] = exp(scores[j] - maxVal);
                    sum += scores[j];
                }
                double invSum = 1.0/sum;
                for(j=0; j<seq; j++) scores[j] *= invSum;
                
                memset(out_row, 0, dim * sizeof(double));
                for(j=0; j<seq; j++) {
                    double s = scores[j];
                    double *v_row = &V->data[j*dim];
                    for(k=0; k<dim; k++) out_row[k] += s * v_row[k];
                }
            }
            free(scores);
        }
    }
}

void internal_attention_causal(tensor_t *Q, tensor_t *K, tensor_t *V, tensor_t *Out, double scale) {
    int seq = Q->rows;
    int dim = Q->cols;
    int i, j, k;
    
    #pragma omp parallel private(i, j, k)
    {
        double *scores = (double *)malloc(seq * sizeof(double));
        if(scores) {
            #pragma omp for
            for(i=0; i<seq; i++) {
                double *q_row = &Q->data[i*dim];
                double *out_row = &Out->data[i*dim];
                double maxVal = -DBL_MAX;
                double sum = 0;
                
                for(j=0; j<seq; j++) {
                    if (j > i) { scores[j] = -1e9; continue; }
                    double *k_row = &K->data[j*dim];
                    double dot = 0;
                    for(k=0; k<dim; k++) dot += q_row[k] * k_row[k];
                    scores[j] = dot * scale;
                }
                
                for(j=0; j<seq; j++) if(scores[j] > maxVal) maxVal = scores[j];
                for(j=0; j<seq; j++) {
                    scores[j] = exp(scores[j] - maxVal);
                    sum += scores[j];
                }
                double invSum = 1.0/sum;
                for(j=0; j<seq; j++) scores[j] *= invSum;
                
                memset(out_row, 0, dim * sizeof(double));
                for(j=0; j<seq; j++) {
                    double s = scores[j];
                    if(s < 1e-9) continue;
                    double *v_row = &V->data[j*dim];
                    for(k=0; k<dim; k++) out_row[k] += s * v_row[k];
                }
            }
            free(scores);
        }
    }
}

void internal_embedding_forward(tensor_t *Emb, tensor_t *Ind, tensor_t *Out) {
    int total = Ind->size;
    int dim = Emb->cols;
    int vocab = Emb->rows;
    int i;
    
    #pragma omp parallel for if(total > 32)
    for(i=0; i<total; i++) {
        int idx = (int)Ind->data[i];
        idx = idx - 1; // Convert from Ring indexing (1-based) to C indexing (0-based)
        if (idx < 0) idx = 0;
        if (idx >= vocab) idx = vocab - 1;
        memcpy(&Out->data[i * dim], &Emb->data[idx * dim], dim * sizeof(double));
    }
}

void internal_embedding_backward(tensor_t *dOut, tensor_t *Ind, tensor_t *dEmb) {
    int total = Ind->size;
    int dim = dEmb->cols;
    int i, j;
    
    // Serial to avoid race conditions
    for(i=0; i<total; i++) {
        int idx = (int)Ind->data[i];
        idx = idx - 1; // Convert from Ring indexing (1-based) to C indexing (0-based)
        if (idx < 0 || idx >= dEmb->rows) continue;
        
        double *g_src = &dOut->data[i * dim];
        double *g_dst = &dEmb->data[idx * dim];
        
        for(j=0; j<dim; j++) g_dst[j] += g_src[j];
    }
}

double internal_mean_global(tensor_t *T) {
    double sum = 0;
    int i;
    #pragma omp parallel for reduction(+:sum) if(T->size > PARALLEL_THRESHOLD)
    for(i=0; i<T->size; i++) sum += T->data[i];
    return sum / T->size;
}

void internal_argmax_rowwise(tensor_t *T, tensor_t *R) {
    int r, c;
    #pragma omp parallel for if(T->rows > 64) private(c)
    for(r=0; r<T->rows; r++) {
        double maxVal = -DBL_MAX;
        int maxIdx = 1;
        int offset = r * T->cols;
        for(c=0; c<T->cols; c++) {
            if(T->data[offset+c] > maxVal) {
                maxVal = T->data[offset+c];
                maxIdx = c + 1;
            }
        }
        R->data[r] = (double)maxIdx;
    }
}

double internal_sum_squares(tensor_t *T) {
    double sum = 0.0;
    int i;
    #pragma omp parallel for reduction(+:sum) if(T->size > 2000)
    for(i = 0; i < T->size; i++) {
        sum += T->data[i] * T->data[i];
    }
    return sum;
}

void internal_clip_tensor(tensor_t *T, double min_val, double max_val) {
    int i;
    #pragma omp parallel for if(T->size > 1000)
    for(i = 0; i < T->size; i++) {
        if (T->data[i] > max_val) T->data[i] = max_val;
        else if (T->data[i] < min_val) T->data[i] = min_val;
    }
}

RING_FUNC(ring_tensor_print_stats) {
    tensor_t *t = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    double min = DBL_MAX, max = -DBL_MAX, sum = 0;
    int i;
    for(i=0; i<t->size; i++) {
        if(t->data[i] < min) min = t->data[i];
        if(t->data[i] > max) max = t->data[i];
        sum += fabs(t->data[i]);
    }
    printf("Tensor Stats: Min=%.4f Max=%.4f AvgAbs=%.4f\n", min, max, sum/t->size);
}

/* 
** Export to List (Fast)
** Converts Tensor to a flat Ring List [v1, v2, v3, ...]
** Critical for passing data to GUI or other libraries.
*/
RING_FUNC(ring_tensor_to_list) {
    tensor_t *T;
    List *pList;
    int i;

    if (RING_API_PARACOUNT != 1) {
        RING_API_ERROR(RING_API_MISS1PARA);
        return;
    }

    T = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    
    // Create new Ring List
    pList = RING_API_NEWLIST;
    
    // Turbo Copy
    for(i = 0; i < T->size; i++) {
        ring_list_adddouble(pList, T->data[i]);
    }
    
    RING_API_RETLIST(pList);
}


// ====== LLM SOTA KERNELS (GEMMA / LLAMA) ======

void internal_rmsnorm(tensor_t *X, tensor_t *Weights, double eps) {
    int i, j;
    int rows = X->rows;
    int cols = X->cols;
    #pragma omp parallel for private(j)
    for (i = 0; i < rows; i++) {
        double sum_sq = 0.0;
        double *x_row = &X->data[i * cols];
        double *w_row = Weights->data;
        for (j = 0; j < cols; j++) {
            sum_sq += x_row[j] * x_row[j];
        }
        double rms = sqrt((sum_sq / cols) + eps);
        double inv_rms = 1.0 / rms;
        for (j = 0; j < cols; j++) {
            x_row[j] = x_row[j] * inv_rms * w_row[j];
        }
    }
}
RING_FUNC(ring_tensor_rmsnorm) {
    if (RING_API_PARACOUNT != 3) { RING_API_ERROR("Requires X, Weights, eps"); return; }
    tensor_t *X = (tensor_t*)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *W = (tensor_t*)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    double eps  = RING_API_GETNUMBER(3);
    internal_rmsnorm(X, W, eps);
}

void internal_rope(tensor_t *Q, tensor_t *K, int dim, double base) {
    int seq = Q->rows;
    int n_heads_q = Q->cols / dim;
    int n_heads_k = K->cols / dim;
    int i, h, d;
    #pragma omp parallel for private(h, d)
    for (i = 0; i < seq; i++) { // i is position
        for (d = 0; d < dim; d += 2) {
            double theta = (double)i * pow(base, -(double)d / dim);
            double cos_t = cos(theta);
            double sin_t = sin(theta);
            // Apply to Q
            for (h = 0; h < n_heads_q; h++) {
                int idx1 = i * (n_heads_q * dim) + h * dim + d;
                int idx2 = idx1 + 1;
                double q1 = Q->data[idx1];
                double q2 = Q->data[idx2];
                Q->data[idx1] = q1 * cos_t - q2 * sin_t;
                Q->data[idx2] = q1 * sin_t + q2 * cos_t;
            }
            if (K != NULL) {
                // Apply to K
                for (h = 0; h < n_heads_k; h++) {
                    int idx1 = i * (n_heads_k * dim) + h * dim + d;
                    int idx2 = idx1 + 1;
                    double k1 = K->data[idx1];
                    double k2 = K->data[idx2];
                    K->data[idx1] = k1 * cos_t - k2 * sin_t;
                    K->data[idx2] = k1 * sin_t + k2 * cos_t;
                }
            }
        }
    }
}
RING_FUNC(ring_tensor_rope) {
    if (RING_API_PARACOUNT != 4) return;
    tensor_t *Q = (tensor_t*)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *K = NULL;
    if (RING_API_ISPOINTER(2)) K = (tensor_t*)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    int dim = (int)RING_API_GETNUMBER(3);
    double base = RING_API_GETNUMBER(4); // Usually 10000.0 or 1000000.0
    internal_rope(Q, K, dim, base);
}

void internal_silu(tensor_t *T) {
    int i;
    #pragma omp parallel for
    for (i = 0; i < T->size; i++) {
        double x = T->data[i];
        T->data[i] = x / (1.0 + exp(-x)); // x * sigmoid(x)
    }
}
RING_FUNC(ring_tensor_silu) {
    if (RING_API_PARACOUNT != 1) return;
    tensor_t *T = (tensor_t*)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    internal_silu(T);
}

// GPU SAT ANNEAL
int gpu_sat_anneal(tensor_t *Field, tensor_t *Momentum, tensor_t *Clauses, tensor_t *Weights, int lits_per_clause, int passes, float lr, float decay) {
#ifdef USE_OPENCL
    if(!gpu_ready) return 0;
    
    int nVars = Field->rows; 
    int nDims = Field->cols; 
    int nClauses = Clauses->rows;
    
    size_t szF = Field->size * sizeof(float);
    size_t szM = Momentum->size * sizeof(float);
    size_t szC = Clauses->size * sizeof(float);
    size_t szW = Weights->size * sizeof(float); // NEW
    
    float *fF = (float*)malloc(szF);
    float *fM = (float*)malloc(szM);
    float *fC = (float*)malloc(szC);
    float *fW = (float*)malloc(szW); // NEW
    
    int i; 
	#pragma omp parallel for private(i)
	for(i=0; i<Field->size; i++) fF[i] = (float)Field->data[i];
	#pragma omp parallel for private(i)
	for(i=0; i<Momentum->size; i++) fM[i] = (float)Momentum->data[i];
	#pragma omp parallel for private(i)
	for(i=0; i<Clauses->size; i++) fC[i] = (float)Clauses->data[i];
	#pragma omp parallel for private(i)
	for(i=0; i<Weights->size; i++) fW[i] = (float)Weights->data[i]; // NEW
    
    cl_int ret;
    cl_mem bufF = clCreateBuffer(clContext, CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR, szF, fF, &ret);
    cl_mem bufM = clCreateBuffer(clContext, CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR, szM, fM, &ret);
    cl_mem bufC = clCreateBuffer(clContext, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR, szC, fC, &ret);
    cl_mem bufW = clCreateBuffer(clContext, CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR, szW, fW, &ret); // NEW
    
    clSetKernelArg(clSatKernel, 0, sizeof(cl_mem), (void*)&bufF);
    clSetKernelArg(clSatKernel, 1, sizeof(cl_mem), (void*)&bufM);
    clSetKernelArg(clSatKernel, 2, sizeof(cl_mem), (void*)&bufC);
    clSetKernelArg(clSatKernel, 3, sizeof(cl_mem), (void*)&bufW); // NEW
    clSetKernelArg(clSatKernel, 4, sizeof(int), &nVars);
    clSetKernelArg(clSatKernel, 5, sizeof(int), &nClauses);
    clSetKernelArg(clSatKernel, 6, sizeof(int), &lits_per_clause);
    clSetKernelArg(clSatKernel, 7, sizeof(int), &passes);
    clSetKernelArg(clSatKernel, 8, sizeof(float), &lr);
    clSetKernelArg(clSatKernel, 9, sizeof(float), &decay);
    
    size_t global_work_size[1] = { (size_t)nDims };
    ret = clEnqueueNDRangeKernel(clQueue, clSatKernel, 1, NULL, global_work_size, NULL, 0, NULL, NULL);
    
    if (ret == CL_SUCCESS) {
        clEnqueueReadBuffer(clQueue, bufF, CL_TRUE, 0, szF, fF, 0, NULL, NULL);
        clEnqueueReadBuffer(clQueue, bufM, CL_TRUE, 0, szM, fM, 0, NULL, NULL);
        clEnqueueReadBuffer(clQueue, bufW, CL_TRUE, 0, szW, fW, 0, NULL, NULL); // NEW
        
        #pragma omp parallel for private(i)
        for(i=0; i<Field->size; i++) Field->data[i] = (double)fF[i];
        #pragma omp parallel for private(i)
        for(i=0; i<Momentum->size; i++) Momentum->data[i] = (double)fM[i];
        #pragma omp parallel for private(i)
        for(i=0; i<Weights->size; i++) Weights->data[i] = (double)fW[i]; // NEW
    }
    
    clReleaseMemObject(bufF); clReleaseMemObject(bufM); clReleaseMemObject(bufC); clReleaseMemObject(bufW);
    free(fF); free(fM); free(fC); free(fW);
    return 1;
#else
	return 0;
#endif
}

RING_FUNC(ring_tensor_sat_anneal) {
    if (RING_API_PARACOUNT != 8) {
        RING_API_ERROR("Requires 8 params: Field, Momentum, Clauses, Weights, lits_per_clause, passes, lr, decay");
        return;
    }
    tensor_t *Field    = (tensor_t *)RING_API_GETCPOINTER(1, RING_VM_POINTER_TENSOR);
    tensor_t *Momentum = (tensor_t *)RING_API_GETCPOINTER(2, RING_VM_POINTER_TENSOR);
    tensor_t *Clauses  = (tensor_t *)RING_API_GETCPOINTER(3, RING_VM_POINTER_TENSOR);
    tensor_t *Weights  = (tensor_t *)RING_API_GETCPOINTER(4, RING_VM_POINTER_TENSOR);
    int lits_per_clause = (int)RING_API_GETNUMBER(5);
    int passes = (int)RING_API_GETNUMBER(6);
    float lr = (float)RING_API_GETNUMBER(7);
    float decay = (float)RING_API_GETNUMBER(8);
    
    gpu_sat_anneal(Field, Momentum, Clauses, Weights, lits_per_clause, passes, lr, decay);
}


/* --- INIT --- */
RING_LIBINIT {
    RING_API_REGISTER("tensor_init", ring_tensor_init);
    RING_API_REGISTER("tensor_reshape", ring_tensor_reshape);
    RING_API_REGISTER("tensor_copy", ring_tensor_copy);
    RING_API_REGISTER("tensor_matmul_batch", ring_tensor_matmul_batch); 
    RING_API_REGISTER("tensor_set", ring_tensor_set);
    RING_API_REGISTER("tensor_get", ring_tensor_get);
    RING_API_REGISTER("tensor_copy_data", ring_tensor_copy_data);
    RING_API_REGISTER("tensor_print_stats", ring_tensor_print_stats);
    
    RING_API_REGISTER("tensor_get_data_ptr", ring_tensor_get_data_ptr);
    
    RING_API_REGISTER("tensor_get_rows", ring_tensor_get_rows);
    RING_API_REGISTER("tensor_get_cols", ring_tensor_get_cols);
    
    RING_API_REGISTER("tensor_add", ring_tensor_add);
    RING_API_REGISTER("tensor_sub", ring_tensor_sub);
    RING_API_REGISTER("tensor_mul_elem", ring_tensor_mul_elem);
    RING_API_REGISTER("tensor_div", ring_tensor_div);
    RING_API_REGISTER("tensor_scalar_mul", ring_tensor_scalar_mul);
    RING_API_REGISTER("tensor_add_scalar", ring_tensor_add_scalar);
    RING_API_REGISTER("tensor_sub_scalar", ring_tensor_sub_scalar);
    
    RING_API_REGISTER("tensor_fill", ring_tensor_fill);
    RING_API_REGISTER("tensor_random", ring_tensor_random);
    RING_API_REGISTER("tensor_square", ring_tensor_square);
    RING_API_REGISTER("tensor_sqrt", ring_tensor_sqrt);
    RING_API_REGISTER("tensor_exp", ring_tensor_exp);
    
    RING_API_REGISTER("tensor_matmul", ring_tensor_matmul);
    RING_API_REGISTER("tensor_transpose", ring_tensor_transpose);
    RING_API_REGISTER("tensor_sum", ring_tensor_sum);
    RING_API_REGISTER("tensor_mean", ring_tensor_mean);
    RING_API_REGISTER("tensor_argmax", ring_tensor_argmax);
    RING_API_REGISTER("tensor_add_row_vec", ring_tensor_add_row_vec);

    RING_API_REGISTER("tensor_sigmoid", ring_tensor_sigmoid);
    RING_API_REGISTER("tensor_sigmoid_prime", ring_tensor_sigmoid_prime);
    RING_API_REGISTER("tensor_tanh", ring_tensor_tanh);
    RING_API_REGISTER("tensor_tanh_prime", ring_tensor_tanh_prime);
    RING_API_REGISTER("tensor_relu", ring_tensor_relu);
    RING_API_REGISTER("tensor_relu_prime", ring_tensor_relu_prime);
    RING_API_REGISTER("tensor_softmax", ring_tensor_softmax);
    
    RING_API_REGISTER("tensor_embedding_forward", ring_tensor_embedding_forward);
    RING_API_REGISTER("tensor_embedding_backward", ring_tensor_embedding_backward);

    RING_API_REGISTER("tensor_layernorm", ring_tensor_layernorm);

    RING_API_REGISTER("tensor_attention_fast", ring_tensor_attention_fast);
    RING_API_REGISTER("tensor_attention_causal", ring_tensor_attention_causal);
    RING_API_REGISTER("tensor_mha_backward_fast", ring_tensor_mha_backward_fast);
    RING_API_REGISTER("tensor_attention_batch", ring_tensor_attention_batch);
    
    RING_API_REGISTER("tensor_select_columns", ring_tensor_select_columns);
    RING_API_REGISTER("tensor_insert_columns", ring_tensor_insert_columns);
    
    
    // --- NEW ---
    RING_API_REGISTER("tensor_slice_rows", ring_tensor_slice_rows);
    RING_API_REGISTER("tensor_insert_rows", ring_tensor_insert_rows);
    
    RING_API_REGISTER("tensor_update_sgd", ring_tensor_update_sgd);
    RING_API_REGISTER("tensor_update_adam", ring_tensor_update_adam);
    RING_API_REGISTER("tensor_dropout", ring_tensor_dropout);

    RING_API_REGISTER("tensor_crossentropy_loss", ring_tensor_crossentropy_loss);
    RING_API_REGISTER("tensor_crossentropy_backward", ring_tensor_crossentropy_backward);

    RING_API_REGISTER("tensor_get_cores", ring_tensor_get_cores);
    RING_API_REGISTER("tensor_set_threads", ring_tensor_set_threads);
    RING_API_REGISTER("tensor_set_gpu_threshold", ring_tensor_set_gpu_threshold);
    RING_API_REGISTER("tensor_set_arena_size", ring_tensor_set_arena_size);

    RING_API_REGISTER("tensor_set_from_list", ring_tensor_set_from_list);
    RING_API_REGISTER("tensor_set_one_hot", ring_tensor_set_one_hot);
    
    RING_API_REGISTER("tensor_save", ring_tensor_save);
    RING_API_REGISTER("tensor_load", ring_tensor_load);
    RING_API_REGISTER("tensor_save_fp32", ring_tensor_save_fp32);
    RING_API_REGISTER("tensor_load_fp32", ring_tensor_load_fp32);

    // In-place load functions
    ring_vm_funcregister("tensor_load_inplace", ring_tensor_load_inplace);
    ring_vm_funcregister("tensor_load_fp32_inplace", ring_tensor_load_fp32_inplace);
    ring_vm_funcregister("graph_run_buffered", ring_graph_run_buffered);

    RING_API_REGISTER("tensor_clip_global_norm", ring_tensor_clip_global_norm);
    RING_API_REGISTER("tensor_clip_tensor", ring_tensor_clip_tensor);
    
    RING_API_REGISTER("tensor_gelu", ring_tensor_gelu);
    RING_API_REGISTER("tensor_gelu_prime", ring_tensor_gelu_prime);

    RING_API_REGISTER("tensor_sum_squares", ring_tensor_sum_squares);

    RING_API_REGISTER("tensor_repeat_rows", ring_tensor_repeat_rows);

    RING_API_REGISTER("tensor_from_memory", ring_tensor_from_memory);
    
    RING_API_REGISTER("tensor_dot_row_vec", ring_tensor_dot_row_vec);

    // --- NEW ---
    RING_API_REGISTER("tensor_attention_linear_causal", ring_tensor_attention_linear_causal);
    RING_API_REGISTER("tensor_attention_linear_optimized", ring_tensor_attention_linear_optimized);
    RING_API_REGISTER("tensor_attention_linear_backward", ring_tensor_attention_linear_backward);
    RING_API_REGISTER("tensor_attention_linear_global_backward", ring_tensor_attention_linear_global_backward);
    
    RING_API_REGISTER("tensor_attention_multihead", ring_tensor_attention_multihead);
    RING_API_REGISTER("tensor_attention_multihead_backward", ring_tensor_attention_multihead_backward);

    RING_API_REGISTER("tensor_set_one_hot_ptr", ring_tensor_set_one_hot_ptr);
    RING_API_REGISTER("tensor_to_list", ring_tensor_to_list);
    RING_API_REGISTER("tensor_sat_anneal", ring_tensor_sat_anneal);
    
    // --- LLM GIANTS CORE ---
    RING_API_REGISTER("tensor_rmsnorm", ring_tensor_rmsnorm);
    RING_API_REGISTER("tensor_rope", ring_tensor_rope);
    RING_API_REGISTER("tensor_silu", ring_tensor_silu);
    
    
    // --- GRAPH ENGINE ---
    RING_API_REGISTER("graph_init", ring_graph_init);
    RING_API_REGISTER("graph_node", ring_graph_node);
    RING_API_REGISTER("graph_add_node", ring_graph_node); // Alias
    RING_API_REGISTER("graph_set_input", ring_graph_set_input);
    RING_API_REGISTER("graph_get_output", ring_graph_get_output);
    RING_API_REGISTER("graph_forward", ring_graph_forward);
    RING_API_REGISTER("graph_backward", ring_graph_backward);
    RING_API_REGISTER("graph_set_optimizer", ring_graph_set_optimizer);
    RING_API_REGISTER("graph_run", ring_graph_run);
    RING_API_REGISTER("graph_update", ring_graph_update);
    RING_API_REGISTER("graph_bind_memory", ring_graph_bind_memory);
    RING_API_REGISTER("graph_bind_grad", ring_graph_bind_grad);
    RING_API_REGISTER("graph_free", ring_graph_free);

    #ifdef USE_OPENCL
        init_opencl();
    #endif

    #ifdef _OPENMP
    omp_set_num_threads(omp_get_num_procs());
    #endif
}
