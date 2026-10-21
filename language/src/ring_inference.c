/*
**  Madar - High-Performance AI-Native Runtime
**  Lightweight Transformer & Qwen Inference Engine
**  Pure ANSI C / C99 Implementation
*/

#include "ring.h"
#include "ring_inference.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifdef _WIN32
#include <windows.h>
#endif

/*
================================================================================
  Fast Vector Dot Products (Q4_0, Q8_0, F16, F32)
================================================================================
*/

static inline float fast_fp16_to_fp32(uint16_t h) {
	union { uint32_t u; float f; } v;
	uint32_t sign = ((uint32_t)h & 0x8000) << 16;
	int32_t exp = (h >> 10) & 0x1F;
	uint32_t mant = (h & 0x3FF) << 13;
	if (exp == 0x1F) {
		v.u = sign | 0x7F800000 | mant;
	} else if (exp == 0) {
		if (mant == 0) {
			v.u = sign;
		} else {
			while (!(mant & 0x00800000)) { mant <<= 1; exp--; }
			exp++;
			mant &= ~0x00800000;
			v.u = sign | ((uint32_t)(exp + 112) << 23) | mant;
		}
	} else {
		v.u = sign | ((uint32_t)(exp + 112) << 23) | mant;
	}
	return v.f;
}

static float dot_q4_0(const RingGGUFBlockQ4_0 *b, const float *x, int k) {
	int nBlocks = k / 32;
	float sum = 0.0f;
	int i, j;
	float d, bsum0, bsum1;
	const uint8_t *qs;
	const float *xi;
	uint8_t q0, q1;

	for (i = 0; i < nBlocks; i++) {
		d = fast_fp16_to_fp32(b[i].d);
		qs = b[i].qs;
		xi = x + i * 32;
		bsum0 = 0.0f;
		bsum1 = 0.0f;
		for (j = 0; j < 16; j += 2) {
			q0 = qs[j];
			q1 = qs[j + 1];
			bsum0 += (float)((int)(q0 & 0x0F) - 8) * xi[j]     + (float)((int)(q0 >> 4) - 8) * xi[j + 16];
			bsum1 += (float)((int)(q1 & 0x0F) - 8) * xi[j + 1] + (float)((int)(q1 >> 4) - 8) * xi[j + 1 + 16];
		}
		sum += (bsum0 + bsum1) * d;
	}
	return sum;
}

static float dot_q8_0(const RingGGUFBlockQ8_0 *b, const float *x, int k) {
	int nBlocks = k / 32;
	float sum = 0.0f;
	int i, j;
	float d, bsum0, bsum1;
	const int8_t *qs;
	const float *xi;

	for (i = 0; i < nBlocks; i++) {
		d = fast_fp16_to_fp32(b[i].d);
		qs = b[i].qs;
		xi = x + i * 32;
		bsum0 = 0.0f;
		bsum1 = 0.0f;
		for (j = 0; j < 32; j += 2) {
			bsum0 += (float)qs[j]     * xi[j];
			bsum1 += (float)qs[j + 1] * xi[j + 1];
		}
		sum += (bsum0 + bsum1) * d;
	}
	return sum;
}

static float dot_q6_k(const RingGGUFBlockQ6_K *b, const float *x, int k) {
	int nBlocks = k / 256;
	float sum = 0.0f;
	int i, n_half, l, is;
	float d;
	const uint8_t *ql;
	const uint8_t *qh;
	const int8_t *sc;
	const float *v;
	int8_t q1, q2, q3, q4;
	float bsum;

	for (i = 0; i < nBlocks; i++) {
		d = fast_fp16_to_fp32(b[i].d);
		ql = b[i].ql;
		qh = b[i].qh;
		sc = b[i].scales;
		v = x + i * 256;
		bsum = 0.0f;

		for (n_half = 0; n_half < 256; n_half += 128) {
			for (l = 0; l < 32; ++l) {
				is = l / 16;
				q1 = (int8_t)((ql[l +  0] & 0xF) | (((qh[l] >> 0) & 3) << 4)) - 32;
				q2 = (int8_t)((ql[l + 32] & 0xF) | (((qh[l] >> 2) & 3) << 4)) - 32;
				q3 = (int8_t)((ql[l +  0] >>  4) | (((qh[l] >> 4) & 3) << 4)) - 32;
				q4 = (int8_t)((ql[l + 32] >>  4) | (((qh[l] >> 6) & 3) << 4)) - 32;

				bsum += (float)sc[is + 0] * (float)q1 * v[l +  0]
				      + (float)sc[is + 2] * (float)q2 * v[l + 32]
				      + (float)sc[is + 4] * (float)q3 * v[l + 64]
				      + (float)sc[is + 6] * (float)q4 * v[l + 96];
			}
			v  += 128;
			ql += 64;
			qh += 32;
			sc += 8;
		}
		sum += bsum * d;
	}
	return sum;
}

static float dot_f16(const ggml_fp16_t *f, const float *x, int k) {
	float sum = 0.0f;
	int i;
	for (i = 0; i < k; i++) {
		sum += fast_fp16_to_fp32(f[i]) * x[i];
	}
	return sum;
}

static float dot_f32(const float *f, const float *x, int k) {
	float sum = 0.0f;
	int i;
	for (i = 0; i < k; i++) {
		sum += f[i] * x[i];
	}
	return sum;
}

/*
================================================================================
  Matrix-Vector Multiplication (Row-by-Row Dot Products)
================================================================================
*/

typedef struct MatVecTask {
	RingGGUF *pGGUF;
	RingGGUFTensorInfo *pInfo;
	const float *pX;
	float *pY;
	const void *pBias;
	RingGGUFTensorInfo *pBiasInfo;
	int nStartRow;
	int nEndRow;
	int K;
} MatVecTask;

