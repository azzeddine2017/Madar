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

#if defined(__AVX2__) || (defined(_MSC_VER) && (defined(_M_AMD64) || defined(_M_X64)))
#include <immintrin.h>
#define MADAR_AVX2 1

static inline float hsum_float_8(__m256 v) {
	__m128 vlow = _mm256_castps256_ps128(v);
	__m128 vhigh = _mm256_extractf128_ps(v, 1);
	__m128 v128 = _mm_add_ps(vlow, vhigh);
	__m128 v64 = _mm_add_ps(v128, _mm_movehl_ps(v128, v128));
	__m128 v32 = _mm_add_ss(v64, _mm_shuffle_ps(v64, v64, 0x55));
	return _mm_cvtss_f32(v32);
}

static inline float ggml_hw_fp16_to_fp32(uint16_t h) {
	return _mm_cvtss_f32(_mm_cvtph_ps(_mm_cvtsi32_si128((int)h)));
}
#endif

#if defined(MADAR_AVX2)
static float dot_q4_0(const RingGGUFBlockQ4_0 *b, const float *x, int k) {
	int nBlocks = k / 32;
	int i = 0;
	const __m128i lowMask = _mm_set1_epi8(0x0F);
	const __m128i c8 = _mm_set1_epi8(8);
	__m256 acc0 = _mm256_setzero_ps();
	__m256 acc1 = _mm256_setzero_ps();

	for (; i + 1 < nBlocks; i += 2) {
		/* Block 0 */
		__m128 h0 = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
		__m256 vd0 = _mm256_broadcastss_ps(h0);
		__m128i raw0 = _mm_loadu_si128((const __m128i *)b[i].qs);
		const float *xi0 = x + i * 32;

		__m128i low0 = _mm_sub_epi8(_mm_and_si128(raw0, lowMask), c8);
		__m128i high0 = _mm_sub_epi8(_mm_and_si128(_mm_srli_epi16(raw0, 4), lowMask), c8);

		__m256 f0_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low0));
		__m256 f1_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low0, 8)));
		__m256 f2_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high0));
		__m256 f3_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high0, 8)));

		__m256 p01_0 = _mm256_fmadd_ps(f0_0, _mm256_loadu_ps(xi0 + 0), _mm256_mul_ps(f1_0, _mm256_loadu_ps(xi0 + 8)));
		__m256 p23_0 = _mm256_fmadd_ps(f2_0, _mm256_loadu_ps(xi0 + 16), _mm256_mul_ps(f3_0, _mm256_loadu_ps(xi0 + 24)));
		acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01_0, p23_0), vd0, acc0);

		/* Block 1 */
		__m128 h1 = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i + 1].d));
		__m256 vd1 = _mm256_broadcastss_ps(h1);
		__m128i raw1 = _mm_loadu_si128((const __m128i *)b[i + 1].qs);
		const float *xi1 = x + (i + 1) * 32;

		__m128i low1 = _mm_sub_epi8(_mm_and_si128(raw1, lowMask), c8);
		__m128i high1 = _mm_sub_epi8(_mm_and_si128(_mm_srli_epi16(raw1, 4), lowMask), c8);

		__m256 f0_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low1));
		__m256 f1_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low1, 8)));
		__m256 f2_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high1));
		__m256 f3_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high1, 8)));

		__m256 p01_1 = _mm256_fmadd_ps(f0_1, _mm256_loadu_ps(xi1 + 0), _mm256_mul_ps(f1_1, _mm256_loadu_ps(xi1 + 8)));
		__m256 p23_1 = _mm256_fmadd_ps(f2_1, _mm256_loadu_ps(xi1 + 16), _mm256_mul_ps(f3_1, _mm256_loadu_ps(xi1 + 24)));
		acc1 = _mm256_fmadd_ps(_mm256_add_ps(p01_1, p23_1), vd1, acc1);
	}

	for (; i < nBlocks; i++) {
		__m128 h = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
		__m256 vd = _mm256_broadcastss_ps(h);
		__m128i raw = _mm_loadu_si128((const __m128i *)b[i].qs);
		const float *xi = x + i * 32;

		__m128i low = _mm_sub_epi8(_mm_and_si128(raw, lowMask), c8);
		__m128i high = _mm_sub_epi8(_mm_and_si128(_mm_srli_epi16(raw, 4), lowMask), c8);

		__m256 f0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low));
		__m256 f1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low, 8)));
		__m256 f2 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high));
		__m256 f3 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high, 8)));

		__m256 p01 = _mm256_fmadd_ps(f0, _mm256_loadu_ps(xi + 0), _mm256_mul_ps(f1, _mm256_loadu_ps(xi + 8)));
		__m256 p23 = _mm256_fmadd_ps(f2, _mm256_loadu_ps(xi + 16), _mm256_mul_ps(f3, _mm256_loadu_ps(xi + 24)));
		acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01, p23), vd, acc0);
	}

	return hsum_float_8(_mm256_add_ps(acc0, acc1));
}

static float dot_q8_0(const RingGGUFBlockQ8_0 *b, const float *x, int k) {
	int nBlocks = k / 32;
	int i = 0;
	__m256 acc0 = _mm256_setzero_ps();
	__m256 acc1 = _mm256_setzero_ps();

	for (; i + 1 < nBlocks; i += 2) {
		/* Block 0 */
		__m128 h0 = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
		__m256 vd0 = _mm256_broadcastss_ps(h0);
		const int8_t *qs0 = b[i].qs;
		const float *xi0 = x + i * 32;

		__m128i q0_15_0  = _mm_loadu_si128((const __m128i *)(qs0 + 0));
		__m128i q16_31_0 = _mm_loadu_si128((const __m128i *)(qs0 + 16));

		__m256 f0_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q0_15_0));
		__m256 f1_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q0_15_0, 8)));
		__m256 f2_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q16_31_0));
		__m256 f3_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q16_31_0, 8)));

		__m256 p01_0 = _mm256_fmadd_ps(f0_0, _mm256_loadu_ps(xi0 + 0), _mm256_mul_ps(f1_0, _mm256_loadu_ps(xi0 + 8)));
		__m256 p23_0 = _mm256_fmadd_ps(f2_0, _mm256_loadu_ps(xi0 + 16), _mm256_mul_ps(f3_0, _mm256_loadu_ps(xi0 + 24)));
		acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01_0, p23_0), vd0, acc0);

		/* Block 1 */
		__m128 h1 = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i + 1].d));
		__m256 vd1 = _mm256_broadcastss_ps(h1);
		const int8_t *qs1 = b[i + 1].qs;
		const float *xi1 = x + (i + 1) * 32;

		__m128i q0_15_1  = _mm_loadu_si128((const __m128i *)(qs1 + 0));
		__m128i q16_31_1 = _mm_loadu_si128((const __m128i *)(qs1 + 16));

		__m256 f0_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q0_15_1));
		__m256 f1_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q0_15_1, 8)));
		__m256 f2_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q16_31_1));
		__m256 f3_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q16_31_1, 8)));

		__m256 p01_1 = _mm256_fmadd_ps(f0_1, _mm256_loadu_ps(xi1 + 0), _mm256_mul_ps(f1_1, _mm256_loadu_ps(xi1 + 8)));
		__m256 p23_1 = _mm256_fmadd_ps(f2_1, _mm256_loadu_ps(xi1 + 16), _mm256_mul_ps(f3_1, _mm256_loadu_ps(xi1 + 24)));
		acc1 = _mm256_fmadd_ps(_mm256_add_ps(p01_1, p23_1), vd1, acc1);
	}

	for (; i < nBlocks; i++) {
		__m128 h = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
		__m256 vd = _mm256_broadcastss_ps(h);
		const int8_t *qs = b[i].qs;
		const float *xi = x + i * 32;

		__m128i q0_15  = _mm_loadu_si128((const __m128i *)(qs + 0));
		__m128i q16_31 = _mm_loadu_si128((const __m128i *)(qs + 16));

		__m256 f0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q0_15));
		__m256 f1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q0_15, 8)));
		__m256 f2 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q16_31));
		__m256 f3 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q16_31, 8)));

		__m256 p01 = _mm256_fmadd_ps(f0, _mm256_loadu_ps(xi + 0), _mm256_mul_ps(f1, _mm256_loadu_ps(xi + 8)));
		__m256 p23 = _mm256_fmadd_ps(f2, _mm256_loadu_ps(xi + 16), _mm256_mul_ps(f3, _mm256_loadu_ps(xi + 24)));
		acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01, p23), vd, acc0);
	}

	return hsum_float_8(_mm256_add_ps(acc0, acc1));
}

static float dot_f16(const ggml_fp16_t *f, const float *x, int k) {
	int i = 0;
	__m256 acc0 = _mm256_setzero_ps();
	__m256 acc1 = _mm256_setzero_ps();
	for (; i + 15 < k; i += 16) {
		__m128i h0 = _mm_loadu_si128((const __m128i *)(f + i));
		__m128i h1 = _mm_loadu_si128((const __m128i *)(f + i + 8));
		acc0 = _mm256_fmadd_ps(_mm256_cvtph_ps(h0), _mm256_loadu_ps(x + i), acc0);
		acc1 = _mm256_fmadd_ps(_mm256_cvtph_ps(h1), _mm256_loadu_ps(x + i + 8), acc1);
	}
	for (; i + 7 < k; i += 8) {
		__m128i h = _mm_loadu_si128((const __m128i *)(f + i));
		acc0 = _mm256_fmadd_ps(_mm256_cvtph_ps(h), _mm256_loadu_ps(x + i), acc0);
	}
	float sum = hsum_float_8(_mm256_add_ps(acc0, acc1));
	for (; i < k; i++) {
		sum += ggml_hw_fp16_to_fp32(f[i]) * x[i];
	}
	return sum;
}

