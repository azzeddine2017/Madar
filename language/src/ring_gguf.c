/*
**  Madar - High-Performance AI-Native Runtime
**  GGUF Model Loader & Tensor Parser (Pure ANSI C / C99)
**  Zero-Copy Memory-Mapped Architecture
*/

#include "ring.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#endif

/*
================================================================================
  Type Names & Helpers
================================================================================
*/

RING_API const char *ring_gguf_type_name(RingGGUFType nType) {
	switch (nType) {
	case RING_GGUF_TYPE_UINT8:   return "UINT8";
	case RING_GGUF_TYPE_INT8:    return "INT8";
	case RING_GGUF_TYPE_UINT16:  return "UINT16";
	case RING_GGUF_TYPE_INT16:   return "INT16";
	case RING_GGUF_TYPE_UINT32:  return "UINT32";
	case RING_GGUF_TYPE_INT32:   return "INT32";
	case RING_GGUF_TYPE_FLOAT32: return "FLOAT32";
	case RING_GGUF_TYPE_BOOL:    return "BOOL";
	case RING_GGUF_TYPE_STRING:  return "STRING";
	case RING_GGUF_TYPE_ARRAY:   return "ARRAY";
	case RING_GGUF_TYPE_UINT64:  return "UINT64";
	case RING_GGUF_TYPE_INT64:   return "INT64";
	case RING_GGUF_TYPE_FLOAT64: return "FLOAT64";
	default:                     return "UNKNOWN";
	}
}

RING_API const char *ring_gguf_tensor_type_name(uint32_t nType) {
	switch (nType) {
	case RING_GGUF_TENSOR_F32:  return "F32";
	case RING_GGUF_TENSOR_F16:  return "F16";
	case RING_GGUF_TENSOR_Q4_0: return "Q4_0";
	case RING_GGUF_TENSOR_Q4_1: return "Q4_1";
	case RING_GGUF_TENSOR_Q5_0: return "Q5_0";
	case RING_GGUF_TENSOR_Q5_1: return "Q5_1";
	case RING_GGUF_TENSOR_Q8_0: return "Q8_0";
	case RING_GGUF_TENSOR_Q8_1: return "Q8_1";
	case RING_GGUF_TENSOR_Q6_K: return "Q6_K";
	case RING_GGUF_TENSOR_I8:   return "I8";
	case RING_GGUF_TENSOR_I16:  return "I16";
	case RING_GGUF_TENSOR_I32:  return "I32";
	case RING_GGUF_TENSOR_I64:  return "I64";
	case RING_GGUF_TENSOR_F64:  return "F64";
	default:                    return "CUSTOM";
	}
}

RING_API uint64_t ring_gguf_calc_tensor_size(uint32_t nType, uint64_t nElements) {
	switch (nType) {
	case RING_GGUF_TENSOR_F32:  return nElements * sizeof(float);
	case RING_GGUF_TENSOR_F16:  return nElements * 2;
	case RING_GGUF_TENSOR_I8:   return nElements * 1;
	case RING_GGUF_TENSOR_I16:  return nElements * 2;
	case RING_GGUF_TENSOR_I32:  return nElements * 4;
	case RING_GGUF_TENSOR_I64:  return nElements * 8;
	case RING_GGUF_TENSOR_F64:  return nElements * sizeof(double);
	case RING_GGUF_TENSOR_Q4_0: return ((nElements + 31) / 32) * sizeof(RingGGUFBlockQ4_0);
	case RING_GGUF_TENSOR_Q4_1: return ((nElements + 31) / 32) * 20;
	case RING_GGUF_TENSOR_Q8_0: return ((nElements + 31) / 32) * sizeof(RingGGUFBlockQ8_0);
	case RING_GGUF_TENSOR_Q8_1: return ((nElements + 31) / 32) * 36;
	case RING_GGUF_TENSOR_Q6_K: return ((nElements + 255) / 256) * sizeof(RingGGUFBlockQ6_K);
	default:                    return nElements * 4;
	}
}

/*
================================================================================
  Binary Stream Reader
================================================================================
*/

typedef struct GGUFReader {
	const uint8_t *pData;
	size_t nSize;
	size_t nPos;
	bool bError;
} GGUFReader;

static bool gguf_read(GGUFReader *r, void *pDest, size_t nBytes) {
	if (r->bError || (r->nPos + nBytes > r->nSize)) {
		r->bError = true;
		return false;
	}
	memcpy(pDest, r->pData + r->nPos, nBytes);
	r->nPos += nBytes;
	return true;
}

static uint32_t gguf_read_u32(GGUFReader *r) {
	uint32_t v = 0;
	gguf_read(r, &v, sizeof(v));
	return v;
}

static uint64_t gguf_read_u64(GGUFReader *r) {
	uint64_t v = 0;
	gguf_read(r, &v, sizeof(v));
	return v;
}

static char *gguf_read_str(GGUFReader *r) {
	uint64_t len = gguf_read_u64(r);
	if (r->bError || (r->nPos + len > r->nSize)) {
		r->bError = true;
		return NULL;
	}
	char *s = (char *)malloc((size_t)len + 1);
	if (!s) {
		r->bError = true;
		return NULL;
	}
	memcpy(s, r->pData + r->nPos, (size_t)len);
	s[len] = '\0';
	r->nPos += (size_t)len;
	return s;
}

