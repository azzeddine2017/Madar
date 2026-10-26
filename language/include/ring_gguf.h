/*
**  Madar - High-Performance AI-Native Runtime
**  GGUF Model Loader & Tensor Parser (Pure ANSI C / C99)
**  Zero-Copy Memory-Mapped Architecture
*/

#ifndef ring_gguf_h
#define ring_gguf_h

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define RING_GGUF_MAGIC 0x46554747 /* "GGUF" in Little Endian */
#define RING_GGUF_DEFAULT_ALIGNMENT 32

/* GGUF Value Types */
typedef enum RingGGUFType {
	RING_GGUF_TYPE_UINT8   = 0,
	RING_GGUF_TYPE_INT8    = 1,
	RING_GGUF_TYPE_UINT16  = 2,
	RING_GGUF_TYPE_INT16   = 3,
	RING_GGUF_TYPE_UINT32  = 4,
	RING_GGUF_TYPE_INT32   = 5,
	RING_GGUF_TYPE_FLOAT32 = 6,
	RING_GGUF_TYPE_BOOL    = 7,
	RING_GGUF_TYPE_STRING  = 8,
	RING_GGUF_TYPE_ARRAY   = 9,
	RING_GGUF_TYPE_UINT64  = 10,
	RING_GGUF_TYPE_INT64   = 11,
	RING_GGUF_TYPE_FLOAT64 = 12
} RingGGUFType;

/* GGUF / GGML Tensor Types */
typedef enum RingGGUFTensorType {
	RING_GGUF_TENSOR_F32     = 0,
	RING_GGUF_TENSOR_F16     = 1,
	RING_GGUF_TENSOR_Q4_0    = 2,
	RING_GGUF_TENSOR_Q4_1    = 3,
	RING_GGUF_TENSOR_Q5_0    = 6,
	RING_GGUF_TENSOR_Q5_1    = 7,
	RING_GGUF_TENSOR_Q8_0    = 8,
	RING_GGUF_TENSOR_Q8_1    = 9,
	RING_GGUF_TENSOR_Q6_K    = 14,
	RING_GGUF_TENSOR_I8      = 24,
	RING_GGUF_TENSOR_I16     = 25,
	RING_GGUF_TENSOR_I32     = 26,
	RING_GGUF_TENSOR_I64     = 27,
	RING_GGUF_TENSOR_F64     = 28
} RingGGUFTensorType;

/* GGUF String */
typedef struct RingGGUFString {
	uint64_t nLen;
	char *pStr;
} RingGGUFString;

/* GGUF Value */
typedef struct RingGGUFValue {
	RingGGUFType nType;
	union {
		uint8_t u8;
		int8_t i8;
		uint16_t u16;
		int16_t i16;
		uint32_t u32;
		int32_t i32;
		float f32;
		uint64_t u64;
		int64_t i64;
		double f64;
		int b;
		RingGGUFString str;
		struct {
			RingGGUFType nItemType;
			uint64_t nCount;
			void *pItems;
		} arr;
	} val;
} RingGGUFValue;

/* GGUF Metadata Key-Value */
typedef struct RingGGUFKV {
	char *pKey;
	RingGGUFValue value;
} RingGGUFKV;

/* GGUF Tensor Info Header */
typedef struct RingGGUFTensorInfo {
	char *pName;
	uint32_t nDims;
	uint64_t aDims[RING_TENSOR_MAX_DIMS];
	uint32_t nType;       /* RingGGUFTensorType */
	uint64_t nOffset;     /* Byte offset relative to data section */
	uint64_t nSize;       /* Total byte size of tensor raw data */
	uint64_t nElements;   /* Total number of elements */
} RingGGUFTensorInfo;

/* GGUF Context */
typedef struct RingGGUF {
	char *pFileName;
	uint32_t nVersion;
	uint64_t nTensors;
	uint64_t nKV;
	uint32_t nAlignment;
	uint64_t nDataOffset; /* Absolute file offset where tensor raw data starts */
	uint64_t nFileSize;

	RingGGUFKV *aKV;
	RingGGUFTensorInfo *aTensors;

	/* Memory Mapping Context */
	const uint8_t *pMappedData;
	size_t nMappedSize;
	void *hFile;
	void *hMapFile;
} RingGGUF;

/* Block Structures for Quantized Dequantization */
#pragma pack(push, 1)
typedef struct RingGGUFBlockQ4_0 {
	uint16_t d;          /* FP16 scale */
	uint8_t qs[16];      /* 16 bytes = 32 nibbles (4-bit values) */
} RingGGUFBlockQ4_0;

typedef struct RingGGUFBlockQ8_0 {
	uint16_t d;          /* FP16 scale */
	int8_t qs[32];       /* 32 bytes = 32 int8 values */
} RingGGUFBlockQ8_0;

typedef struct RingGGUFBlockQ6_K {
	uint8_t ql[128];     /* Lower 4 bits of 6-bit quants */
	uint8_t qh[64];      /* Upper 2 bits of 6-bit quants */
	int8_t  scales[16];  /* 8-bit scales for 16-weight sub-blocks */
	uint16_t d;          /* FP16 scale */
} RingGGUFBlockQ6_K;
#pragma pack(pop)

/* Core C APIs */
RING_API RingGGUF *ring_gguf_open(const char *cFileName);
RING_API void ring_gguf_close(RingGGUF *pGGUF);

RING_API const char *ring_gguf_type_name(RingGGUFType nType);
RING_API const char *ring_gguf_tensor_type_name(uint32_t nType);

RING_API RingGGUFKV *ring_gguf_find_kv(RingGGUF *pGGUF, const char *cKey);
RING_API RingGGUFTensorInfo *ring_gguf_find_tensor(RingGGUF *pGGUF, const char *cName);
RING_API RingGGUFTensorInfo *ring_gguf_get_tensor_by_index(RingGGUF *pGGUF, unsigned int nIndex);

RING_API const void *ring_gguf_get_tensor_data(RingGGUF *pGGUF, RingGGUFTensorInfo *pInfo);
RING_API uint64_t ring_gguf_calc_tensor_size(uint32_t nType, uint64_t nElements);

/* Native Madar Tensor Integration */
RING_API RingTensor *ring_gguf_load_tensor(void *pRingState, RingGGUF *pGGUF, const char *cName);
RING_API RingTensor *ring_gguf_load_tensor_by_index(void *pRingState, RingGGUF *pGGUF, unsigned int nIndex);
RING_API RingTensor *ring_gguf_load_tensor_f32(void *pRingState, RingGGUF *pGGUF, const char *cName);

/* Dequantization Helpers */
RING_API void ring_gguf_dequantize_q4_0(const void *pSrc, float *pDst, uint64_t nElements);
RING_API void ring_gguf_dequantize_q8_0(const void *pSrc, float *pDst, uint64_t nElements);
RING_API void ring_gguf_dequantize_q6_k(const void *pSrc, float *pDst, uint64_t nElements);
RING_API void ring_gguf_dequantize_f16(const void *pSrc, float *pDst, uint64_t nElements);

/* Scripting Registration */
RING_API void ring_gguf_loadfunctions(void *pRingState);

#endif /* ring_gguf_h */