static float dot_f32(const float *f, const float *x, int k) {
	int i = 0;
	__m256 acc0 = _mm256_setzero_ps();
	__m256 acc1 = _mm256_setzero_ps();

	for (; i + 15 < k; i += 16) {
		acc0 = _mm256_fmadd_ps(_mm256_loadu_ps(f + i), _mm256_loadu_ps(x + i), acc0);
		acc1 = _mm256_fmadd_ps(_mm256_loadu_ps(f + i + 8), _mm256_loadu_ps(x + i + 8), acc1);
	}
	for (; i + 7 < k; i += 8) {
		acc0 = _mm256_fmadd_ps(_mm256_loadu_ps(f + i), _mm256_loadu_ps(x + i), acc0);
	}
	float sum = hsum_float_8(_mm256_add_ps(acc0, acc1));
	for (; i < k; i++) {
		sum += f[i] * x[i];
	}
	return sum;
}
#else
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
#endif

static float dot_q6_k(const RingGGUFBlockQ6_K *b, const float *x, int k) {
	int nBlocks = k / 256;
	float sum = 0.0f;
	int i;

	for (i = 0; i < nBlocks; i++) {
#if defined(MADAR_AVX2)
		float d = ggml_hw_fp16_to_fp32(b[i].d);
#else
		float d = fast_fp16_to_fp32(b[i].d);
#endif
		const uint8_t *ql = b[i].ql;
		const uint8_t *qh = b[i].qh;
		const int8_t *sc = b[i].scales;
		const float *v = x + i * 256;
		float bsum = 0.0f;

		for (int n_half = 0; n_half < 256; n_half += 128) {
			for (int h = 0; h < 2; h++) {
				float s0 = (float)sc[h + 0];
				float s2 = (float)sc[h + 2];
				float s4 = (float)sc[h + 4];
				float s6 = (float)sc[h + 6];
				int l_start = h * 16;
				int l_end = l_start + 16;

				for (int l = l_start; l < l_end; l++) {
					int8_t q1 = (int8_t)((ql[l +  0] & 0xF) | (((qh[l] >> 0) & 3) << 4)) - 32;
					int8_t q2 = (int8_t)((ql[l + 32] & 0xF) | (((qh[l] >> 2) & 3) << 4)) - 32;
					int8_t q3 = (int8_t)((ql[l +  0] >>  4) | (((qh[l] >> 4) & 3) << 4)) - 32;
					int8_t q4 = (int8_t)((ql[l + 32] >>  4) | (((qh[l] >> 6) & 3) << 4)) - 32;

					bsum += s0 * (float)q1 * v[l +  0]
					      + s2 * (float)q2 * v[l + 32]
					      + s4 * (float)q3 * v[l + 64]
					      + s6 * (float)q4 * v[l + 96];
				}
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

	if (!pRaw) return;

	nType = task->pInfo->nType;
	K = task->K;

	if (nType == RING_GGUF_TENSOR_Q4_0) {
		size_t rowStride = (size_t)(K / 32) * sizeof(RingGGUFBlockQ4_0);
		const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
		for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
			val = dot_q4_0((const RingGGUFBlockQ4_0 *)pRow, task->pX, K);
			if (task->pBias) {
				val += (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16) ?
					   fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r]) :
					   ((const float *)task->pBias)[r];
			}
			task->pY[r] = val;
		}
		return;
	} else if (nType == RING_GGUF_TENSOR_Q8_0) {
		size_t rowStride = (size_t)(K / 32) * sizeof(RingGGUFBlockQ8_0);
		const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
		for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
			val = dot_q8_0((const RingGGUFBlockQ8_0 *)pRow, task->pX, K);
			if (task->pBias) {
				val += (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16) ?
					   fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r]) :
					   ((const float *)task->pBias)[r];
			}
			task->pY[r] = val;
		}
		return;
	} else if (nType == RING_GGUF_TENSOR_F16) {
		size_t rowStride = (size_t)K * sizeof(ggml_fp16_t);
		const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
		for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
			val = dot_f16((const ggml_fp16_t *)pRow, task->pX, K);
			if (task->pBias) {
				val += (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16) ?
					   fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r]) :
					   ((const float *)task->pBias)[r];
			}
			task->pY[r] = val;
		}
		return;
	} else if (nType == RING_GGUF_TENSOR_F32) {
		size_t rowStride = (size_t)K * sizeof(float);
		const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
		for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
			val = dot_f32((const float *)pRow, task->pX, K);
			if (task->pBias) {
				val += (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16) ?
					   fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r]) :
					   ((const float *)task->pBias)[r];
			}
			task->pY[r] = val;
		}
		return;
	} else if (nType == RING_GGUF_TENSOR_Q6_K) {
		size_t rowStride = (size_t)(K / 256) * sizeof(RingGGUFBlockQ6_K);
		const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
		for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
			val = dot_q6_k((const RingGGUFBlockQ6_K *)pRow, task->pX, K);
			if (task->pBias) {
				val += (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16) ?
					   fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r]) :
					   ((const float *)task->pBias)[r];
			}
			task->pY[r] = val;
		}
		return;
	} else {
		static int s_unsupportedWarn = 0;
		if (s_unsupportedWarn++ < 1) {
			printf("\n[MADAR AI] Warning: matvec_compute_rows unsupported tensor type: %u for '%s'!\n",
				   nType, task->pInfo->pName ? task->pInfo->pName : "unknown");
		}
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

/*
================================================================================
  GPU Acceleration Engine (OpenCL Dynamic Zero-Copy Subsystem)
================================================================================
*/

#include "opencl_stub.h"

static int s_cl_loaded = 0;
static pfn_clGetPlatformIDs            p_clGetPlatformIDs = NULL;
static pfn_clGetDeviceIDs              p_clGetDeviceIDs = NULL;
static pfn_clGetDeviceInfo             p_clGetDeviceInfo = NULL;
static pfn_clCreateContext             p_clCreateContext = NULL;
static pfn_clCreateCommandQueue        p_clCreateCommandQueue = NULL;
static pfn_clCreateBuffer              p_clCreateBuffer = NULL;
static pfn_clCreateProgramWithSource   p_clCreateProgramWithSource = NULL;
static pfn_clBuildProgram              p_clBuildProgram = NULL;
static pfn_clGetProgramBuildInfo       p_clGetProgramBuildInfo = NULL;
static pfn_clCreateKernel              p_clCreateKernel = NULL;
static pfn_clSetKernelArg              p_clSetKernelArg = NULL;
static pfn_clEnqueueNDRangeKernel      p_clEnqueueNDRangeKernel = NULL;
static pfn_clEnqueueReadBuffer         p_clEnqueueReadBuffer = NULL;
static pfn_clEnqueueWriteBuffer        p_clEnqueueWriteBuffer = NULL;
static pfn_clFinish                    p_clFinish = NULL;
static pfn_clReleaseMemObject          p_clReleaseMemObject = NULL;
static pfn_clReleaseKernel             p_clReleaseKernel = NULL;
static pfn_clReleaseProgram            p_clReleaseProgram = NULL;
static pfn_clReleaseCommandQueue       p_clReleaseCommandQueue = NULL;
static pfn_clReleaseContext            p_clReleaseContext = NULL;

static int madar_opencl_load_dll(void) {
	if (s_cl_loaded == 1) return 1;
	if (s_cl_loaded == -1) return 0;

#ifdef _WIN32
	HMODULE hLib = LoadLibraryA("OpenCL.dll");
	if (!hLib) {
		s_cl_loaded = -1;
		return 0;
	}
	#define LOAD_CL_SYM(name) do { \
		p_##name = (pfn_##name)GetProcAddress(hLib, #name); \
		if (!p_##name) { s_cl_loaded = -1; return 0; } \
	} while(0)

	LOAD_CL_SYM(clGetPlatformIDs);
	LOAD_CL_SYM(clGetDeviceIDs);
	LOAD_CL_SYM(clGetDeviceInfo);
	LOAD_CL_SYM(clCreateContext);
	LOAD_CL_SYM(clCreateCommandQueue);
	LOAD_CL_SYM(clCreateBuffer);
	LOAD_CL_SYM(clCreateProgramWithSource);
	LOAD_CL_SYM(clBuildProgram);
	LOAD_CL_SYM(clGetProgramBuildInfo);
	LOAD_CL_SYM(clCreateKernel);
	LOAD_CL_SYM(clSetKernelArg);
	LOAD_CL_SYM(clEnqueueNDRangeKernel);
	LOAD_CL_SYM(clEnqueueReadBuffer);
	LOAD_CL_SYM(clEnqueueWriteBuffer);
	LOAD_CL_SYM(clFinish);
	LOAD_CL_SYM(clReleaseMemObject);
	LOAD_CL_SYM(clReleaseKernel);
	LOAD_CL_SYM(clReleaseProgram);
	LOAD_CL_SYM(clReleaseCommandQueue);
	LOAD_CL_SYM(clReleaseContext);

	#undef LOAD_CL_SYM
	s_cl_loaded = 1;
	return 1;
#else
	s_cl_loaded = -1;
	return 0;
#endif
}

static const char *s_madar_cl_source =
"inline float fp16_to_fp32(ushort h) {\n"
"    uint sign = ((uint)h & 0x8000) << 16;\n"
"    uint exp  = (h >> 10) & 0x1F;\n"
"    uint mant = (h & 0x3FF) << 13;\n"
"    if (exp == 0x1F) return as_float(sign | 0x7F800000 | mant);\n"
"    if (exp == 0) return (mant == 0) ? as_float(sign) : as_float(sign | ((exp + 112) << 23) | mant);\n"
"    return as_float(sign | ((exp + 112) << 23) | mant);\n"
"}\n"
"\n"
"typedef struct {\n"
"    ushort d;\n"
"    uchar qs[16];\n"
"} block_q4_0;\n"
"\n"
"__kernel void matvec_q4_0_kernel(\n"
"    __global const block_q4_0* W,\n"
"    __global const float* x,\n"
"    __global float* y,\n"
"    int K, int N)\n"
"{\n"
"    int r = get_global_id(0);\n"
"    if (r >= N) return;\n"
"    int num_blocks = K / 32;\n"
"    __global const block_q4_0* row = W + (size_t)r * num_blocks;\n"
"    float sum = 0.0f;\n"
"    for (int b = 0; b < num_blocks; b++) {\n"
"        float d = fp16_to_fp32(row[b].d);\n"
"        __global const uchar* qs = row[b].qs;\n"
"        __global const float* bx = x + b * 32;\n"
"        float4 acc = (float4)(0.0f);\n"
"        for (int j = 0; j < 16; j += 4) {\n"
"            uchar4 bytes = vload4(0, qs + j);\n"
"            int4 low  = convert_int4(bytes & (uchar4)0x0F) - (int4)8;\n"
"            int4 high = convert_int4(bytes >> (uchar4)4)   - (int4)8;\n"
"            float4 vx_low  = vload4(0, bx + j);\n"
"            float4 vx_high = vload4(0, bx + j + 16);\n"
"            acc += convert_float4(low)  * vx_low;\n"
"            acc += convert_float4(high) * vx_high;\n"
"        }\n"
"        sum += (acc.x + acc.y + acc.z + acc.w) * d;\n"
"    }\n"
"    y[r] = sum;\n"
"}\n"
"\n"
"typedef struct {\n"
"    ushort d;\n"
"    char qs[32];\n"
"} block_q8_0;\n"
"\n"
"__kernel void matvec_q8_0_kernel(\n"
"    __global const block_q8_0* W,\n"
"    __global const float* x,\n"
"    __global float* y,\n"
"    int K, int N)\n"
"{\n"
"    int r = get_global_id(0);\n"
"    if (r >= N) return;\n"
"    int num_blocks = K / 32;\n"
"    __global const block_q8_0* row = W + (size_t)r * num_blocks;\n"
"    float sum = 0.0f;\n"
"    for (int b = 0; b < num_blocks; b++) {\n"
"        float d = fp16_to_fp32(row[b].d);\n"
"        __global const char* qs = row[b].qs;\n"
"        __global const float* bx = x + b * 32;\n"
"        float4 acc0 = (float4)(0.0f);\n"
"        float4 acc1 = (float4)(0.0f);\n"
"        for (int j = 0; j < 32; j += 8) {\n"
"            char4 q0 = vload4(0, qs + j);\n"
"            char4 q1 = vload4(0, qs + j + 4);\n"
"            float4 vx0 = vload4(0, bx + j);\n"
"            float4 vx1 = vload4(0, bx + j + 4);\n"
"            acc0 += convert_float4(q0) * vx0;\n"
"            acc1 += convert_float4(q1) * vx1;\n"
"        }\n"
"        float4 acc = acc0 + acc1;\n"
"        sum += (acc.x + acc.y + acc.z + acc.w) * d;\n"
"    }\n"
"    y[r] = sum;\n"
"}\n"
"\n"
"typedef struct {\n"
"    uchar ql[128];\n"
"    uchar qh[64];\n"
"    char  scales[16];\n"
"    ushort d;\n"
"} block_q6_k;\n"
"\n"
"__kernel void matvec_q6_k_kernel(\n"
"    __global const block_q6_k* W,\n"
"    __global const float* x,\n"
"    __global float* y,\n"
"    int K, int N)\n"
"{\n"
"    int r = get_global_id(0);\n"
"    if (r >= N) return;\n"
"    int num_blocks = K / 256;\n"
"    __global const block_q6_k* row = W + (size_t)r * num_blocks;\n"
"    float sum = 0.0f;\n"
"    for (int b = 0; b < num_blocks; b++) {\n"
"        float d = fp16_to_fp32(row[b].d);\n"
"        int x_idx = b * 256;\n"
"        float bsum = 0.0f;\n"
"        for (int h = 0; h < 2; h++) {\n"
"            int v_offset = x_idx + h * 128;\n"
"            int ql_offset = h * 64;\n"
"            int qh_offset = h * 32;\n"
"            int sc_offset = h * 8;\n"
"            for (int sub = 0; sub < 2; sub++) {\n"
"                float s0 = (float)row[b].scales[sc_offset + sub + 0];\n"
"                float s2 = (float)row[b].scales[sc_offset + sub + 2];\n"
"                float s4 = (float)row[b].scales[sc_offset + sub + 4];\n"
"                float s6 = (float)row[b].scales[sc_offset + sub + 6];\n"
"                int l_start = sub * 16;\n"
"                int l_end = l_start + 16;\n"
"                float4 acc0 = (float4)(0.0f);\n"
"                float4 acc1 = (float4)(0.0f);\n"
"                float4 acc2 = (float4)(0.0f);\n"
"                float4 acc3 = (float4)(0.0f);\n"
"                for (int l = l_start; l < l_end; l += 4) {\n"
"                    uchar4 ql0 = vload4(0, row[b].ql + ql_offset + l + 0);\n"
"                    uchar4 ql1 = vload4(0, row[b].ql + ql_offset + l + 32);\n"
"                    uchar4 qh0 = vload4(0, row[b].qh + qh_offset + l);\n"
"                    int4 q1 = convert_int4((ql0 & (uchar4)0xF) | (((qh0 >> (uchar4)0) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
"                    int4 q2 = convert_int4((ql1 & (uchar4)0xF) | (((qh0 >> (uchar4)2) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
"                    int4 q3 = convert_int4((ql0 >> (uchar4)4)  | (((qh0 >> (uchar4)4) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
"                    int4 q4 = convert_int4((ql1 >> (uchar4)4)  | (((qh0 >> (uchar4)6) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
"                    float4 x0 = vload4(0, x + v_offset + l +  0);\n"
"                    float4 x1 = vload4(0, x + v_offset + l + 32);\n"
"                    float4 x2 = vload4(0, x + v_offset + l + 64);\n"
"                    float4 x3 = vload4(0, x + v_offset + l + 96);\n"
"                    acc0 += convert_float4(q1) * x0;\n"
"                    acc1 += convert_float4(q2) * x1;\n"
"                    acc2 += convert_float4(q3) * x2;\n"
"                    acc3 += convert_float4(q4) * x3;\n"
"                }\n"
"                bsum += s0 * (acc0.x + acc0.y + acc0.z + acc0.w)\n"
"                      + s2 * (acc1.x + acc1.y + acc1.z + acc1.w)\n"
"                      + s4 * (acc2.x + acc2.y + acc2.z + acc2.w)\n"
"                      + s6 * (acc3.x + acc3.y + acc3.z + acc3.w);\n"
"            }\n"
"        }\n"
"        sum += bsum * d;\n"
"    }\n"
"    y[r] = sum;\n"
"}\n";

static int madar_gpu_init(RingModel *pModel) {
	cl_platform_id platform = NULL;
	cl_device_id device = NULL;
	cl_uint numPlatforms = 0, numDevices = 0;
	cl_context ctx = NULL;
	cl_command_queue queue = NULL;
	cl_program prog = NULL;
	cl_kernel kQ4 = NULL, kQ8 = NULL, kQ6 = NULL;
	cl_int ret = 0;
	char devName[128] = {0};

	pModel->bGPUEnabled = 0;

	const char *envGPU = getenv("MADAR_GPU");
	if (envGPU && strcmp(envGPU, "0") == 0) {
		printf("  [Madar GPU] Disabled via MADAR_GPU=0 (Running Pure CPU AVX2)\n");
		return 0;
	}

	if (!madar_opencl_load_dll()) return 0;

	ret = p_clGetPlatformIDs(1, &platform, &numPlatforms);
	if (ret != CL_SUCCESS || numPlatforms == 0) return 0;

	/* Try to get GPU device first */
	ret = p_clGetDeviceIDs(platform, CL_DEVICE_TYPE_GPU, 1, &device, &numDevices);
	if (ret != CL_SUCCESS || numDevices == 0) {
		/* Fallback to any OpenCL device */
		ret = p_clGetDeviceIDs(platform, CL_DEVICE_TYPE_ALL, 1, &device, &numDevices);
		if (ret != CL_SUCCESS || numDevices == 0) return 0;
	}

	p_clGetDeviceInfo(device, CL_DEVICE_NAME, sizeof(devName), devName, NULL);

	ctx = p_clCreateContext(NULL, 1, &device, NULL, NULL, &ret);
	if (ret != CL_SUCCESS || !ctx) return 0;

	queue = p_clCreateCommandQueue(ctx, device, 0, &ret);
	if (ret != CL_SUCCESS || !queue) {
		p_clReleaseContext(ctx);
		return 0;
	}

	prog = p_clCreateProgramWithSource(ctx, 1, &s_madar_cl_source, NULL, &ret);
	if (ret != CL_SUCCESS || !prog) {
		p_clReleaseCommandQueue(queue);
		p_clReleaseContext(ctx);
		return 0;
	}

	ret = p_clBuildProgram(prog, 1, &device, "-cl-fast-relaxed-math -cl-mad-enable", NULL, NULL);
	if (ret != CL_SUCCESS) {
		ret = p_clBuildProgram(prog, 1, &device, NULL, NULL, NULL);
	}

	if (ret != CL_SUCCESS) {
		char buildLog[2048] = {0};
		p_clGetProgramBuildInfo(prog, device, CL_PROGRAM_BUILD_LOG, sizeof(buildLog) - 1, buildLog, NULL);
		printf("[MADAR GPU] OpenCL Build Failed:\n%s\n", buildLog);
		p_clReleaseProgram(prog);
		p_clReleaseCommandQueue(queue);
		p_clReleaseContext(ctx);
		return 0;
	}

	kQ4 = p_clCreateKernel(prog, "matvec_q4_0_kernel", &ret);
	kQ8 = p_clCreateKernel(prog, "matvec_q8_0_kernel", &ret);
	kQ6 = p_clCreateKernel(prog, "matvec_q6_k_kernel", &ret);

	p_clReleaseProgram(prog);

	size_t maxK = (pModel->config.nFF > pModel->config.nEmbd) ? pModel->config.nFF : pModel->config.nEmbd;
	if (maxK < 16384) maxK = 16384;
	size_t maxN = pModel->config.nVocab;
	if (maxN < (size_t)pModel->config.nFF) maxN = pModel->config.nFF;

	cl_mem bufX = p_clCreateBuffer(ctx, CL_MEM_READ_WRITE, maxK * sizeof(float), NULL, &ret);
	cl_mem bufY = p_clCreateBuffer(ctx, CL_MEM_READ_WRITE, maxN * sizeof(float), NULL, &ret);

	if (!bufX || !bufY) {
		if (kQ4) p_clReleaseKernel(kQ4);
		if (kQ8) p_clReleaseKernel(kQ8);
		if (kQ6) p_clReleaseKernel(kQ6);
		if (bufX) p_clReleaseMemObject(bufX);
		if (bufY) p_clReleaseMemObject(bufY);
		p_clReleaseCommandQueue(queue);
		p_clReleaseContext(ctx);
		return 0;
	}

	pModel->pGPUContext = ctx;
	pModel->pGPUQueue = queue;
	pModel->pGPUKernelQ4 = kQ4;
	pModel->pGPUKernelQ8 = kQ8;
	pModel->pGPUKernelQ6 = kQ6;
	pModel->pGPUBufX = bufX;
	pModel->pGPUBufY = bufY;
	pModel->nGPUBufXSize = maxK;
	pModel->nGPUBufYSize = maxN;

	/* Pre-map the huge Output (LM Head) weight tensor to zero-copy GPU memory */
	if (pModel->pOutput) {
		const void *pOutData = ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pOutput);
		if (pOutData && pModel->pOutput->nSize > 0) {
			cl_mem bufOut = p_clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
											(size_t)pModel->pOutput->nSize, (void *)pOutData, &ret);
			if (ret == CL_SUCCESS && bufOut) {
				pModel->pGPUBufOutputWeight = bufOut;
			}
		}
	}

	/* Pre-map FFN weights (Gate, Up, Down) for all layers to zero-copy GPU memory */
	if (pModel->aLayers) {
		for (uint32_t l = 0; l < pModel->config.nLayers; l++) {
			RingLayerWeights *layer = &pModel->aLayers[l];
			if (layer->pFFNGate && layer->pFFNGate->nSize > 0) {
				const void *pData = ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNGate);
				if (pData) {
					layer->pGPUBufGate = (void *)p_clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
																  (size_t)layer->pFFNGate->nSize, (void *)pData, &ret);
				}
			}
			if (layer->pFFNUp && layer->pFFNUp->nSize > 0) {
				const void *pData = ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNUp);
				if (pData) {
					layer->pGPUBufUp = (void *)p_clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
																(size_t)layer->pFFNUp->nSize, (void *)pData, &ret);
				}
			}
			if (layer->pFFNDown && layer->pFFNDown->nSize > 0) {
				const void *pData = ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNDown);
				if (pData) {
					layer->pGPUBufDown = (void *)p_clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
																  (size_t)layer->pFFNDown->nSize, (void *)pData, &ret);
				}
			}
		}
	}

	pModel->bGPUEnabled = 1;
	printf("  [Madar GPU] Acceleration Active: %s (Zero-Copy LM Head + %u FFN Layers)\n",
		   devName, pModel->config.nLayers);
	return 1;
}