static void gguf_free_value(RingGGUFValue *v) {
	if (v->nType == RING_GGUF_TYPE_STRING) {
		if (v->val.str.pStr) {
			free(v->val.str.pStr);
			v->val.str.pStr = NULL;
		}
	} else if (v->nType == RING_GGUF_TYPE_ARRAY) {
		if (v->val.arr.pItems) {
			if (v->val.arr.nItemType == RING_GGUF_TYPE_STRING) {
				char **ppStr = (char **)v->val.arr.pItems;
				for (uint64_t i = 0; i < v->val.arr.nCount; i++) {
					if (ppStr[i]) free(ppStr[i]);
				}
			}
			free(v->val.arr.pItems);
			v->val.arr.pItems = NULL;
		}
	}
}

static bool gguf_read_value(GGUFReader *r, RingGGUFType nType, RingGGUFValue *outVal) {
	outVal->nType = nType;
	switch (nType) {
	case RING_GGUF_TYPE_UINT8:   return gguf_read(r, &outVal->val.u8, 1);
	case RING_GGUF_TYPE_INT8:    return gguf_read(r, &outVal->val.i8, 1);
	case RING_GGUF_TYPE_UINT16:  return gguf_read(r, &outVal->val.u16, 2);
	case RING_GGUF_TYPE_INT16:   return gguf_read(r, &outVal->val.i16, 2);
	case RING_GGUF_TYPE_UINT32:  return gguf_read(r, &outVal->val.u32, 4);
	case RING_GGUF_TYPE_INT32:   return gguf_read(r, &outVal->val.i32, 4);
	case RING_GGUF_TYPE_FLOAT32: return gguf_read(r, &outVal->val.f32, 4);
	case RING_GGUF_TYPE_UINT64:  return gguf_read(r, &outVal->val.u64, 8);
	case RING_GGUF_TYPE_INT64:   return gguf_read(r, &outVal->val.i64, 8);
	case RING_GGUF_TYPE_FLOAT64: return gguf_read(r, &outVal->val.f64, 8);
	case RING_GGUF_TYPE_BOOL: {
		uint8_t b = 0;
		if (!gguf_read(r, &b, 1)) return false;
		outVal->val.b = (b != 0);
		return true;
	}
	case RING_GGUF_TYPE_STRING: {
		char *s = gguf_read_str(r);
		if (!s) return false;
		outVal->val.str.pStr = s;
		outVal->val.str.nLen = strlen(s);
		return true;
	}
	case RING_GGUF_TYPE_ARRAY: {
		uint32_t itemType = gguf_read_u32(r);
		uint64_t count = gguf_read_u64(r);
		if (r->bError) return false;
		outVal->val.arr.nItemType = (RingGGUFType)itemType;
		outVal->val.arr.nCount = count;

		if (itemType == RING_GGUF_TYPE_STRING) {
			char **ppStr = (char **)malloc((size_t)count * sizeof(char *));
			if (!ppStr) return false;
			for (uint64_t i = 0; i < count; i++) {
				ppStr[i] = gguf_read_str(r);
				if (!ppStr[i]) {
					for (uint64_t j = 0; j < i; j++) free(ppStr[j]);
					free(ppStr);
					return false;
				}
			}
			outVal->val.arr.pItems = ppStr;
		} else {
			size_t itemSize = 4;
			switch ((RingGGUFType)itemType) {
			case RING_GGUF_TYPE_UINT8:
			case RING_GGUF_TYPE_INT8:
			case RING_GGUF_TYPE_BOOL:   itemSize = 1; break;
			case RING_GGUF_TYPE_UINT16:
			case RING_GGUF_TYPE_INT16:  itemSize = 2; break;
			case RING_GGUF_TYPE_UINT32:
			case RING_GGUF_TYPE_INT32:
			case RING_GGUF_TYPE_FLOAT32: itemSize = 4; break;
			case RING_GGUF_TYPE_UINT64:
			case RING_GGUF_TYPE_INT64:
			case RING_GGUF_TYPE_FLOAT64: itemSize = 8; break;
			default: itemSize = 4; break;
			}
			size_t totalBytes = (size_t)count * itemSize;
			void *pItems = malloc(totalBytes > 0 ? totalBytes : 1);
			if (!pItems) return false;
			if (!gguf_read(r, pItems, totalBytes)) {
				free(pItems);
				return false;
			}
			outVal->val.arr.pItems = pItems;
		}
		return true;
	}
	default:
		r->bError = true;
		return false;
	}
}

/*
================================================================================
  Model Loading & Lifecycle
================================================================================
*/