static void matvec_compute_rows(MatVecTask *task) {
	const uint8_t *pRaw = (const uint8_t *)ring_gguf_get_tensor_data(task->pGGUF, task->pInfo);
	uint32_t nType;
	int K, r;
	float val;
	const RingGGUFBlockQ4_0 *b4;
	const RingGGUFBlockQ8_0 *b8;
	const ggml_fp16_t *f16;
	const float *f32;

	if (!pRaw) return;

	nType = task->pInfo->nType;
	K = task->K;

	for (r = task->nStartRow; r < task->nEndRow; r++) {
		val = 0.0f;
		if (nType == RING_GGUF_TENSOR_Q4_0) {
			b4 = (const RingGGUFBlockQ4_0 *)(pRaw + (size_t)r * (K / 32) * sizeof(RingGGUFBlockQ4_0));
			val = dot_q4_0(b4, task->pX, K);
		} else if (nType == RING_GGUF_TENSOR_Q8_0) {
			b8 = (const RingGGUFBlockQ8_0 *)(pRaw + (size_t)r * (K / 32) * sizeof(RingGGUFBlockQ8_0));
			val = dot_q8_0(b8, task->pX, K);
		} else if (nType == RING_GGUF_TENSOR_F16) {
			f16 = (const ggml_fp16_t *)(pRaw + (size_t)r * K * sizeof(ggml_fp16_t));
			val = dot_f16(f16, task->pX, K);
		} else if (nType == RING_GGUF_TENSOR_F32) {
			f32 = (const float *)(pRaw + (size_t)r * K * sizeof(float));
			val = dot_f32(f32, task->pX, K);
		} else if (nType == RING_GGUF_TENSOR_Q6_K) {
			const RingGGUFBlockQ6_K *b6 = (const RingGGUFBlockQ6_K *)(pRaw + (size_t)r * (K / 256) * sizeof(RingGGUFBlockQ6_K));
			val = dot_q6_k(b6, task->pX, K);
		} else {
			static int s_unsupportedWarn = 0;
			if (s_unsupportedWarn++ < 1) {
				printf("\n[MADAR AI] Warning: matvec_compute_rows unsupported tensor type: %u for '%s'!\n",
					   nType, task->pInfo->pName ? task->pInfo->pName : "unknown");
			}
		}

		if (task->pBias) {
			if (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16) {
				val += fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r]);
			} else {
				val += ((const float *)task->pBias)[r];
			}
		}
		task->pY[r] = val;
	}
}

#ifdef _WIN32
typedef struct {
	RingModel *pModel;
	int nIndex;
} RingWorkerParam;

static DWORD WINAPI ring_model_worker_proc(LPVOID lpParam) {
	RingWorkerParam *param = (RingWorkerParam *)lpParam;
	RingModel *pModel = param->pModel;
	int idx = param->nIndex;
	free(param);

	while (1) {
		WaitForSingleObject((HANDLE)pModel->hStartEvents[idx], INFINITE);
		if (pModel->bWorkerShutdown) break;
		if (pModel->pWorkerTasks[idx]) {
			matvec_compute_rows((MatVecTask *)pModel->pWorkerTasks[idx]);
		}
		SetEvent((HANDLE)pModel->hDoneEvents[idx]);
	}
	return 0;
}
#endif

static void matvec_multiply(RingModel *pModel, RingGGUFTensorInfo *pInfo, const float *x, float *y,
							RingGGUFTensorInfo *pBiasInfo) {
	int K, N;
	const float *pBias;
	MatVecTask task;
#ifdef _WIN32
	int nTotalThreads, nWorkers, nChunk, i;
#endif

	if (!pModel || !pInfo || !x || !y) return;

	K = (int)pInfo->aDims[0];
	N = (int)pInfo->aDims[1];
	pBias = NULL;

	if (pBiasInfo) {
		pBias = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, pBiasInfo);
	}

#ifdef _WIN32
	if (pModel->nThreads >= 2 && N >= 128 && pModel->nWorkerCount > 0) {
		nTotalThreads = pModel->nThreads;
		if (nTotalThreads > pModel->nWorkerCount + 1) {
			nTotalThreads = pModel->nWorkerCount + 1;
		}
		nWorkers = nTotalThreads - 1;
		nChunk = N / nTotalThreads;

		for (i = 0; i < nWorkers; i++) {
			MatVecTask *pTask = (MatVecTask *)pModel->pWorkerTasks[i];
			pTask->pGGUF = pModel->pGGUF;
			pTask->pInfo = pInfo;
			pTask->pX = x;
			pTask->pY = y;
			pTask->pBias = pBias;
			pTask->pBiasInfo = pBiasInfo;
			pTask->nStartRow = i * nChunk;
			pTask->nEndRow = (i + 1) * nChunk;
			pTask->K = K;
			SetEvent((HANDLE)pModel->hStartEvents[i]);
		}

		/* Main thread computes the remainder */
		task.pGGUF = pModel->pGGUF;
		task.pInfo = pInfo;
		task.pX = x;
		task.pY = y;
		task.pBias = pBias;
		task.pBiasInfo = pBiasInfo;
		task.nStartRow = nWorkers * nChunk;
		task.nEndRow = N;
		task.K = K;
		matvec_compute_rows(&task);

		/* Wait for all active worker threads */
		WaitForMultipleObjects((DWORD)nWorkers, (const HANDLE *)pModel->hDoneEvents, TRUE, INFINITE);
		return;
	}
#endif

	task.pGGUF = pModel->pGGUF;
	task.pInfo = pInfo;
	task.pX = x;
	task.pY = y;
	task.pBias = pBias;
	task.pBiasInfo = pBiasInfo;
	task.nStartRow = 0;
	task.nEndRow = N;
	task.K = K;
	matvec_compute_rows(&task);
}

/*
================================================================================
  Neural Operations: RMSNorm, RoPE, Softmax, SiLU
================================================================================
*/

static void rmsnorm(float *o, const float *x, const float *weight, int size, float eps) {
	float ss = 0.0f;
	float inv;
	int i;

	for (i = 0; i < size; i++) ss += x[i] * x[i];
	ss /= (float)size;
	ss += eps;
	inv = 1.0f / sqrtf(ss);

	if (weight) {
		for (i = 0; i < size; i++) o[i] = x[i] * inv * weight[i];
	} else {
		for (i = 0; i < size; i++) o[i] = x[i] * inv;
	}
}

static void apply_rope(float *vec, int nHeads, int headDim, int pos, float freqBase) {
	int h, i;
	float *head;
	float freq, val, cosVal, sinVal, v0, v1;
	int half = headDim / 2;

	for (h = 0; h < nHeads; h++) {
		head = vec + h * headDim;
		for (i = 0; i < half; i++) {
			freq = 1.0f / powf(freqBase, (float)(2 * i) / (float)headDim);
			val = (float)pos * freq;
			cosVal = cosf(val);
			sinVal = sinf(val);
			v0 = head[i];
			v1 = head[i + half];
			head[i]        = v0 * cosVal - v1 * sinVal;
			head[i + half] = v0 * sinVal + v1 * cosVal;
		}
	}
}

static void softmax(float *x, int size) {
	float maxVal = x[0];
	float sum = 0.0f;
	float inv;
	int i;

	for (i = 1; i < size; i++) {
		if (x[i] > maxVal) maxVal = x[i];
	}
	for (i = 0; i < size; i++) {
		x[i] = expf(x[i] - maxVal);
		sum += x[i];
	}
	inv = 1.0f / sum;
	for (i = 0; i < size; i++) {
		x[i] *= inv;
	}
}