static int madar_gpu_matvec(RingModel *pModel, RingGGUFTensorInfo *pInfo, cl_mem bufW,
							const float *x, float *y, RingGGUFTensorInfo *pBiasInfo) {
	if (!pModel || !pModel->bGPUEnabled || !pInfo || !x || !y) return 0;

	cl_command_queue queue = (cl_command_queue)pModel->pGPUQueue;
	cl_kernel kernel = NULL;

	if (pInfo->nType == RING_GGUF_TENSOR_Q4_0) {
		kernel = (cl_kernel)pModel->pGPUKernelQ4;
	} else if (pInfo->nType == RING_GGUF_TENSOR_Q8_0) {
		kernel = (cl_kernel)pModel->pGPUKernelQ8;
	} else if (pInfo->nType == RING_GGUF_TENSOR_Q6_K) {
		kernel = (cl_kernel)pModel->pGPUKernelQ6;
	} else {
		return 0;
	}

	if (!kernel) return 0;

	int K = (int)pInfo->aDims[0];
	int N = (int)pInfo->aDims[1];

	if ((size_t)K > pModel->nGPUBufXSize || (size_t)N > pModel->nGPUBufYSize) return 0;

	if (!bufW) {
		if (pInfo == pModel->pOutput && pModel->pGPUBufOutputWeight) {
			bufW = (cl_mem)pModel->pGPUBufOutputWeight;
		}
	}
	if (!bufW) return 0;

	cl_mem bufX = (cl_mem)pModel->pGPUBufX;
	cl_mem bufY = (cl_mem)pModel->pGPUBufY;

	/* 1. Write X vector to GPU */
	cl_int ret = p_clEnqueueWriteBuffer(queue, bufX, CL_FALSE, 0, K * sizeof(float), x, 0, NULL, NULL);
	if (ret != CL_SUCCESS) return 0;

	/* 2. Set Kernel Arguments */
	p_clSetKernelArg(kernel, 0, sizeof(cl_mem), &bufW);
	p_clSetKernelArg(kernel, 1, sizeof(cl_mem), &bufX);
	p_clSetKernelArg(kernel, 2, sizeof(cl_mem), &bufY);
	p_clSetKernelArg(kernel, 3, sizeof(int), &K);
	p_clSetKernelArg(kernel, 4, sizeof(int), &N);

	/* 3. Launch 1D Grid across N output elements with balanced workgroup size */
	size_t localSize = 64;
	size_t globalSize = ((size_t)N + localSize - 1) / localSize * localSize;
	ret = p_clEnqueueNDRangeKernel(queue, kernel, 1, NULL, &globalSize, &localSize, 0, NULL, NULL);
	if (ret != CL_SUCCESS) return 0;

	/* 4. Read result back into y */
	ret = p_clEnqueueReadBuffer(queue, bufY, CL_TRUE, 0, N * sizeof(float), y, 0, NULL, NULL);
	if (ret != CL_SUCCESS) return 0;

	/* 5. Add bias if present */
	if (pBiasInfo) {
		const void *pBias = ring_gguf_get_tensor_data(pModel->pGGUF, pBiasInfo);
		if (pBias) {
			if (pBiasInfo->nType == RING_GGUF_TENSOR_F16) {
				const ggml_fp16_t *f16 = (const ggml_fp16_t *)pBias;
				for (int r = 0; r < N; r++) y[r] += fast_fp16_to_fp32(f16[r]);
			} else {
				const float *f32 = (const float *)pBias;
				for (int r = 0; r < N; r++) y[r] += f32[r];
			}
		}
	}

	return 1;
}