RING_API RingGGUF *ring_gguf_open(const char *cFileName) {
	if (!cFileName) return NULL;

	RingGGUF *pGGUF = (RingGGUF *)malloc(sizeof(RingGGUF));
	if (!pGGUF) return NULL;
	memset(pGGUF, 0, sizeof(RingGGUF));

	#if defined(_MSC_VER)
	pGGUF->pFileName = _strdup(cFileName);
	#else
	pGGUF->pFileName = strdup(cFileName);
	#endif
	pGGUF->nAlignment = RING_GGUF_DEFAULT_ALIGNMENT;

	/* High-Performance Memory Mapping (Zero-Copy) */
	#ifdef _WIN32
	HANDLE hFile = CreateFileA(cFileName, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (hFile != INVALID_HANDLE_VALUE) {
		LARGE_INTEGER liSize;
		if (GetFileSizeEx(hFile, &liSize)) {
			pGGUF->nFileSize = (uint64_t)liSize.QuadPart;
			HANDLE hMap = CreateFileMappingA(hFile, NULL, PAGE_READONLY, 0, 0, NULL);
			if (hMap != NULL) {
				void *pMapped = MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0);
				if (pMapped != NULL) {
					pGGUF->pMappedData = (const uint8_t *)pMapped;
					pGGUF->nMappedSize = (size_t)pGGUF->nFileSize;
					pGGUF->hMapFile = (void *)hMap;
					pGGUF->hFile = (void *)hFile;
				} else {
					CloseHandle(hMap);
				}
			}
		}
		if (!pGGUF->pMappedData) {
			CloseHandle(hFile);
			pGGUF->hFile = NULL;
		}
	}
	#else
	int fd = open(cFileName, O_RDONLY);
	if (fd != -1) {
		struct stat sb;
		if (fstat(fd, &sb) != -1) {
			pGGUF->nFileSize = (uint64_t)sb.st_size;
			void *pMapped = mmap(NULL, sb.st_size, PROT_READ, MAP_SHARED, fd, 0);
			if (pMapped != MAP_FAILED) {
				pGGUF->pMappedData = (const uint8_t *)pMapped;
				pGGUF->nMappedSize = (size_t)sb.st_size;
				pGGUF->hMapFile = (void *)(intptr_t)(fd + 1);
				pGGUF->hFile = (void *)(intptr_t)fd;
			} else {
				close(fd);
			}
		} else {
			close(fd);
		}
	}
	#endif

	/* Portable fallback if not memory-mapped */
	if (!pGGUF->pMappedData) {
		FILE *fp = fopen(cFileName, "rb");
		if (!fp) {
			#ifdef _WIN32
			printf("\n[MADAR GGUF] Error: Failed to open file '%s' (Win32 Error: %lu)\n", cFileName, (unsigned long)GetLastError());
			#else
			printf("\n[MADAR GGUF] Error: Failed to open file '%s'\n", cFileName);
			#endif
			free(pGGUF->pFileName);
			free(pGGUF);
			return NULL;
		}
		#if defined(_WIN32) && !defined(__BORLANDC__)
		_fseeki64(fp, 0, SEEK_END);
		pGGUF->nFileSize = (uint64_t)_ftelli64(fp);
		_fseeki64(fp, 0, SEEK_SET);
		#else
		fseek(fp, 0, SEEK_END);
		pGGUF->nFileSize = (uint64_t)ftell(fp);
		fseek(fp, 0, SEEK_SET);
		#endif

		uint8_t *pBuf = (uint8_t *)malloc((size_t)pGGUF->nFileSize);
		if (!pBuf) {
			printf("\n[MADAR GGUF] Error: Out of memory allocating %llu bytes for file buffer!\n", (unsigned long long)pGGUF->nFileSize);
			fclose(fp);
			free(pGGUF->pFileName);
			free(pGGUF);
			return NULL;
		}
		size_t nRead = fread(pBuf, 1, (size_t)pGGUF->nFileSize, fp);
		fclose(fp);
		if (nRead != (size_t)pGGUF->nFileSize) {
			printf("\n[MADAR GGUF] Error: Incomplete read of file '%s' (%zu / %llu bytes)\n", cFileName, nRead, (unsigned long long)pGGUF->nFileSize);
			free(pBuf);
			free(pGGUF->pFileName);
			free(pGGUF);
			return NULL;
		}
		pGGUF->pMappedData = pBuf;
		pGGUF->nMappedSize = (size_t)pGGUF->nFileSize;
	}

	/* Initialize Stream Reader */
	GGUFReader reader;
	reader.pData = pGGUF->pMappedData;
	reader.nSize = pGGUF->nMappedSize;
	reader.nPos = 0;
	reader.bError = false;

	/* Validate Header Magic */
	uint32_t magic = gguf_read_u32(&reader);
	if (magic != RING_GGUF_MAGIC) {
		printf("\n[MADAR GGUF] Error: Invalid GGUF magic 0x%08X (expected 0x%08X) in '%s'\n", magic, RING_GGUF_MAGIC, cFileName);
		ring_gguf_close(pGGUF);
		return NULL;
	}

	/* Read Version */
	pGGUF->nVersion = gguf_read_u32(&reader);
	if (pGGUF->nVersion < 2 || pGGUF->nVersion > 3) {
		printf("\n[MADAR GGUF] Error: Unsupported GGUF version %u in '%s'\n", pGGUF->nVersion, cFileName);
		ring_gguf_close(pGGUF);
		return NULL;
	}

	/* Read Tensor and Metadata Counts */
	pGGUF->nTensors = gguf_read_u64(&reader);
	pGGUF->nKV = gguf_read_u64(&reader);

	/* Allocate Metadata Array */
	if (pGGUF->nKV > 0) {
		pGGUF->aKV = (RingGGUFKV *)malloc((size_t)pGGUF->nKV * sizeof(RingGGUFKV));
		if (!pGGUF->aKV) {
			printf("\n[MADAR GGUF] Error: Failed to allocate %llu KV entries!\n", (unsigned long long)pGGUF->nKV);
			ring_gguf_close(pGGUF);
			return NULL;
		}
		memset(pGGUF->aKV, 0, (size_t)pGGUF->nKV * sizeof(RingGGUFKV));

		for (uint64_t i = 0; i < pGGUF->nKV; i++) {
			pGGUF->aKV[i].pKey = gguf_read_str(&reader);
			uint32_t vtype = gguf_read_u32(&reader);
			if (reader.bError || !gguf_read_value(&reader, (RingGGUFType)vtype, &pGGUF->aKV[i].value)) {
				printf("\n[MADAR GGUF] Error: Failed reading KV #%llu ('%s', type=%u). Reader pos: %zu/%zu\n",
					(unsigned long long)i, pGGUF->aKV[i].pKey ? pGGUF->aKV[i].pKey : "(null)",
					vtype, reader.nPos, reader.nSize);
				ring_gguf_close(pGGUF);
				return NULL;
			}
			/* Check for custom alignment metadata */
			if (pGGUF->aKV[i].pKey && strcmp(pGGUF->aKV[i].pKey, "general.alignment") == 0) {
				if (vtype == RING_GGUF_TYPE_UINT32) {
					pGGUF->nAlignment = pGGUF->aKV[i].value.val.u32;
				} else if (vtype == RING_GGUF_TYPE_UINT64) {
					pGGUF->nAlignment = (uint32_t)pGGUF->aKV[i].value.val.u64;
				}
			}
		}
	}

	/* Allocate Tensor Info Table */
	if (pGGUF->nTensors > 0) {
		pGGUF->aTensors = (RingGGUFTensorInfo *)malloc((size_t)pGGUF->nTensors * sizeof(RingGGUFTensorInfo));
		if (!pGGUF->aTensors) {
			printf("\n[MADAR GGUF] Error: Failed to allocate %llu tensor entries!\n", (unsigned long long)pGGUF->nTensors);
			ring_gguf_close(pGGUF);
			return NULL;
		}
		memset(pGGUF->aTensors, 0, (size_t)pGGUF->nTensors * sizeof(RingGGUFTensorInfo));

		for (uint64_t i = 0; i < pGGUF->nTensors; i++) {
			RingGGUFTensorInfo *pInfo = &pGGUF->aTensors[i];
			pInfo->pName = gguf_read_str(&reader);
			uint32_t fileDims = gguf_read_u32(&reader);
			pInfo->nDims = fileDims > RING_TENSOR_MAX_DIMS ? RING_TENSOR_MAX_DIMS : fileDims;

			pInfo->nElements = 1;
			for (uint32_t d = 0; d < fileDims; d++) {
				uint64_t dim = gguf_read_u64(&reader);
				if (d < RING_TENSOR_MAX_DIMS) {
					pInfo->aDims[d] = dim;
					pInfo->nElements *= dim;
				}
			}
			pInfo->nType = gguf_read_u32(&reader);
			pInfo->nOffset = gguf_read_u64(&reader);
			pInfo->nSize = ring_gguf_calc_tensor_size(pInfo->nType, pInfo->nElements);

			if (reader.bError) {
				printf("\n[MADAR GGUF] Error: Failed reading tensor #%llu ('%s'). Reader pos: %zu/%zu\n",
					(unsigned long long)i, pInfo->pName ? pInfo->pName : "(null)",
					reader.nPos, reader.nSize);
				ring_gguf_close(pGGUF);
				return NULL;
			}
		}
	}

	/* Compute Data Section Starting Offset */
	size_t curPos = reader.nPos;
	size_t align = pGGUF->nAlignment > 0 ? pGGUF->nAlignment : RING_GGUF_DEFAULT_ALIGNMENT;
	pGGUF->nDataOffset = (curPos + align - 1) / align * align;

	return pGGUF;
}

