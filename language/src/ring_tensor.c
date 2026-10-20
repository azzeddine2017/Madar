/*
**  Madar (RingTensor) - High-Performance AI-Native Runtime
**  ANSI C (C99) Native Tensor Implementation
*/

#include "ring.h"
#include "ring_tensor.h"
#include <math.h>

/* Returns the byte size of a single element for the specified data type */
RING_API size_t ring_tensor_element_size(RingTensorType nType) {
	switch (nType) {
	case RING_TENSOR_TYPE_FLOAT32:
		return sizeof(float);
	case RING_TENSOR_TYPE_FLOAT16:
		return 2; /* 16-bit half precision */
	case RING_TENSOR_TYPE_INT8:
		return sizeof(int8_t);
	case RING_TENSOR_TYPE_INT32:
		return sizeof(int32_t);
	case RING_TENSOR_TYPE_FLOAT64:
		return sizeof(double);
	default:
		return sizeof(float);
	}
}

/* Calculates the total number of elements in the tensor */
RING_API size_t ring_tensor_total_elements(const RingTensor *pTensor) {
	size_t nTotal = 1;
	uint32_t i;
	if (pTensor == NULL || pTensor->nDims == 0) {
		return 0;
	}
	for (i = 0; i < pTensor->nDims; i++) {
		nTotal *= pTensor->aShape[i];
	}
	return nTotal;
}

/* Returns pointer to the start of the tensor's data view */
RING_API void *ring_tensor_data(const RingTensor *pTensor) {
	if (pTensor == NULL || pTensor->pStorage == NULL || pTensor->pStorage->pData == NULL) {
		return NULL;
	}
	return (void *)((char *)pTensor->pStorage->pData + pTensor->nOffset);
}

/* Internal helper: compute contiguous C-order strides */
static void ring_tensor_compute_strides(RingTensor *pTensor) {
	int i;
	if (pTensor->nDims == 0) return;
	pTensor->aStrides[pTensor->nDims - 1] = 1;
	for (i = (int)pTensor->nDims - 2; i >= 0; i--) {
		pTensor->aStrides[i] = pTensor->aStrides[i + 1] * (int64_t)pTensor->aShape[i + 1];
	}
	pTensor->lContiguous = 1;
}

/* Allocate a new Tensor with freshly allocated zeroed contiguous memory */
RING_API RingTensor *ring_tensor_new(void *pState, RingTensorType nType, uint32_t nDims, const size_t *aShape) {
	RingTensor *pTensor;
	RingTensorStorage *pStorage;
	size_t nElemSize, nTotalElems, nTotalBytes;
	uint32_t i;

	if (nDims > RING_TENSOR_MAX_DIMS || nDims == 0) {
		return NULL;
	}

	pTensor = (RingTensor *)ring_state_malloc(pState, sizeof(RingTensor));
	if (pTensor == NULL) return NULL;

	pStorage = (RingTensorStorage *)ring_state_malloc(pState, sizeof(RingTensorStorage));
	if (pStorage == NULL) {
		ring_state_free(pState, pTensor);
		return NULL;
	}

	nElemSize = ring_tensor_element_size(nType);
	nTotalElems = 1;
	for (i = 0; i < nDims; i++) {
		pTensor->aShape[i] = aShape[i];
		nTotalElems *= aShape[i];
	}
	nTotalBytes = nTotalElems * nElemSize;

	pStorage->pData = ring_state_calloc(pState, nTotalElems, nElemSize);
	if (pStorage->pData == NULL && nTotalBytes > 0) {
		ring_state_free(pState, pStorage);
		ring_state_free(pState, pTensor);
		return NULL;
	}

	pStorage->nBytes = nTotalBytes;
	pStorage->nRefCount = 1;
	pStorage->lOwnsData = 1;

	pTensor->pStorage = pStorage;
	pTensor->nDataType = nType;
	pTensor->nOffset = 0;
	pTensor->nDims = nDims;
	ring_tensor_compute_strides(pTensor);

	return pTensor;
}

/* Wrap an existing buffer into a Tensor without copying (Zero-Copy) */
RING_API RingTensor *ring_tensor_new_from_buffer(void *pState, void *pBuffer, size_t nBytes, RingTensorType nType, uint32_t nDims, const size_t *aShape, uint8_t lTakeOwnership) {
	RingTensor *pTensor;
	RingTensorStorage *pStorage;
	uint32_t i;

	if (nDims > RING_TENSOR_MAX_DIMS || nDims == 0 || pBuffer == NULL) {
		return NULL;
	}

	pTensor = (RingTensor *)ring_state_malloc(pState, sizeof(RingTensor));
	if (pTensor == NULL) return NULL;

	pStorage = (RingTensorStorage *)ring_state_malloc(pState, sizeof(RingTensorStorage));
	if (pStorage == NULL) {
		ring_state_free(pState, pTensor);
		return NULL;
	}

	pStorage->pData = pBuffer;
	pStorage->nBytes = nBytes;
	pStorage->nRefCount = 1;
	pStorage->lOwnsData = lTakeOwnership;

	pTensor->pStorage = pStorage;
	pTensor->nDataType = nType;
	pTensor->nOffset = 0;
	pTensor->nDims = nDims;
	for (i = 0; i < nDims; i++) {
		pTensor->aShape[i] = aShape[i];
	}
	ring_tensor_compute_strides(pTensor);

	return pTensor;
}

/* Destroy a Tensor descriptor and decrement storage refcount */
RING_API RingTensor *ring_tensor_delete(void *pState, RingTensor *pTensor) {
	if (pTensor == NULL) return NULL;

	if (pTensor->pStorage != NULL) {
		if (pTensor->pStorage->nRefCount > 1) {
			pTensor->pStorage->nRefCount--;
		} else {
			if (pTensor->pStorage->lOwnsData && pTensor->pStorage->pData != NULL) {
				ring_state_free(pState, pTensor->pStorage->pData);
			}
			ring_state_free(pState, pTensor->pStorage);
		}
	}
	ring_state_free(pState, pTensor);
	return NULL;
}

/* Create a shallow Zero-Copy view referencing the exact same buffer */
RING_API RingTensor *ring_tensor_create_view(void *pState, RingTensor *pSource) {
	RingTensor *pView;
	uint32_t i;

	if (pSource == NULL || pSource->pStorage == NULL) return NULL;

	pView = (RingTensor *)ring_state_malloc(pState, sizeof(RingTensor));
	if (pView == NULL) return NULL;

	pView->pStorage = pSource->pStorage;
	pSource->pStorage->nRefCount++;

	pView->nDataType = pSource->nDataType;
	pView->nOffset = pSource->nOffset;
	pView->nDims = pSource->nDims;
	pView->lContiguous = pSource->lContiguous;

	for (i = 0; i < pSource->nDims; i++) {
		pView->aShape[i] = pSource->aShape[i];
		pView->aStrides[i] = pSource->aStrides[i];
	}

	return pView;
}