/*
================================================================================
  Inference Engine Lifecycle
================================================================================
*/

static uint32_t gguf_get_u32_val(RingGGUFKV *kv, uint32_t defVal) {
	if (!kv) return defVal;
	switch (kv->value.nType) {
		case RING_GGUF_TYPE_UINT32: return kv->value.val.u32;
		case RING_GGUF_TYPE_INT32:  return (uint32_t)kv->value.val.i32;
		case RING_GGUF_TYPE_UINT64: return (uint32_t)kv->value.val.u64;
		case RING_GGUF_TYPE_INT64:  return (uint32_t)kv->value.val.i64;
		case RING_GGUF_TYPE_UINT16: return (uint32_t)kv->value.val.u16;
		case RING_GGUF_TYPE_INT16:  return (uint32_t)kv->value.val.i16;
		default: return defVal;
	}
}

static float gguf_get_f32_val(RingGGUFKV *kv, float defVal) {
	if (!kv) return defVal;
	if (kv->value.nType == RING_GGUF_TYPE_FLOAT32) return kv->value.val.f32;
	if (kv->value.nType == RING_GGUF_TYPE_FLOAT64) return (float)kv->value.val.f64;
	return defVal;
}

RING_API RingModel *ring_model_load(const char *cFileName) {
	RingGGUF *pGGUF;
	RingTokenizer *pTok;
	RingModel *pModel;
	char key[128];
	RingGGUFKV *kv;
	const char *arch;
	uint32_t l;
	size_t kvSize;

#ifdef _WIN32
	SetConsoleCP(CP_UTF8);
	SetConsoleOutputCP(CP_UTF8);
#endif

	pGGUF = ring_gguf_open(cFileName);
	if (!pGGUF) {
		printf("\n[MADAR AI] Error: ring_gguf_open failed to open '%s'!\n", cFileName);
		return NULL;
	}

	pTok = ring_tokenizer_create(pGGUF);
	if (!pTok) {
		printf("\n[MADAR AI] Error: ring_tokenizer_create failed for '%s'!\n", cFileName);
		ring_gguf_close(pGGUF);
		return NULL;
	}

	pModel = (RingModel *)calloc(1, sizeof(RingModel));
	if (!pModel) {
		printf("\n[MADAR AI] Error: Out of memory allocating RingModel!\n");
		ring_tokenizer_delete(pTok);
		ring_gguf_close(pGGUF);
		return NULL;
	}

	pModel->pGGUF = pGGUF;
	pModel->pTokenizer = pTok;
	pModel->nThreads = 4; /* Default: 4 threads */

	/* Read Architecture & Metadata */
	kv = ring_gguf_find_kv(pGGUF, "general.architecture");
	if (kv && kv->value.nType == RING_GGUF_TYPE_STRING) {
		strncpy(pModel->config.cArch, kv->value.val.str.pStr, sizeof(pModel->config.cArch) - 1);
	} else {
		strcpy(pModel->config.cArch, "qwen2");
	}

	arch = pModel->config.cArch;

	/* Vocabulary */
	pModel->config.nVocab = pTok->nVocabSize;

	/* Context Length */
	snprintf(key, sizeof(key), "%s.context_length", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.nCtx = gguf_get_u32_val(kv, 2048);

	/* Embedding Length */
	snprintf(key, sizeof(key), "%s.embedding_length", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.nEmbd = gguf_get_u32_val(kv, 896);

	/* Block Count (Layers) */
	snprintf(key, sizeof(key), "%s.block_count", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.nLayers = gguf_get_u32_val(kv, 24);

	/* Attention Heads */
	snprintf(key, sizeof(key), "%s.attention.head_count", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	if (!kv) kv = ring_gguf_find_kv(pGGUF, "attention.head_count");
	pModel->config.nHeads = gguf_get_u32_val(kv, 14);

	snprintf(key, sizeof(key), "%s.attention.head_count_kv", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	if (!kv) kv = ring_gguf_find_kv(pGGUF, "attention.head_count_kv");
	pModel->config.nHeadsKV = gguf_get_u32_val(kv, pModel->config.nHeads);

	snprintf(key, sizeof(key), "%s.attention.key_length", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	if (kv) {
		pModel->config.nHeadDim = gguf_get_u32_val(kv, 64);
	} else {
		pModel->config.nHeadDim = pModel->config.nHeads > 0 ? (pModel->config.nEmbd / pModel->config.nHeads) : 64;
	}

	/* Feed-Forward Length */
	snprintf(key, sizeof(key), "%s.feed_forward_length", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.nFF = gguf_get_u32_val(kv, 4864);

	/* Epsilon & RoPE */
	snprintf(key, sizeof(key), "%s.attention.layer_norm_rms_epsilon", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.fNormEps = gguf_get_f32_val(kv, 1e-6f);

	snprintf(key, sizeof(key), "%s.rope.freq_base", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.fRopeFreqBase = gguf_get_f32_val(kv, 1000000.0f);

	/* Locate Tensors */
	pModel->pTokenEmbd = ring_gguf_find_tensor(pGGUF, "token_embd.weight");
	if (!pModel->pTokenEmbd) pModel->pTokenEmbd = ring_gguf_find_tensor(pGGUF, "model.embed_tokens.weight");

	pModel->pOutputNorm = ring_gguf_find_tensor(pGGUF, "output_norm.weight");
	if (!pModel->pOutputNorm) pModel->pOutputNorm = ring_gguf_find_tensor(pGGUF, "model.norm.weight");

	pModel->pOutput = ring_gguf_find_tensor(pGGUF, "output.weight");
	if (!pModel->pOutput) pModel->pOutput = ring_gguf_find_tensor(pGGUF, "lm_head.weight");
	if (!pModel->pOutput) {
		pModel->pOutput = pModel->pTokenEmbd;
	}

	/* If output tensor has an unsupported quantized type, fall back to tied token_embd */
	if (pModel->pOutput && pModel->pOutput->nType != RING_GGUF_TENSOR_Q4_0 &&
		pModel->pOutput->nType != RING_GGUF_TENSOR_Q8_0 &&
		pModel->pOutput->nType != RING_GGUF_TENSOR_Q6_K &&
		pModel->pOutput->nType != RING_GGUF_TENSOR_F16 &&
		pModel->pOutput->nType != RING_GGUF_TENSOR_F32) {
		if (pModel->pTokenEmbd && (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0 ||
								   pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0 ||
								   pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q6_K ||
								   pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16 ||
								   pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F32)) {
			printf("  [Info] output.weight type (%u) not supported. Using tied token_embd.weight (%s)\n",
				   pModel->pOutput->nType, ring_gguf_tensor_type_name(pModel->pTokenEmbd->nType));
			pModel->pOutput = pModel->pTokenEmbd;
		}
	}

	if (!pModel->pTokenEmbd) {
		printf("\n[MADAR AI] Error: Token embedding tensor (token_embd.weight) not found in GGUF!\n");
		ring_model_free(pModel);
		return NULL;
	}
	if (!pModel->pOutputNorm) {
		printf("\n[MADAR AI] Error: Output norm tensor (output_norm.weight) not found in GGUF!\n");
		ring_model_free(pModel);
		return NULL;
	}

	pModel->aLayers = (RingLayerWeights *)calloc(pModel->config.nLayers, sizeof(RingLayerWeights));
	if (!pModel->aLayers) {
		printf("\n[MADAR AI] Error: Out of memory allocating layer weights!\n");
		ring_model_free(pModel);
		return NULL;
	}

	for (l = 0; l < pModel->config.nLayers; l++) {
		snprintf(key, sizeof(key), "blk.%u.attn_norm.weight", l);
		pModel->aLayers[l].pAttnNorm = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pAttnNorm) {
			snprintf(key, sizeof(key), "model.layers.%u.input_layernorm.weight", l);
			pModel->aLayers[l].pAttnNorm = ring_gguf_find_tensor(pGGUF, key);
		}

		snprintf(key, sizeof(key), "blk.%u.attn_q.weight", l);
		pModel->aLayers[l].pAttnQ = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pAttnQ) {
			snprintf(key, sizeof(key), "model.layers.%u.self_attn.q_proj.weight", l);
			pModel->aLayers[l].pAttnQ = ring_gguf_find_tensor(pGGUF, key);
		}
		snprintf(key, sizeof(key), "blk.%u.attn_q.bias", l);
		pModel->aLayers[l].pAttnQ_Bias = ring_gguf_find_tensor(pGGUF, key);

		snprintf(key, sizeof(key), "blk.%u.attn_k.weight", l);
		pModel->aLayers[l].pAttnK = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pAttnK) {
			snprintf(key, sizeof(key), "model.layers.%u.self_attn.k_proj.weight", l);
			pModel->aLayers[l].pAttnK = ring_gguf_find_tensor(pGGUF, key);
		}
		snprintf(key, sizeof(key), "blk.%u.attn_k.bias", l);
		pModel->aLayers[l].pAttnK_Bias = ring_gguf_find_tensor(pGGUF, key);

		snprintf(key, sizeof(key), "blk.%u.attn_v.weight", l);
		pModel->aLayers[l].pAttnV = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pAttnV) {
			snprintf(key, sizeof(key), "model.layers.%u.self_attn.v_proj.weight", l);
			pModel->aLayers[l].pAttnV = ring_gguf_find_tensor(pGGUF, key);
		}
		snprintf(key, sizeof(key), "blk.%u.attn_v.bias", l);
		pModel->aLayers[l].pAttnV_Bias = ring_gguf_find_tensor(pGGUF, key);

		snprintf(key, sizeof(key), "blk.%u.attn_output.weight", l);
		pModel->aLayers[l].pAttnOut = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pAttnOut) {
			snprintf(key, sizeof(key), "model.layers.%u.self_attn.o_proj.weight", l);
			pModel->aLayers[l].pAttnOut = ring_gguf_find_tensor(pGGUF, key);
		}

		snprintf(key, sizeof(key), "blk.%u.ffn_norm.weight", l);
		pModel->aLayers[l].pFFNNorm = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pFFNNorm) {
			snprintf(key, sizeof(key), "model.layers.%u.post_attention_layernorm.weight", l);
			pModel->aLayers[l].pFFNNorm = ring_gguf_find_tensor(pGGUF, key);
		}

		snprintf(key, sizeof(key), "blk.%u.ffn_gate.weight", l);
		pModel->aLayers[l].pFFNGate = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pFFNGate) {
			snprintf(key, sizeof(key), "model.layers.%u.mlp.gate_proj.weight", l);
			pModel->aLayers[l].pFFNGate = ring_gguf_find_tensor(pGGUF, key);
		}

		snprintf(key, sizeof(key), "blk.%u.ffn_up.weight", l);
		pModel->aLayers[l].pFFNUp = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pFFNUp) {
			snprintf(key, sizeof(key), "model.layers.%u.mlp.up_proj.weight", l);
			pModel->aLayers[l].pFFNUp = ring_gguf_find_tensor(pGGUF, key);
		}

		snprintf(key, sizeof(key), "blk.%u.ffn_down.weight", l);
		pModel->aLayers[l].pFFNDown = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pFFNDown) {
			snprintf(key, sizeof(key), "model.layers.%u.mlp.down_proj.weight", l);
			pModel->aLayers[l].pFFNDown = ring_gguf_find_tensor(pGGUF, key);
		}
	}

	if (pModel->config.nLayers > 0 && !pModel->aLayers[0].pAttnQ) {
		printf("\n[MADAR AI] Error: Layer 0 attention Q weights not found in GGUF!\n");
		ring_model_free(pModel);
		return NULL;
	}

	/* Allocate KV Cache */
	pModel->nMaxSeq = 512;
	pModel->nKVDim = pModel->config.nHeadsKV * pModel->config.nHeadDim;
	kvSize = (size_t)pModel->config.nLayers * pModel->nMaxSeq * pModel->nKVDim;

	pModel->pKVCache_K = (float *)calloc(kvSize, sizeof(float));
	pModel->pKVCache_V = (float *)calloc(kvSize, sizeof(float));

	/* Working Activation Buffers */
	pModel->pActX      = (float *)calloc(pModel->config.nEmbd, sizeof(float));
	pModel->pActXB     = (float *)calloc(pModel->config.nEmbd, sizeof(float));
	pModel->pActQ      = (float *)calloc(pModel->config.nHeads * pModel->config.nHeadDim, sizeof(float));
	pModel->pActK      = (float *)calloc(pModel->nKVDim, sizeof(float));
	pModel->pActV      = (float *)calloc(pModel->nKVDim, sizeof(float));
	pModel->pActAttOut = (float *)calloc(pModel->config.nHeads * pModel->config.nHeadDim, sizeof(float));
	pModel->pActHB      = (float *)calloc(pModel->config.nFF, sizeof(float));
	pModel->pActHB2     = (float *)calloc(pModel->config.nFF, sizeof(float));
	pModel->pActAttnProj = (float *)calloc(pModel->config.nEmbd, sizeof(float));
	pModel->pActFFNOut  = (float *)calloc(pModel->config.nEmbd, sizeof(float));
	pModel->pLogits     = (float *)calloc(pModel->config.nVocab, sizeof(float));

#ifdef _WIN32
	/* Initialize Persistent Thread Pool for Parallel Inference (Supports up to 8 threads) */
	pModel->nWorkerCount = RING_MODEL_MAX_WORKERS;
	pModel->bWorkerShutdown = 0;
	{
		int i;
		for (i = 0; i < RING_MODEL_MAX_WORKERS; i++) {
			pModel->pWorkerTasks[i] = calloc(1, sizeof(MatVecTask));
			pModel->hStartEvents[i] = (void *)CreateEvent(NULL, FALSE, FALSE, NULL);
			pModel->hDoneEvents[i]  = (void *)CreateEvent(NULL, FALSE, FALSE, NULL);
			if (pModel->hStartEvents[i] && pModel->hDoneEvents[i]) {
				RingWorkerParam *param = (RingWorkerParam *)malloc(sizeof(RingWorkerParam));
				if (param) {
					param->pModel = pModel;
					param->nIndex = i;
					pModel->hWorkerThreads[i] = (void *)CreateThread(NULL, 0, ring_model_worker_proc, param, 0, NULL);
				}
			}
		}
	}
#endif

	printf("  [Model Specs] %s | L:%u | Dim:%u | Heads:%u(KV:%u) | FF:%u | Vocab:%u\n",
		   pModel->config.cArch, pModel->config.nLayers, pModel->config.nEmbd,
		   pModel->config.nHeads, pModel->config.nHeadsKV, pModel->config.nFF, pModel->config.nVocab);

	printf("  [Tensors] Embd: %s (%s, %llux%llu) | Out: %s (%s, %llux%llu)\n",
		   pModel->pTokenEmbd ? pModel->pTokenEmbd->pName : "NULL",
		   pModel->pTokenEmbd ? ring_gguf_tensor_type_name(pModel->pTokenEmbd->nType) : "NULL",
		   pModel->pTokenEmbd ? pModel->pTokenEmbd->aDims[0] : 0,
		   pModel->pTokenEmbd ? pModel->pTokenEmbd->aDims[1] : 0,
		   pModel->pOutput ? pModel->pOutput->pName : "NULL",
		   pModel->pOutput ? ring_gguf_tensor_type_name(pModel->pOutput->nType) : "NULL",
		   pModel->pOutput ? pModel->pOutput->aDims[0] : 0,
		   pModel->pOutput ? pModel->pOutput->aDims[1] : 0);

	return pModel;
}