RING_API void ring_gguf_close(RingGGUF *pGGUF) {
	if (!pGGUF) return;

	if (pGGUF->aKV) {
		for (uint64_t i = 0; i < pGGUF->nKV; i++) {
			if (pGGUF->aKV[i].pKey) free(pGGUF->aKV[i].pKey);
			gguf_free_value(&pGGUF->aKV[i].value);
		}
		free(pGGUF->aKV);
		pGGUF->aKV = NULL;
	}

	if (pGGUF->aTensors) {
		for (uint64_t i = 0; i < pGGUF->nTensors; i++) {
			if (pGGUF->aTensors[i].pName) free(pGGUF->aTensors[i].pName);
		}
		free(pGGUF->aTensors);
		pGGUF->aTensors = NULL;
	}

	if (pGGUF->hMapFile) {
		#ifdef _WIN32
		UnmapViewOfFile((void *)pGGUF->pMappedData);
		CloseHandle((HANDLE)pGGUF->hMapFile);
		if (pGGUF->hFile) CloseHandle((HANDLE)pGGUF->hFile);
		#else
		munmap((void *)pGGUF->pMappedData, pGGUF->nMappedSize);
		close((int)(intptr_t)pGGUF->hFile);
		#endif
	} else if (pGGUF->pMappedData) {
		free((void *)pGGUF->pMappedData);
	}

	if (pGGUF->pFileName) free(pGGUF->pFileName);
	free(pGGUF);
}