static void madar_gpu_cleanup(RingModel *pModel) {
	if (!pModel || !pModel->bGPUEnabled) return;

	if (pModel->aLayers) {
		for (uint32_t l = 0; l < pModel->config.nLayers; l++) {
			RingLayerWeights *layer = &pModel->aLayers[l];
			if (layer->pGPUBufGate) {
				p_clReleaseMemObject((cl_mem)layer->pGPUBufGate);
				layer->pGPUBufGate = NULL;
			}
			if (layer->pGPUBufUp) {
				p_clReleaseMemObject((cl_mem)layer->pGPUBufUp);
				layer->pGPUBufUp = NULL;
			}
			if (layer->pGPUBufDown) {
				p_clReleaseMemObject((cl_mem)layer->pGPUBufDown);
				layer->pGPUBufDown = NULL;
			}
		}
	}

	if (pModel->pGPUBufOutputWeight) {
		p_clReleaseMemObject((cl_mem)pModel->pGPUBufOutputWeight);
		pModel->pGPUBufOutputWeight = NULL;
	}
	if (pModel->pGPUBufX) {
		p_clReleaseMemObject((cl_mem)pModel->pGPUBufX);
		pModel->pGPUBufX = NULL;
	}
	if (pModel->pGPUBufY) {
		p_clReleaseMemObject((cl_mem)pModel->pGPUBufY);
		pModel->pGPUBufY = NULL;
	}
	if (pModel->pGPUKernelQ4) {
		p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ4);
		pModel->pGPUKernelQ4 = NULL;
	}
	if (pModel->pGPUKernelQ8) {
		p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ8);
		pModel->pGPUKernelQ8 = NULL;
	}
	if (pModel->pGPUKernelQ6) {
		p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ6);
		pModel->pGPUKernelQ6 = NULL;
	}
	if (pModel->pGPUQueue) {
		p_clReleaseCommandQueue((cl_command_queue)pModel->pGPUQueue);
		pModel->pGPUQueue = NULL;
	}
	if (pModel->pGPUContext) {
		p_clReleaseContext((cl_context)pModel->pGPUContext);
		pModel->pGPUContext = NULL;
	}
	pModel->bGPUEnabled = 0;
}

static void matvec_multiply_gpu(RingModel *pModel, RingGGUFTensorInfo *pInfo, void *pGPUBuf,
								const float *x, float *y, RingGGUFTensorInfo *pBiasInfo) {
	int K, N;
	const float *pBias;
	MatVecTask task;
#ifdef _WIN32
	int nTotalThreads, nWorkers, nChunk, i;
#endif

	if (!pModel || !pInfo || !x || !y) return;

	K = (int)pInfo->aDims[0];
	N = (int)pInfo->aDims[1];

	/* GPU Offload: Check if pre-mapped GPU buffer is available */
	if (pModel->bGPUEnabled) {
		cl_mem bufW = (cl_mem)pGPUBuf;
		if (!bufW && pInfo == pModel->pOutput) {
			bufW = (cl_mem)pModel->pGPUBufOutputWeight;
		}
		if (bufW) {
			if (madar_gpu_matvec(pModel, pInfo, bufW, x, y, pBiasInfo)) {
				return;
			}
		}
	}
	pBias = NULL;

	if (pBiasInfo) {
		pBias = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, pBiasInfo);
	}