RING_API void ring_model_free(RingModel *pModel) {
	if (!pModel) return;

#ifdef _WIN32
	pModel->bWorkerShutdown = 1;
	{
		int i;
		for (i = 0; i < pModel->nWorkerCount; i++) {
			if (pModel->hStartEvents[i]) {
				SetEvent((HANDLE)pModel->hStartEvents[i]);
			}
		}
		for (i = 0; i < pModel->nWorkerCount; i++) {
			if (pModel->hWorkerThreads[i]) {
				WaitForSingleObject((HANDLE)pModel->hWorkerThreads[i], 1000);
				CloseHandle((HANDLE)pModel->hWorkerThreads[i]);
				pModel->hWorkerThreads[i] = NULL;
			}
			if (pModel->hStartEvents[i]) {
				CloseHandle((HANDLE)pModel->hStartEvents[i]);
				pModel->hStartEvents[i] = NULL;
			}
			if (pModel->hDoneEvents[i]) {
				CloseHandle((HANDLE)pModel->hDoneEvents[i]);
				pModel->hDoneEvents[i] = NULL;
			}
			if (pModel->pWorkerTasks[i]) {
				free(pModel->pWorkerTasks[i]);
				pModel->pWorkerTasks[i] = NULL;
			}
		}
	}
#endif

	if (pModel->pKVCache_K) free(pModel->pKVCache_K);
	if (pModel->pKVCache_V) free(pModel->pKVCache_V);

	if (pModel->pActX)      free(pModel->pActX);
	if (pModel->pActXB)     free(pModel->pActXB);
	if (pModel->pActQ)      free(pModel->pActQ);
	if (pModel->pActK)      free(pModel->pActK);
	if (pModel->pActV)      free(pModel->pActV);
	if (pModel->pActAttOut) free(pModel->pActAttOut);
	if (pModel->pActHB)       free(pModel->pActHB);
	if (pModel->pActHB2)      free(pModel->pActHB2);
	if (pModel->pActAttnProj) free(pModel->pActAttnProj);
	if (pModel->pActFFNOut)   free(pModel->pActFFNOut);
	if (pModel->pLogits)      free(pModel->pLogits);

	if (pModel->aLayers)    free(pModel->aLayers);
	if (pModel->pTokenizer) ring_tokenizer_delete(pModel->pTokenizer);
	if (pModel->pGGUF)      ring_gguf_close(pModel->pGGUF);

	free(pModel);
}