/*
================================================================================
  Metadata Queries
================================================================================
*/

RING_API RingGGUFKV *ring_gguf_find_kv(RingGGUF *pGGUF, const char *cKey) {
	if (!pGGUF || !cKey || !pGGUF->aKV) return NULL;
	for (uint64_t i = 0; i < pGGUF->nKV; i++) {
		if (pGGUF->aKV[i].pKey && strcmp(pGGUF->aKV[i].pKey, cKey) == 0) {
			return &pGGUF->aKV[i];
		}
	}
	return NULL;
}

RING_API RingGGUFTensorInfo *ring_gguf_find_tensor(RingGGUF *pGGUF, const char *cName) {
	if (!pGGUF || !cName || !pGGUF->aTensors) return NULL;
	for (uint64_t i = 0; i < pGGUF->nTensors; i++) {
		if (pGGUF->aTensors[i].pName && strcmp(pGGUF->aTensors[i].pName, cName) == 0) {
			return &pGGUF->aTensors[i];
		}
	}
	return NULL;
}

RING_API RingGGUFTensorInfo *ring_gguf_get_tensor_by_index(RingGGUF *pGGUF, unsigned int nIndex) {
	if (!pGGUF || !pGGUF->aTensors || nIndex >= pGGUF->nTensors) return NULL;
	return &pGGUF->aTensors[nIndex];
}

RING_API const void *ring_gguf_get_tensor_data(RingGGUF *pGGUF, RingGGUFTensorInfo *pInfo) {
	if (!pGGUF || !pInfo || !pGGUF->pMappedData) return NULL;
	uint64_t absOffset = pGGUF->nDataOffset + pInfo->nOffset;
	if (absOffset + pInfo->nSize > pGGUF->nFileSize) return NULL;
	return pGGUF->pMappedData + absOffset;
}

/*
================================================================================
  Dequantization Implementations
================================================================================
*/

RING_API void ring_gguf_dequantize_f16(const void *pSrc, float *pDst, uint64_t nElements) {
	const uint16_t *src = (const uint16_t *)pSrc;
	for (uint64_t i = 0; i < nElements; i++) {
		pDst[i] = ggml_fp16_to_fp32(src[i]);
	}
}

RING_API void ring_gguf_dequantize_q8_0(const void *pSrc, float *pDst, uint64_t nElements) {
	const RingGGUFBlockQ8_0 *blocks = (const RingGGUFBlockQ8_0 *)pSrc;
	uint64_t nBlocks = nElements / 32;
	for (uint64_t b = 0; b < nBlocks; b++) {
		float d = ggml_fp16_to_fp32(blocks[b].d);
		for (int i = 0; i < 32; i++) {
			pDst[b * 32 + i] = (float)blocks[b].qs[i] * d;
		}
	}
}

RING_API void ring_gguf_dequantize_q4_0(const void *pSrc, float *pDst, uint64_t nElements) {
	const RingGGUFBlockQ4_0 *blocks = (const RingGGUFBlockQ4_0 *)pSrc;
	uint64_t nBlocks = nElements / 32;
	for (uint64_t b = 0; b < nBlocks; b++) {
		float d = ggml_fp16_to_fp32(blocks[b].d);
		for (int i = 0; i < 16; i++) {
			uint8_t q = blocks[b].qs[i];
			int x0 = (q & 0x0F) - 8;
			int x1 = (q >> 4)   - 8;
			pDst[b * 32 + i]      = (float)x0 * d;
			pDst[b * 32 + i + 16] = (float)x1 * d;
		}
	}
}

RING_API void ring_gguf_dequantize_q6_k(const void *pSrc, float *pDst, uint64_t nElements) {
	const RingGGUFBlockQ6_K *blocks = (const RingGGUFBlockQ6_K *)pSrc;
	uint64_t nBlocks = nElements / 256;
	for (uint64_t b = 0; b < nBlocks; b++) {
		float d = ggml_fp16_to_fp32(blocks[b].d);
		const uint8_t *ql = blocks[b].ql;
		const uint8_t *qh = blocks[b].qh;
		const int8_t *sc = blocks[b].scales;
		float *dst = pDst + b * 256;

		for (int n_half = 0; n_half < 256; n_half += 128) {
			for (int h = 0; h < 2; h++) {
				float s0 = (float)sc[h + 0] * d;
				float s2 = (float)sc[h + 2] * d;
				float s4 = (float)sc[h + 4] * d;
				float s6 = (float)sc[h + 6] * d;
				int l_start = h * 16;
				int l_end = l_start + 16;

				for (int l = l_start; l < l_end; l++) {
					int8_t q1 = (int8_t)((ql[l +  0] & 0xF) | (((qh[l] >> 0) & 3) << 4)) - 32;
					int8_t q2 = (int8_t)((ql[l + 32] & 0xF) | (((qh[l] >> 2) & 3) << 4)) - 32;
					int8_t q3 = (int8_t)((ql[l +  0] >>  4) | (((qh[l] >> 4) & 3) << 4)) - 32;
					int8_t q4 = (int8_t)((ql[l + 32] >>  4) | (((qh[l] >> 6) & 3) << 4)) - 32;

					dst[l +  0] = s0 * (float)q1;
					dst[l + 32] = s2 * (float)q2;
					dst[l + 64] = s4 * (float)q3;
					dst[l + 96] = s6 * (float)q4;
				}
			}
			dst += 128;
			ql  += 64;
			qh  += 32;
			sc  += 8;
		}
	}
}