/* Slice a Tensor along dimension nDim without allocating new memory */
RING_API RingTensor *ring_tensor_slice(void *pState, RingTensor *pSource, uint32_t nDim, size_t nStart, size_t nEnd, int64_t nStep) {
	RingTensor *pSlice;
	size_t nDimSize, nElemSize;

	if (pSource == NULL || nDim >= pSource->nDims || nStep == 0) return NULL;

	nDimSize = pSource->aShape[nDim];
	if (nStart >= nDimSize) nStart = nDimSize;
	if (nEnd > nDimSize) nEnd = nDimSize;
	if (nStart > nEnd) nStart = nEnd;

	pSlice = ring_tensor_create_view(pState, pSource);
	if (pSlice == NULL) return NULL;

	nElemSize = ring_tensor_element_size(pSource->nDataType);
	pSlice->nOffset += (nStart * (size_t)pSource->aStrides[nDim]) * nElemSize;
	pSlice->aShape[nDim] = (nEnd - nStart + ((size_t)nStep - 1)) / (size_t)nStep;
	pSlice->aStrides[nDim] = pSource->aStrides[nDim] * nStep;

	if (nStep != 1) {
		pSlice->lContiguous = 0;
	}

	return pSlice;
}

/* Reshape tensor (Zero-Copy when contiguous) */
RING_API RingTensor *ring_tensor_reshape(void *pState, RingTensor *pSource, uint32_t nDims, const size_t *aNewShape) {
	RingTensor *pReshaped;
	size_t nOldTotal, nNewTotal;
	uint32_t i;

	if (pSource == NULL || nDims == 0 || nDims > RING_TENSOR_MAX_DIMS) return NULL;
	if (!pSource->lContiguous) {
		/* Strided/non-contiguous views must be cloned before reshaping */
		return NULL;
	}

	nOldTotal = ring_tensor_total_elements(pSource);
	nNewTotal = 1;
	for (i = 0; i < nDims; i++) {
		nNewTotal *= aNewShape[i];
	}
	if (nOldTotal != nNewTotal) {
		return NULL;
	}

	pReshaped = ring_tensor_create_view(pState, pSource);
	if (pReshaped == NULL) return NULL;

	pReshaped->nDims = nDims;
	for (i = 0; i < nDims; i++) {
		pReshaped->aShape[i] = aNewShape[i];
	}
	ring_tensor_compute_strides(pReshaped);

	return pReshaped;
}

/* Convert RingTensor to a nested Ring List */
RING_API struct List *ring_tensor_to_list(void *pState, RingTensor *pTensor) {
	List *pList;
	size_t nTotal, i;
	float *pDataF32;
	double *pDataF64;
	int32_t *pDataI32;
	int8_t *pDataI8;

	if (pTensor == NULL) return NULL;

	pList = ring_list_new_gc(pState, 0);
	nTotal = ring_tensor_total_elements(pTensor);

	switch (pTensor->nDataType) {
	case RING_TENSOR_TYPE_FLOAT32:
		pDataF32 = (float *)ring_tensor_data(pTensor);
		for (i = 0; i < nTotal; i++) {
			ring_list_adddouble_gc(pState, pList, (double)pDataF32[i]);
		}
		break;
	case RING_TENSOR_TYPE_FLOAT64:
		pDataF64 = (double *)ring_tensor_data(pTensor);
		for (i = 0; i < nTotal; i++) {
			ring_list_adddouble_gc(pState, pList, pDataF64[i]);
		}
		break;
	case RING_TENSOR_TYPE_INT32:
		pDataI32 = (int32_t *)ring_tensor_data(pTensor);
		for (i = 0; i < nTotal; i++) {
			ring_list_adddouble_gc(pState, pList, (double)pDataI32[i]);
		}
		break;
	case RING_TENSOR_TYPE_INT8:
		pDataI8 = (int8_t *)ring_tensor_data(pTensor);
		for (i = 0; i < nTotal; i++) {
			ring_list_adddouble_gc(pState, pList, (double)pDataI8[i]);
		}
		break;
	default:
		break;
	}
	return pList;
}

/* Convert a flat Ring List of numbers into a 1D Tensor */
RING_API RingTensor *ring_list_to_tensor(void *pState, struct List *pList, RingTensorType nType) {
	RingTensor *pTensor;
	size_t nSize, i;
	size_t aShape[1];
	float *pDataF32;
	double *pDataF64;
	int32_t *pDataI32;
	int8_t *pDataI8;

	if (pList == NULL) return NULL;

	nSize = ring_list_getsize(pList);
	aShape[0] = nSize;

	pTensor = ring_tensor_new(pState, nType, 1, aShape);
	if (pTensor == NULL) return NULL;

	switch (nType) {
	case RING_TENSOR_TYPE_FLOAT32:
		pDataF32 = (float *)ring_tensor_data(pTensor);
		for (i = 0; i < nSize; i++) {
			pDataF32[i] = (float)ring_list_getdouble(pList, (unsigned int)(i + 1));
		}
		break;
	case RING_TENSOR_TYPE_FLOAT64:
		pDataF64 = (double *)ring_tensor_data(pTensor);
		for (i = 0; i < nSize; i++) {
			pDataF64[i] = ring_list_getdouble(pList, (unsigned int)(i + 1));
		}
		break;
	case RING_TENSOR_TYPE_INT32:
		pDataI32 = (int32_t *)ring_tensor_data(pTensor);
		for (i = 0; i < nSize; i++) {
			pDataI32[i] = (int32_t)ring_list_getdouble(pList, (unsigned int)(i + 1));
		}
		break;
	case RING_TENSOR_TYPE_INT8:
		pDataI8 = (int8_t *)ring_tensor_data(pTensor);
		for (i = 0; i < nSize; i++) {
			pDataI8[i] = (int8_t)ring_list_getdouble(pList, (unsigned int)(i + 1));
		}
		break;
	default:
		break;
	}
	return pTensor;
}