RING_API void ring_model_set_threads(RingModel *pModel, int nThreads) {
	if (!pModel) return;
	if (nThreads < 1) nThreads = 1;
	if (nThreads > RING_MODEL_MAX_WORKERS + 1) nThreads = RING_MODEL_MAX_WORKERS + 1;
	pModel->nThreads = nThreads;
}

RING_API void ring_model_reset_kv(RingModel *pModel) {
	size_t kvSize;
	if (!pModel || !pModel->pKVCache_K || !pModel->pKVCache_V) return;
	kvSize = (size_t)pModel->config.nLayers * pModel->nMaxSeq * pModel->nKVDim;
	memset(pModel->pKVCache_K, 0, kvSize * sizeof(float));
	memset(pModel->pKVCache_V, 0, kvSize * sizeof(float));
	if (pModel->pTokenizer) pModel->pTokenizer->nUtf8BufLen = 0;
}

/*
================================================================================
  Transformer Forward Pass (One Token at Position `pos`)
================================================================================
*/

RING_API void ring_model_forward_ex(RingModel *pModel, int nToken, int nPos, int bComputeLogits) {
	int nEmbd, nHeadDim, nHeads, nHeadsKV, nKVDim, nFF, groupSize;
	float eps, freqBase, scale;
	const uint8_t *pRawEmbd;
	const RingGGUFBlockQ4_0 *b4;
	const ggml_fp16_t *f16;
	uint32_t l;
	RingLayerWeights *layer;
	const float *attnNormW, *ffnNormW, *outNormW;
	int seqIdx, validTokens;
	size_t kvOffset, tOffset;
	int h, kvH, d, t, i;
	float *qHead, *outHead, *kHead, *vHead;
	float attScores[512];
	float score, sumV, g, silu_g;
	float *attnOut = pModel->pActAttnProj;
	float *ffnOut = pModel->pActFFNOut;

	if (!pModel || nToken < 0 || (uint32_t)nToken >= pModel->config.nVocab) return;

	nEmbd = (int)pModel->config.nEmbd;
	nHeadDim = (int)pModel->config.nHeadDim;
	nHeads = (int)pModel->config.nHeads;
	nHeadsKV = (int)pModel->config.nHeadsKV;
	nKVDim = (int)pModel->nKVDim;
	nFF = (int)pModel->config.nFF;
	groupSize = (nHeadsKV > 0) ? (nHeads / nHeadsKV) : 1;
	if (groupSize <= 0) groupSize = 1;
	eps = pModel->config.fNormEps;
	freqBase = pModel->config.fRopeFreqBase;

	/* 1. Embedding Lookup */
	pRawEmbd = (const uint8_t *)ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pTokenEmbd);
	if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0) {
		b4 = (const RingGGUFBlockQ4_0 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) * sizeof(RingGGUFBlockQ4_0));
		ring_gguf_dequantize_q4_0(b4, pModel->pActX, nEmbd);
	} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0) {
		const RingGGUFBlockQ8_0 *b8 = (const RingGGUFBlockQ8_0 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) * sizeof(RingGGUFBlockQ8_0));
		ring_gguf_dequantize_q8_0(b8, pModel->pActX, nEmbd);
	} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16) {
		f16 = (const ggml_fp16_t *)(pRawEmbd + (size_t)nToken * nEmbd * sizeof(ggml_fp16_t));
		ring_gguf_dequantize_f16(f16, pModel->pActX, nEmbd);
	} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F32) {
		memcpy(pModel->pActX, pRawEmbd + (size_t)nToken * nEmbd * sizeof(float), nEmbd * sizeof(float));
	} else {
		printf("\n[MADAR AI] Warning: Unknown embedding tensor type: %u\n", pModel->pTokenEmbd->nType);
	}

	/* 2. Forward through Transformer Layers */
	for (l = 0; l < pModel->config.nLayers; l++) {
		layer = &pModel->aLayers[l];

		/* RMSNorm before Attention */
		attnNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, layer->pAttnNorm);
		rmsnorm(pModel->pActXB, pModel->pActX, attnNormW, nEmbd, eps);

		/* Compute Q, K, V */
		matvec_multiply(pModel, layer->pAttnQ, pModel->pActXB, pModel->pActQ, layer->pAttnQ_Bias);
		matvec_multiply(pModel, layer->pAttnK, pModel->pActXB, pModel->pActK, layer->pAttnK_Bias);
		matvec_multiply(pModel, layer->pAttnV, pModel->pActXB, pModel->pActV, layer->pAttnV_Bias);

		/* RoPE on Q and K */
		apply_rope(pModel->pActQ, nHeads, nHeadDim, nPos, freqBase);
		apply_rope(pModel->pActK, nHeadsKV, nHeadDim, nPos, freqBase);

		/* Store K, V in KV Cache */
		seqIdx = nPos % pModel->nMaxSeq;
		kvOffset = ((size_t)l * pModel->nMaxSeq + seqIdx) * nKVDim;
		memcpy(pModel->pKVCache_K + kvOffset, pModel->pActK, nKVDim * sizeof(float));
		memcpy(pModel->pKVCache_V + kvOffset, pModel->pActV, nKVDim * sizeof(float));

		/* Scaled Dot-Product Attention with GQA */
		scale = 1.0f / sqrtf((float)nHeadDim);
		validTokens = (nPos < (int)pModel->nMaxSeq) ? (nPos + 1) : (int)pModel->nMaxSeq;

		for (h = 0; h < nHeads; h++) {
			kvH = h / groupSize;
			if (kvH >= nHeadsKV) kvH = nHeadsKV - 1;

			qHead = pModel->pActQ + h * nHeadDim;
			outHead = pModel->pActAttOut + h * nHeadDim;

			for (t = 0; t < validTokens; t++) {
				tOffset = ((size_t)l * pModel->nMaxSeq + t) * nKVDim + (size_t)kvH * nHeadDim;
				kHead = pModel->pKVCache_K + tOffset;
				score = 0.0f;
				for (d = 0; d < nHeadDim; d++) {
					score += qHead[d] * kHead[d];
				}
				attScores[t] = score * scale;
			}

			softmax(attScores, validTokens);

			for (d = 0; d < nHeadDim; d++) {
				outHead[d] = 0.0f;
			}
			for (t = 0; t < validTokens; t++) {
				tOffset = ((size_t)l * pModel->nMaxSeq + t) * nKVDim + (size_t)kvH * nHeadDim;
				vHead = pModel->pKVCache_V + tOffset;
				float a = attScores[t];
				for (d = 0; d < nHeadDim; d++) {
					outHead[d] += a * vHead[d];
				}
			}
		}

		/* Attention Output Projection */
		matvec_multiply(pModel, layer->pAttnOut, pModel->pActAttOut, attnOut, NULL);

		/* Residual Addition: x = x + attnOut */
		for (i = 0; i < nEmbd; i++) {
			pModel->pActX[i] += attnOut[i];
		}

		/* RMSNorm before FFN */
		ffnNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNNorm);
		rmsnorm(pModel->pActXB, pModel->pActX, ffnNormW, nEmbd, eps);

		/* SwiGLU FFN: gate = W_gate * xb, up = W_up * xb */
		matvec_multiply(pModel, layer->pFFNGate, pModel->pActXB, pModel->pActHB, NULL);
		matvec_multiply(pModel, layer->pFFNUp,   pModel->pActXB, pModel->pActHB2, NULL);

		/* SiLU Activation: hb = (gate * sigmoid(gate)) * up */
		for (i = 0; i < nFF; i++) {
			g = pModel->pActHB[i];
			silu_g = g / (1.0f + expf(-g));
			pModel->pActHB[i] = silu_g * pModel->pActHB2[i];
		}

		/* Down Projection: ffnOut = W_down * hb */
		matvec_multiply(pModel, layer->pFFNDown, pModel->pActHB, ffnOut, NULL);

		/* Residual Addition: x = x + ffnOut */
		for (i = 0; i < nEmbd; i++) {
			pModel->pActX[i] += ffnOut[i];
		}
	}

	/* 3. Final Output RMSNorm & Logits (Only when requested) */
	if (bComputeLogits) {
		outNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pOutputNorm);
		rmsnorm(pModel->pActXB, pModel->pActX, outNormW, nEmbd, eps);

		/* 4. Output Projection to Logits */
		matvec_multiply(pModel, pModel->pOutput, pModel->pActXB, pModel->pLogits, NULL);
	}
}