#ifdef _WIN32
	/* Adaptive multi-threading:
	   Only distribute across Win32 worker threads if N >= 512 and total ops >= 1,500,000.
	   For smaller matrices (e.g. Attn K/V projections), executing directly on the calling core
	   with AVX2 FMA is faster than the round-trip latency of Win32 context switches. */
	if (pModel->nThreads >= 2 && N >= 512 && ((int64_t)N * K >= 1500000) && pModel->nWorkerCount > 0) {
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

static void matvec_multiply(RingModel *pModel, RingGGUFTensorInfo *pInfo, const float *x, float *y,
							RingGGUFTensorInfo *pBiasInfo) {
	matvec_multiply_gpu(pModel, pInfo, NULL, x, y, pBiasInfo);
}

/*
================================================================================
  Neural Operations: RMSNorm, LayerNorm, RoPE, Softmax, SiLU, GELU
================================================================================
*/

static void layernorm(float *o, const float *x, const float *weight, const float *bias, int size, float eps) {
	float sum = 0.0f;
	float ss = 0.0f;
	float mean, var, inv;
	int i = 0;

#if defined(MADAR_AVX2)
	__m256 accSum0 = _mm256_setzero_ps();
	__m256 accSum1 = _mm256_setzero_ps();
	for (; i + 15 < size; i += 16) {
		accSum0 = _mm256_add_ps(accSum0, _mm256_loadu_ps(x + i));
		accSum1 = _mm256_add_ps(accSum1, _mm256_loadu_ps(x + i + 8));
	}
	for (; i + 7 < size; i += 8) {
		accSum0 = _mm256_add_ps(accSum0, _mm256_loadu_ps(x + i));
	}
	sum = hsum_float_8(_mm256_add_ps(accSum0, accSum1));
#endif
	for (; i < size; i++) sum += x[i];
	mean = sum / (float)size;

	i = 0;
#if defined(MADAR_AVX2)
	__m256 vMean = _mm256_set1_ps(mean);
	__m256 accVar0 = _mm256_setzero_ps();
	__m256 accVar1 = _mm256_setzero_ps();
	for (; i + 15 < size; i += 16) {
		__m256 d0 = _mm256_sub_ps(_mm256_loadu_ps(x + i), vMean);
		__m256 d1 = _mm256_sub_ps(_mm256_loadu_ps(x + i + 8), vMean);
		accVar0 = _mm256_fmadd_ps(d0, d0, accVar0);
		accVar1 = _mm256_fmadd_ps(d1, d1, accVar1);
	}
	for (; i + 7 < size; i += 8) {
		__m256 d = _mm256_sub_ps(_mm256_loadu_ps(x + i), vMean);
		accVar0 = _mm256_fmadd_ps(d, d, accVar0);
	}
	ss = hsum_float_8(_mm256_add_ps(accVar0, accVar1));
#endif
	for (; i < size; i++) {
		float d = x[i] - mean;
		ss += d * d;
	}
	var = ss / (float)size;
	inv = 1.0f / sqrtf(var + eps);

	i = 0;
#if defined(MADAR_AVX2)
	__m256 vinv = _mm256_set1_ps(inv);
	for (; i + 7 < size; i += 8) {
		__m256 vx = _mm256_sub_ps(_mm256_loadu_ps(x + i), vMean);
		__m256 val = _mm256_mul_ps(vx, vinv);
		if (weight) val = _mm256_mul_ps(val, _mm256_loadu_ps(weight + i));
		if (bias)   val = _mm256_add_ps(val, _mm256_loadu_ps(bias + i));
		_mm256_storeu_ps(o + i, val);
	}
#endif
	for (; i < size; i++) {
		float val = (x[i] - mean) * inv;
		if (weight) val *= weight[i];
		if (bias)   val += bias[i];
		o[i] = val;
	}
}

static inline float fast_gelu(float x) {
	float x3 = x * x * x;
	return 0.5f * x * (1.0f + tanhf(0.79788456f * (x + 0.044715f * x3)));
}

static void rmsnorm(float *o, const float *x, const float *weight, int size, float eps) {
	float ss = 0.0f;
	float inv;
	int i = 0;

#if defined(MADAR_AVX2)
	__m256 acc0 = _mm256_setzero_ps();
	__m256 acc1 = _mm256_setzero_ps();
	for (; i + 15 < size; i += 16) {
		__m256 v0 = _mm256_loadu_ps(x + i);
		__m256 v1 = _mm256_loadu_ps(x + i + 8);
		acc0 = _mm256_fmadd_ps(v0, v0, acc0);
		acc1 = _mm256_fmadd_ps(v1, v1, acc1);
	}
	for (; i + 7 < size; i += 8) {
		__m256 v = _mm256_loadu_ps(x + i);
		acc0 = _mm256_fmadd_ps(v, v, acc0);
	}
	ss = hsum_float_8(_mm256_add_ps(acc0, acc1));
#endif
	for (; i < size; i++) ss += x[i] * x[i];
	ss /= (float)size;
	ss += eps;
	inv = 1.0f / sqrtf(ss);

	i = 0;
#if defined(MADAR_AVX2)
	__m256 vinv = _mm256_set1_ps(inv);
	if (weight) {
		for (; i + 7 < size; i += 8) {
			__m256 vx = _mm256_loadu_ps(x + i);
			__m256 vw = _mm256_loadu_ps(weight + i);
			_mm256_storeu_ps(o + i, _mm256_mul_ps(_mm256_mul_ps(vx, vinv), vw));
		}
	} else {
		for (; i + 7 < size; i += 8) {
			__m256 vx = _mm256_loadu_ps(x + i);
			_mm256_storeu_ps(o + i, _mm256_mul_ps(vx, vinv));
		}
	}
#endif
	if (weight) {
		for (; i < size; i++) o[i] = x[i] * inv * weight[i];
	} else {
		for (; i < size; i++) o[i] = x[i] * inv;
	}
}

static void apply_rope(float *vec, int nHeads, int headDim, int pos, float freqBase) {
	int h, i;
	float *head;
	float freq, val, v0, v1;
	int half = headDim / 2;
	float aCos[128], aSin[128];

	if (half > 128) half = 128;

	/* Precompute trigonometric values once per layer instead of redundantly for each head */
	for (i = 0; i < half; i++) {
		freq = 1.0f / powf(freqBase, (float)(2 * i) / (float)headDim);
		val = (float)pos * freq;
		aCos[i] = cosf(val);
		aSin[i] = sinf(val);
	}

	for (h = 0; h < nHeads; h++) {
		head = vec + h * headDim;
		for (i = 0; i < half; i++) {
			v0 = head[i];
			v1 = head[i + half];
			head[i]        = v0 * aCos[i] - v1 * aSin[i];
			head[i + half] = v0 * aSin[i] + v1 * aCos[i];
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
	pModel->config.bIsBert = (strcmp(arch, "bert") == 0 ||
	                          strcmp(arch, "xlm-roberta") == 0 ||
	                          strcmp(arch, "roberta") == 0);

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
	if (!kv) {
		snprintf(key, sizeof(key), "%s.attention.layer_norm_epsilon", arch);
		kv = ring_gguf_find_kv(pGGUF, key);
	}
	pModel->config.fNormEps = gguf_get_f32_val(kv, 1e-5f);

	/* Pooling Type (for BERT) */
	snprintf(key, sizeof(key), "%s.pooling_type", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.nPoolingType = gguf_get_u32_val(kv, 2); /* Default: 2 (CLS) */

	snprintf(key, sizeof(key), "%s.rope.freq_base", arch);
	kv = ring_gguf_find_kv(pGGUF, key);
	pModel->config.fRopeFreqBase = gguf_get_f32_val(kv, 1000000.0f);

	/* Locate Tensors */
	pModel->pTokenEmbd = ring_gguf_find_tensor(pGGUF, "token_embd.weight");
	if (!pModel->pTokenEmbd) pModel->pTokenEmbd = ring_gguf_find_tensor(pGGUF, "model.embed_tokens.weight");

	if (pModel->config.bIsBert) {
		pModel->pPosEmbd = ring_gguf_find_tensor(pGGUF, "position_embd.weight");
		pModel->pTokenTypes = ring_gguf_find_tensor(pGGUF, "token_types.weight");
		pModel->pTokenEmbdNorm = ring_gguf_find_tensor(pGGUF, "token_embd_norm.weight");
		pModel->pTokenEmbdNorm_Bias = ring_gguf_find_tensor(pGGUF, "token_embd_norm.bias");
	}

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
	if (!pModel->pOutputNorm && !pModel->config.bIsBert) {
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
			snprintf(key, sizeof(key), "blk.%u.attn_output_norm.weight", l);
			pModel->aLayers[l].pAttnNorm = ring_gguf_find_tensor(pGGUF, key);
		}
		if (!pModel->aLayers[l].pAttnNorm) {
			snprintf(key, sizeof(key), "model.layers.%u.input_layernorm.weight", l);
			pModel->aLayers[l].pAttnNorm = ring_gguf_find_tensor(pGGUF, key);
		}
		snprintf(key, sizeof(key), "blk.%u.attn_norm.bias", l);
		pModel->aLayers[l].pAttnNorm_Bias = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pAttnNorm_Bias) {
			snprintf(key, sizeof(key), "blk.%u.attn_output_norm.bias", l);
			pModel->aLayers[l].pAttnNorm_Bias = ring_gguf_find_tensor(pGGUF, key);
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
		snprintf(key, sizeof(key), "blk.%u.attn_output.bias", l);
		pModel->aLayers[l].pAttnOut_Bias = ring_gguf_find_tensor(pGGUF, key);

		snprintf(key, sizeof(key), "blk.%u.ffn_norm.weight", l);
		pModel->aLayers[l].pFFNNorm = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pFFNNorm) {
			snprintf(key, sizeof(key), "blk.%u.layer_output_norm.weight", l);
			pModel->aLayers[l].pFFNNorm = ring_gguf_find_tensor(pGGUF, key);
		}
		if (!pModel->aLayers[l].pFFNNorm) {
			snprintf(key, sizeof(key), "model.layers.%u.post_attention_layernorm.weight", l);
			pModel->aLayers[l].pFFNNorm = ring_gguf_find_tensor(pGGUF, key);
		}
		snprintf(key, sizeof(key), "blk.%u.ffn_norm.bias", l);
		pModel->aLayers[l].pFFNNorm_Bias = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pFFNNorm_Bias) {
			snprintf(key, sizeof(key), "blk.%u.layer_output_norm.bias", l);
			pModel->aLayers[l].pFFNNorm_Bias = ring_gguf_find_tensor(pGGUF, key);
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
		snprintf(key, sizeof(key), "blk.%u.ffn_up.bias", l);
		pModel->aLayers[l].pFFNUp_Bias = ring_gguf_find_tensor(pGGUF, key);

		snprintf(key, sizeof(key), "blk.%u.ffn_down.weight", l);
		pModel->aLayers[l].pFFNDown = ring_gguf_find_tensor(pGGUF, key);
		if (!pModel->aLayers[l].pFFNDown) {
			snprintf(key, sizeof(key), "model.layers.%u.mlp.down_proj.weight", l);
			pModel->aLayers[l].pFFNDown = ring_gguf_find_tensor(pGGUF, key);
		}
		snprintf(key, sizeof(key), "blk.%u.ffn_down.bias", l);
		pModel->aLayers[l].pFFNDown_Bias = ring_gguf_find_tensor(pGGUF, key);
	}

	if (pModel->config.nLayers > 0 && !pModel->aLayers[0].pAttnQ) {
		printf("\n[MADAR AI] Error: Layer 0 attention Q weights not found in GGUF!\n");
		ring_model_free(pModel);
		return NULL;
	}

	/* Allocate KV Cache (FP16 Compressed - 50% Memory Savings) */
	pModel->nMaxSeq = 2048;
	pModel->nKVDim = pModel->config.nHeadsKV * pModel->config.nHeadDim;
	kvSize = (size_t)pModel->config.nLayers * pModel->nMaxSeq * pModel->nKVDim;

	pModel->pKVCache_K = (ggml_fp16_t *)calloc(kvSize, sizeof(ggml_fp16_t));
	pModel->pKVCache_V = (ggml_fp16_t *)calloc(kvSize, sizeof(ggml_fp16_t));
	pModel->pAttScores = (float *)calloc(pModel->nMaxSeq, sizeof(float));

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
					if (pModel->hWorkerThreads[i]) {
						SetThreadPriority((HANDLE)pModel->hWorkerThreads[i], THREAD_PRIORITY_HIGHEST);
					}
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

	/* Initialize GPU Acceleration (OpenCL Engine) */
	madar_gpu_init(pModel);

	return pModel;
}

RING_API void ring_model_free(RingModel *pModel) {
	if (!pModel) return;

	madar_gpu_cleanup(pModel);

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
	if (pModel->pAttScores) free(pModel->pAttScores);

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

RING_API void ring_model_set_gpu(RingModel *pModel, int bEnable) {
	if (!pModel) return;
	pModel->bGPUEnabled = bEnable ? 1 : 0;
}

RING_API void ring_model_reset_kv(RingModel *pModel) {
	size_t kvSize;
	if (!pModel || !pModel->pKVCache_K || !pModel->pKVCache_V) return;
	kvSize = (size_t)pModel->config.nLayers * pModel->nMaxSeq * pModel->nKVDim;
	memset(pModel->pKVCache_K, 0, kvSize * sizeof(ggml_fp16_t));
	memset(pModel->pKVCache_V, 0, kvSize * sizeof(ggml_fp16_t));
	if (pModel->pTokenizer) pModel->pTokenizer->nUtf8BufLen = 0;
}

/*
================================================================================
  Transformer Forward Pass (One Token at Position `pos`)
================================================================================
*/

static inline float dot_fp32_fp16(const float *q, const ggml_fp16_t *k, int dim) {
#if defined(MADAR_AVX2)
	__m256 acc0 = _mm256_setzero_ps();
	__m256 acc1 = _mm256_setzero_ps();
	int d = 0;
	for (; d + 15 < dim; d += 16) {
		__m128i h0 = _mm_loadu_si128((const __m128i *)(k + d));
		__m128i h1 = _mm_loadu_si128((const __m128i *)(k + d + 8));
		acc0 = _mm256_fmadd_ps(_mm256_loadu_ps(q + d), _mm256_cvtph_ps(h0), acc0);
		acc1 = _mm256_fmadd_ps(_mm256_loadu_ps(q + d + 8), _mm256_cvtph_ps(h1), acc1);
	}
	for (; d + 7 < dim; d += 8) {
		__m128i h = _mm_loadu_si128((const __m128i *)(k + d));
		acc0 = _mm256_fmadd_ps(_mm256_loadu_ps(q + d), _mm256_cvtph_ps(h), acc0);
	}
	float s = hsum_float_8(_mm256_add_ps(acc0, acc1));
	for (; d < dim; d++) s += ggml_hw_fp16_to_fp32(k[d]) * q[d];
	return s;
#else
	float s = 0.0f;
	int d;
	for (d = 0; d < dim; d++) s += q[d] * fast_fp16_to_fp32(k[d]);
	return s;
#endif
}

static inline void add_scaled_fp16(float *out, float a, const ggml_fp16_t *v, int dim) {
#if defined(MADAR_AVX2)
	__m256 va = _mm256_set1_ps(a);
	int d = 0;
	for (; d + 7 < dim; d += 8) {
		__m128i h = _mm_loadu_si128((const __m128i *)(v + d));
		__m256 vf = _mm256_cvtph_ps(h);
		__m256 vo = _mm256_loadu_ps(out + d);
		_mm256_storeu_ps(out + d, _mm256_fmadd_ps(va, vf, vo));
	}
	for (; d < dim; d++) out[d] += a * ggml_hw_fp16_to_fp32(v[d]);
#else
	int d;
	for (d = 0; d < dim; d++) out[d] += a * fast_fp16_to_fp32(v[d]);
#endif
}

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
	float *qHead, *outHead;
	const ggml_fp16_t *kHead, *vHead;
	float *attScores = pModel->pAttScores;
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
	} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q6_K) {
		const RingGGUFBlockQ6_K *b6 = (const RingGGUFBlockQ6_K *)(pRawEmbd + (size_t)nToken * (nEmbd / 256) * sizeof(RingGGUFBlockQ6_K));
		ring_gguf_dequantize_q6_k(b6, pModel->pActX, nEmbd);
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

		/* Store K, V in FP16 Compressed KV Cache */
		seqIdx = nPos % pModel->nMaxSeq;
		kvOffset = ((size_t)l * pModel->nMaxSeq + seqIdx) * nKVDim;
		for (i = 0; i < nKVDim; i++) {
			pModel->pKVCache_K[kvOffset + i] = ggml_fp32_to_fp16(pModel->pActK[i]);
			pModel->pKVCache_V[kvOffset + i] = ggml_fp32_to_fp16(pModel->pActV[i]);
		}

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
				score = dot_fp32_fp16(qHead, kHead, nHeadDim);
				attScores[t] = score * scale;
			}

			softmax(attScores, validTokens);

			memset(outHead, 0, nHeadDim * sizeof(float));
			for (t = 0; t < validTokens; t++) {
				tOffset = ((size_t)l * pModel->nMaxSeq + t) * nKVDim + (size_t)kvH * nHeadDim;
				vHead = pModel->pKVCache_V + tOffset;
				add_scaled_fp16(outHead, attScores[t], vHead, nHeadDim);
			}
		}

		/* Attention Output Projection */
		matvec_multiply(pModel, layer->pAttnOut, pModel->pActAttOut, attnOut, NULL);

		/* Residual Addition: x = x + attnOut */
		i = 0;