/* Formatted print representation of a Tensor */
RING_API void ring_tensor_print(void *pState, RingTensor *pTensor) {
	size_t nTotal, i;
	float *pDataF32;
	double *pDataF64;
	int32_t *pDataI32;
	int8_t *pDataI8;
	uint32_t d;

	if (pTensor == NULL) {
		printf("Tensor(NULL)\n");
		return;
	}

	printf("Tensor(shape=[");
	for (d = 0; d < pTensor->nDims; d++) {
		printf("%zu%s", pTensor->aShape[d], (d + 1 < pTensor->nDims) ? ", " : "");
	}
	printf("], type=");
	switch (pTensor->nDataType) {
	case RING_TENSOR_TYPE_FLOAT32: printf("Float32"); break;
	case RING_TENSOR_TYPE_FLOAT16: printf("Float16"); break;
	case RING_TENSOR_TYPE_INT8:    printf("Int8"); break;
	case RING_TENSOR_TYPE_INT32:   printf("Int32"); break;
	case RING_TENSOR_TYPE_FLOAT64: printf("Float64"); break;
	}
	printf(", data=[");

	nTotal = ring_tensor_total_elements(pTensor);
	for (i = 0; i < nTotal && i < 16; i++) {
		switch (pTensor->nDataType) {
		case RING_TENSOR_TYPE_FLOAT32:
			pDataF32 = (float *)ring_tensor_data(pTensor);
			printf("%.4f", pDataF32[i]);
			break;
		case RING_TENSOR_TYPE_FLOAT64:
			pDataF64 = (double *)ring_tensor_data(pTensor);
			printf("%.4f", pDataF64[i]);
			break;
		case RING_TENSOR_TYPE_INT32:
			pDataI32 = (int32_t *)ring_tensor_data(pTensor);
			printf("%d", pDataI32[i]);
			break;
		case RING_TENSOR_TYPE_INT8:
			pDataI8 = (int8_t *)ring_tensor_data(pTensor);
			printf("%d", (int)pDataI8[i]);
			break;
		default:
			printf("?");
			break;
		}
		if (i + 1 < nTotal && i + 1 < 16) printf(", ");
	}
	if (nTotal > 16) {
		printf(", ... (%zu elements)", nTotal);
	}
	printf("])\n");
}

/* ==================================================================== */
/*             Element Access, Indexing & Mutation                      */
/* ==================================================================== */

static void *ring_tensor_element_ptr(const RingTensor *pTensor, const size_t *aIndices) {
	size_t nOffsetInElements = 0;
	uint32_t i;
	if (pTensor == NULL || aIndices == NULL) return NULL;
	for (i = 0; i < pTensor->nDims; i++) {
		if (aIndices[i] >= pTensor->aShape[i]) {
			return NULL;
		}
		nOffsetInElements += aIndices[i] * pTensor->aStrides[i];
	}
	return (void *)((char *)ring_tensor_data(pTensor) + nOffsetInElements * ring_tensor_element_size(pTensor->nDataType));
}

RING_API double ring_tensor_get_element(const RingTensor *pTensor, const size_t *aIndices) {
	void *ptr;
	if (pTensor == NULL || aIndices == NULL) return 0.0;
	ptr = ring_tensor_element_ptr(pTensor, aIndices);
	if (ptr == NULL) return 0.0;
	switch (pTensor->nDataType) {
	case RING_TENSOR_TYPE_FLOAT32:
		return (double)(*(float *)ptr);
	case RING_TENSOR_TYPE_FLOAT64:
		return *(double *)ptr;
	case RING_TENSOR_TYPE_INT32:
		return (double)(*(int32_t *)ptr);
	case RING_TENSOR_TYPE_INT8:
		return (double)(*(int8_t *)ptr);
	default:
		return 0.0;
	}
}

RING_API void ring_tensor_set_element(RingTensor *pTensor, const size_t *aIndices, double nValue) {
	void *ptr;
	if (pTensor == NULL || aIndices == NULL) return;
	ptr = ring_tensor_element_ptr(pTensor, aIndices);
	if (ptr == NULL) return;
	switch (pTensor->nDataType) {
	case RING_TENSOR_TYPE_FLOAT32:
		*(float *)ptr = (float)nValue;
		break;
	case RING_TENSOR_TYPE_FLOAT64:
		*(double *)ptr = nValue;
		break;
	case RING_TENSOR_TYPE_INT32:
		*(int32_t *)ptr = (int32_t)nValue;
		break;
	case RING_TENSOR_TYPE_INT8:
		*(int8_t *)ptr = (int8_t)nValue;
		break;
	default:
		break;
	}
}

RING_API void ring_tensor_fill(RingTensor *pTensor, double nValue) {
	size_t nTotal, i;
	if (pTensor == NULL) return;
	nTotal = ring_tensor_total_elements(pTensor);
	if (pTensor->lContiguous) {
		switch (pTensor->nDataType) {
		case RING_TENSOR_TYPE_FLOAT32: {
			float *p = (float *)ring_tensor_data(pTensor);
			float val = (float)nValue;
			for (i = 0; i < nTotal; i++) p[i] = val;
			break;
		}
		case RING_TENSOR_TYPE_FLOAT64: {
			double *p = (double *)ring_tensor_data(pTensor);
			for (i = 0; i < nTotal; i++) p[i] = nValue;
			break;
		}
		case RING_TENSOR_TYPE_INT32: {
			int32_t *p = (int32_t *)ring_tensor_data(pTensor);
			int32_t val = (int32_t)nValue;
			for (i = 0; i < nTotal; i++) p[i] = val;
			break;
		}
		case RING_TENSOR_TYPE_INT8: {
			int8_t *p = (int8_t *)ring_tensor_data(pTensor);
			int8_t val = (int8_t)nValue;
			for (i = 0; i < nTotal; i++) p[i] = val;
			break;
		}
		default:
			break;
		}
	}
}

/* ==================================================================== */
/*             Element-wise Math & Arithmetic                           */
/* ==================================================================== */

static int ring_tensor_shapes_equal(const RingTensor *pA, const RingTensor *pB) {
	uint32_t i;
	if (pA == NULL || pB == NULL) return 0;
	if (pA->nDims != pB->nDims) return 0;
	for (i = 0; i < pA->nDims; i++) {
		if (pA->aShape[i] != pB->aShape[i]) return 0;
	}
	return 1;
}