RING_API void ring_model_forward(RingModel *pModel, int nToken, int nPos) {
	ring_model_forward_ex(pModel, nToken, nPos, 1);
}

/*
================================================================================
  Sampling (Greedy & Temperature)
================================================================================
*/

RING_API int ring_model_sample(RingModel *pModel, float fTemp) {
	uint32_t nVocab, i, j;
	float *logits;
	int bestToken;
	float maxLogit, invTemp, sumExp, r, accum;
	int topK = 40;
	int topIndices[40];
	float topLogits[40];
	float minTopLogit;
	int minTopIdx;

	if (!pModel) return 0;

	nVocab = pModel->config.nVocab;
	logits = pModel->pLogits;

	/* Greedy Sampling (Argmax) */
	if (fTemp <= 0.05f) {
		bestToken = 0;
		maxLogit = logits[0];
		for (i = 1; i < nVocab; i++) {
			if (logits[i] > maxLogit) {
				maxLogit = logits[i];
				bestToken = (int)i;
			}
		}
		return bestToken;
	}

	/* Top-K Filtering (K = 40) to eliminate uniform tail noise across 151k vocab */
	if (topK > (int)nVocab) topK = (int)nVocab;
	for (i = 0; i < (uint32_t)topK; i++) {
		topIndices[i] = (int)i;
		topLogits[i] = logits[i];
	}

	minTopLogit = topLogits[0];
	minTopIdx = 0;
	for (j = 1; j < (uint32_t)topK; j++) {
		if (topLogits[j] < minTopLogit) {
			minTopLogit = topLogits[j];
			minTopIdx = (int)j;
		}
	}

	for (i = (uint32_t)topK; i < nVocab; i++) {
		if (logits[i] > minTopLogit) {
			topIndices[minTopIdx] = (int)i;
			topLogits[minTopIdx] = logits[i];

			minTopLogit = topLogits[0];
			minTopIdx = 0;
			for (j = 1; j < (uint32_t)topK; j++) {
				if (topLogits[j] < minTopLogit) {
					minTopLogit = topLogits[j];
					minTopIdx = (int)j;
				}
			}
		}
	}

	maxLogit = topLogits[0];
	for (j = 1; j < (uint32_t)topK; j++) {
		if (topLogits[j] > maxLogit) maxLogit = topLogits[j];
	}

	invTemp = 1.0f / fTemp;
	sumExp = 0.0f;
	for (j = 0; j < (uint32_t)topK; j++) {
		topLogits[j] = expf((topLogits[j] - maxLogit) * invTemp);
		sumExp += topLogits[j];
	}

	/* 30-bit high resolution pseudo-random value */
	{
		uint32_t r32 = (((uint32_t)rand() & 0x7FFF) << 15) | ((uint32_t)rand() & 0x7FFF);
		r = ((float)r32 / (float)0x3FFFFFFF) * sumExp;
	}

	accum = 0.0f;
	for (j = 0; j < (uint32_t)topK; j++) {
		accum += topLogits[j];
		if (accum >= r) return topIndices[j];
	}

	return topIndices[0];
}