#if defined(MADAR_AVX2)
		for (; i + 7 < nEmbd; i += 8) {
			_mm256_storeu_ps(pModel->pActX + i, _mm256_add_ps(_mm256_loadu_ps(pModel->pActX + i), _mm256_loadu_ps(attnOut + i)));
		}
#endif
		for (; i < nEmbd; i++) {
			pModel->pActX[i] += attnOut[i];
		}

		/* RMSNorm before FFN */
		ffnNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNNorm);
		rmsnorm(pModel->pActXB, pModel->pActX, ffnNormW, nEmbd, eps);

		/* SwiGLU FFN: gate = W_gate * xb, up = W_up * xb */
		matvec_multiply_gpu(pModel, layer->pFFNGate, layer->pGPUBufGate, pModel->pActXB, pModel->pActHB, NULL);
		matvec_multiply_gpu(pModel, layer->pFFNUp,   layer->pGPUBufUp,   pModel->pActXB, pModel->pActHB2, NULL);

		/* SiLU Activation: hb = (gate * sigmoid(gate)) * up */
		for (i = 0; i < nFF; i++) {
			g = pModel->pActHB[i];
			silu_g = g / (1.0f + expf(-g));
			pModel->pActHB[i] = silu_g * pModel->pActHB2[i];
		}

		/* Down Projection: ffnOut = W_down * hb */
		matvec_multiply_gpu(pModel, layer->pFFNDown, layer->pGPUBufDown, pModel->pActHB, ffnOut, NULL);

		/* Residual Addition: x = x + ffnOut */
		i = 0;
#if defined(MADAR_AVX2)
		for (; i + 7 < nEmbd; i += 8) {
			_mm256_storeu_ps(pModel->pActX + i, _mm256_add_ps(_mm256_loadu_ps(pModel->pActX + i), _mm256_loadu_ps(ffnOut + i)));
		}
#endif
		for (; i < nEmbd; i++) {
			pModel->pActX[i] += ffnOut[i];
		}
	}

	/* 3. Final Output RMSNorm & Logits (Only when requested) */
	if (bComputeLogits) {
		outNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pOutputNorm);
		rmsnorm(pModel->pActXB, pModel->pActX, outNormW, nEmbd, eps);

		/* 4. Output Projection to Logits */
		matvec_multiply_gpu(pModel, pModel->pOutput, pModel->pGPUBufOutputWeight, pModel->pActXB, pModel->pLogits, NULL);
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
  Text Generation & Streaming Generator
================================================================================
*/

RING_API int ring_model_prefill(RingModel *pModel, const char *cPrompt, int nMaxTokens, float fTemp) {
	int promptTokens[2048];
	int i;

	if (!pModel || !cPrompt) return 0;
	if (nMaxTokens <= 0) nMaxTokens = 64;
	if (nMaxTokens > 2048) nMaxTokens = 2048;

	pModel->nPromptTokens = ring_tokenizer_encode(pModel->pTokenizer, cPrompt, promptTokens, 2048);
	if (pModel->nPromptTokens <= 0) {
		pModel->bGenFinished = 1;
		return 0;
	}

	ring_model_reset_kv(pModel);

	/* Evaluate Prompt - ONLY compute logits on the LAST prompt token to skip huge matrix multiply on prefill! */
	for (i = 0; i < pModel->nPromptTokens; i++) {
		int bComputeLogits = (i == pModel->nPromptTokens - 1) ? 1 : 0;
		ring_model_forward_ex(pModel, promptTokens[i], i, bComputeLogits);
	}

	pModel->nCurPos = pModel->nPromptTokens;
	pModel->nGenCount = 0;
	pModel->nMaxGenTokens = nMaxTokens;
	pModel->fCurrentTemp = fTemp;
	pModel->bGenFinished = 0;

	return pModel->nPromptTokens;
}