RING_API RingTensor *ring_tensor_add(void *pState, RingTensor *pA, RingTensor *pB) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (!ring_tensor_shapes_equal(pA, pB)) return NULL;
	pOut = ring_tensor_new(pState, pA->nDataType, pA->nDims, pA->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pA);

	if (pA->lContiguous && pB->lContiguous) {
		if (pA->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *a = (float *)ring_tensor_data(pA);
			float *b = (float *)ring_tensor_data(pB);
			float *c = (float *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] + b[i];
		} else if (pA->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *a = (double *)ring_tensor_data(pA);
			double *b = (double *)ring_tensor_data(pB);
			double *c = (double *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] + b[i];
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_sub(void *pState, RingTensor *pA, RingTensor *pB) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (!ring_tensor_shapes_equal(pA, pB)) return NULL;
	pOut = ring_tensor_new(pState, pA->nDataType, pA->nDims, pA->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pA);

	if (pA->lContiguous && pB->lContiguous) {
		if (pA->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *a = (float *)ring_tensor_data(pA);
			float *b = (float *)ring_tensor_data(pB);
			float *c = (float *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] - b[i];
		} else if (pA->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *a = (double *)ring_tensor_data(pA);
			double *b = (double *)ring_tensor_data(pB);
			double *c = (double *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] - b[i];
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_mul(void *pState, RingTensor *pA, RingTensor *pB) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (!ring_tensor_shapes_equal(pA, pB)) return NULL;
	pOut = ring_tensor_new(pState, pA->nDataType, pA->nDims, pA->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pA);

	if (pA->lContiguous && pB->lContiguous) {
		if (pA->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *a = (float *)ring_tensor_data(pA);
			float *b = (float *)ring_tensor_data(pB);
			float *c = (float *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] * b[i];
		} else if (pA->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *a = (double *)ring_tensor_data(pA);
			double *b = (double *)ring_tensor_data(pB);
			double *c = (double *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] * b[i];
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_div(void *pState, RingTensor *pA, RingTensor *pB) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (!ring_tensor_shapes_equal(pA, pB)) return NULL;
	pOut = ring_tensor_new(pState, pA->nDataType, pA->nDims, pA->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pA);

	if (pA->lContiguous && pB->lContiguous) {
		if (pA->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *a = (float *)ring_tensor_data(pA);
			float *b = (float *)ring_tensor_data(pB);
			float *c = (float *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = (b[i] != 0.0f) ? (a[i] / b[i]) : 0.0f;
		} else if (pA->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *a = (double *)ring_tensor_data(pA);
			double *b = (double *)ring_tensor_data(pB);
			double *c = (double *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = (b[i] != 0.0) ? (a[i] / b[i]) : 0.0;
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_scale(void *pState, RingTensor *pA, double nScalar) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (pA == NULL) return NULL;
	pOut = ring_tensor_new(pState, pA->nDataType, pA->nDims, pA->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pA);

	if (pA->lContiguous) {
		if (pA->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *a = (float *)ring_tensor_data(pA);
			float *c = (float *)ring_tensor_data(pOut);
			float s = (float)nScalar;
			for (i = 0; i < nTotal; i++) c[i] = a[i] * s;
		} else if (pA->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *a = (double *)ring_tensor_data(pA);
			double *c = (double *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] * nScalar;
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_add_scalar(void *pState, RingTensor *pA, double nScalar) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (pA == NULL) return NULL;
	pOut = ring_tensor_new(pState, pA->nDataType, pA->nDims, pA->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pA);

	if (pA->lContiguous) {
		if (pA->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *a = (float *)ring_tensor_data(pA);
			float *c = (float *)ring_tensor_data(pOut);
			float s = (float)nScalar;
			for (i = 0; i < nTotal; i++) c[i] = a[i] + s;
		} else if (pA->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *a = (double *)ring_tensor_data(pA);
			double *c = (double *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) c[i] = a[i] + nScalar;
		}
	}
	return pOut;
}

/* ==================================================================== */
/*          High-Performance Matrix Multiplication (GEMM)               */
/* ==================================================================== */

#define GEMM_BLOCK_SIZE 32

static void ring_gemm_f32(size_t M, size_t N, size_t K, const float *A, size_t lda, const float *B, size_t ldb, float *C, size_t ldc) {
	size_t ii, jj, kk, i, j, k;
	for (ii = 0; ii < M; ii += GEMM_BLOCK_SIZE) {
		size_t i_end = (ii + GEMM_BLOCK_SIZE < M) ? ii + GEMM_BLOCK_SIZE : M;
		for (kk = 0; kk < K; kk += GEMM_BLOCK_SIZE) {
			size_t k_end = (kk + GEMM_BLOCK_SIZE < K) ? kk + GEMM_BLOCK_SIZE : K;
			for (jj = 0; jj < N; jj += GEMM_BLOCK_SIZE) {
				size_t j_end = (jj + GEMM_BLOCK_SIZE < N) ? jj + GEMM_BLOCK_SIZE : N;
				for (i = ii; i < i_end; i++) {
					for (k = kk; k < k_end; k++) {
						float a_ik = A[i * lda + k];
						for (j = jj; j < j_end; j++) {
							C[i * ldc + j] += a_ik * B[k * ldb + j];
						}
					}
				}
			}
		}
	}
}

RING_API RingTensor *ring_tensor_matmul(void *pState, RingTensor *pA, RingTensor *pB) {
	size_t M, K, N;
	size_t aShapeOut[RING_TENSOR_MAX_DIMS];
	uint32_t nDimsOut;
	RingTensor *pC;

	if (pA == NULL || pB == NULL) return NULL;

	/* 2D x 2D: [M, K] x [K, N] -> [M, N] */
	if (pA->nDims == 2 && pB->nDims == 2) {
		M = pA->aShape[0];
		K = pA->aShape[1];
		if (pB->aShape[0] != K) return NULL;
		N = pB->aShape[1];

		nDimsOut = 2;
		aShapeOut[0] = M;
		aShapeOut[1] = N;
		pC = ring_tensor_new(pState, RING_TENSOR_TYPE_FLOAT32, nDimsOut, aShapeOut);
		if (pC == NULL) return NULL;

		ring_gemm_f32(M, N, K,
			(const float *)ring_tensor_data(pA), K,
			(const float *)ring_tensor_data(pB), N,
			(float *)ring_tensor_data(pC), N);
		return pC;
	}

	/* Batched 3D GEMM: [B, M, K] x [B, K, N] -> [B, M, N] */
	if (pA->nDims == 3 && pB->nDims == 3) {
		size_t B_count = pA->aShape[0];
		size_t b;
		if (pB->aShape[0] != B_count) return NULL;
		M = pA->aShape[1];
		K = pA->aShape[2];
		if (pB->aShape[1] != K) return NULL;
		N = pB->aShape[2];

		nDimsOut = 3;
		aShapeOut[0] = B_count;
		aShapeOut[1] = M;
		aShapeOut[2] = N;
		pC = ring_tensor_new(pState, RING_TENSOR_TYPE_FLOAT32, nDimsOut, aShapeOut);
		if (pC == NULL) return NULL;

		for (b = 0; b < B_count; b++) {
			const float *pA_batch = (const float *)ring_tensor_data(pA) + b * M * K;
			const float *pB_batch = (const float *)ring_tensor_data(pB) + b * K * N;
			float *pC_batch = (float *)ring_tensor_data(pC) + b * M * N;
			ring_gemm_f32(M, N, K, pA_batch, K, pB_batch, N, pC_batch, N);
		}
		return pC;
	}

	return NULL;
}

/* ==================================================================== */
/*                  Neural Network Activations                          */
/* ==================================================================== */

RING_API RingTensor *ring_tensor_relu(void *pState, RingTensor *pSource) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (pSource == NULL) return NULL;
	pOut = ring_tensor_new(pState, pSource->nDataType, pSource->nDims, pSource->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pSource);

	if (pSource->lContiguous) {
		if (pSource->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *src = (float *)ring_tensor_data(pSource);
			float *dst = (float *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) dst[i] = (src[i] > 0.0f) ? src[i] : 0.0f;
		} else if (pSource->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *src = (double *)ring_tensor_data(pSource);
			double *dst = (double *)ring_tensor_data(pOut);
			for (i = 0; i < nTotal; i++) dst[i] = (src[i] > 0.0) ? src[i] : 0.0;
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_gelu(void *pState, RingTensor *pSource) {
	RingTensor *pOut;
	size_t nTotal, i;
	const float kSqrt2OverPi = 0.7978845608028654f;
	const float kCoeff = 0.044715f;

	if (pSource == NULL) return NULL;
	pOut = ring_tensor_new(pState, pSource->nDataType, pSource->nDims, pSource->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pSource);

	if (pSource->lContiguous && pSource->nDataType == RING_TENSOR_TYPE_FLOAT32) {
		float *src = (float *)ring_tensor_data(pSource);
		float *dst = (float *)ring_tensor_data(pOut);
		for (i = 0; i < nTotal; i++) {
			float x = src[i];
			float inner = kSqrt2OverPi * (x + kCoeff * x * x * x);
			dst[i] = 0.5f * x * (1.0f + (float)tanh(inner));
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_sigmoid(void *pState, RingTensor *pSource) {
	RingTensor *pOut;
	size_t nTotal, i;
	if (pSource == NULL) return NULL;
	pOut = ring_tensor_new(pState, pSource->nDataType, pSource->nDims, pSource->aShape);
	if (pOut == NULL) return NULL;
	nTotal = ring_tensor_total_elements(pSource);

	if (pSource->lContiguous && pSource->nDataType == RING_TENSOR_TYPE_FLOAT32) {
		float *src = (float *)ring_tensor_data(pSource);
		float *dst = (float *)ring_tensor_data(pOut);
		for (i = 0; i < nTotal; i++) {
			dst[i] = 1.0f / (1.0f + (float)exp(-src[i]));
		}
	}
	return pOut;
}

RING_API RingTensor *ring_tensor_softmax(void *pState, RingTensor *pSource, int nDim) {
	RingTensor *pOut;
	size_t nRows = 1, nCols = 1, r, c;
	(void)nDim;

	if (pSource == NULL || pSource->nDims == 0) return NULL;
	pOut = ring_tensor_new(pState, pSource->nDataType, pSource->nDims, pSource->aShape);
	if (pOut == NULL) return NULL;

	if (pSource->nDims == 1) {
		nRows = 1;
		nCols = pSource->aShape[0];
	} else {
		uint32_t d;
		for (d = 0; d < pSource->nDims - 1; d++) {
			nRows *= pSource->aShape[d];
		}
		nCols = pSource->aShape[pSource->nDims - 1];
	}

	if (pSource->lContiguous && pSource->nDataType == RING_TENSOR_TYPE_FLOAT32) {
		float *src = (float *)ring_tensor_data(pSource);
		float *dst = (float *)ring_tensor_data(pOut);

		for (r = 0; r < nRows; r++) {
			float *pRowSrc = src + r * nCols;
			float *pRowDst = dst + r * nCols;
			float maxVal = pRowSrc[0];
			float sumExp = 0.0f;

			for (c = 1; c < nCols; c++) {
				if (pRowSrc[c] > maxVal) maxVal = pRowSrc[c];
			}
			for (c = 0; c < nCols; c++) {
				pRowDst[c] = (float)exp(pRowSrc[c] - maxVal);
				sumExp += pRowDst[c];
			}
			for (c = 0; c < nCols; c++) {
				pRowDst[c] /= (sumExp > 0.0f) ? sumExp : 1.0f;
			}
		}
	}
	return pOut;
}

/* ==================================================================== */
/*                        Reductions                                    */
/* ==================================================================== */

RING_API double ring_tensor_sum(const RingTensor *pTensor) {
	double sum = 0.0;
	size_t nTotal, i;
	if (pTensor == NULL) return 0.0;
	nTotal = ring_tensor_total_elements(pTensor);
	if (pTensor->lContiguous) {
		if (pTensor->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *p = (float *)ring_tensor_data(pTensor);
			for (i = 0; i < nTotal; i++) sum += (double)p[i];
		} else if (pTensor->nDataType == RING_TENSOR_TYPE_FLOAT64) {
			double *p = (double *)ring_tensor_data(pTensor);
			for (i = 0; i < nTotal; i++) sum += p[i];
		}
	}
	return sum;
}

RING_API double ring_tensor_mean(const RingTensor *pTensor) {
	size_t nTotal;
	if (pTensor == NULL) return 0.0;
	nTotal = ring_tensor_total_elements(pTensor);
	if (nTotal == 0) return 0.0;
	return ring_tensor_sum(pTensor) / (double)nTotal;
}

RING_API double ring_tensor_max(const RingTensor *pTensor) {
	double maxVal = -1e30;
	size_t nTotal, i;
	if (pTensor == NULL) return 0.0;
	nTotal = ring_tensor_total_elements(pTensor);
	if (nTotal == 0) return 0.0;
	if (pTensor->lContiguous) {
		if (pTensor->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *p = (float *)ring_tensor_data(pTensor);
			maxVal = (double)p[0];
			for (i = 1; i < nTotal; i++) {
				if ((double)p[i] > maxVal) maxVal = (double)p[i];
			}
		}
	}
	return maxVal;
}

RING_API double ring_tensor_min(const RingTensor *pTensor) {
	double minVal = 1e30;
	size_t nTotal, i;
	if (pTensor == NULL) return 0.0;
	nTotal = ring_tensor_total_elements(pTensor);
	if (nTotal == 0) return 0.0;
	if (pTensor->lContiguous) {
		if (pTensor->nDataType == RING_TENSOR_TYPE_FLOAT32) {
			float *p = (float *)ring_tensor_data(pTensor);
			minVal = (double)p[0];
			for (i = 1; i < nTotal; i++) {
				if ((double)p[i] < minVal) minVal = (double)p[i];
			}
		}
	}
	return minVal;
}

/* ==================================================================== */
/*                  Ring Scripting API Functions                        */
/* ==================================================================== */

static RingTensorType ring_tensor_parse_type_str(const char *cType) {
	if (cType == NULL) return RING_TENSOR_TYPE_FLOAT32;
	if (strcmp(cType, "float32") == 0 || strcmp(cType, "f32") == 0 || strcmp(cType, "FLOAT32") == 0) return RING_TENSOR_TYPE_FLOAT32;
	if (strcmp(cType, "float16") == 0 || strcmp(cType, "f16") == 0 || strcmp(cType, "FLOAT16") == 0) return RING_TENSOR_TYPE_FLOAT16;
	if (strcmp(cType, "int8") == 0    || strcmp(cType, "i8") == 0  || strcmp(cType, "INT8") == 0)    return RING_TENSOR_TYPE_INT8;
	if (strcmp(cType, "int32") == 0   || strcmp(cType, "i32") == 0 || strcmp(cType, "INT32") == 0)   return RING_TENSOR_TYPE_INT32;
	if (strcmp(cType, "float64") == 0 || strcmp(cType, "f64") == 0 || strcmp(cType, "double") == 0 || strcmp(cType, "FLOAT64") == 0) return RING_TENSOR_TYPE_FLOAT64;
	return RING_TENSOR_TYPE_FLOAT32;
}

RING_FUNC(ring_tensor_api_new) {
	RingTensor *pTensor;
	RingTensorType nType = RING_TENSOR_TYPE_FLOAT32;
	size_t aShape[RING_TENSOR_MAX_DIMS];
	uint32_t nDims = 0;
	uint32_t i;
	List *pShapeList;

	if (RING_API_PARACOUNT < 1 || RING_API_PARACOUNT > 2) {
		RING_API_ERROR(RING_API_BADPARACOUNT);
		return;
	}

	if (RING_API_ISLIST(1)) {
		pShapeList = RING_API_GETLIST(1);
		nDims = (uint32_t)ring_list_getsize(pShapeList);
		if (nDims == 0 || nDims > RING_TENSOR_MAX_DIMS) {
			RING_API_ERROR(RING_API_BADPARARANGE);
			return;
		}
		for (i = 0; i < nDims; i++) {
			aShape[i] = (size_t)ring_list_getdouble(pShapeList, (unsigned int)(i + 1));
			if (aShape[i] == 0) {
				RING_API_ERROR(RING_API_BADPARAVALUE);
				return;
			}
		}
	} else if (RING_API_ISNUMBER(1)) {
		nDims = 1;
		aShape[0] = (size_t)RING_API_GETNUMBER(1);
		if (aShape[0] == 0) {
			RING_API_ERROR(RING_API_BADPARAVALUE);
			return;
		}
	} else {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	if (RING_API_PARACOUNT == 2) {
		if (!RING_API_ISSTRING(2)) {
			RING_API_ERROR(RING_API_BADPARATYPE);
			return;
		}
		nType = ring_tensor_parse_type_str(RING_API_GETSTRING(2));
	}

	pTensor = ring_tensor_new(RING_API_STATE, nType, nDims, aShape);
	if (pTensor == NULL) {
		RING_API_ERROR(RING_OOM);
		return;
	}

	RING_API_RETMANAGEDCPOINTER(pTensor, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_from_list) {
	RingTensor *pTensor;
	RingTensorType nType = RING_TENSOR_TYPE_FLOAT32;

	if (RING_API_PARACOUNT < 1 || RING_API_PARACOUNT > 2) {
		RING_API_ERROR(RING_API_BADPARACOUNT);
		return;
	}
	if (!RING_API_ISLIST(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	if (RING_API_PARACOUNT == 2) {
		if (!RING_API_ISSTRING(2)) {
			RING_API_ERROR(RING_API_BADPARATYPE);
			return;
		}
		nType = ring_tensor_parse_type_str(RING_API_GETSTRING(2));
	}

	pTensor = ring_list_to_tensor(RING_API_STATE, RING_API_GETLIST(1), nType);
	if (pTensor == NULL) {
		RING_API_ERROR(RING_OOM);
		return;
	}

	RING_API_RETMANAGEDCPOINTER(pTensor, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_to_list) {
	RingTensor *pTensor;
	List *pList;

	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	pList = ring_tensor_to_list(RING_API_STATE, pTensor);
	if (pList == NULL) {
		RING_API_ERROR(RING_OOM);
		return;
	}

	RING_API_RETLIST(pList);
}

RING_FUNC(ring_tensor_api_shape) {
	RingTensor *pTensor;
	List *pList;
	uint32_t i;

	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	pList = RING_API_NEWLIST;
	for (i = 0; i < pTensor->nDims; i++) {
		ring_list_adddouble(pList, (double)pTensor->aShape[i]);
	}
	RING_API_RETLIST(pList);
}

RING_FUNC(ring_tensor_api_dims) {
	RingTensor *pTensor;

	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	RING_API_RETNUMBER((double)pTensor->nDims);
}

RING_FUNC(ring_tensor_api_elements) {
	RingTensor *pTensor;

	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	RING_API_RETNUMBER((double)ring_tensor_total_elements(pTensor));
}

RING_FUNC(ring_tensor_api_type) {
	RingTensor *pTensor;

	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	switch (pTensor->nDataType) {
	case RING_TENSOR_TYPE_FLOAT32: RING_API_RETSTRING("Float32"); break;
	case RING_TENSOR_TYPE_FLOAT16: RING_API_RETSTRING("Float16"); break;
	case RING_TENSOR_TYPE_INT8:    RING_API_RETSTRING("Int8"); break;
	case RING_TENSOR_TYPE_INT32:   RING_API_RETSTRING("Int32"); break;
	case RING_TENSOR_TYPE_FLOAT64: RING_API_RETSTRING("Float64"); break;
	default:                       RING_API_RETSTRING("Unknown"); break;
	}
}

RING_FUNC(ring_tensor_api_slice) {
	RingTensor *pSource, *pSlice;
	uint32_t nDim;
	size_t nStart, nEnd;
	int64_t nStep = 1;

	if (RING_API_PARACOUNT < 4 || RING_API_PARACOUNT > 5) {
		RING_API_ERROR(RING_API_BADPARACOUNT);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISNUMBER(2) || !RING_API_ISNUMBER(3) || !RING_API_ISNUMBER(4)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pSource = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pSource == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	/* Ring uses 1-based indexing for dimensions: Dim 1 -> Index 0 */
	nDim = (uint32_t)RING_API_GETNUMBER(2);
	if (nDim < 1 || nDim > pSource->nDims) {
		RING_API_ERROR(RING_API_BADPARARANGE);
		return;
	}
	nDim -= 1;

	/* 1-based indices for start and end */
	nStart = (size_t)RING_API_GETNUMBER(3);
	nEnd   = (size_t)RING_API_GETNUMBER(4);
	if (nStart >= 1) nStart -= 1; else nStart = 0;
	if (nEnd > pSource->aShape[nDim]) nEnd = pSource->aShape[nDim];

	if (RING_API_PARACOUNT == 5) {
		if (!RING_API_ISNUMBER(5)) {
			RING_API_ERROR(RING_API_BADPARATYPE);
			return;
		}
		nStep = (int64_t)RING_API_GETNUMBER(5);
		if (nStep <= 0) {
			RING_API_ERROR(RING_API_BADPARAVALUE);
			return;
		}
	}

	pSlice = ring_tensor_slice(RING_API_STATE, pSource, nDim, nStart, nEnd, nStep);
	if (pSlice == NULL) {
		RING_API_ERROR(RING_API_INTERNALFAILURE);
		return;
	}

	RING_API_RETMANAGEDCPOINTER(pSlice, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_reshape) {
	RingTensor *pSource, *pReshaped;
	List *pShapeList;
	size_t aNewShape[RING_TENSOR_MAX_DIMS];
	uint32_t nDims, i;

	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISLIST(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pSource = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pSource == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	pShapeList = RING_API_GETLIST(2);
	nDims = (uint32_t)ring_list_getsize(pShapeList);
	if (nDims == 0 || nDims > RING_TENSOR_MAX_DIMS) {
		RING_API_ERROR(RING_API_BADPARARANGE);
		return;
	}

	for (i = 0; i < nDims; i++) {
		aNewShape[i] = (size_t)ring_list_getdouble(pShapeList, (unsigned int)(i + 1));
	}

	pReshaped = ring_tensor_reshape(RING_API_STATE, pSource, nDims, aNewShape);
	if (pReshaped == NULL) {
		RING_API_ERROR("Reshape failed! Total elements must match and tensor must be contiguous.");
		return;
	}

	RING_API_RETMANAGEDCPOINTER(pReshaped, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_print) {
	RingTensor *pTensor;

	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	ring_tensor_print(RING_API_STATE, pTensor);
}

RING_FUNC(ring_tensor_api_istensor) {
	List *pList;

	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}

	if (RING_API_ISCPOINTER(1)) {
		pList = RING_API_GETLIST(1);
		if (strcmp(ring_list_getstring(pList, RING_CPOINTER_TYPE), "TENSOR") == 0) {
			RING_API_RETNUMBER(1.0);
			return;
		}
	}
	RING_API_RETNUMBER(0.0);
}

RING_FUNC(ring_tensor_api_get) {
	RingTensor *pTensor;
	size_t aIndices[RING_TENSOR_MAX_DIMS];
	uint32_t i, nCount;
	double val;

	if (RING_API_PARACOUNT < 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	if (RING_API_ISLIST(2)) {
		List *pList = RING_API_GETLIST(2);
		nCount = (uint32_t)ring_list_getsize(pList);
		if (nCount != pTensor->nDims) {
			RING_API_ERROR("Index count must match tensor dimensions!");
			return;
		}
		for (i = 0; i < nCount; i++) {
			double idx = ring_list_getdouble(pList, (unsigned int)(i + 1));
			if (idx < 1.0 || (size_t)idx > pTensor->aShape[i]) {
				RING_API_ERROR("Tensor index out of bounds!");
				return;
			}
			aIndices[i] = (size_t)(idx - 1.0);
		}
	} else {
		nCount = (uint32_t)(RING_API_PARACOUNT - 1);
		if (nCount != pTensor->nDims) {
			RING_API_ERROR("Index count must match tensor dimensions!");
			return;
		}
		for (i = 0; i < nCount; i++) {
			double idx = RING_API_GETNUMBER(i + 2);
			if (idx < 1.0 || (size_t)idx > pTensor->aShape[i]) {
				RING_API_ERROR("Tensor index out of bounds!");
				return;
			}
			aIndices[i] = (size_t)(idx - 1.0);
		}
	}

	val = ring_tensor_get_element(pTensor, aIndices);
	RING_API_RETNUMBER(val);
}

RING_FUNC(ring_tensor_api_set) {
	RingTensor *pTensor;
	size_t aIndices[RING_TENSOR_MAX_DIMS];
	uint32_t i, nCount;
	double nVal;

	if (RING_API_PARACOUNT < 3) {
		RING_API_ERROR("tensor_set requires tensor, indices, and value!");
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}

	if (RING_API_ISLIST(2)) {
		List *pList = RING_API_GETLIST(2);
		nCount = (uint32_t)ring_list_getsize(pList);
		if (nCount != pTensor->nDims) {
			RING_API_ERROR("Index count must match tensor dimensions!");
			return;
		}
		for (i = 0; i < nCount; i++) {
			double idx = ring_list_getdouble(pList, (unsigned int)(i + 1));
			if (idx < 1.0 || (size_t)idx > pTensor->aShape[i]) {
				RING_API_ERROR("Tensor index out of bounds!");
				return;
			}
			aIndices[i] = (size_t)(idx - 1.0);
		}
		nVal = RING_API_GETNUMBER(3);
	} else {
		nCount = (uint32_t)(RING_API_PARACOUNT - 2);
		if (nCount != pTensor->nDims) {
			RING_API_ERROR("Index count must match tensor dimensions!");
			return;
		}
		for (i = 0; i < nCount; i++) {
			double idx = RING_API_GETNUMBER(i + 2);
			if (idx < 1.0 || (size_t)idx > pTensor->aShape[i]) {
				RING_API_ERROR("Tensor index out of bounds!");
				return;
			}
			aIndices[i] = (size_t)(idx - 1.0);
		}
		nVal = RING_API_GETNUMBER(RING_API_PARACOUNT);
	}

	ring_tensor_set_element(pTensor, aIndices, nVal);
}

RING_FUNC(ring_tensor_api_fill) {
	RingTensor *pTensor;
	double nVal;

	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISNUMBER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (pTensor == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}
	nVal = RING_API_GETNUMBER(2);
	ring_tensor_fill(pTensor, nVal);
}

RING_FUNC(ring_tensor_api_add) {
	RingTensor *pA, *pB, *pC;
	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISCPOINTER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pA = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pB = (RingTensor *)RING_API_GETCPOINTER(2, "TENSOR");
	if (pA == NULL || pB == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}
	pC = ring_tensor_add(RING_API_STATE, pA, pB);
	if (pC == NULL) {
		RING_API_ERROR("tensor_add failed: Shapes must match!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pC, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_sub) {
	RingTensor *pA, *pB, *pC;
	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISCPOINTER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pA = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pB = (RingTensor *)RING_API_GETCPOINTER(2, "TENSOR");
	if (pA == NULL || pB == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}
	pC = ring_tensor_sub(RING_API_STATE, pA, pB);
	if (pC == NULL) {
		RING_API_ERROR("tensor_sub failed: Shapes must match!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pC, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_mul) {
	RingTensor *pA, *pB, *pC;
	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISCPOINTER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pA = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pB = (RingTensor *)RING_API_GETCPOINTER(2, "TENSOR");
	if (pA == NULL || pB == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}
	pC = ring_tensor_mul(RING_API_STATE, pA, pB);
	if (pC == NULL) {
		RING_API_ERROR("tensor_mul failed: Shapes must match!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pC, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_div) {
	RingTensor *pA, *pB, *pC;
	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISCPOINTER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pA = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pB = (RingTensor *)RING_API_GETCPOINTER(2, "TENSOR");
	if (pA == NULL || pB == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}
	pC = ring_tensor_div(RING_API_STATE, pA, pB);
	if (pC == NULL) {
		RING_API_ERROR("tensor_div failed: Shapes must match!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pC, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_scale) {
	RingTensor *pA, *pC;
	double nScalar;
	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISNUMBER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pA = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	nScalar = RING_API_GETNUMBER(2);
	pC = ring_tensor_scale(RING_API_STATE, pA, nScalar);
	if (pC == NULL) {
		RING_API_ERROR("tensor_scale failed!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pC, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_add_scalar) {
	RingTensor *pA, *pC;
	double nScalar;
	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISNUMBER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pA = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	nScalar = RING_API_GETNUMBER(2);
	pC = ring_tensor_add_scalar(RING_API_STATE, pA, nScalar);
	if (pC == NULL) {
		RING_API_ERROR("tensor_add_scalar failed!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pC, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_matmul) {
	RingTensor *pA, *pB, *pC;
	if (RING_API_PARACOUNT != 2) {
		RING_API_ERROR(RING_API_MISS2PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1) || !RING_API_ISCPOINTER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pA = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pB = (RingTensor *)RING_API_GETCPOINTER(2, "TENSOR");
	if (pA == NULL || pB == NULL) {
		RING_API_ERROR(RING_API_NULLPOINTER);
		return;
	}
	pC = ring_tensor_matmul(RING_API_STATE, pA, pB);
	if (pC == NULL) {
		RING_API_ERROR("tensor_matmul failed: Incompatible dimensions for matrix multiplication!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pC, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_relu) {
	RingTensor *pSource, *pOut;
	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pSource = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pOut = ring_tensor_relu(RING_API_STATE, pSource);
	if (pOut == NULL) {
		RING_API_ERROR("tensor_relu failed!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pOut, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_gelu) {
	RingTensor *pSource, *pOut;
	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pSource = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pOut = ring_tensor_gelu(RING_API_STATE, pSource);
	if (pOut == NULL) {
		RING_API_ERROR("tensor_gelu failed!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pOut, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_sigmoid) {
	RingTensor *pSource, *pOut;
	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pSource = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	pOut = ring_tensor_sigmoid(RING_API_STATE, pSource);
	if (pOut == NULL) {
		RING_API_ERROR("tensor_sigmoid failed!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pOut, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_softmax) {
	RingTensor *pSource, *pOut;
	int nDim = -1;
	if (RING_API_PARACOUNT < 1 || RING_API_PARACOUNT > 2) {
		RING_API_ERROR(RING_API_BADPARACOUNT);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pSource = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	if (RING_API_PARACOUNT == 2) {
		nDim = (int)RING_API_GETNUMBER(2);
	}
	pOut = ring_tensor_softmax(RING_API_STATE, pSource, nDim);
	if (pOut == NULL) {
		RING_API_ERROR("tensor_softmax failed!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pOut, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_tensor_api_sum) {
	RingTensor *pTensor;
	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	RING_API_RETNUMBER(ring_tensor_sum(pTensor));
}

RING_FUNC(ring_tensor_api_mean) {
	RingTensor *pTensor;
	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	RING_API_RETNUMBER(ring_tensor_mean(pTensor));
}

RING_FUNC(ring_tensor_api_max) {
	RingTensor *pTensor;
	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	RING_API_RETNUMBER(ring_tensor_max(pTensor));
}

RING_FUNC(ring_tensor_api_min) {
	RingTensor *pTensor;
	if (RING_API_PARACOUNT != 1) {
		RING_API_ERROR(RING_API_MISS1PARA);
		return;
	}
	if (!RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pTensor = (RingTensor *)RING_API_GETCPOINTER(1, "TENSOR");
	RING_API_RETNUMBER(ring_tensor_min(pTensor));
}

RING_FUNC(ring_tensor_api_ggml_version) {
	RING_API_RETSTRING("GGML Core (ANSI C99 Embedded)");
}

RING_FUNC(ring_tensor_api_ggml_fp32_to_fp16) {
	float val;
	ggml_fp16_t h;
	if (RING_API_PARACOUNT != 1 || !RING_API_ISNUMBER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	val = (float)RING_API_GETNUMBER(1);
	h = ggml_fp32_to_fp16(val);
	RING_API_RETNUMBER((double)h);
}

RING_FUNC(ring_tensor_api_ggml_fp16_to_fp32) {
	ggml_fp16_t h;
	float val;
	if (RING_API_PARACOUNT != 1 || !RING_API_ISNUMBER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	h = (ggml_fp16_t)RING_API_GETNUMBER(1);
	val = ggml_fp16_to_fp32(h);
	RING_API_RETNUMBER((double)val);
}

/* Register all Tensor functions in Ring VM */
RING_API void ring_tensor_loadfunctions(RingState *pRingState) {
	/* Ensure GGML lookup tables (FP16, GELU, EXP) and internal state are initialized */
	{
		struct ggml_init_params params;
		struct ggml_context *ctx;
		ggml_time_init();
		params.mem_size = 1024 * 1024;
		params.mem_buffer = NULL;
		ctx = ggml_init(params);
		if (ctx) ggml_free(ctx);
	}

	RING_API_REGISTER("tensor", ring_tensor_api_new);
	RING_API_REGISTER("tensor_new", ring_tensor_api_new);
	RING_API_REGISTER("tensor_from_list", ring_tensor_api_from_list);
	RING_API_REGISTER("tensor_to_list", ring_tensor_api_to_list);
	RING_API_REGISTER("tensor_shape", ring_tensor_api_shape);
	RING_API_REGISTER("tensor_dims", ring_tensor_api_dims);
	RING_API_REGISTER("tensor_elements", ring_tensor_api_elements);
	RING_API_REGISTER("tensor_type", ring_tensor_api_type);
	RING_API_REGISTER("tensor_slice", ring_tensor_api_slice);
	RING_API_REGISTER("tensor_reshape", ring_tensor_api_reshape);
	RING_API_REGISTER("tensor_print", ring_tensor_api_print);
	RING_API_REGISTER("istensor", ring_tensor_api_istensor);

	/* Indexing & Mutation */
	RING_API_REGISTER("tensor_get", ring_tensor_api_get);
	RING_API_REGISTER("tensor_set", ring_tensor_api_set);
	RING_API_REGISTER("tensor_fill", ring_tensor_api_fill);

	/* Element-wise Math */
	RING_API_REGISTER("tensor_add", ring_tensor_api_add);
	RING_API_REGISTER("tensor_sub", ring_tensor_api_sub);
	RING_API_REGISTER("tensor_mul", ring_tensor_api_mul);
	RING_API_REGISTER("tensor_div", ring_tensor_api_div);
	RING_API_REGISTER("tensor_scale", ring_tensor_api_scale);
	RING_API_REGISTER("tensor_mul_scalar", ring_tensor_api_scale);
	RING_API_REGISTER("tensor_add_scalar", ring_tensor_api_add_scalar);

	/* High-Performance Matrix Multiplication */
	RING_API_REGISTER("tensor_matmul", ring_tensor_api_matmul);

	/* Neural Activations */
	RING_API_REGISTER("tensor_relu", ring_tensor_api_relu);
	RING_API_REGISTER("tensor_gelu", ring_tensor_api_gelu);
	RING_API_REGISTER("tensor_sigmoid", ring_tensor_api_sigmoid);
	RING_API_REGISTER("tensor_softmax", ring_tensor_api_softmax);

	/* Reductions */
	RING_API_REGISTER("tensor_sum", ring_tensor_api_sum);
	RING_API_REGISTER("tensor_mean", ring_tensor_api_mean);
	RING_API_REGISTER("tensor_max", ring_tensor_api_max);
	RING_API_REGISTER("tensor_min", ring_tensor_api_min);

	/* GGML Integration & Precision */
	RING_API_REGISTER("ggml_version", ring_tensor_api_ggml_version);
	RING_API_REGISTER("ggml_fp32_to_fp16", ring_tensor_api_ggml_fp32_to_fp16);
	RING_API_REGISTER("ggml_fp16_to_fp32", ring_tensor_api_ggml_fp16_to_fp32);
}