/*
================================================================================
  Text Generation Loop
================================================================================
*/

RING_API char *ring_model_generate_stream(RingModel *pModel, const char *cPrompt, int nMaxTokens, float fTemp, int bStreamStdout) {
	int promptTokens[1024];
	int genTokens[1024];
	int nPromptTokens, nGen = 0, i, curPos, nextToken;
	char *tokenStr;

	if (!pModel || !cPrompt) return _strdup("");
	if (nMaxTokens <= 0) nMaxTokens = 64;
	if (nMaxTokens > 1024) nMaxTokens = 1024;

	/* Tokenize Prompt */
	nPromptTokens = ring_tokenizer_encode(pModel->pTokenizer, cPrompt, promptTokens, 1024);
	if (nPromptTokens <= 0) return _strdup("");

	ring_model_reset_kv(pModel);

	/* Evaluate Prompt - ONLY compute logits on the LAST prompt token to skip huge matrix multiply on prefill! */
	for (i = 0; i < nPromptTokens; i++) {
		int bComputeLogits = (i == nPromptTokens - 1) ? 1 : 0;
		ring_model_forward_ex(pModel, promptTokens[i], i, bComputeLogits);
	}

	/* Autoregressive Generation Loop */
	curPos = nPromptTokens;
	while (nGen < nMaxTokens) {
		/* Gentle repetition penalty applied at most ONCE per unique token in the last 32 tokens */
		int penaltyStart = (nGen > 32) ? (nGen - 32) : 0;
		for (i = penaltyStart; i < nGen; i++) {
			int prevTok = genTokens[i];
			int alreadyPenalized = 0;
			int k;
			for (k = penaltyStart; k < i; k++) {
				if (genTokens[k] == prevTok) {
					alreadyPenalized = 1;
					break;
				}
			}
			if (!alreadyPenalized && prevTok >= 0 && (uint32_t)prevTok < pModel->config.nVocab) {
				if (pModel->pLogits[prevTok] > 0.0f) {
					pModel->pLogits[prevTok] /= 1.1f;
				} else {
					pModel->pLogits[prevTok] *= 1.1f;
				}
			}
		}

		/* Suppress immediate EOS on the very first generated token */
		if (nGen == 0) {
			if (pModel->pTokenizer->nEosToken >= 0 && (uint32_t)pModel->pTokenizer->nEosToken < pModel->config.nVocab) {
				pModel->pLogits[pModel->pTokenizer->nEosToken] = -1e9f;
			}
			if (pModel->config.nVocab > 151645) {
				pModel->pLogits[151643] = -1e9f; /* <|endoftext|> */
				pModel->pLogits[151645] = -1e9f; /* <|im_end|> */
			}
		}

		nextToken = ring_model_sample(pModel, fTemp);

		/* Check Qwen & Standard Stop Tokens (only after producing at least one token) */
		if (nGen > 0 && (nextToken == pModel->pTokenizer->nEosToken ||
			nextToken == 151643 || /* <|endoftext|> */
			nextToken == 151645)) { /* <|im_end|> */
			break;
		}

		genTokens[nGen++] = nextToken;

		if (bStreamStdout) {
			tokenStr = ring_tokenizer_decode_tokens(pModel->pTokenizer, &nextToken, 1);
			if (tokenStr) {
				fputs(tokenStr, stdout);
				fflush(stdout);
				free(tokenStr);
			}
		}

		ring_model_forward_ex(pModel, nextToken, curPos++, 1);
	}

	if (bStreamStdout && pModel->pTokenizer && pModel->pTokenizer->nUtf8BufLen > 0) {
		char flushBuf[16];
		int flushW = 0;
		ring_tokenizer_flush(pModel->pTokenizer, flushBuf, &flushW, sizeof(flushBuf));
		if (flushW > 0) {
			flushBuf[flushW] = '\0';
			fputs(flushBuf, stdout);
			fflush(stdout);
		}
	}

	return ring_tokenizer_decode_tokens(pModel->pTokenizer, genTokens, nGen);
}