/*
================================================================================
  Native Madar Tensor Construction
================================================================================
*/

static RingTensor *gguf_create_tensor_from_info(void *pRingState, RingGGUF *pGGUF, RingGGUFTensorInfo *pInfo, bool bForceF32) {
	const void *pRawData = ring_gguf_get_tensor_data(pGGUF, pInfo);
	if (!pRawData) return NULL;

	size_t aShape[RING_TENSOR_MAX_DIMS];
	for (uint32_t i = 0; i < pInfo->nDims; i++) {
		aShape[i] = (size_t)pInfo->aDims[i];
	}

	if (bForceF32 || pInfo->nType == RING_GGUF_TENSOR_F32) {
		RingTensor *pTensor = ring_tensor_new(pRingState, RING_TENSOR_TYPE_FLOAT32, pInfo->nDims, aShape);
		if (!pTensor) return NULL;
		float *pDst = (float *)ring_tensor_data(pTensor);

		if (pInfo->nType == RING_GGUF_TENSOR_F32) {
			memcpy(pDst, pRawData, (size_t)pInfo->nSize);
		} else if (pInfo->nType == RING_GGUF_TENSOR_F16) {
			ring_gguf_dequantize_f16(pRawData, pDst, pInfo->nElements);
		} else if (pInfo->nType == RING_GGUF_TENSOR_Q8_0) {
			ring_gguf_dequantize_q8_0(pRawData, pDst, pInfo->nElements);
		} else if (pInfo->nType == RING_GGUF_TENSOR_Q4_0) {
			ring_gguf_dequantize_q4_0(pRawData, pDst, pInfo->nElements);
		} else if (pInfo->nType == RING_GGUF_TENSOR_Q6_K) {
			ring_gguf_dequantize_q6_k(pRawData, pDst, pInfo->nElements);
		} else {
			ring_tensor_delete(pRingState, pTensor);
			return NULL;
		}
		return pTensor;
	}

	/* Zero-Copy Native Tensor View */
	RingTensorType tType = RING_TENSOR_TYPE_FLOAT32;
	if (pInfo->nType == RING_GGUF_TENSOR_F16) {
		tType = RING_TENSOR_TYPE_FLOAT16;
	} else if (pInfo->nType == RING_GGUF_TENSOR_I8) {
		tType = RING_TENSOR_TYPE_INT8;
	} else if (pInfo->nType == RING_GGUF_TENSOR_I32) {
		tType = RING_TENSOR_TYPE_INT32;
	} else if (pInfo->nType == RING_GGUF_TENSOR_F64) {
		tType = RING_TENSOR_TYPE_FLOAT64;
	} else {
		/* Quantized formats (Q4_0, Q8_0) must be dequantized to F32 */
		return gguf_create_tensor_from_info(pRingState, pGGUF, pInfo, true);
	}

	return ring_tensor_new_from_buffer(pRingState, (void *)pRawData, (size_t)pInfo->nSize, tType, pInfo->nDims, aShape, 0);
}

RING_API RingTensor *ring_gguf_load_tensor(void *pRingState, RingGGUF *pGGUF, const char *cName) {
	RingGGUFTensorInfo *pInfo = ring_gguf_find_tensor(pGGUF, cName);
	if (!pInfo) return NULL;
	return gguf_create_tensor_from_info(pRingState, pGGUF, pInfo, false);
}

RING_API RingTensor *ring_gguf_load_tensor_by_index(void *pRingState, RingGGUF *pGGUF, unsigned int nIndex) {
	RingGGUFTensorInfo *pInfo = ring_gguf_get_tensor_by_index(pGGUF, nIndex);
	if (!pInfo) return NULL;
	return gguf_create_tensor_from_info(pRingState, pGGUF, pInfo, false);
}

RING_API RingTensor *ring_gguf_load_tensor_f32(void *pRingState, RingGGUF *pGGUF, const char *cName) {
	RingGGUFTensorInfo *pInfo = ring_gguf_find_tensor(pGGUF, cName);
	if (!pInfo) return NULL;
	return gguf_create_tensor_from_info(pRingState, pGGUF, pInfo, true);
}

/*
================================================================================
  Ring Scripting VM APIs
================================================================================
*/

static void ring_gguf_gc_close(void *pRingState, void *pPointer) {
	(void)pRingState;
	if (pPointer) {
		ring_gguf_close((RingGGUF *)pPointer);
	}
}

RING_FUNC(ring_gguf_api_open) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISSTRING(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	const char *cFile = RING_API_GETSTRING(1);
	RingGGUF *pGGUF = ring_gguf_open(cFile);
	if (!pGGUF) {
		RING_API_ERROR("Failed to open or parse GGUF file!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pGGUF, "GGUF", (void (*)(void *, void *))ring_gguf_gc_close);
}

RING_FUNC(ring_gguf_api_close) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (pGGUF) {
		ring_gguf_close(pGGUF);
		RING_API_SETNULLPOINTER(1);
	}
}

RING_FUNC(ring_gguf_api_version) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }
	RING_API_RETNUMBER(pGGUF->nVersion);
}