RING_API int ring_model_has_more(RingModel *pModel) {
	if (!pModel) return 0;
	return (!pModel->bGenFinished && pModel->nGenCount < pModel->nMaxGenTokens);
}

RING_API char *ring_model_step(RingModel *pModel) {
	int i, nextToken;
	int penaltyStart;
	char *tokenStr;

	if (!pModel || pModel->bGenFinished || pModel->nGenCount >= pModel->nMaxGenTokens) {
		if (pModel && pModel->pTokenizer && pModel->pTokenizer->nUtf8BufLen > 0) {
			char flushBuf[16];
			int flushW = 0;
			ring_tokenizer_flush(pModel->pTokenizer, flushBuf, &flushW, sizeof(flushBuf));
			if (flushW > 0) {
				flushBuf[flushW] = '\0';
				return _strdup(flushBuf);
			}
		}
		return _strdup("");
	}

	/* Repetition penalty (1.25x) over the last 64 generated tokens */
	penaltyStart = (pModel->nGenCount > 64) ? (pModel->nGenCount - 64) : 0;
	for (i = penaltyStart; i < pModel->nGenCount; i++) {
		int prevTok = pModel->aGenTokens[i];
		int alreadyPenalized = 0;
		int k;
		for (k = penaltyStart; k < i; k++) {
			if (pModel->aGenTokens[k] == prevTok) {
				alreadyPenalized = 1;
				break;
			}
		}
		if (!alreadyPenalized && prevTok >= 0 && (uint32_t)prevTok < pModel->config.nVocab) {
			float fPenalty = 1.25f;
			/* Extra consecutive penalty if token equals immediately preceding token to prevent loops */
			if (pModel->nGenCount > 0 && prevTok == pModel->aGenTokens[pModel->nGenCount - 1]) {
				fPenalty = 1.55f;
			}
			if (pModel->pLogits[prevTok] > 0.0f) {
				pModel->pLogits[prevTok] /= fPenalty;
			} else {
				pModel->pLogits[prevTok] *= fPenalty;
			}
		}
	}

	/* Suppress immediate EOS on the very first generated token */
	if (pModel->nGenCount == 0) {
		if (pModel->pTokenizer->nEosToken >= 0 && (uint32_t)pModel->pTokenizer->nEosToken < pModel->config.nVocab) {
			pModel->pLogits[pModel->pTokenizer->nEosToken] = -1e9f;
		}
		if (pModel->config.nVocab > 151645) {
			pModel->pLogits[151643] = -1e9f; /* <|endoftext|> */
			pModel->pLogits[151645] = -1e9f; /* <|im_end|> */
		}
	}

	nextToken = ring_model_sample(pModel, pModel->fCurrentTemp);

	/* Check Qwen & Standard Stop Tokens */
	if (pModel->nGenCount > 0 && (nextToken == pModel->pTokenizer->nEosToken ||
		nextToken == 151643 || /* <|endoftext|> */
		nextToken == 151645)) { /* <|im_end|> */
		pModel->bGenFinished = 1;
		if (pModel->pTokenizer && pModel->pTokenizer->nUtf8BufLen > 0) {
			char flushBuf[16];
			int flushW = 0;
			ring_tokenizer_flush(pModel->pTokenizer, flushBuf, &flushW, sizeof(flushBuf));
			if (flushW > 0) {
				flushBuf[flushW] = '\0';
				return _strdup(flushBuf);
			}
		}
		return _strdup("");
	}

	pModel->aGenTokens[pModel->nGenCount++] = nextToken;

	tokenStr = ring_tokenizer_decode_tokens(pModel->pTokenizer, &nextToken, 1);

	ring_model_forward_ex(pModel, nextToken, pModel->nCurPos++, 1);

	if (!tokenStr) return _strdup("");
	return tokenStr;
}

RING_API char *ring_model_generate_stream(RingModel *pModel, const char *cPrompt, int nMaxTokens, float fTemp, int bStreamStdout) {
	if (!ring_model_prefill(pModel, cPrompt, nMaxTokens, fTemp)) return _strdup("");

	while (ring_model_has_more(pModel)) {
		char *tokenStr = ring_model_step(pModel);
		if (tokenStr) {
			if (bStreamStdout && tokenStr[0] != '\0') {
				fputs(tokenStr, stdout);
				fflush(stdout);
			}
			free(tokenStr);
		}
	}

	/* Flush any remaining UTF-8 bytes to stdout if streaming */
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

	return ring_tokenizer_decode_tokens(pModel->pTokenizer, pModel->aGenTokens, pModel->nGenCount);
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

static RingTensor *ring_model_embedding_bert(void *pRingState, RingModel *pModel, const int *aTokens, int nTokens) {
	int nEmbd = (int)pModel->config.nEmbd;
	int nLayers = (int)pModel->config.nLayers;
	int nHeads = (int)pModel->config.nHeads;
	int nHeadDim = (int)pModel->config.nHeadDim;
	int nFF = (int)pModel->config.nFF;
	float eps = pModel->config.fNormEps;
	float scale = 1.0f / sqrtf((float)nHeadDim);
	int S = nTokens;
	int t, l, h, i, j, d;

	if (S <= 0 || nEmbd <= 0) return NULL;
	if (S > 2048) S = 2048; /* Context cap */

	float *pSeqX = (float *)calloc((size_t)S * nEmbd, sizeof(float));
	float *pSeqQ = (float *)calloc((size_t)S * nEmbd, sizeof(float));
	float *pSeqK = (float *)calloc((size_t)S * nEmbd, sizeof(float));
	float *pSeqV = (float *)calloc((size_t)S * nEmbd, sizeof(float));
	float *pSeqAttOut = (float *)calloc((size_t)S * nEmbd, sizeof(float));
	float *pActHB = (float *)calloc(nFF, sizeof(float));
	float *pScores = (float *)calloc(S, sizeof(float));

	if (!pSeqX || !pSeqQ || !pSeqK || !pSeqV || !pSeqAttOut || !pActHB || !pScores) {
		if (pSeqX) free(pSeqX);
		if (pSeqQ) free(pSeqQ);
		if (pSeqK) free(pSeqK);
		if (pSeqV) free(pSeqV);
		if (pSeqAttOut) free(pSeqAttOut);
		if (pActHB) free(pActHB);
		if (pScores) free(pScores);
		return NULL;
	}

	const uint8_t *pRawEmbd = (const uint8_t *)ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pTokenEmbd);
	const void *pPosEmbdData = pModel->pPosEmbd ? ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pPosEmbd) : NULL;
	const void *pTypeData = pModel->pTokenTypes ? ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pTokenTypes) : NULL;
	const float *pEmbNormW = pModel->pTokenEmbdNorm ? (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pTokenEmbdNorm) : NULL;
	const float *pEmbNormB = pModel->pTokenEmbdNorm_Bias ? (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pTokenEmbdNorm_Bias) : NULL;

	/* 1. Embedding lookup + Positional + Types + LayerNorm */
	for (t = 0; t < S; t++) {
		int tok = aTokens[t];
		float *xt = pSeqX + (size_t)t * nEmbd;

		if (tok >= 0 && (uint32_t)tok < pModel->config.nVocab) {
			if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q6_K) {
				const RingGGUFBlockQ6_K *b6 = (const RingGGUFBlockQ6_K *)(pRawEmbd + (size_t)tok * (nEmbd / 256) * sizeof(RingGGUFBlockQ6_K));
				ring_gguf_dequantize_q6_k(b6, xt, nEmbd);
			} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0) {
				const RingGGUFBlockQ4_0 *b4 = (const RingGGUFBlockQ4_0 *)(pRawEmbd + (size_t)tok * (nEmbd / 32) * sizeof(RingGGUFBlockQ4_0));
				ring_gguf_dequantize_q4_0(b4, xt, nEmbd);
			} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0) {
				const RingGGUFBlockQ8_0 *b8 = (const RingGGUFBlockQ8_0 *)(pRawEmbd + (size_t)tok * (nEmbd / 32) * sizeof(RingGGUFBlockQ8_0));
				ring_gguf_dequantize_q8_0(b8, xt, nEmbd);
			} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16) {
				ring_gguf_dequantize_f16((const ggml_fp16_t *)pRawEmbd + (size_t)tok * nEmbd, xt, nEmbd);
			} else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F32) {
				memcpy(xt, (const float *)pRawEmbd + (size_t)tok * nEmbd, nEmbd * sizeof(float));
			}
		}

		/* Learned Absolute Position Embedding (RoBERTa padding offset = 2) */
		if (pPosEmbdData) {
			int posIdx = t + 2;
			if (posIdx >= (int)pModel->config.nCtx) posIdx = (int)pModel->config.nCtx - 1;
			const float *posVec = (const float *)pPosEmbdData + (size_t)posIdx * nEmbd;
			for (d = 0; d < nEmbd; d++) xt[d] += posVec[d];
		}

		/* Token Types */
		if (pTypeData) {
			const float *typeVec = (const float *)pTypeData;
			for (d = 0; d < nEmbd; d++) xt[d] += typeVec[d];
		}

		/* Embedding LayerNorm */
		layernorm(xt, xt, pEmbNormW, pEmbNormB, nEmbd, eps);
	}

	/* 2. Transformer Encoder Layers */
	for (l = 0; l < nLayers; l++) {
		RingLayerWeights *layer = &pModel->aLayers[l];
		const float *attnNormW = layer->pAttnNorm ? (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, layer->pAttnNorm) : NULL;
		const float *attnNormB = layer->pAttnNorm_Bias ? (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, layer->pAttnNorm_Bias) : NULL;
		const float *ffnNormW = layer->pFFNNorm ? (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNNorm) : NULL;
		const float *ffnNormB = layer->pFFNNorm_Bias ? (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNNorm_Bias) : NULL;

		/* A. Compute Q, K, V for all tokens */
		for (t = 0; t < S; t++) {
			matvec_multiply(pModel, layer->pAttnQ, pSeqX + (size_t)t * nEmbd, pSeqQ + (size_t)t * nEmbd, layer->pAttnQ_Bias);
			matvec_multiply(pModel, layer->pAttnK, pSeqX + (size_t)t * nEmbd, pSeqK + (size_t)t * nEmbd, layer->pAttnK_Bias);
			matvec_multiply(pModel, layer->pAttnV, pSeqX + (size_t)t * nEmbd, pSeqV + (size_t)t * nEmbd, layer->pAttnV_Bias);
		}

		/* B. Multi-Head Bidirectional Attention */
		for (h = 0; h < nHeads; h++) {
			for (i = 0; i < S; i++) {
				float *qHead = pSeqQ + (size_t)i * nEmbd + h * nHeadDim;
				for (j = 0; j < S; j++) {
					float *kHead = pSeqK + (size_t)j * nEmbd + h * nHeadDim;
					float s = dot_f32(qHead, kHead, nHeadDim);
					pScores[j] = s * scale;
				}
				softmax(pScores, S);

				float *outHead = pSeqAttOut + (size_t)i * nEmbd + h * nHeadDim;
				memset(outHead, 0, nHeadDim * sizeof(float));
				for (j = 0; j < S; j++) {
					float w = pScores[j];
					float *vHead = pSeqV + (size_t)j * nEmbd + h * nHeadDim;
					for (d = 0; d < nHeadDim; d++) {
						outHead[d] += w * vHead[d];
					}
				}
			}
		}

		/* C. Output Projection + Residual + LayerNorm */
		for (i = 0; i < S; i++) {
			float *xi = pSeqX + (size_t)i * nEmbd;
			float *attOut = pSeqAttOut + (size_t)i * nEmbd;
			matvec_multiply(pModel, layer->pAttnOut, attOut, pModel->pActAttnProj, layer->pAttnOut_Bias);
			for (d = 0; d < nEmbd; d++) {
				xi[d] += pModel->pActAttnProj[d];
			}
			layernorm(xi, xi, attnNormW, attnNormB, nEmbd, eps);
		}

		/* D. FFN (GELU) + Residual + LayerNorm */
		for (i = 0; i < S; i++) {
			float *xi = pSeqX + (size_t)i * nEmbd;
			matvec_multiply(pModel, layer->pFFNUp, xi, pActHB, layer->pFFNUp_Bias);
			for (d = 0; d < nFF; d++) {
				pActHB[d] = fast_gelu(pActHB[d]);
			}
			matvec_multiply(pModel, layer->pFFNDown, pActHB, pModel->pActFFNOut, layer->pFFNDown_Bias);
			for (d = 0; d < nEmbd; d++) {
				xi[d] += pModel->pActFFNOut[d];
			}
			layernorm(xi, xi, ffnNormW, ffnNormB, nEmbd, eps);
		}
	}

	/* 3. Pooling: CLS token (token 0) or Mean */
	size_t aShape[1];
	aShape[0] = (size_t)nEmbd;
	RingTensor *pTensor = ring_tensor_new(pRingState, RING_TENSOR_TYPE_FLOAT32, 1, aShape);
	if (!pTensor) {
		free(pSeqX); free(pSeqQ); free(pSeqK); free(pSeqV);
		free(pSeqAttOut); free(pActHB); free(pScores);
		return NULL;
	}
	float *pData = (float *)ring_tensor_data(pTensor);

	double sumSq = 0.0;
	if (pModel->config.nPoolingType == 1) {
		/* Mean pooling across all tokens */
		double invS = 1.0 / (double)S;
		for (d = 0; d < nEmbd; d++) {
			double meanVal = 0.0;
			for (t = 0; t < S; t++) {
				meanVal += (double)pSeqX[(size_t)t * nEmbd + d];
			}
			meanVal *= invS;
			pData[d] = (float)meanVal;
			sumSq += meanVal * meanVal;
		}
	} else {
		/* CLS token pooling (token 0: <s>) - BGE-M3 standard */
		for (d = 0; d < nEmbd; d++) {
			double val = (double)pSeqX[d];
			pData[d] = (float)val;
			sumSq += val * val;
		}
	}

	/* 4. L2 Normalization */
	if (sumSq > 1e-12) {
		double invNorm = 1.0 / sqrt(sumSq);
		for (d = 0; d < nEmbd; d++) {
			pData[d] = (float)((double)pData[d] * invNorm);
		}
	}

	free(pSeqX);
	free(pSeqQ);
	free(pSeqK);
	free(pSeqV);
	free(pSeqAttOut);
	free(pActHB);
	free(pScores);

	return pTensor;
}