RING_API char *ring_model_generate(RingModel *pModel, const char *cPrompt, int nMaxTokens, float fTemp) {
	return ring_model_generate_stream(pModel, cPrompt, nMaxTokens, fTemp, 0);
}

/*
================================================================================
  Ring Scripting VM APIs
================================================================================
*/

RING_FUNC(ring_model_api_open) {
	const char *cFile;
	RingModel *pModel;

	if (RING_API_PARACOUNT != 1 || !RING_API_ISSTRING(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	cFile = RING_API_GETSTRING(1);
	if (!cFile || strlen(cFile) == 0) {
		RING_API_ERROR("Model file path cannot be empty!");
		return;
	}
	pModel = ring_model_load(cFile);
	if (!pModel) {
		RING_API_ERROR("Failed to load AI Model from GGUF file!");
		return;
	}

	RING_API_RETMANAGEDCPOINTER(pModel, "MADAR_MODEL", (void (*)(void *, void *))ring_model_free);
}

RING_FUNC(ring_model_api_close) {
	RingModel *pModel;

	if (RING_API_PARACOUNT != 1 || !RING_API_ISPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	if (pModel) {
		ring_model_free(pModel);
		RING_API_SETNULLPOINTER(1);
	}
}

RING_FUNC(ring_model_api_set_threads) {
	RingModel *pModel;

	if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) || !RING_API_ISNUMBER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);
	ring_model_set_threads(pModel, (int)RING_API_GETNUMBER(2));
}

RING_FUNC(ring_model_api_tokenize) {
	RingModel *pModel;
	int aTokens[1024];
	int n, i;
	List *pList;

	if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);

	n = ring_tokenizer_encode(pModel->pTokenizer, RING_API_GETSTRING(2), aTokens, 1024);

	pList = RING_API_NEWLIST;
	for (i = 0; i < n; i++) {
		ring_list_adddouble(pList, (double)aTokens[i]);
	}
	RING_API_RETLIST(pList);
}

RING_FUNC(ring_model_api_detokenize) {
	RingModel *pModel;
	int aTokens[1024];
	int nTokens = 0, i;
	char *outText;
	List *pList;

	if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);

	if (RING_API_ISNUMBER(2)) {
		aTokens[0] = (int)RING_API_GETNUMBER(2);
		nTokens = 1;
	} else if (RING_API_ISLIST(2)) {
		pList = RING_API_GETLIST(2);
		nTokens = ring_list_getsize(pList);
		if (nTokens > 1024) nTokens = 1024;
		for (i = 1; i <= nTokens; i++) {
			aTokens[i - 1] = (int)ring_list_getdouble(pList, i);
		}
	} else {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	outText = ring_tokenizer_decode_tokens(pModel->pTokenizer, aTokens, nTokens);
	RING_API_RETSTRING(outText);
	free(outText);
}

RING_FUNC(ring_model_api_generate) {
	RingModel *pModel;
	const char *cPrompt;
	int nMaxTokens = 64;
	float fTemp = 0.7f;
	char *cResult;

	if (RING_API_PARACOUNT < 2 || !RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);

	cPrompt = RING_API_GETSTRING(2);

	if (RING_API_PARACOUNT >= 3 && RING_API_ISNUMBER(3)) {
		nMaxTokens = (int)RING_API_GETNUMBER(3);
	}
	if (RING_API_PARACOUNT >= 4 && RING_API_ISNUMBER(4)) {
		fTemp = (float)RING_API_GETNUMBER(4);
	}

	cResult = ring_model_generate(pModel, cPrompt, nMaxTokens, fTemp);
	RING_API_RETSTRING(cResult);
	free(cResult);
}

RING_FUNC(ring_model_api_generate_stream) {
	RingModel *pModel;
	const char *cPrompt;
	int nMaxTokens = 64;
	float fTemp = 0.7f;
	char *cResult;

	if (RING_API_PARACOUNT < 2 || !RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);

	cPrompt = RING_API_GETSTRING(2);

	if (RING_API_PARACOUNT >= 3 && RING_API_ISNUMBER(3)) {
		nMaxTokens = (int)RING_API_GETNUMBER(3);
	}
	if (RING_API_PARACOUNT >= 4 && RING_API_ISNUMBER(4)) {
		fTemp = (float)RING_API_GETNUMBER(4);
	}

	cResult = ring_model_generate_stream(pModel, cPrompt, nMaxTokens, fTemp, 1);
	RING_API_RETSTRING(cResult);
	free(cResult);
}

RING_FUNC(ring_model_api_reset) {
	RingModel *pModel;

	if (RING_API_PARACOUNT != 1 || !RING_API_ISPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);
	ring_model_reset_kv(pModel);
}

RING_FUNC(ring_model_api_is_arabic) {
	const char *str;
	if (RING_API_PARACOUNT != 1 || !RING_API_ISSTRING(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	str = RING_API_GETSTRING(1);
	while (str && *str) {
		unsigned char c = (unsigned char)*str;
		if (c == 0xD8 || c == 0xD9) {
			RING_API_RETNUMBER(1);
			return;
		}
		str++;
	}
	RING_API_RETNUMBER(0);
}

RING_API void ring_inference_loadfunctions(void *pRingState) {
	RING_API_REGISTER("madar_model_open", ring_model_api_open);
	RING_API_REGISTER("madar_model_close", ring_model_api_close);
	RING_API_REGISTER("madar_model_set_threads", ring_model_api_set_threads);
	RING_API_REGISTER("madar_model_tokenize", ring_model_api_tokenize);
	RING_API_REGISTER("madar_model_detokenize", ring_model_api_detokenize);
	RING_API_REGISTER("madar_model_generate", ring_model_api_generate);
	RING_API_REGISTER("madar_model_generate_stream", ring_model_api_generate_stream);
	RING_API_REGISTER("madar_model_reset", ring_model_api_reset);
	RING_API_REGISTER("madar_is_arabic", ring_model_api_is_arabic);
}