RING_FUNC(ring_gguf_api_tensor_count) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }
	RING_API_RETNUMBER((double)pGGUF->nTensors);
}

RING_FUNC(ring_gguf_api_metadata_count) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }
	RING_API_RETNUMBER((double)pGGUF->nKV);
}

RING_FUNC(ring_gguf_api_alignment) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }
	RING_API_RETNUMBER(pGGUF->nAlignment);
}

RING_FUNC(ring_gguf_api_architecture) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }
	RingGGUFKV *pKV = ring_gguf_find_kv(pGGUF, "general.architecture");
	if (pKV && pKV->value.nType == RING_GGUF_TYPE_STRING && pKV->value.val.str.pStr) {
		RING_API_RETSTRING(pKV->value.val.str.pStr);
	} else {
		RING_API_RETSTRING("");
	}
}

RING_FUNC(ring_gguf_api_metadata_keys) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }

	List *pList = RING_API_NEWLIST;
	for (uint64_t i = 0; i < pGGUF->nKV; i++) {
		if (pGGUF->aKV[i].pKey) {
			ring_list_addstring(pList, pGGUF->aKV[i].pKey);
		}
	}
	RING_API_RETLIST(pList);
}

RING_FUNC(ring_gguf_api_metadata_get) {
	if (RING_API_PARACOUNT != 2 || !RING_API_ISCPOINTER(1) || !RING_API_ISSTRING(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	const char *cKey = RING_API_GETSTRING(2);
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }

	RingGGUFKV *pKV = ring_gguf_find_kv(pGGUF, cKey);
	if (!pKV) {
		return; /* Returns NULL / empty */
	}

	switch (pKV->value.nType) {
	case RING_GGUF_TYPE_STRING:
		RING_API_RETSTRING(pKV->value.val.str.pStr ? pKV->value.val.str.pStr : "");
		break;
	case RING_GGUF_TYPE_UINT8:   RING_API_RETNUMBER(pKV->value.val.u8); break;
	case RING_GGUF_TYPE_INT8:    RING_API_RETNUMBER(pKV->value.val.i8); break;
	case RING_GGUF_TYPE_UINT16:  RING_API_RETNUMBER(pKV->value.val.u16); break;
	case RING_GGUF_TYPE_INT16:   RING_API_RETNUMBER(pKV->value.val.i16); break;
	case RING_GGUF_TYPE_UINT32:  RING_API_RETNUMBER(pKV->value.val.u32); break;
	case RING_GGUF_TYPE_INT32:   RING_API_RETNUMBER(pKV->value.val.i32); break;
	case RING_GGUF_TYPE_FLOAT32: RING_API_RETNUMBER(pKV->value.val.f32); break;
	case RING_GGUF_TYPE_UINT64:  RING_API_RETNUMBER((double)pKV->value.val.u64); break;
	case RING_GGUF_TYPE_INT64:   RING_API_RETNUMBER((double)pKV->value.val.i64); break;
	case RING_GGUF_TYPE_FLOAT64: RING_API_RETNUMBER(pKV->value.val.f64); break;
	case RING_GGUF_TYPE_BOOL:    RING_API_RETNUMBER(pKV->value.val.b); break;
	case RING_GGUF_TYPE_ARRAY: {
		List *pList = RING_API_NEWLIST;
		uint64_t cnt = pKV->value.val.arr.nCount;
		if (pKV->value.val.arr.nItemType == RING_GGUF_TYPE_STRING) {
			char **ppStr = (char **)pKV->value.val.arr.pItems;
			for (uint64_t i = 0; i < cnt; i++) {
				ring_list_addstring(pList, ppStr[i] ? ppStr[i] : "");
			}
		} else {
			for (uint64_t i = 0; i < cnt; i++) {
				double dVal = 0.0;
				switch (pKV->value.val.arr.nItemType) {
				case RING_GGUF_TYPE_UINT8:   dVal = ((uint8_t *)pKV->value.val.arr.pItems)[i]; break;
				case RING_GGUF_TYPE_INT8:    dVal = ((int8_t *)pKV->value.val.arr.pItems)[i]; break;
				case RING_GGUF_TYPE_UINT16:  dVal = ((uint16_t *)pKV->value.val.arr.pItems)[i]; break;
				case RING_GGUF_TYPE_INT16:   dVal = ((int16_t *)pKV->value.val.arr.pItems)[i]; break;
				case RING_GGUF_TYPE_UINT32:  dVal = ((uint32_t *)pKV->value.val.arr.pItems)[i]; break;
				case RING_GGUF_TYPE_INT32:   dVal = ((int32_t *)pKV->value.val.arr.pItems)[i]; break;
				case RING_GGUF_TYPE_FLOAT32: dVal = ((float *)pKV->value.val.arr.pItems)[i]; break;
				case RING_GGUF_TYPE_FLOAT64: dVal = ((double *)pKV->value.val.arr.pItems)[i]; break;
				default: break;
				}
				ring_list_adddouble(pList, dVal);
			}
		}
		RING_API_RETLIST(pList);
		break;
	}
	default:
		break;
	}
}

RING_FUNC(ring_gguf_api_tensor_names) {
	if (RING_API_PARACOUNT != 1 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }

	List *pList = RING_API_NEWLIST;
	for (uint64_t i = 0; i < pGGUF->nTensors; i++) {
		if (pGGUF->aTensors[i].pName) {
			ring_list_addstring(pList, pGGUF->aTensors[i].pName);
		}
	}
	RING_API_RETLIST(pList);
}

RING_FUNC(ring_gguf_api_tensor_info) {
	if (RING_API_PARACOUNT != 2 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }

	RingGGUFTensorInfo *pInfo = NULL;
	if (RING_API_ISSTRING(2)) {
		pInfo = ring_gguf_find_tensor(pGGUF, RING_API_GETSTRING(2));
	} else if (RING_API_ISNUMBER(2)) {
		unsigned int idx = (unsigned int)RING_API_GETNUMBER(2);
		/* Support 1-based index */
		if (idx >= 1) idx -= 1;
		pInfo = ring_gguf_get_tensor_by_index(pGGUF, idx);
	}
	if (!pInfo) {
		RING_API_ERROR("Tensor not found!");
		return;
	}

	List *pList = RING_API_NEWLIST;
	ring_list_addstring(pList, pInfo->pName ? pInfo->pName : "");
	ring_list_addstring(pList, ring_gguf_tensor_type_name(pInfo->nType));
	ring_list_adddouble(pList, (double)pInfo->nDims);

	List *pShapeList = ring_list_newlist(pList);
	for (uint32_t d = 0; d < pInfo->nDims; d++) {
		ring_list_adddouble(pShapeList, (double)pInfo->aDims[d]);
	}

	ring_list_adddouble(pList, (double)pInfo->nElements);
	ring_list_adddouble(pList, (double)pInfo->nSize);
	ring_list_adddouble(pList, (double)pInfo->nOffset);

	RING_API_RETLIST(pList);
}

RING_FUNC(ring_gguf_api_tensor_get) {
	if (RING_API_PARACOUNT != 2 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }

	RingTensor *pTensor = NULL;
	if (RING_API_ISSTRING(2)) {
		pTensor = ring_gguf_load_tensor(RING_API_STATE, pGGUF, RING_API_GETSTRING(2));
	} else if (RING_API_ISNUMBER(2)) {
		unsigned int idx = (unsigned int)RING_API_GETNUMBER(2);
		if (idx >= 1) idx -= 1;
		pTensor = ring_gguf_load_tensor_by_index(RING_API_STATE, pGGUF, idx);
	}
	if (!pTensor) {
		RING_API_ERROR("gguf_tensor_get: Failed to load tensor!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pTensor, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_gguf_api_tensor_to_f32) {
	if (RING_API_PARACOUNT != 2 || !RING_API_ISCPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	RingGGUF *pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	if (!pGGUF) { RING_API_ERROR(RING_API_NULLPOINTER); return; }

	RingTensor *pTensor = NULL;
	if (RING_API_ISSTRING(2)) {
		pTensor = ring_gguf_load_tensor_f32(RING_API_STATE, pGGUF, RING_API_GETSTRING(2));
	} else if (RING_API_ISNUMBER(2)) {
		unsigned int idx = (unsigned int)RING_API_GETNUMBER(2);
		if (idx >= 1) idx -= 1;
		RingGGUFTensorInfo *pInfo = ring_gguf_get_tensor_by_index(pGGUF, idx);
		if (pInfo && pInfo->pName) {
			pTensor = ring_gguf_load_tensor_f32(RING_API_STATE, pGGUF, pInfo->pName);
		}
	}
	if (!pTensor) {
		RING_API_ERROR("gguf_tensor_to_f32: Failed to load and dequantize tensor!");
		return;
	}
	RING_API_RETMANAGEDCPOINTER(pTensor, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

/*
================================================================================
  Registration Function
================================================================================
*/

RING_API void ring_gguf_loadfunctions(void *pRingState) {
	RING_API_REGISTER("gguf_open", ring_gguf_api_open);
	RING_API_REGISTER("gguf_close", ring_gguf_api_close);
	RING_API_REGISTER("gguf_version", ring_gguf_api_version);
	RING_API_REGISTER("gguf_tensor_count", ring_gguf_api_tensor_count);
	RING_API_REGISTER("gguf_metadata_count", ring_gguf_api_metadata_count);
	RING_API_REGISTER("gguf_alignment", ring_gguf_api_alignment);
	RING_API_REGISTER("gguf_architecture", ring_gguf_api_architecture);
	RING_API_REGISTER("gguf_metadata_keys", ring_gguf_api_metadata_keys);
	RING_API_REGISTER("gguf_metadata_get", ring_gguf_api_metadata_get);
	RING_API_REGISTER("gguf_tensor_names", ring_gguf_api_tensor_names);
	RING_API_REGISTER("gguf_tensor_info", ring_gguf_api_tensor_info);
	RING_API_REGISTER("gguf_tensor_get", ring_gguf_api_tensor_get);
	RING_API_REGISTER("gguf_tensor_to_f32", ring_gguf_api_tensor_to_f32);
	ring_tokenizer_loadfunctions(pRingState);
	ring_inference_loadfunctions(pRingState);
}