RING_API RingTensor *ring_model_embedding(void *pRingState, RingModel *pModel, const char *cText) {
	int promptTokens[2048];
	int nPromptTokens, i, d;
	int nEmbd;
	size_t aShape[1];
	RingTensor *pTensor;
	float *pData;
	float *pMean;
	const float *outNormW;
	double sumSq, invNorm, invN;

	if (!pModel || !cText) return NULL;
	nEmbd = (int)pModel->config.nEmbd;
	if (nEmbd <= 0) return NULL;

	nPromptTokens = ring_tokenizer_encode(pModel->pTokenizer, cText, promptTokens, 2048);
	if (nPromptTokens <= 0) return NULL;

	if (pModel->config.bIsBert) {
		return ring_model_embedding_bert(pRingState, pModel, promptTokens, nPromptTokens);
	}

	pMean = (float *)calloc(nEmbd, sizeof(float));
	if (!pMean) return NULL;

	outNormW = pModel->pOutputNorm ? (const float *)ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pOutputNorm) : NULL;

	ring_model_reset_kv(pModel);

	/* Forward all prompt tokens through Transformer layers and accumulate hidden states for Mean Pooling */
	for (i = 0; i < nPromptTokens; i++) {
		ring_model_forward_ex(pModel, promptTokens[i], i, 0);

		if (outNormW) {
			rmsnorm(pModel->pActXB, pModel->pActX, outNormW, nEmbd, pModel->config.fNormEps);
		} else {
			memcpy(pModel->pActXB, pModel->pActX, nEmbd * sizeof(float));
		}

		/* Skip attention sink token at i=0 for significantly sharper semantic contrast */
		if (nPromptTokens > 1 && i == 0) continue;

		for (d = 0; d < nEmbd; d++) {
			pMean[d] += pModel->pActXB[d];
		}
	}

	/* Allocate a native 1D RingTensor of shape [nEmbd] */
	aShape[0] = (size_t)nEmbd;
	pTensor = ring_tensor_new(pRingState, RING_TENSOR_TYPE_FLOAT32, 1, aShape);
	if (!pTensor) {
		free(pMean);
		return NULL;
	}

	pData = (float *)ring_tensor_data(pTensor);
	if (!pData) {
		free(pMean);
		ring_tensor_delete(pRingState, pTensor);
		return NULL;
	}

	/* Mean pooling average & L2-normalization for unit-vector cosine similarity */
	sumSq = 0.0;
	{
		int nTokensCount = (nPromptTokens > 1) ? (nPromptTokens - 1) : 1;
		invN = 1.0 / (double)nTokensCount;
	}
	for (d = 0; d < nEmbd; d++) {
		double meanVal = (double)pMean[d] * invN;
		pData[d] = (float)meanVal;
		sumSq += meanVal * meanVal;
	}
	free(pMean);

	if (sumSq > 1e-12) {
		invNorm = 1.0 / sqrt(sumSq);
		for (d = 0; d < nEmbd; d++) {
			pData[d] = (float)((double)pData[d] * invNorm);
		}
	}

	return pTensor;
}

RING_FUNC(ring_model_api_embedding) {
	RingModel *pModel;
	const char *cText;
	RingTensor *pTensor;

	if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);

	cText = RING_API_GETSTRING(2);
	pTensor = ring_model_embedding(RING_API_STATE, pModel, cText);
	if (!pTensor) {
		RING_API_ERROR("Failed to compute text embedding vector!");
		return;
	}

	RING_API_RETMANAGEDCPOINTER(pTensor, "TENSOR", (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_model_api_prefill) {
	RingModel *pModel;
	const char *cPrompt;
	int nMaxTokens = 128;
	float fTemp = 0.7f;
	int nPromptTokens;

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

	nPromptTokens = ring_model_prefill(pModel, cPrompt, nMaxTokens, fTemp);
	RING_API_RETNUMBER(nPromptTokens);
}

RING_FUNC(ring_model_api_has_more) {
	RingModel *pModel;
	if (RING_API_PARACOUNT != 1 || !RING_API_ISPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);

	RING_API_RETNUMBER(ring_model_has_more(pModel));
}

RING_FUNC(ring_model_api_step) {
	RingModel *pModel;
	char *cChunk;
	if (RING_API_PARACOUNT != 1 || !RING_API_ISPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);

	cChunk = ring_model_step(pModel);
	if (cChunk) {
		RING_API_RETSTRING(cChunk);
		free(cChunk);
	} else {
		RING_API_RETSTRING("");
	}
}

RING_FUNC(ring_model_api_set_gpu) {
	RingModel *pModel;
	int bEnable;
	if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) || !RING_API_ISNUMBER(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}
	pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
	RING_API_CHECKNULLPOINTER(pModel);
	bEnable = (int)RING_API_GETNUMBER(2);
	ring_model_set_gpu(pModel, bEnable);
}

RING_API void ring_inference_loadfunctions(void *pRingState) {
	RING_API_REGISTER("madar_model_open", ring_model_api_open);
	RING_API_REGISTER("madar_model_close", ring_model_api_close);
	RING_API_REGISTER("madar_model_set_threads", ring_model_api_set_threads);
	RING_API_REGISTER("madar_model_set_gpu", ring_model_api_set_gpu);
	RING_API_REGISTER("madar_model_tokenize", ring_model_api_tokenize);
	RING_API_REGISTER("madar_model_detokenize", ring_model_api_detokenize);
	RING_API_REGISTER("madar_model_generate", ring_model_api_generate);
	RING_API_REGISTER("madar_model_generate_stream", ring_model_api_generate_stream);
	RING_API_REGISTER("madar_model_prefill", ring_model_api_prefill);
	RING_API_REGISTER("madar_model_has_more", ring_model_api_has_more);
	RING_API_REGISTER("madar_model_step", ring_model_api_step);
	RING_API_REGISTER("madar_model_reset", ring_model_api_reset);
	RING_API_REGISTER("madar_is_arabic", ring_model_api_is_arabic);
	RING_API_REGISTER("madar_model_embedding", ring_model_api_embedding);
}
