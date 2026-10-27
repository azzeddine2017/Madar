/*
**  Madar (RingTensor) - High-Performance AI-Native Runtime
**  ANSI C (C99) Native Tensor Core
*/

#ifndef ring_tensor_h
#define ring_tensor_h

#include <stddef.h>
#include <stdint.h>

#define RING_TENSOR_MAX_DIMS 8

/* Supported Quantized & Precision Data Types */
typedef enum RingTensorType {
	RING_TENSOR_TYPE_FLOAT32 = 0,
	RING_TENSOR_TYPE_FLOAT16 = 1,
	RING_TENSOR_TYPE_INT8    = 2,
	RING_TENSOR_TYPE_INT32   = 3,
	RING_TENSOR_TYPE_FLOAT64 = 4
} RingTensorType;

/* Underlying Continuous Memory Storage (with RefCount for zero-copy views) */
typedef struct RingTensorStorage {
	void         *pData;          /* Raw byte buffer */
	size_t        nBytes;         /* Total allocated bytes */
	unsigned int  nRefCount;      /* Reference counter for shared views */
	uint8_t       lOwnsData;      /* 1 = Free buffer on 0 refs, 0 = External/mmap */
} RingTensorStorage;

/* Forward declaration */
struct List;

/* Tensor Descriptor (Views / Slices share the same Storage) */
typedef struct RingTensor {
	RingTensorStorage *pStorage;   /* Pointer to actual memory */
	RingTensorType     nDataType;  /* Data type enum */
	size_t             nOffset;    /* Byte offset from pStorage->pData */
	uint32_t           nDims;      /* Number of dimensions (rank) */
	size_t             aShape[RING_TENSOR_MAX_DIMS];   /* Size of each dimension */
	int64_t            aStrides[RING_TENSOR_MAX_DIMS]; /* Stride per dim (in elements) */
	uint8_t            lContiguous;/* 1 if memory is strictly contiguous (C-order) */
} RingTensor;

/* Lifecycle APIs */
RING_API RingTensor *ring_tensor_new(void *pState, RingTensorType nType, uint32_t nDims, const size_t *aShape);
RING_API RingTensor *ring_tensor_new_from_buffer(void *pState, void *pBuffer, size_t nBytes, RingTensorType nType, uint32_t nDims, const size_t *aShape, uint8_t lTakeOwnership);
RING_API RingTensor *ring_tensor_delete(void *pState, RingTensor *pTensor);

/* Zero-Copy View & Slicing Operations */
RING_API RingTensor *ring_tensor_create_view(void *pState, RingTensor *pSource);
RING_API RingTensor *ring_tensor_slice(void *pState, RingTensor *pSource, uint32_t nDim, size_t nStart, size_t nEnd, int64_t nStep);
RING_API RingTensor *ring_tensor_reshape(void *pState, RingTensor *pSource, uint32_t nDims, const size_t *aNewShape);
RING_API void        ring_tensor_print(void *pState, RingTensor *pTensor);

/* Interop with Ring List */
RING_API struct List *ring_tensor_to_list(void *pState, RingTensor *pTensor);
RING_API RingTensor  *ring_list_to_tensor(void *pState, struct List *pList, RingTensorType nType);

/* Element access & mutation */
RING_API double ring_tensor_get_element(const RingTensor *pTensor, const size_t *aIndices);
RING_API void   ring_tensor_set_element(RingTensor *pTensor, const size_t *aIndices, double nValue);
RING_API void   ring_tensor_fill(RingTensor *pTensor, double nValue);

/* Element-wise Math */
RING_API RingTensor *ring_tensor_add(void *pState, RingTensor *pA, RingTensor *pB);
RING_API RingTensor *ring_tensor_sub(void *pState, RingTensor *pA, RingTensor *pB);
RING_API RingTensor *ring_tensor_mul(void *pState, RingTensor *pA, RingTensor *pB); /* Hadamard */
RING_API RingTensor *ring_tensor_div(void *pState, RingTensor *pA, RingTensor *pB);
RING_API RingTensor *ring_tensor_scale(void *pState, RingTensor *pA, double nScalar);
RING_API RingTensor *ring_tensor_add_scalar(void *pState, RingTensor *pA, double nScalar);

/* High-Performance Matrix Multiplication (GEMM) */
RING_API RingTensor *ring_tensor_matmul(void *pState, RingTensor *pA, RingTensor *pB);

/* Neural Activations */
RING_API RingTensor *ring_tensor_relu(void *pState, RingTensor *pSource);
RING_API RingTensor *ring_tensor_gelu(void *pState, RingTensor *pSource);
RING_API RingTensor *ring_tensor_sigmoid(void *pState, RingTensor *pSource);
RING_API RingTensor *ring_tensor_softmax(void *pState, RingTensor *pSource, int nDim);

/* Reductions & Similarities */
RING_API double ring_tensor_sum(const RingTensor *pTensor);
RING_API double ring_tensor_mean(const RingTensor *pTensor);
RING_API double ring_tensor_max(const RingTensor *pTensor);
RING_API double ring_tensor_min(const RingTensor *pTensor);
RING_API double ring_tensor_cosine_similarity(const RingTensor *pA, const RingTensor *pB);

/* Data access and geometry helpers */
RING_API size_t ring_tensor_element_size(RingTensorType nType);
RING_API size_t ring_tensor_total_elements(const RingTensor *pTensor);
RING_API void  *ring_tensor_data(const RingTensor *pTensor);

/* VM Scripting Functions Loader */
RING_API void ring_tensor_loadfunctions(RingState *pRingState);

#endif
