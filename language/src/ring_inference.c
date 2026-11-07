/*
**  Madar - High-Performance AI-Native Runtime
**  Lightweight Transformer & Qwen Inference Engine
**  Pure ANSI C / C99 Implementation
*/

#include "ring_inference.h"
#include "ring.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#include <pthread.h>
#include <semaphore.h>
#include <unistd.h>
#endif

/*
================================================================================
  Fast Vector Dot Products (Q4_0, Q8_0, F16, F32)
================================================================================
*/

static inline float fast_fp16_to_fp32(uint16_t h) {
  union {
    uint32_t u;
    float f;
  } v;
  uint32_t sign = ((uint32_t)h & 0x8000) << 16;
  int32_t exp = (h >> 10) & 0x1F;
  uint32_t mant = (h & 0x3FF) << 13;
  if (exp == 0x1F) {
    v.u = sign | 0x7F800000 | mant;
  } else if (exp == 0) {
    if (mant == 0) {
      v.u = sign;
    } else {
      while (!(mant & 0x00800000)) {
        mant <<= 1;
        exp--;
      }
      exp++;
      mant &= ~0x00800000;
      v.u = sign | ((uint32_t)(exp + 112) << 23) | mant;
    }
  } else {
    v.u = sign | ((uint32_t)(exp + 112) << 23) | mant;
  }
  return v.f;
}

#if defined(__AVX2__) ||                                                       \
    (defined(_MSC_VER) && (defined(_M_AMD64) || defined(_M_X64)))
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
    __m128i high0 =
        _mm_sub_epi8(_mm_and_si128(_mm_srli_epi16(raw0, 4), lowMask), c8);

    __m256 f0_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low0));
    __m256 f1_0 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low0, 8)));
    __m256 f2_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high0));
    __m256 f3_0 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high0, 8)));

    __m256 p01_0 =
        _mm256_fmadd_ps(f0_0, _mm256_loadu_ps(xi0 + 0),
                        _mm256_mul_ps(f1_0, _mm256_loadu_ps(xi0 + 8)));
    __m256 p23_0 =
        _mm256_fmadd_ps(f2_0, _mm256_loadu_ps(xi0 + 16),
                        _mm256_mul_ps(f3_0, _mm256_loadu_ps(xi0 + 24)));
    acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01_0, p23_0), vd0, acc0);

    /* Block 1 */
    __m128 h1 = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i + 1].d));
    __m256 vd1 = _mm256_broadcastss_ps(h1);
    __m128i raw1 = _mm_loadu_si128((const __m128i *)b[i + 1].qs);
    const float *xi1 = x + (i + 1) * 32;

    __m128i low1 = _mm_sub_epi8(_mm_and_si128(raw1, lowMask), c8);
    __m128i high1 =
        _mm_sub_epi8(_mm_and_si128(_mm_srli_epi16(raw1, 4), lowMask), c8);

    __m256 f0_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low1));
    __m256 f1_1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low1, 8)));
    __m256 f2_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high1));
    __m256 f3_1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high1, 8)));

    __m256 p01_1 =
        _mm256_fmadd_ps(f0_1, _mm256_loadu_ps(xi1 + 0),
                        _mm256_mul_ps(f1_1, _mm256_loadu_ps(xi1 + 8)));
    __m256 p23_1 =
        _mm256_fmadd_ps(f2_1, _mm256_loadu_ps(xi1 + 16),
                        _mm256_mul_ps(f3_1, _mm256_loadu_ps(xi1 + 24)));
    acc1 = _mm256_fmadd_ps(_mm256_add_ps(p01_1, p23_1), vd1, acc1);
  }

  for (; i < nBlocks; i++) {
    __m128 h = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
    __m256 vd = _mm256_broadcastss_ps(h);
    __m128i raw = _mm_loadu_si128((const __m128i *)b[i].qs);
    const float *xi = x + i * 32;

    __m128i low = _mm_sub_epi8(_mm_and_si128(raw, lowMask), c8);
    __m128i high =
        _mm_sub_epi8(_mm_and_si128(_mm_srli_epi16(raw, 4), lowMask), c8);

    __m256 f0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low));
    __m256 f1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low, 8)));
    __m256 f2 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high));
    __m256 f3 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high, 8)));

    __m256 p01 = _mm256_fmadd_ps(f0, _mm256_loadu_ps(xi + 0),
                                 _mm256_mul_ps(f1, _mm256_loadu_ps(xi + 8)));
    __m256 p23 = _mm256_fmadd_ps(f2, _mm256_loadu_ps(xi + 16),
                                 _mm256_mul_ps(f3, _mm256_loadu_ps(xi + 24)));
    acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01, p23), vd, acc0);
  }

  return hsum_float_8(_mm256_add_ps(acc0, acc1));
}

static float dot_q4_1(const RingGGUFBlockQ4_1 *b, const float *x, int k) {
  int nBlocks = k / 32;
  int i = 0;
  const __m128i lowMask = _mm_set1_epi8(0x0F);
  __m256 acc0 = _mm256_setzero_ps();
  __m256 acc1 = _mm256_setzero_ps();

  for (; i + 1 < nBlocks; i += 2) {
    /* Block 0 */
    __m128 h0_d = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
    __m128 h0_m = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].m));
    __m256 vd0 = _mm256_broadcastss_ps(h0_d);
    __m256 vm0 = _mm256_broadcastss_ps(h0_m);
    __m128i raw0 = _mm_loadu_si128((const __m128i *)b[i].qs);
    const float *xi0 = x + i * 32;

    __m128i low0 = _mm_and_si128(raw0, lowMask);
    __m128i high0 = _mm_and_si128(_mm_srli_epi16(raw0, 4), lowMask);

    __m256 f0_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low0));
    __m256 f1_0 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low0, 8)));
    __m256 f2_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high0));
    __m256 f3_0 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high0, 8)));

    __m256 x0_0 = _mm256_loadu_ps(xi0 + 0);
    __m256 x1_0 = _mm256_loadu_ps(xi0 + 8);
    __m256 x2_0 = _mm256_loadu_ps(xi0 + 16);
    __m256 x3_0 = _mm256_loadu_ps(xi0 + 24);

    __m256 p01_0 = _mm256_fmadd_ps(f0_0, x0_0, _mm256_mul_ps(f1_0, x1_0));
    __m256 p23_0 = _mm256_fmadd_ps(f2_0, x2_0, _mm256_mul_ps(f3_0, x3_0));
    acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01_0, p23_0), vd0, acc0);
    __m256 xsum0 =
        _mm256_add_ps(_mm256_add_ps(x0_0, x1_0), _mm256_add_ps(x2_0, x3_0));
    acc0 = _mm256_fmadd_ps(xsum0, vm0, acc0);

    /* Block 1 */
    __m128 h1_d = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i + 1].d));
    __m128 h1_m = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i + 1].m));
    __m256 vd1 = _mm256_broadcastss_ps(h1_d);
    __m256 vm1 = _mm256_broadcastss_ps(h1_m);
    __m128i raw1 = _mm_loadu_si128((const __m128i *)b[i + 1].qs);
    const float *xi1 = x + (i + 1) * 32;

    __m128i low1 = _mm_and_si128(raw1, lowMask);
    __m128i high1 = _mm_and_si128(_mm_srli_epi16(raw1, 4), lowMask);

    __m256 f0_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low1));
    __m256 f1_1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low1, 8)));
    __m256 f2_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high1));
    __m256 f3_1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high1, 8)));

    __m256 x0_1 = _mm256_loadu_ps(xi1 + 0);
    __m256 x1_1 = _mm256_loadu_ps(xi1 + 8);
    __m256 x2_1 = _mm256_loadu_ps(xi1 + 16);
    __m256 x3_1 = _mm256_loadu_ps(xi1 + 24);

    __m256 p01_1 = _mm256_fmadd_ps(f0_1, x0_1, _mm256_mul_ps(f1_1, x1_1));
    __m256 p23_1 = _mm256_fmadd_ps(f2_1, x2_1, _mm256_mul_ps(f3_1, x3_1));
    acc1 = _mm256_fmadd_ps(_mm256_add_ps(p01_1, p23_1), vd1, acc1);
    __m256 xsum1 =
        _mm256_add_ps(_mm256_add_ps(x0_1, x1_1), _mm256_add_ps(x2_1, x3_1));
    acc1 = _mm256_fmadd_ps(xsum1, vm1, acc1);
  }

  for (; i < nBlocks; i++) {
    __m128 h_d = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
    __m128 h_m = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].m));
    __m256 vd = _mm256_broadcastss_ps(h_d);
    __m256 vm = _mm256_broadcastss_ps(h_m);
    __m128i raw = _mm_loadu_si128((const __m128i *)b[i].qs);
    const float *xi = x + i * 32;

    __m128i low = _mm_and_si128(raw, lowMask);
    __m128i high = _mm_and_si128(_mm_srli_epi16(raw, 4), lowMask);

    __m256 f0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(low));
    __m256 f1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(low, 8)));
    __m256 f2 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(high));
    __m256 f3 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(high, 8)));

    __m256 x0 = _mm256_loadu_ps(xi + 0);
    __m256 x1 = _mm256_loadu_ps(xi + 8);
    __m256 x2 = _mm256_loadu_ps(xi + 16);
    __m256 x3 = _mm256_loadu_ps(xi + 24);

    __m256 p01 = _mm256_fmadd_ps(f0, x0, _mm256_mul_ps(f1, x1));
    __m256 p23 = _mm256_fmadd_ps(f2, x2, _mm256_mul_ps(f3, x3));
    acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01, p23), vd, acc0);
    __m256 xsum = _mm256_add_ps(_mm256_add_ps(x0, x1), _mm256_add_ps(x2, x3));
    acc0 = _mm256_fmadd_ps(xsum, vm, acc0);
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

    __m128i q0_15_0 = _mm_loadu_si128((const __m128i *)(qs0 + 0));
    __m128i q16_31_0 = _mm_loadu_si128((const __m128i *)(qs0 + 16));

    __m256 f0_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q0_15_0));
    __m256 f1_0 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q0_15_0, 8)));
    __m256 f2_0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q16_31_0));
    __m256 f3_0 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q16_31_0, 8)));

    __m256 p01_0 =
        _mm256_fmadd_ps(f0_0, _mm256_loadu_ps(xi0 + 0),
                        _mm256_mul_ps(f1_0, _mm256_loadu_ps(xi0 + 8)));
    __m256 p23_0 =
        _mm256_fmadd_ps(f2_0, _mm256_loadu_ps(xi0 + 16),
                        _mm256_mul_ps(f3_0, _mm256_loadu_ps(xi0 + 24)));
    acc0 = _mm256_fmadd_ps(_mm256_add_ps(p01_0, p23_0), vd0, acc0);

    /* Block 1 */
    __m128 h1 = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i + 1].d));
    __m256 vd1 = _mm256_broadcastss_ps(h1);
    const int8_t *qs1 = b[i + 1].qs;
    const float *xi1 = x + (i + 1) * 32;

    __m128i q0_15_1 = _mm_loadu_si128((const __m128i *)(qs1 + 0));
    __m128i q16_31_1 = _mm_loadu_si128((const __m128i *)(qs1 + 16));

    __m256 f0_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q0_15_1));
    __m256 f1_1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q0_15_1, 8)));
    __m256 f2_1 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q16_31_1));
    __m256 f3_1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q16_31_1, 8)));

    __m256 p01_1 =
        _mm256_fmadd_ps(f0_1, _mm256_loadu_ps(xi1 + 0),
                        _mm256_mul_ps(f1_1, _mm256_loadu_ps(xi1 + 8)));
    __m256 p23_1 =
        _mm256_fmadd_ps(f2_1, _mm256_loadu_ps(xi1 + 16),
                        _mm256_mul_ps(f3_1, _mm256_loadu_ps(xi1 + 24)));
    acc1 = _mm256_fmadd_ps(_mm256_add_ps(p01_1, p23_1), vd1, acc1);
  }

  for (; i < nBlocks; i++) {
    __m128 h = _mm_cvtph_ps(_mm_cvtsi32_si128((int)b[i].d));
    __m256 vd = _mm256_broadcastss_ps(h);
    const int8_t *qs = b[i].qs;
    const float *xi = x + i * 32;

    __m128i q0_15 = _mm_loadu_si128((const __m128i *)(qs + 0));
    __m128i q16_31 = _mm_loadu_si128((const __m128i *)(qs + 16));

    __m256 f0 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q0_15));
    __m256 f1 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q0_15, 8)));
    __m256 f2 = _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(q16_31));
    __m256 f3 =
        _mm256_cvtepi32_ps(_mm256_cvtepi8_epi32(_mm_srli_si128(q16_31, 8)));

    __m256 p01 = _mm256_fmadd_ps(f0, _mm256_loadu_ps(xi + 0),
                                 _mm256_mul_ps(f1, _mm256_loadu_ps(xi + 8)));
    __m256 p23 = _mm256_fmadd_ps(f2, _mm256_loadu_ps(xi + 16),
                                 _mm256_mul_ps(f3, _mm256_loadu_ps(xi + 24)));
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
    acc1 =
        _mm256_fmadd_ps(_mm256_cvtph_ps(h1), _mm256_loadu_ps(x + i + 8), acc1);
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
    acc0 =
        _mm256_fmadd_ps(_mm256_loadu_ps(f + i), _mm256_loadu_ps(x + i), acc0);
    acc1 = _mm256_fmadd_ps(_mm256_loadu_ps(f + i + 8),
                           _mm256_loadu_ps(x + i + 8), acc1);
  }
  for (; i + 7 < k; i += 8) {
    acc0 =
        _mm256_fmadd_ps(_mm256_loadu_ps(f + i), _mm256_loadu_ps(x + i), acc0);
  }
  float sum = hsum_float_8(_mm256_add_ps(acc0, acc1));
  for (; i < k; i++) {
    sum += f[i] * x[i];
  }
  return sum;
}

static float dot_i2_s(const uint8_t *qs, const float *x, int k) {
  int nBlocks = k / 128;
  float sum = 0.0f;
  static const float s_lut[4] = {-1.0f, 0.0f, 1.0f, 0.0f};
  int b, j, m;

  __m256 vsum0 = _mm256_setzero_ps();
  __m256 vsum1 = _mm256_setzero_ps();

  for (b = 0; b < nBlocks; b++) {
    const uint8_t *bqs = qs + b * 32;
    const float *bx0 = x + b * 128;
    const float *bx1 = bx0 + 32;
    const float *bx2 = bx0 + 64;
    const float *bx3 = bx0 + 96;

    for (j = 0; j < 32; j += 8) {
      float w0[8], w1[8], w2[8], w3[8];
      for (m = 0; m < 8; m++) {
        uint8_t byte = bqs[j + m];
        w0[m] = s_lut[(byte >> 6) & 3];
        w1[m] = s_lut[(byte >> 4) & 3];
        w2[m] = s_lut[(byte >> 2) & 3];
        w3[m] = s_lut[byte & 3];
      }
      vsum0 =
          _mm256_fmadd_ps(_mm256_loadu_ps(w0), _mm256_loadu_ps(bx0 + j), vsum0);
      vsum1 =
          _mm256_fmadd_ps(_mm256_loadu_ps(w1), _mm256_loadu_ps(bx1 + j), vsum1);
      vsum0 =
          _mm256_fmadd_ps(_mm256_loadu_ps(w2), _mm256_loadu_ps(bx2 + j), vsum0);
      vsum1 =
          _mm256_fmadd_ps(_mm256_loadu_ps(w3), _mm256_loadu_ps(bx3 + j), vsum1);
    }
  }
  sum = hsum_float_8(_mm256_add_ps(vsum0, vsum1));
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
      bsum0 += (float)((int)(q0 & 0x0F) - 8) * xi[j] +
               (float)((int)(q0 >> 4) - 8) * xi[j + 16];
      bsum1 += (float)((int)(q1 & 0x0F) - 8) * xi[j + 1] +
               (float)((int)(q1 >> 4) - 8) * xi[j + 1 + 16];
    }
    sum += (bsum0 + bsum1) * d;
  }
  return sum;
}

static float dot_q4_1(const RingGGUFBlockQ4_1 *b, const float *x, int k) {
  int nBlocks = k / 32;
  float sum = 0.0f;
  int i, j;
  float d, m, bsum0, bsum1, xsum;
  const uint8_t *qs;
  const float *xi;
  uint8_t q0, q1;

  for (i = 0; i < nBlocks; i++) {
    d = fast_fp16_to_fp32(b[i].d);
    m = fast_fp16_to_fp32(b[i].m);
    qs = b[i].qs;
    xi = x + i * 32;
    bsum0 = 0.0f;
    bsum1 = 0.0f;
    xsum = 0.0f;
    for (j = 0; j < 16; j += 2) {
      q0 = qs[j];
      q1 = qs[j + 1];
      float vx0 = xi[j];
      float vx1 = xi[j + 1];
      float vx16 = xi[j + 16];
      float vx17 = xi[j + 1 + 16];
      bsum0 += (float)(q0 & 0x0F) * vx0 + (float)(q0 >> 4) * vx16;
      bsum1 += (float)(q1 & 0x0F) * vx1 + (float)(q1 >> 4) * vx17;
      xsum += vx0 + vx1 + vx16 + vx17;
    }
    sum += (bsum0 + bsum1) * d + xsum * m;
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
      bsum0 += (float)qs[j] * xi[j];
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

static float dot_i2_s(const uint8_t *qs, const float *x, int k) {
  int nBlocks = k / 128;
  float sum = 0.0f;
  static const float s_lut[4] = {-1.0f, 0.0f, 1.0f, 0.0f};
  int b, j;

  for (b = 0; b < nBlocks; b++) {
    const uint8_t *bqs = qs + b * 32;
    const float *xb = x + b * 128;
    for (j = 0; j < 32; j++) {
      uint8_t byte = bqs[j];
      float w0 = s_lut[(byte >> 6) & 3];
      float w1 = s_lut[(byte >> 4) & 3];
      float w2 = s_lut[(byte >> 2) & 3];
      float w3 = s_lut[byte & 3];
      sum +=
          w0 * xb[0 + j] + w1 * xb[32 + j] + w2 * xb[64 + j] + w3 * xb[96 + j];
    }
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
          int8_t q1 =
              (int8_t)((ql[l + 0] & 0xF) | (((qh[l] >> 0) & 3) << 4)) - 32;
          int8_t q2 =
              (int8_t)((ql[l + 32] & 0xF) | (((qh[l] >> 2) & 3) << 4)) - 32;
          int8_t q3 =
              (int8_t)((ql[l + 0] >> 4) | (((qh[l] >> 4) & 3) << 4)) - 32;
          int8_t q4 =
              (int8_t)((ql[l + 32] >> 4) | (((qh[l] >> 6) & 3) << 4)) - 32;

          bsum += s0 * (float)q1 * v[l + 0] + s2 * (float)q2 * v[l + 32] +
                  s4 * (float)q3 * v[l + 64] + s6 * (float)q4 * v[l + 96];
        }
      }
      v += 128;
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
  const uint8_t *pRaw =
      (const uint8_t *)ring_gguf_get_tensor_data(task->pGGUF, task->pInfo);
  uint32_t nType;
  int K, r;
  float val;

  if (!pRaw)
    return;

  nType = task->pInfo->nType;
  K = task->K;

  if (nType == RING_GGUF_TENSOR_Q4_0) {
    size_t rowStride = (size_t)(K / 32) * sizeof(RingGGUFBlockQ4_0);
    const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
    for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
      val = dot_q4_0((const RingGGUFBlockQ4_0 *)pRow, task->pX, K);
      if (task->pBias) {
        val +=
            (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16)
                ? fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r])
                : ((const float *)task->pBias)[r];
      }
      task->pY[r] = val;
    }
    return;
  } else if (nType == RING_GGUF_TENSOR_Q4_1) {
    size_t rowStride = (size_t)(K / 32) * sizeof(RingGGUFBlockQ4_1);
    const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
    for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
      val = dot_q4_1((const RingGGUFBlockQ4_1 *)pRow, task->pX, K);
      if (task->pBias) {
        val +=
            (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16)
                ? fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r])
                : ((const float *)task->pBias)[r];
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
        val +=
            (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16)
                ? fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r])
                : ((const float *)task->pBias)[r];
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
        val +=
            (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16)
                ? fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r])
                : ((const float *)task->pBias)[r];
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
        val +=
            (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16)
                ? fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r])
                : ((const float *)task->pBias)[r];
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
        val +=
            (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16)
                ? fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r])
                : ((const float *)task->pBias)[r];
      }
      task->pY[r] = val;
    }
    return;
  } else if (nType == RING_GGUF_TENSOR_I2_S || nType == 35) {
    size_t rowStride = (size_t)(K / 4);
    const uint8_t *pRow = pRaw + (size_t)task->nStartRow * rowStride;
    float scale = 1.0f;
    if (task->pInfo) {
      uint64_t packedBytes = (task->pInfo->nElements + 3) / 4;
      const float *pScalePtr = (const float *)(pRaw + packedBytes);
      if (pScalePtr[0] != 0.0f && !isnan(pScalePtr[0]) &&
          !isinf(pScalePtr[0])) {
        scale = pScalePtr[0];
      }
    }
    for (r = task->nStartRow; r < task->nEndRow; r++, pRow += rowStride) {
      val = dot_i2_s(pRow, task->pX, K) * scale;
      if (task->pBias) {
        val +=
            (task->pBiasInfo && task->pBiasInfo->nType == RING_GGUF_TENSOR_F16)
                ? fast_fp16_to_fp32(((const ggml_fp16_t *)task->pBias)[r])
                : ((const float *)task->pBias)[r];
      }
      task->pY[r] = val;
    }
    return;
  } else {
    static int s_unsupportedWarn = 0;
    if (s_unsupportedWarn++ < 1) {
      printf("\n[MADAR AI] Warning: matvec_compute_rows unsupported tensor "
             "type: %u for '%s'!\n",
             nType, task->pInfo->pName ? task->pInfo->pName : "unknown");
    }
  }
}

typedef struct {
  RingModel *pModel;
  int nIndex;
} RingWorkerParam;

#ifdef _WIN32
static DWORD WINAPI ring_model_worker_proc(LPVOID lpParam) {
  RingWorkerParam *param = (RingWorkerParam *)lpParam;
  RingModel *pModel = param->pModel;
  int idx = param->nIndex;
  free(param);

  while (1) {
    WaitForSingleObject((HANDLE)pModel->hStartEvents[idx], INFINITE);
    if (pModel->bWorkerShutdown)
      break;
    if (pModel->pWorkerTasks[idx]) {
      matvec_compute_rows((MatVecTask *)pModel->pWorkerTasks[idx]);
    }
    SetEvent((HANDLE)pModel->hDoneEvents[idx]);
  }
  return 0;
}
#else
static void *ring_model_worker_proc(void *lpParam) {
  RingWorkerParam *param = (RingWorkerParam *)lpParam;
  RingModel *pModel = param->pModel;
  int idx = param->nIndex;
  free(param);

  while (1) {
    sem_wait((sem_t *)pModel->hStartEvents[idx]);
    if (pModel->bWorkerShutdown)
      break;
    if (pModel->pWorkerTasks[idx]) {
      matvec_compute_rows((MatVecTask *)pModel->pWorkerTasks[idx]);
    }
    sem_post((sem_t *)pModel->hDoneEvents[idx]);
  }
  return NULL;
}
#endif

/*
================================================================================
  GPU Acceleration Engine (OpenCL Dynamic Zero-Copy Subsystem)
================================================================================
*/

#include "opencl_stub.h"

static int s_cl_loaded = 0;
static pfn_clGetPlatformIDs p_clGetPlatformIDs = NULL;
static pfn_clGetDeviceIDs p_clGetDeviceIDs = NULL;
static pfn_clGetDeviceInfo p_clGetDeviceInfo = NULL;
static pfn_clCreateContext p_clCreateContext = NULL;
static pfn_clCreateCommandQueue p_clCreateCommandQueue = NULL;
static pfn_clCreateBuffer p_clCreateBuffer = NULL;
static pfn_clCreateProgramWithSource p_clCreateProgramWithSource = NULL;
static pfn_clBuildProgram p_clBuildProgram = NULL;
static pfn_clGetProgramBuildInfo p_clGetProgramBuildInfo = NULL;
static pfn_clCreateKernel p_clCreateKernel = NULL;
static pfn_clSetKernelArg p_clSetKernelArg = NULL;
static pfn_clEnqueueNDRangeKernel p_clEnqueueNDRangeKernel = NULL;
static pfn_clEnqueueReadBuffer p_clEnqueueReadBuffer = NULL;
static pfn_clEnqueueWriteBuffer p_clEnqueueWriteBuffer = NULL;
static pfn_clFinish p_clFinish = NULL;
static pfn_clReleaseMemObject p_clReleaseMemObject = NULL;
static pfn_clReleaseKernel p_clReleaseKernel = NULL;
static pfn_clReleaseProgram p_clReleaseProgram = NULL;
static pfn_clReleaseCommandQueue p_clReleaseCommandQueue = NULL;
static pfn_clReleaseContext p_clReleaseContext = NULL;

static int madar_opencl_load_dll(void) {
  if (s_cl_loaded == 1)
    return 1;
  if (s_cl_loaded == -1)
    return 0;

#ifdef _WIN32
  HMODULE hLib = LoadLibraryA("OpenCL.dll");
  if (!hLib) {
    s_cl_loaded = -1;
    return 0;
  }
#define LOAD_CL_SYM(name)                                                      \
  do {                                                                         \
    p_##name = (pfn_##name)GetProcAddress(hLib, #name);                        \
    if (!p_##name) {                                                           \
      s_cl_loaded = -1;                                                        \
      return 0;                                                                \
    }                                                                          \
  } while (0)
#else
  void *hLib = dlopen("libOpenCL.so.1", RTLD_LAZY);
  if (!hLib)
    hLib = dlopen("libOpenCL.so", RTLD_LAZY);
  if (!hLib)
    hLib = dlopen("libnvidia-opencl.so.1", RTLD_LAZY);
  if (!hLib) {
    s_cl_loaded = -1;
    return 0;
  }
#define LOAD_CL_SYM(name)                                                      \
  do {                                                                         \
    p_##name = (pfn_##name)dlsym(hLib, #name);                                 \
    if (!p_##name) {                                                           \
      s_cl_loaded = -1;                                                        \
      return 0;                                                                \
    }                                                                          \
  } while (0)
#endif

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
}

static const char *s_madar_cl_source =
    "inline float fp16_to_fp32(ushort h) {\n"
    "    uint sign = ((uint)h & 0x8000) << 16;\n"
    "    uint exp  = (h >> 10) & 0x1F;\n"
    "    uint mant = (h & 0x3FF) << 13;\n"
    "    if (exp == 0x1F) return as_float(sign | 0x7F800000 | mant);\n"
    "    if (exp == 0) return (mant == 0) ? as_float(sign) : as_float(sign | "
    "((exp + 112) << 23) | mant);\n"
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
    "    ushort m;\n"
    "    uchar qs[16];\n"
    "} block_q4_1;\n"
    "\n"
    "__kernel void matvec_q4_1_kernel(\n"
    "    __global const block_q4_1* W,\n"
    "    __global const float* x,\n"
    "    __global float* y,\n"
    "    int K, int N)\n"
    "{\n"
    "    int r = get_global_id(0);\n"
    "    if (r >= N) return;\n"
    "    int num_blocks = K / 32;\n"
    "    __global const block_q4_1* row = W + (size_t)r * num_blocks;\n"
    "    float sum = 0.0f;\n"
    "    for (int b = 0; b < num_blocks; b++) {\n"
    "        float d = fp16_to_fp32(row[b].d);\n"
    "        float m = fp16_to_fp32(row[b].m);\n"
    "        __global const uchar* qs = row[b].qs;\n"
    "        __global const float* bx = x + b * 32;\n"
    "        float4 acc = (float4)(0.0f);\n"
    "        float4 xsum = (float4)(0.0f);\n"
    "        for (int j = 0; j < 16; j += 4) {\n"
    "            uchar4 bytes = vload4(0, qs + j);\n"
    "            int4 low  = convert_int4(bytes & (uchar4)0x0F);\n"
    "            int4 high = convert_int4(bytes >> (uchar4)4);\n"
    "            float4 vx_low  = vload4(0, bx + j);\n"
    "            float4 vx_high = vload4(0, bx + j + 16);\n"
    "            acc += convert_float4(low)  * vx_low;\n"
    "            acc += convert_float4(high) * vx_high;\n"
    "            xsum += vx_low + vx_high;\n"
    "        }\n"
    "        sum += (acc.x + acc.y + acc.z + acc.w) * d + (xsum.x + xsum.y + "
    "xsum.z + xsum.w) * m;\n"
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
    "                    uchar4 ql0 = vload4(0, row[b].ql + ql_offset + l + "
    "0);\n"
    "                    uchar4 ql1 = vload4(0, row[b].ql + ql_offset + l + "
    "32);\n"
    "                    uchar4 qh0 = vload4(0, row[b].qh + qh_offset + l);\n"
    "                    int4 q1 = convert_int4((ql0 & (uchar4)0xF) | (((qh0 "
    ">> (uchar4)0) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
    "                    int4 q2 = convert_int4((ql1 & (uchar4)0xF) | (((qh0 "
    ">> (uchar4)2) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
    "                    int4 q3 = convert_int4((ql0 >> (uchar4)4)  | (((qh0 "
    ">> (uchar4)4) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
    "                    int4 q4 = convert_int4((ql1 >> (uchar4)4)  | (((qh0 "
    ">> (uchar4)6) & (uchar4)3) << (uchar4)4)) - (int4)32;\n"
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
    "}\n"
    "\n"
    "__kernel void gemv_batch_q4_0_kernel(\n"
    "    __global const block_q4_0* W,\n"
    "    __global const float* x,\n"
    "    __global float* y,\n"
    "    int K, int N, int B)\n"
    "{\n"
    "    int r = get_global_id(0);\n"
    "    int t = get_global_id(1);\n"
    "    if (r >= N || t >= B) return;\n"
    "    int num_blocks = K / 32;\n"
    "    __global const block_q4_0* row = W + (size_t)r * num_blocks;\n"
    "    __global const float* bx_base = x + (size_t)t * K;\n"
    "    float sum = 0.0f;\n"
    "    for (int b = 0; b < num_blocks; b++) {\n"
    "        float d = fp16_to_fp32(row[b].d);\n"
    "        __global const uchar* qs = row[b].qs;\n"
    "        __global const float* bx = bx_base + b * 32;\n"
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
    "    y[(size_t)t * N + r] = sum;\n"
    "}\n"
    "\n"
    "__kernel void silu_mul_batch_kernel(\n"
    "    __global float* gate,\n"
    "    __global const float* up,\n"
    "    int total_elements)\n"
    "{\n"
    "    int i = get_global_id(0);\n"
    "    if (i >= total_elements) return;\n"
    "    float g = gate[i];\n"
    "    float silu_g = g / (1.0f + exp(-g));\n"
    "    gate[i] = silu_g * up[i];\n"
    "}\n"
    "\n"
    "typedef struct {\n"
    "    ushort d;\n"
    "    uchar qs[32];\n"
    "} block_i2_s;\n"
    "\n"
    "__kernel void matvec_i2_s_kernel(\n"
    "    __global const block_i2_s* W,\n"
    "    __global const float* x,\n"
    "    __global float* y,\n"
    "    int K, int N)\n"
    "{\n"
    "    int r = get_global_id(0);\n"
    "    if (r >= N) return;\n"
    "    int num_blocks = K / 128;\n"
    "    __global const block_i2_s* row = W + (size_t)r * num_blocks;\n"
    "    float sum = 0.0f;\n"
    "    for (int b = 0; b < num_blocks; b++) {\n"
    "        float d = fp16_to_fp32(row[b].d);\n"
    "        __global const uchar* qs = row[b].qs;\n"
    "        __global const float* bx = x + b * 128;\n"
    "        float bsum = 0.0f;\n"
    "        for (int j = 0; j < 32; j += 4) {\n"
    "            uchar4 bytes = vload4(0, qs + j);\n"
    "            int4 w0 = (int4)((bytes.x & 3) - 1, ((bytes.x >> 2) & 3) - 1, "
    "((bytes.x >> 4) & 3) - 1, ((bytes.x >> 6) & 3) - 1);\n"
    "            int4 w1 = (int4)((bytes.y & 3) - 1, ((bytes.y >> 2) & 3) - 1, "
    "((bytes.y >> 4) & 3) - 1, ((bytes.y >> 6) & 3) - 1);\n"
    "            int4 w2 = (int4)((bytes.z & 3) - 1, ((bytes.z >> 2) & 3) - 1, "
    "((bytes.z >> 4) & 3) - 1, ((bytes.z >> 6) & 3) - 1);\n"
    "            int4 w3 = (int4)((bytes.w & 3) - 1, ((bytes.w >> 2) & 3) - 1, "
    "((bytes.w >> 4) & 3) - 1, ((bytes.w >> 6) & 3) - 1);\n"
    "            float4 vx0 = vload4(0, bx + (j + 0) * 4);\n"
    "            float4 vx1 = vload4(0, bx + (j + 1) * 4);\n"
    "            float4 vx2 = vload4(0, bx + (j + 2) * 4);\n"
    "            float4 vx3 = vload4(0, bx + (j + 3) * 4);\n"
    "            float4 s = convert_float4(w0) * vx0 + convert_float4(w1) * "
    "vx1 + convert_float4(w2) * vx2 + convert_float4(w3) * vx3;\n"
    "            bsum += (s.x + s.y + s.z + s.w);\n"
    "        }\n"
    "        sum += bsum * d;\n"
    "    }\n"
    "    y[r] = sum;\n"
    "}\n"
    "\n"
    "__kernel void gemv_batch_i2_s_kernel(\n"
    "    __global const block_i2_s* W,\n"
    "    __global const float* x,\n"
    "    __global float* y,\n"
    "    int K, int N, int B)\n"
    "{\n"
    "    int r = get_global_id(0);\n"
    "    int t = get_global_id(1);\n"
    "    if (r >= N || t >= B) return;\n"
    "    int num_blocks = K / 128;\n"
    "    __global const block_i2_s* row = W + (size_t)r * num_blocks;\n"
    "    __global const float* bx_base = x + (size_t)t * K;\n"
    "    float sum = 0.0f;\n"
    "    for (int b = 0; b < num_blocks; b++) {\n"
    "        float d = fp16_to_fp32(row[b].d);\n"
    "        __global const uchar* qs = row[b].qs;\n"
    "        __global const float* bx = bx_base + b * 128;\n"
    "        float bsum = 0.0f;\n"
    "        for (int j = 0; j < 32; j += 4) {\n"
    "            uchar4 bytes = vload4(0, qs + j);\n"
    "            int4 w0 = (int4)((bytes.x & 3) - 1, ((bytes.x >> 2) & 3) - 1, "
    "((bytes.x >> 4) & 3) - 1, ((bytes.x >> 6) & 3) - 1);\n"
    "            int4 w1 = (int4)((bytes.y & 3) - 1, ((bytes.y >> 2) & 3) - 1, "
    "((bytes.y >> 4) & 3) - 1, ((bytes.y >> 6) & 3) - 1);\n"
    "            int4 w2 = (int4)((bytes.z & 3) - 1, ((bytes.z >> 2) & 3) - 1, "
    "((bytes.z >> 4) & 3) - 1, ((bytes.z >> 6) & 3) - 1);\n"
    "            int4 w3 = (int4)((bytes.w & 3) - 1, ((bytes.w >> 2) & 3) - 1, "
    "((bytes.w >> 4) & 3) - 1, ((bytes.w >> 6) & 3) - 1);\n"
    "            float4 vx0 = vload4(0, bx + (j + 0) * 4);\n"
    "            float4 vx1 = vload4(0, bx + (j + 1) * 4);\n"
    "            float4 vx2 = vload4(0, bx + (j + 2) * 4);\n"
    "            float4 vx3 = vload4(0, bx + (j + 3) * 4);\n"
    "            float4 s = convert_float4(w0) * vx0 + convert_float4(w1) * "
    "vx1 + convert_float4(w2) * vx2 + convert_float4(w3) * vx3;\n"
    "            bsum += (s.x + s.y + s.z + s.w);\n"
    "        }\n"
    "        sum += bsum * d;\n"
    "    }\n"
    "    y[(size_t)t * N + r] = sum;\n"
    "}\n";

static int madar_gpu_init(RingModel *pModel) {
  cl_platform_id platform = NULL;
  cl_device_id device = NULL;
  cl_uint numPlatforms = 0, numDevices = 0;
  cl_context ctx = NULL;
  cl_command_queue queue = NULL;
  cl_program prog = NULL;
  cl_kernel kQ4 = NULL, kQ4_1 = NULL, kQ8 = NULL, kQ6 = NULL, kQ4Batch = NULL,
            kSiLUBatch = NULL, kI2_S = NULL, kI2_SBatch = NULL;
  cl_mem bufGate = NULL, bufUp = NULL, bufDown = NULL;
  cl_int ret = 0;
  char devName[128] = {0};

  pModel->bGPUEnabled = 0;

  const char *envGPU = getenv("MADAR_GPU");
  if (envGPU && strcmp(envGPU, "0") == 0) {
    printf("  [Madar GPU] Disabled via MADAR_GPU=0 (Running Pure CPU AVX2)\n");
    return 0;
  }

  if (pModel->config.bIsBitNet) {
    if (!envGPU || strcmp(envGPU, "1") != 0) {
      /* Default to high-performance CPU AVX2 multi-threading for BitNet ternary
       * models */
      return 0;
    }
  }

  if (!madar_opencl_load_dll())
    return 0;

  ret = p_clGetPlatformIDs(1, &platform, &numPlatforms);
  if (ret != CL_SUCCESS || numPlatforms == 0)
    return 0;

  /* Try to get GPU device first */
  ret = p_clGetDeviceIDs(platform, CL_DEVICE_TYPE_GPU, 1, &device, &numDevices);
  if (ret != CL_SUCCESS || numDevices == 0) {
    /* Fallback to any OpenCL device */
    ret =
        p_clGetDeviceIDs(platform, CL_DEVICE_TYPE_ALL, 1, &device, &numDevices);
    if (ret != CL_SUCCESS || numDevices == 0)
      return 0;
  }

  p_clGetDeviceInfo(device, CL_DEVICE_NAME, sizeof(devName), devName, NULL);

  ctx = p_clCreateContext(NULL, 1, &device, NULL, NULL, &ret);
  if (ret != CL_SUCCESS || !ctx)
    return 0;

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

  ret = p_clBuildProgram(prog, 1, &device,
                         "-cl-fast-relaxed-math -cl-mad-enable", NULL, NULL);
  if (ret != CL_SUCCESS) {
    ret = p_clBuildProgram(prog, 1, &device, NULL, NULL, NULL);
  }

  if (ret != CL_SUCCESS) {
    char buildLog[2048] = {0};
    p_clGetProgramBuildInfo(prog, device, CL_PROGRAM_BUILD_LOG,
                            sizeof(buildLog) - 1, buildLog, NULL);
    printf("[MADAR GPU] OpenCL Build Failed:\n%s\n", buildLog);
    p_clReleaseProgram(prog);
    p_clReleaseCommandQueue(queue);
    p_clReleaseContext(ctx);
    return 0;
  }

  kQ4 = p_clCreateKernel(prog, "matvec_q4_0_kernel", &ret);
  kQ4_1 = p_clCreateKernel(prog, "matvec_q4_1_kernel", &ret);
  kQ8 = p_clCreateKernel(prog, "matvec_q8_0_kernel", &ret);
  kQ6 = p_clCreateKernel(prog, "matvec_q6_k_kernel", &ret);
  kQ4Batch = p_clCreateKernel(prog, "gemv_batch_q4_0_kernel", &ret);
  kSiLUBatch = p_clCreateKernel(prog, "silu_mul_batch_kernel", &ret);
  kI2_S = p_clCreateKernel(prog, "matvec_i2_s_kernel", &ret);
  kI2_SBatch = p_clCreateKernel(prog, "gemv_batch_i2_s_kernel", &ret);

  p_clReleaseProgram(prog);

  size_t maxBatch = 32;
  size_t maxK = (pModel->config.nFF > pModel->config.nEmbd)
                    ? pModel->config.nFF
                    : pModel->config.nEmbd;
  if (maxK < 16384)
    maxK = 16384;
  size_t maxN = pModel->config.nVocab;
  if (maxN < (size_t)pModel->config.nFF)
    maxN = pModel->config.nFF;

  size_t ffnElements = maxBatch * (size_t)pModel->config.nFF;
  if (ffnElements < 32768)
    ffnElements = 32768;

  cl_mem bufX = p_clCreateBuffer(ctx, CL_MEM_READ_WRITE,
                                 maxBatch * maxK * sizeof(float), NULL, &ret);
  cl_mem bufY = p_clCreateBuffer(ctx, CL_MEM_READ_WRITE,
                                 maxBatch * maxN * sizeof(float), NULL, &ret);
  bufGate = p_clCreateBuffer(ctx, CL_MEM_READ_WRITE,
                             ffnElements * sizeof(float), NULL, &ret);
  bufUp = p_clCreateBuffer(ctx, CL_MEM_READ_WRITE, ffnElements * sizeof(float),
                           NULL, &ret);
  bufDown = p_clCreateBuffer(ctx, CL_MEM_READ_WRITE,
                             maxBatch * pModel->config.nEmbd * sizeof(float),
                             NULL, &ret);

  if (!bufX || !bufY || !bufGate || !bufUp || !bufDown) {
    if (kQ4)
      p_clReleaseKernel(kQ4);
    if (kQ4_1)
      p_clReleaseKernel(kQ4_1);
    if (kQ8)
      p_clReleaseKernel(kQ8);
    if (kQ6)
      p_clReleaseKernel(kQ6);
    if (kQ4Batch)
      p_clReleaseKernel(kQ4Batch);
    if (kSiLUBatch)
      p_clReleaseKernel(kSiLUBatch);
    if (kI2_S)
      p_clReleaseKernel(kI2_S);
    if (kI2_SBatch)
      p_clReleaseKernel(kI2_SBatch);
    if (bufX)
      p_clReleaseMemObject(bufX);
    if (bufY)
      p_clReleaseMemObject(bufY);
    if (bufGate)
      p_clReleaseMemObject(bufGate);
    if (bufUp)
      p_clReleaseMemObject(bufUp);
    if (bufDown)
      p_clReleaseMemObject(bufDown);
    p_clReleaseCommandQueue(queue);
    p_clReleaseContext(ctx);
    return 0;
  }

  pModel->pGPUContext = ctx;
  pModel->pGPUQueue = queue;
  pModel->pGPUKernelQ4 = kQ4;
  pModel->pGPUKernelQ4_1 = kQ4_1;
  pModel->pGPUKernelQ8 = kQ8;
  pModel->pGPUKernelQ6 = kQ6;
  pModel->pGPUKernelQ4Batch = kQ4Batch;
  pModel->pGPUKernelSiLUBatch = kSiLUBatch;
  pModel->pGPUKernelI2_S = kI2_S;
  pModel->pGPUKernelI2_SBatch = kI2_SBatch;
  pModel->pGPUBufX = bufX;
  pModel->pGPUBufY = bufY;
  pModel->pGPUBufGate = bufGate;
  pModel->pGPUBufUp = bufUp;
  pModel->pGPUBufDown = bufDown;
  pModel->nGPUBufXSize = maxBatch * maxK;
  pModel->nGPUBufYSize = maxBatch * maxN;
  pModel->nGPUBufFFNSize = ffnElements;

  /* Pre-map the huge Output (LM Head) weight tensor to zero-copy GPU memory */
  if (pModel->pOutput) {
    const void *pOutData =
        ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pOutput);
    if (pOutData && pModel->pOutput->nSize > 0) {
      cl_mem bufOut = p_clCreateBuffer(
          ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
          (size_t)pModel->pOutput->nSize, (void *)pOutData, &ret);
      if (ret == CL_SUCCESS && bufOut) {
        pModel->pGPUBufOutputWeight = bufOut;
      }
    }
  }

  /* Pre-map FFN weights (Gate, Up, Down) for all layers to zero-copy GPU memory
   * (Q4_0 models) */
  if (pModel->aLayers) {
    for (uint32_t l = 0; l < pModel->config.nLayers; l++) {
      RingLayerWeights *layer = &pModel->aLayers[l];
      if (layer->pFFNGate && layer->pFFNGate->nType == RING_GGUF_TENSOR_Q4_0 &&
          layer->pFFNGate->nSize > 0) {
        const void *pData =
            ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNGate);
        if (pData) {
          layer->pGPUBufGate = (void *)p_clCreateBuffer(
              ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
              (size_t)layer->pFFNGate->nSize, (void *)pData, &ret);
          if (ret != CL_SUCCESS)
            layer->pGPUBufGate = NULL;
        }
      }
      if (layer->pFFNUp && layer->pFFNUp->nType == RING_GGUF_TENSOR_Q4_0 &&
          layer->pFFNUp->nSize > 0) {
        const void *pData =
            ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNUp);
        if (pData) {
          layer->pGPUBufUp = (void *)p_clCreateBuffer(
              ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
              (size_t)layer->pFFNUp->nSize, (void *)pData, &ret);
          if (ret != CL_SUCCESS)
            layer->pGPUBufUp = NULL;
        }
      }
      if (layer->pFFNDown && layer->pFFNDown->nType == RING_GGUF_TENSOR_Q4_0 &&
          layer->pFFNDown->nSize > 0) {
        const void *pData =
            ring_gguf_get_tensor_data(pModel->pGGUF, layer->pFFNDown);
        if (pData) {
          layer->pGPUBufDown = (void *)p_clCreateBuffer(
              ctx, CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
              (size_t)layer->pFFNDown->nSize, (void *)pData, &ret);
          if (ret != CL_SUCCESS)
            layer->pGPUBufDown = NULL;
        }
      }
    }
  }

  pModel->bGPUEnabled = 1;
  printf("  [Madar GPU] Acceleration Active: %s (Zero-Copy LM Head + %u FFN "
         "Layers)\n",
         devName, pModel->config.nLayers);
  return 1;
}

static int madar_gpu_matvec(RingModel *pModel, RingGGUFTensorInfo *pInfo,
                            cl_mem bufW, const float *x, float *y,
                            RingGGUFTensorInfo *pBiasInfo) {
  if (!pModel || !pModel->bGPUEnabled || !pInfo || !x || !y)
    return 0;

  cl_command_queue queue = (cl_command_queue)pModel->pGPUQueue;
  cl_kernel kernel = NULL;

  if (pInfo->nType == RING_GGUF_TENSOR_Q4_0) {
    kernel = (cl_kernel)pModel->pGPUKernelQ4;
  } else if (pInfo->nType == RING_GGUF_TENSOR_Q4_1) {
    kernel = (cl_kernel)pModel->pGPUKernelQ4_1;
  } else if (pInfo->nType == RING_GGUF_TENSOR_Q8_0) {
    kernel = (cl_kernel)pModel->pGPUKernelQ8;
  } else if (pInfo->nType == RING_GGUF_TENSOR_Q6_K) {
    kernel = (cl_kernel)pModel->pGPUKernelQ6;
  } else if (pInfo->nType == RING_GGUF_TENSOR_I2_S) {
    kernel = (cl_kernel)pModel->pGPUKernelI2_S;
  } else {
    return 0;
  }

  if (!kernel)
    return 0;

  int K = (int)pInfo->aDims[0];
  int N = (int)pInfo->aDims[1];

  if ((size_t)K > pModel->nGPUBufXSize || (size_t)N > pModel->nGPUBufYSize)
    return 0;

  if (!bufW) {
    if (pInfo == pModel->pOutput && pModel->pGPUBufOutputWeight) {
      bufW = (cl_mem)pModel->pGPUBufOutputWeight;
    }
  }
  if (!bufW)
    return 0;

  cl_mem bufX = (cl_mem)pModel->pGPUBufX;
  cl_mem bufY = (cl_mem)pModel->pGPUBufY;

  /* 1. Write X vector to GPU */
  cl_int ret = p_clEnqueueWriteBuffer(queue, bufX, CL_FALSE, 0,
                                      K * sizeof(float), x, 0, NULL, NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 2. Set Kernel Arguments */
  p_clSetKernelArg(kernel, 0, sizeof(cl_mem), &bufW);
  p_clSetKernelArg(kernel, 1, sizeof(cl_mem), &bufX);
  p_clSetKernelArg(kernel, 2, sizeof(cl_mem), &bufY);
  p_clSetKernelArg(kernel, 3, sizeof(int), &K);
  p_clSetKernelArg(kernel, 4, sizeof(int), &N);

  /* 3. Launch 1D Grid across N output elements with balanced workgroup size */
  size_t localSize = 64;
  size_t globalSize = ((size_t)N + localSize - 1) / localSize * localSize;
  ret = p_clEnqueueNDRangeKernel(queue, kernel, 1, NULL, &globalSize,
                                 &localSize, 0, NULL, NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 4. Read result back into y */
  ret = p_clEnqueueReadBuffer(queue, bufY, CL_TRUE, 0, N * sizeof(float), y, 0,
                              NULL, NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 5. Add bias if present */
  if (pBiasInfo) {
    const void *pBias = ring_gguf_get_tensor_data(pModel->pGGUF, pBiasInfo);
    if (pBias) {
      if (pBiasInfo->nType == RING_GGUF_TENSOR_F16) {
        const ggml_fp16_t *f16 = (const ggml_fp16_t *)pBias;
        for (int r = 0; r < N; r++)
          y[r] += fast_fp16_to_fp32(f16[r]);
      } else {
        const float *f32 = (const float *)pBias;
        for (int r = 0; r < N; r++)
          y[r] += f32[r];
      }
    }
  }

  return 1;
}

static void madar_gpu_cleanup(RingModel *pModel) {
  if (!pModel || !pModel->bGPUEnabled)
    return;

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
  if (pModel->pGPUBufGate) {
    p_clReleaseMemObject((cl_mem)pModel->pGPUBufGate);
    pModel->pGPUBufGate = NULL;
  }
  if (pModel->pGPUBufUp) {
    p_clReleaseMemObject((cl_mem)pModel->pGPUBufUp);
    pModel->pGPUBufUp = NULL;
  }
  if (pModel->pGPUBufDown) {
    p_clReleaseMemObject((cl_mem)pModel->pGPUBufDown);
    pModel->pGPUBufDown = NULL;
  }
  if (pModel->pGPUKernelQ4) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ4);
    pModel->pGPUKernelQ4 = NULL;
  }
  if (pModel->pGPUKernelQ4_1) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ4_1);
    pModel->pGPUKernelQ4_1 = NULL;
  }
  if (pModel->pGPUKernelQ8) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ8);
    pModel->pGPUKernelQ8 = NULL;
  }
  if (pModel->pGPUKernelQ6) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ6);
    pModel->pGPUKernelQ6 = NULL;
  }
  if (pModel->pGPUKernelQ4Batch) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelQ4Batch);
    pModel->pGPUKernelQ4Batch = NULL;
  }
  if (pModel->pGPUKernelSiLUBatch) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelSiLUBatch);
    pModel->pGPUKernelSiLUBatch = NULL;
  }
  if (pModel->pGPUKernelI2_S) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelI2_S);
    pModel->pGPUKernelI2_S = NULL;
  }
  if (pModel->pGPUKernelI2_SBatch) {
    p_clReleaseKernel((cl_kernel)pModel->pGPUKernelI2_SBatch);
    pModel->pGPUKernelI2_SBatch = NULL;
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

static int madar_gpu_ffn_fused_batch(RingModel *pModel, RingLayerWeights *layer,
                                     const float *x, float *y, int B) {
  cl_command_queue queue;
  cl_kernel kGEMV, kSiLU;
  cl_mem bufW_Gate, bufW_Up, bufW_Down;
  cl_mem bufX, bufGate, bufUp, bufDown;
  int nEmbd, nFF, totalElements;
  size_t globalSize[2], localSize[2];
  size_t globalSiLU, localSiLU;
  size_t globalDown[2];
  cl_int ret;

  if (!pModel || !pModel->bGPUEnabled || !layer || !x || !y || B <= 0)
    return 0;
  if (!layer->pGPUBufGate || !layer->pGPUBufUp || !layer->pGPUBufDown)
    return 0;
  if (!pModel->pGPUKernelQ4Batch || !pModel->pGPUKernelSiLUBatch)
    return 0;

  if (layer->pFFNGate->nType != RING_GGUF_TENSOR_Q4_0 ||
      layer->pFFNUp->nType != RING_GGUF_TENSOR_Q4_0 ||
      layer->pFFNDown->nType != RING_GGUF_TENSOR_Q4_0) {
    return 0;
  }

  queue = (cl_command_queue)pModel->pGPUQueue;
  kGEMV = (cl_kernel)pModel->pGPUKernelQ4Batch;
  kSiLU = (cl_kernel)pModel->pGPUKernelSiLUBatch;

  bufW_Gate = (cl_mem)layer->pGPUBufGate;
  bufW_Up = (cl_mem)layer->pGPUBufUp;
  bufW_Down = (cl_mem)layer->pGPUBufDown;

  bufX = (cl_mem)pModel->pGPUBufX;
  bufGate = (cl_mem)pModel->pGPUBufGate;
  bufUp = (cl_mem)pModel->pGPUBufUp;
  bufDown = (cl_mem)pModel->pGPUBufDown;

  nEmbd = (int)pModel->config.nEmbd;
  nFF = (int)pModel->config.nFF;

  /* 1. Asynchronously write X batch to GPU (Single non-blocking transfer) */
  ret = p_clEnqueueWriteBuffer(queue, bufX, CL_FALSE, 0,
                               (size_t)B * nEmbd * sizeof(float), x, 0, NULL,
                               NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 2. Gate MatVec: bufX (B x nEmbd) * W_gate -> bufGate (B x nFF) */
  p_clSetKernelArg(kGEMV, 0, sizeof(cl_mem), &bufW_Gate);
  p_clSetKernelArg(kGEMV, 1, sizeof(cl_mem), &bufX);
  p_clSetKernelArg(kGEMV, 2, sizeof(cl_mem), &bufGate);
  p_clSetKernelArg(kGEMV, 3, sizeof(int), &nEmbd);
  p_clSetKernelArg(kGEMV, 4, sizeof(int), &nFF);
  p_clSetKernelArg(kGEMV, 5, sizeof(int), &B);

  localSize[0] = 64;
  localSize[1] = 1;
  globalSize[0] = ((size_t)nFF + 63) / 64 * 64;
  globalSize[1] = (size_t)B;

  ret = p_clEnqueueNDRangeKernel(queue, kGEMV, 2, NULL, globalSize, localSize,
                                 0, NULL, NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 3. Up MatVec: bufX (B x nEmbd) * W_up -> bufUp (B x nFF) */
  p_clSetKernelArg(kGEMV, 0, sizeof(cl_mem), &bufW_Up);
  p_clSetKernelArg(kGEMV, 1, sizeof(cl_mem), &bufX);
  p_clSetKernelArg(kGEMV, 2, sizeof(cl_mem), &bufUp);
  p_clSetKernelArg(kGEMV, 3, sizeof(int), &nEmbd);
  p_clSetKernelArg(kGEMV, 4, sizeof(int), &nFF);
  p_clSetKernelArg(kGEMV, 5, sizeof(int), &B);

  ret = p_clEnqueueNDRangeKernel(queue, kGEMV, 2, NULL, globalSize, localSize,
                                 0, NULL, NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 4. Elementwise SiLU-Mul on GPU: bufGate = silu(bufGate) * bufUp */
  totalElements = B * nFF;
  p_clSetKernelArg(kSiLU, 0, sizeof(cl_mem), &bufGate);
  p_clSetKernelArg(kSiLU, 1, sizeof(cl_mem), &bufUp);
  p_clSetKernelArg(kSiLU, 2, sizeof(int), &totalElements);

  localSiLU = 64;
  globalSiLU = ((size_t)totalElements + 63) / 64 * 64;

  ret = p_clEnqueueNDRangeKernel(queue, kSiLU, 1, NULL, &globalSiLU, &localSiLU,
                                 0, NULL, NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 5. Down MatVec: bufGate (B x nFF) * W_down -> bufDown (B x nEmbd) */
  p_clSetKernelArg(kGEMV, 0, sizeof(cl_mem), &bufW_Down);
  p_clSetKernelArg(kGEMV, 1, sizeof(cl_mem), &bufGate);
  p_clSetKernelArg(kGEMV, 2, sizeof(cl_mem), &bufDown);
  p_clSetKernelArg(kGEMV, 3, sizeof(int), &nFF);
  p_clSetKernelArg(kGEMV, 4, sizeof(int), &nEmbd);
  p_clSetKernelArg(kGEMV, 5, sizeof(int), &B);

  globalDown[0] = ((size_t)nEmbd + 63) / 64 * 64;
  globalDown[1] = (size_t)B;

  ret = p_clEnqueueNDRangeKernel(queue, kGEMV, 2, NULL, globalDown, localSize,
                                 0, NULL, NULL);
  if (ret != CL_SUCCESS)
    return 0;

  /* 6. Single blocking read of the final output (Only B x nEmbd floats) */
  ret = p_clEnqueueReadBuffer(queue, bufDown, CL_TRUE, 0,
                              (size_t)B * nEmbd * sizeof(float), y, 0, NULL,
                              NULL);
  if (ret != CL_SUCCESS)
    return 0;

  return 1;
}

static inline int madar_gpu_ffn_fused(RingModel *pModel,
                                      RingLayerWeights *layer, const float *x,
                                      float *y) {
  return madar_gpu_ffn_fused_batch(pModel, layer, x, y, 1);
}

static void matvec_multiply_gpu(RingModel *pModel, RingGGUFTensorInfo *pInfo,
                                void *pGPUBuf, const float *x, float *y,
                                RingGGUFTensorInfo *pBiasInfo) {
  int K, N;
  const float *pBias;
  MatVecTask task;
  int nTotalThreads, nWorkers, nChunk, i;

  if (!pModel || !pInfo || !x || !y)
    return;

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

  /* Adaptive multi-threading:
     Distribute across worker threads if N >= 512 and total ops >= 1,500,000.
     For smaller matrices (e.g. Attn K/V projections), executing directly on
     the calling core with AVX2 FMA is faster than the round-trip latency of
     thread synchronization. */
  if (pModel->nThreads >= 2 && N >= 512 && ((int64_t)N * K >= 1500000) &&
      pModel->nWorkerCount > 0) {
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
#ifdef _WIN32
      SetEvent((HANDLE)pModel->hStartEvents[i]);
#else
      sem_post((sem_t *)pModel->hStartEvents[i]);
#endif
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
#ifdef _WIN32
    WaitForMultipleObjects((DWORD)nWorkers, (const HANDLE *)pModel->hDoneEvents,
                           TRUE, INFINITE);
#else
    for (i = 0; i < nWorkers; i++) {
      sem_wait((sem_t *)pModel->hDoneEvents[i]);
    }
#endif
    return;
  }

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

static void matvec_multiply(RingModel *pModel, RingGGUFTensorInfo *pInfo,
                            const float *x, float *y,
                            RingGGUFTensorInfo *pBiasInfo) {
  matvec_multiply_gpu(pModel, pInfo, NULL, x, y, pBiasInfo);

  /* LoRA Adapter Fusion (Zero-Copy Native Merge) */
  if (pModel && pModel->bLoRAEnabled && pModel->pLoRA_A_Q && pInfo &&
      pInfo->pName) {
    const char *pName = pInfo->pName;
    const float *pA = NULL;
    const float *pB = NULL;

    if (strstr(pName, "attn_q") || strstr(pName, "q_proj")) {
      pA = pModel->pLoRA_A_Q;
      pB = pModel->pLoRA_B_Q;
    } else if (strstr(pName, "attn_v") || strstr(pName, "v_proj")) {
      pA = pModel->pLoRA_A_V;
      pB = pModel->pLoRA_B_V;
    } else if (strstr(pName, "attn_output") || strstr(pName, "attn_out") ||
               strstr(pName, "out_proj")) {
      pA = pModel->pLoRA_A_Out;
      pB = pModel->pLoRA_B_Out;
    }

    if (pA && pB) {
      int r = pModel->nLoRARank;
      int inDim = (int)pInfo->aDims[0];
      int outDim = (int)pInfo->aDims[1];
      float scale = pModel->fLoRAScale;
      float *h = pModel->pLoRA_Scratch;
      int i, j;

      /* 1. Low-rank projection: h = A * x (Rank x 1) */
      for (i = 0; i < r; i++) {
        const float *pRowA = pA + (size_t)i * inDim;
        float sum = 0.0f;
        for (j = 0; j < inDim; j++) {
          sum += pRowA[j] * x[j];
        }
        h[i] = sum;
      }

      /* 2. Residual delta projection: y += scale * (B * h) */
      for (i = 0; i < outDim; i++) {
        const float *pRowB = pB + (size_t)i * r;
        float sum = 0.0f;
        for (j = 0; j < r; j++) {
          sum += pRowB[j] * h[j];
        }
        y[i] += scale * sum;
      }
    }
  }
}

/*
================================================================================
  Neural Operations: RMSNorm, LayerNorm, RoPE, Softmax, SiLU, GELU
================================================================================
*/

static void layernorm(float *o, const float *x, const float *weight,
                      const float *bias, int size, float eps) {
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
  for (; i < size; i++)
    sum += x[i];
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
    if (weight)
      val = _mm256_mul_ps(val, _mm256_loadu_ps(weight + i));
    if (bias)
      val = _mm256_add_ps(val, _mm256_loadu_ps(bias + i));
    _mm256_storeu_ps(o + i, val);
  }
#endif
  for (; i < size; i++) {
    float val = (x[i] - mean) * inv;
    if (weight)
      val *= weight[i];
    if (bias)
      val += bias[i];
    o[i] = val;
  }
}

static inline float fast_gelu(float x) {
  float x3 = x * x * x;
  return 0.5f * x * (1.0f + tanhf(0.79788456f * (x + 0.044715f * x3)));
}

static void rmsnorm(float *o, const float *x, const float *weight, int size,
                    float eps) {
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
  for (; i < size; i++)
    ss += x[i] * x[i];
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
    for (; i < size; i++)
      o[i] = x[i] * inv * weight[i];
  } else {
    for (; i < size; i++)
      o[i] = x[i] * inv;
  }
}

static void apply_rope(float *vec, int nHeads, int headDim, int pos,
                       float freqBase) {
  int h, i;
  float *head;
  float freq, val, v0, v1;
  int half = headDim / 2;
  float aCos[128], aSin[128];

  if (half > 128)
    half = 128;

  /* Precompute trigonometric values once per layer instead of redundantly for
   * each head */
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
      head[i] = v0 * aCos[i] - v1 * aSin[i];
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
    if (x[i] > maxVal)
      maxVal = x[i];
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
  if (!kv)
    return defVal;
  switch (kv->value.nType) {
  case RING_GGUF_TYPE_UINT32:
    return kv->value.val.u32;
  case RING_GGUF_TYPE_INT32:
    return (uint32_t)kv->value.val.i32;
  case RING_GGUF_TYPE_UINT64:
    return (uint32_t)kv->value.val.u64;
  case RING_GGUF_TYPE_INT64:
    return (uint32_t)kv->value.val.i64;
  case RING_GGUF_TYPE_UINT16:
    return (uint32_t)kv->value.val.u16;
  case RING_GGUF_TYPE_INT16:
    return (uint32_t)kv->value.val.i16;
  default:
    return defVal;
  }
}

static float gguf_get_f32_val(RingGGUFKV *kv, float defVal) {
  if (!kv)
    return defVal;
  if (kv->value.nType == RING_GGUF_TYPE_FLOAT32)
    return kv->value.val.f32;
  if (kv->value.nType == RING_GGUF_TYPE_FLOAT64)
    return (float)kv->value.val.f64;
  if (kv->value.nType == RING_GGUF_TYPE_UINT32)
    return (float)kv->value.val.u32;
  if (kv->value.nType == RING_GGUF_TYPE_INT32)
    return (float)kv->value.val.i32;
  if (kv->value.nType == RING_GGUF_TYPE_UINT64)
    return (float)kv->value.val.u64;
  if (kv->value.nType == RING_GGUF_TYPE_INT64)
    return (float)kv->value.val.i64;
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
    printf("\n[MADAR AI] Error: ring_gguf_open failed to open '%s'!\n",
           cFileName);
    return NULL;
  }

  pTok = ring_tokenizer_create(pGGUF);
  if (!pTok) {
    printf("\n[MADAR AI] Error: ring_tokenizer_create failed for '%s'!\n",
           cFileName);
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
    strncpy(pModel->config.cArch, kv->value.val.str.pStr,
            sizeof(pModel->config.cArch) - 1);
  } else {
    strcpy(pModel->config.cArch, "qwen2");
  }

  arch = pModel->config.cArch;
  pModel->config.bIsBert =
      (strcmp(arch, "bert") == 0 || strcmp(arch, "xlm-roberta") == 0 ||
       strcmp(arch, "roberta") == 0);
  pModel->config.bIsBitNet =
      (strcmp(arch, "bitnet-b1.58") == 0 || strcmp(arch, "bitnet") == 0);

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
  if (!kv)
    kv = ring_gguf_find_kv(pGGUF, "attention.head_count");
  pModel->config.nHeads = gguf_get_u32_val(kv, 14);

  snprintf(key, sizeof(key), "%s.attention.head_count_kv", arch);
  kv = ring_gguf_find_kv(pGGUF, key);
  if (!kv)
    kv = ring_gguf_find_kv(pGGUF, "attention.head_count_kv");
  pModel->config.nHeadsKV = gguf_get_u32_val(kv, pModel->config.nHeads);

  snprintf(key, sizeof(key), "%s.attention.key_length", arch);
  kv = ring_gguf_find_kv(pGGUF, key);
  if (kv) {
    pModel->config.nHeadDim = gguf_get_u32_val(kv, 64);
  } else {
    pModel->config.nHeadDim =
        pModel->config.nHeads > 0
            ? (pModel->config.nEmbd / pModel->config.nHeads)
            : 64;
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
  if (!pModel->pTokenEmbd)
    pModel->pTokenEmbd =
        ring_gguf_find_tensor(pGGUF, "model.embed_tokens.weight");

  if (pModel->config.bIsBert) {
    pModel->pPosEmbd = ring_gguf_find_tensor(pGGUF, "position_embd.weight");
    pModel->pTokenTypes = ring_gguf_find_tensor(pGGUF, "token_types.weight");
    pModel->pTokenEmbdNorm =
        ring_gguf_find_tensor(pGGUF, "token_embd_norm.weight");
    pModel->pTokenEmbdNorm_Bias =
        ring_gguf_find_tensor(pGGUF, "token_embd_norm.bias");
    if (pModel->pPosEmbd && pModel->pPosEmbd->aDims[1] > 0) {
      pModel->config.nCtx = (uint32_t)pModel->pPosEmbd->aDims[1];
    }
  }

  pModel->pOutputNorm = ring_gguf_find_tensor(pGGUF, "output_norm.weight");
  if (!pModel->pOutputNorm)
    pModel->pOutputNorm = ring_gguf_find_tensor(pGGUF, "model.norm.weight");

  pModel->pOutput = ring_gguf_find_tensor(pGGUF, "output.weight");
  if (!pModel->pOutput)
    pModel->pOutput = ring_gguf_find_tensor(pGGUF, "lm_head.weight");
  if (!pModel->pOutput) {
    pModel->pOutput = pModel->pTokenEmbd;
  }

  /* If output tensor has an unsupported quantized type, fall back to tied
   * token_embd */
  if (pModel->pOutput && pModel->pOutput->nType != RING_GGUF_TENSOR_Q4_0 &&
      pModel->pOutput->nType != RING_GGUF_TENSOR_Q4_1 &&
      pModel->pOutput->nType != RING_GGUF_TENSOR_Q8_0 &&
      pModel->pOutput->nType != RING_GGUF_TENSOR_Q6_K &&
      pModel->pOutput->nType != RING_GGUF_TENSOR_I2_S &&
      pModel->pOutput->nType != RING_GGUF_TENSOR_F16 &&
      pModel->pOutput->nType != RING_GGUF_TENSOR_F32) {
    if (pModel->pTokenEmbd &&
        (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0 ||
         pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_1 ||
         pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0 ||
         pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q6_K ||
         pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_I2_S ||
         pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16 ||
         pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F32)) {
      printf("  [Info] output.weight type (%u) not supported. Using tied "
             "token_embd.weight (%s)\n",
             pModel->pOutput->nType,
             ring_gguf_tensor_type_name(pModel->pTokenEmbd->nType));
      pModel->pOutput = pModel->pTokenEmbd;
    }
  }

  if (!pModel->pTokenEmbd) {
    printf("\n[MADAR AI] Error: Token embedding tensor (token_embd.weight) not "
           "found in GGUF!\n");
    ring_model_free(pModel);
    return NULL;
  }
  if (!pModel->pOutputNorm && !pModel->config.bIsBert) {
    printf("\n[MADAR AI] Error: Output norm tensor (output_norm.weight) not "
           "found in GGUF!\n");
    ring_model_free(pModel);
    return NULL;
  }

  pModel->aLayers = (RingLayerWeights *)calloc(pModel->config.nLayers,
                                               sizeof(RingLayerWeights));
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

    snprintf(key, sizeof(key), "blk.%u.attn_sub_norm.weight", l);
    pModel->aLayers[l].pAttnSubNorm = ring_gguf_find_tensor(pGGUF, key);
    if (!pModel->aLayers[l].pAttnSubNorm) {
      snprintf(key, sizeof(key),
               "model.layers.%u.self_attn.inner_attn_ln.weight", l);
      pModel->aLayers[l].pAttnSubNorm = ring_gguf_find_tensor(pGGUF, key);
    }

    snprintf(key, sizeof(key), "blk.%u.ffn_norm.weight", l);
    pModel->aLayers[l].pFFNNorm = ring_gguf_find_tensor(pGGUF, key);
    if (!pModel->aLayers[l].pFFNNorm) {
      snprintf(key, sizeof(key), "blk.%u.layer_output_norm.weight", l);
      pModel->aLayers[l].pFFNNorm = ring_gguf_find_tensor(pGGUF, key);
    }
    if (!pModel->aLayers[l].pFFNNorm) {
      snprintf(key, sizeof(key),
               "model.layers.%u.post_attention_layernorm.weight", l);
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

    snprintf(key, sizeof(key), "blk.%u.ffn_sub_norm.weight", l);
    pModel->aLayers[l].pFFNSubNorm = ring_gguf_find_tensor(pGGUF, key);
    if (!pModel->aLayers[l].pFFNSubNorm) {
      snprintf(key, sizeof(key), "model.layers.%u.mlp.ffn_layernorm.weight", l);
      pModel->aLayers[l].pFFNSubNorm = ring_gguf_find_tensor(pGGUF, key);
    }

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
    printf("\n[MADAR AI] Error: Layer 0 attention Q weights not found in "
           "GGUF!\n");
    ring_model_free(pModel);
    return NULL;
  }

  /* Determine Optimal Context Length by Model Architecture & Size */
  {
    char ctxKey[128];
    RingGGUFKV *kvCtx = NULL;
    uint32_t nGGUFContext = 0;

    snprintf(ctxKey, sizeof(ctxKey), "%s.context_length", arch);
    kvCtx = ring_gguf_find_kv(pGGUF, ctxKey);
    if (!kvCtx)
      kvCtx = ring_gguf_find_kv(pGGUF, "context_length");
    if (kvCtx)
      nGGUFContext = gguf_get_u32_val(kvCtx, 0);

    if (pModel->config.bIsBert) {
      if (pModel->pPosEmbd && pModel->pPosEmbd->aDims[1] > 2) {
        pModel->nMaxSeq = (uint32_t)(pModel->pPosEmbd->aDims[1] - 2);
      } else if (nGGUFContext > 0) {
        pModel->nMaxSeq = nGGUFContext;
      } else {
        pModel->nMaxSeq = 512;
      }
      if (pModel->nMaxSeq > 8192)
        pModel->nMaxSeq = 8192;
    } else if (nGGUFContext > 0 && nGGUFContext <= 2048) {
      pModel->nMaxSeq = nGGUFContext;
    } else if (pModel->config.nEmbd <= 1024) {
      /* Ultra-compact models (0.5B): 4,096 tokens (4K) */
      pModel->nMaxSeq = 4096;
    } else {
      /* 1.5B, 3B, 7B, 14B & DeepSeek-R1 (Distill): 8,192 tokens (8K) */
      pModel->nMaxSeq = 8192;
    }
  }
  pModel->nKVDim = pModel->config.nHeadsKV * pModel->config.nHeadDim;
  kvSize = (size_t)pModel->config.nLayers * pModel->nMaxSeq * pModel->nKVDim;

  pModel->pKVCache_K = (ggml_fp16_t *)calloc(kvSize, sizeof(ggml_fp16_t));
  pModel->pKVCache_V = (ggml_fp16_t *)calloc(kvSize, sizeof(ggml_fp16_t));
  pModel->pAttScores = (float *)calloc(pModel->nMaxSeq, sizeof(float));

  /* Working Activation Buffers */
  pModel->pActX = (float *)calloc(pModel->config.nEmbd, sizeof(float));
  pModel->pActXB = (float *)calloc(pModel->config.nEmbd, sizeof(float));
  pModel->pActQ = (float *)calloc(
      pModel->config.nHeads * pModel->config.nHeadDim, sizeof(float));
  pModel->pActK = (float *)calloc(pModel->nKVDim, sizeof(float));
  pModel->pActV = (float *)calloc(pModel->nKVDim, sizeof(float));
  pModel->pActAttOut = (float *)calloc(
      pModel->config.nHeads * pModel->config.nHeadDim, sizeof(float));
  pModel->pActHB = (float *)calloc(pModel->config.nFF, sizeof(float));
  pModel->pActHB2 = (float *)calloc(pModel->config.nFF, sizeof(float));
  pModel->pActAttnProj = (float *)calloc(pModel->config.nEmbd, sizeof(float));
  pModel->pActFFNOut = (float *)calloc(pModel->config.nEmbd, sizeof(float));
  pModel->pLogits = (float *)calloc(pModel->config.nVocab, sizeof(float));

#ifdef _WIN32
  /* Initialize Persistent Thread Pool for Parallel Inference (Supports up to
   * 8 threads) */
  pModel->nWorkerCount = RING_MODEL_MAX_WORKERS;
  pModel->bWorkerShutdown = 0;
  {
    int i;
    for (i = 0; i < RING_MODEL_MAX_WORKERS; i++) {
      pModel->pWorkerTasks[i] = calloc(1, sizeof(MatVecTask));
      pModel->hStartEvents[i] = (void *)CreateEvent(NULL, FALSE, FALSE, NULL);
      pModel->hDoneEvents[i] = (void *)CreateEvent(NULL, FALSE, FALSE, NULL);
      if (pModel->hStartEvents[i] && pModel->hDoneEvents[i]) {
        RingWorkerParam *param =
            (RingWorkerParam *)malloc(sizeof(RingWorkerParam));
        if (param) {
          param->pModel = pModel;
          param->nIndex = i;
          pModel->hWorkerThreads[i] = (void *)CreateThread(
              NULL, 0, ring_model_worker_proc, param, 0, NULL);
          if (pModel->hWorkerThreads[i]) {
            SetThreadPriority((HANDLE)pModel->hWorkerThreads[i],
                              THREAD_PRIORITY_HIGHEST);
          }
        }
      }
    }
  }
#else
  /* Initialize Persistent POSIX Thread Pool for Parallel Inference */
  pModel->nWorkerCount = RING_MODEL_MAX_WORKERS;
  pModel->bWorkerShutdown = 0;
  {
    int i;
    for (i = 0; i < RING_MODEL_MAX_WORKERS; i++) {
      pModel->pWorkerTasks[i] = calloc(1, sizeof(MatVecTask));
      sem_t *semStart = (sem_t *)malloc(sizeof(sem_t));
      sem_t *semDone = (sem_t *)malloc(sizeof(sem_t));
      if (semStart && semDone) {
        sem_init(semStart, 0, 0);
        sem_init(semDone, 0, 0);
        pModel->hStartEvents[i] = (void *)semStart;
        pModel->hDoneEvents[i] = (void *)semDone;

        RingWorkerParam *param =
            (RingWorkerParam *)malloc(sizeof(RingWorkerParam));
        if (param) {
          param->pModel = pModel;
          param->nIndex = i;
          pthread_t th;
          if (pthread_create(&th, NULL, ring_model_worker_proc, param) == 0) {
            pModel->hWorkerThreads[i] = (void *)(intptr_t)th;
          } else {
            free(param);
            pModel->hWorkerThreads[i] = NULL;
          }
        }
      }
    }
  }
#endif

  printf("  [Model Specs] %s | L:%u | Dim:%u | Heads:%u(KV:%u) | FF:%u | "
         "Vocab:%u | Context:%u\n",
         pModel->config.cArch, pModel->config.nLayers, pModel->config.nEmbd,
         pModel->config.nHeads, pModel->config.nHeadsKV, pModel->config.nFF,
         pModel->config.nVocab, pModel->nMaxSeq);

  printf(
      "  [Tensors] Embd: %s (%s, %llux%llu) | Out: %s (%s, %llux%llu)\n",
      pModel->pTokenEmbd ? pModel->pTokenEmbd->pName : "NULL",
      pModel->pTokenEmbd ? ring_gguf_tensor_type_name(pModel->pTokenEmbd->nType)
                         : "NULL",
      pModel->pTokenEmbd ? (unsigned long long)pModel->pTokenEmbd->aDims[0]
                         : 0ULL,
      pModel->pTokenEmbd ? (unsigned long long)pModel->pTokenEmbd->aDims[1]
                         : 0ULL,
      pModel->pOutput ? pModel->pOutput->pName : "NULL",
      pModel->pOutput ? ring_gguf_tensor_type_name(pModel->pOutput->nType)
                      : "NULL",
      pModel->pOutput ? (unsigned long long)pModel->pOutput->aDims[0] : 0ULL,
      pModel->pOutput ? (unsigned long long)pModel->pOutput->aDims[1] : 0ULL);

  /* Initialize GPU Acceleration (OpenCL Engine) */
  madar_gpu_init(pModel);

  return pModel;
}

RING_API void ring_model_free(RingModel *pModel) {
  if (!pModel)
    return;

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
#else
  pModel->bWorkerShutdown = 1;
  {
    int i;
    for (i = 0; i < pModel->nWorkerCount; i++) {
      if (pModel->hStartEvents[i]) {
        sem_post((sem_t *)pModel->hStartEvents[i]);
      }
    }
    for (i = 0; i < pModel->nWorkerCount; i++) {
      if (pModel->hWorkerThreads[i]) {
        pthread_join((pthread_t)(intptr_t)pModel->hWorkerThreads[i], NULL);
        pModel->hWorkerThreads[i] = NULL;
      }
      if (pModel->hStartEvents[i]) {
        sem_destroy((sem_t *)pModel->hStartEvents[i]);
        free(pModel->hStartEvents[i]);
        pModel->hStartEvents[i] = NULL;
      }
      if (pModel->hDoneEvents[i]) {
        sem_destroy((sem_t *)pModel->hDoneEvents[i]);
        free(pModel->hDoneEvents[i]);
        pModel->hDoneEvents[i] = NULL;
      }
      if (pModel->pWorkerTasks[i]) {
        free(pModel->pWorkerTasks[i]);
        pModel->pWorkerTasks[i] = NULL;
      }
    }
  }
#endif

  if (pModel->pKVCache_K)
    free(pModel->pKVCache_K);
  if (pModel->pKVCache_V)
    free(pModel->pKVCache_V);
  if (pModel->pAttScores)
    free(pModel->pAttScores);

  if (pModel->pActX)
    free(pModel->pActX);
  if (pModel->pActXB)
    free(pModel->pActXB);
  if (pModel->pActQ)
    free(pModel->pActQ);
  if (pModel->pActK)
    free(pModel->pActK);
  if (pModel->pActV)
    free(pModel->pActV);
  if (pModel->pActAttOut)
    free(pModel->pActAttOut);
  if (pModel->pActHB)
    free(pModel->pActHB);
  if (pModel->pActHB2)
    free(pModel->pActHB2);
  if (pModel->pActAttnProj)
    free(pModel->pActAttnProj);
  if (pModel->pActFFNOut)
    free(pModel->pActFFNOut);
  if (pModel->pLogits)
    free(pModel->pLogits);

  if (pModel->aLayers)
    free(pModel->aLayers);
  if (pModel->pTokenizer)
    ring_tokenizer_delete(pModel->pTokenizer);
  if (pModel->pGGUF)
    ring_gguf_close(pModel->pGGUF);

  /* Clean up LoRA adapter memory */
  if (pModel->pLoRA_A_Q)
    free(pModel->pLoRA_A_Q);
  if (pModel->pLoRA_B_Q)
    free(pModel->pLoRA_B_Q);
  if (pModel->pLoRA_A_V)
    free(pModel->pLoRA_A_V);
  if (pModel->pLoRA_B_V)
    free(pModel->pLoRA_B_V);
  if (pModel->pLoRA_A_Out)
    free(pModel->pLoRA_A_Out);
  if (pModel->pLoRA_B_Out)
    free(pModel->pLoRA_B_Out);
  if (pModel->pLoRA_Scratch)
    free(pModel->pLoRA_Scratch);

  /* Clean up Multi-Layer LoRA memory */
  if (pModel->aLoRALayers) {
    RingLoRALayerAdapter *pAdapters =
        (RingLoRALayerAdapter *)pModel->aLoRALayers;
    for (uint32_t l = 0; l < pModel->config.nLayers; l++) {
      if (pAdapters[l].pA_Q)
        free(pAdapters[l].pA_Q);
      if (pAdapters[l].pB_Q)
        free(pAdapters[l].pB_Q);
      if (pAdapters[l].pA_Out)
        free(pAdapters[l].pA_Out);
      if (pAdapters[l].pB_Out)
        free(pAdapters[l].pB_Out);
      if (pAdapters[l].pdA_Q)
        free(pAdapters[l].pdA_Q);
      if (pAdapters[l].pdB_Q)
        free(pAdapters[l].pdB_Q);
      if (pAdapters[l].pdA_Out)
        free(pAdapters[l].pdA_Out);
      if (pAdapters[l].pdB_Out)
        free(pAdapters[l].pdB_Out);
      if (pAdapters[l].pMA_Q)
        free(pAdapters[l].pMA_Q);
      if (pAdapters[l].pVA_Q)
        free(pAdapters[l].pVA_Q);
      if (pAdapters[l].pMB_Q)
        free(pAdapters[l].pMB_Q);
      if (pAdapters[l].pVB_Q)
        free(pAdapters[l].pVB_Q);
      if (pAdapters[l].pMA_Out)
        free(pAdapters[l].pMA_Out);
      if (pAdapters[l].pVA_Out)
        free(pAdapters[l].pVA_Out);
      if (pAdapters[l].pMB_Out)
        free(pAdapters[l].pMB_Out);
      if (pAdapters[l].pVB_Out)
        free(pAdapters[l].pVB_Out);
    }
    free(pModel->aLoRALayers);
    pModel->aLoRALayers = NULL;
  }
  if (pModel->pLayerActIn) {
    free(pModel->pLayerActIn);
    pModel->pLayerActIn = NULL;
  }
  if (pModel->pGradH) {
    free(pModel->pGradH);
    pModel->pGradH = NULL;
  }

  free(pModel);
}

RING_API void ring_model_set_threads(RingModel *pModel, int nThreads) {
  if (!pModel)
    return;
  if (nThreads < 1)
    nThreads = 1;
  if (nThreads > RING_MODEL_MAX_WORKERS + 1)
    nThreads = RING_MODEL_MAX_WORKERS + 1;
  pModel->nThreads = nThreads;
}

RING_API void ring_model_set_gpu(RingModel *pModel, int bEnable) {
  if (!pModel)
    return;
  pModel->bGPUEnabled = bEnable ? 1 : 0;
}

RING_API void ring_model_reset_kv(RingModel *pModel) {
  size_t kvSize;
  if (!pModel || !pModel->pKVCache_K || !pModel->pKVCache_V)
    return;
  kvSize = (size_t)pModel->config.nLayers * pModel->nMaxSeq * pModel->nKVDim;
  memset(pModel->pKVCache_K, 0, kvSize * sizeof(ggml_fp16_t));
  memset(pModel->pKVCache_V, 0, kvSize * sizeof(ggml_fp16_t));
  if (pModel->pTokenizer)
    pModel->pTokenizer->nUtf8BufLen = 0;
}

/*
================================================================================
  Multi-Layer LoRA Causal Training Engine (Native Madar AI)
================================================================================
*/

static float *read_tensor_file_to_f32(const char *cFile, int *pRows,
                                      int *pCols);

static void get_output_tensor_row_f32(RingModel *pModel, uint32_t row,
                                      float *dst) {
  RingGGUFTensorInfo *pInfo = pModel->pOutput;
  if (!pInfo || !dst)
    return;
  const uint8_t *pRaw =
      (const uint8_t *)ring_gguf_get_tensor_data(pModel->pGGUF, pInfo);
  if (!pRaw)
    return;
  int K = (int)pInfo->aDims[0];
  if (pInfo->nType == RING_GGUF_TENSOR_Q4_0) {
    const RingGGUFBlockQ4_0 *pRow =
        (const RingGGUFBlockQ4_0 *)(pRaw + (size_t)row * (K / 32) *
                                               sizeof(RingGGUFBlockQ4_0));
    ring_gguf_dequantize_q4_0(pRow, dst, K);
  } else if (pInfo->nType == RING_GGUF_TENSOR_Q6_K) {
    const RingGGUFBlockQ6_K *pRow =
        (const RingGGUFBlockQ6_K *)(pRaw + (size_t)row * (K / 256) *
                                               sizeof(RingGGUFBlockQ6_K));
    ring_gguf_dequantize_q6_k(pRow, dst, K);
  } else if (pInfo->nType == RING_GGUF_TENSOR_Q8_0) {
    const RingGGUFBlockQ8_0 *pRow =
        (const RingGGUFBlockQ8_0 *)(pRaw + (size_t)row * (K / 32) *
                                               sizeof(RingGGUFBlockQ8_0));
    ring_gguf_dequantize_q8_0(pRow, dst, K);
  } else if (pInfo->nType == RING_GGUF_TENSOR_F32) {
    memcpy(dst, (const float *)pRaw + (size_t)row * K, K * sizeof(float));
  }
}

static void save_f32_to_tensor_file(const char *cPath, const float *pData,
                                    int rows, int cols) {
  FILE *fp = fopen(cPath, "wb");
  if (!fp)
    return;
  fwrite(&rows, sizeof(int), 1, fp);
  fwrite(&cols, sizeof(int), 1, fp);
  size_t count = (size_t)rows * cols;
  double *pTemp = (double *)malloc(count * sizeof(double));
  if (pTemp) {
    for (size_t i = 0; i < count; i++)
      pTemp[i] = (double)pData[i];
    fwrite(pTemp, sizeof(double), count, fp);
    free(pTemp);
  }
  fclose(fp);
}

RING_API int ring_model_init_lora(RingModel *pModel, int nRank, float fAlpha) {
  if (!pModel)
    return 0;
  uint32_t nLayers = pModel->config.nLayers;
  int nEmbd = (int)pModel->config.nEmbd;
  if (nLayers == 0 || nEmbd == 0)
    return 0;

  if (nRank <= 0)
    nRank = 16;
  if (fAlpha <= 0.0f)
    fAlpha = 32.0f;

  pModel->nLoRARank = nRank;
  pModel->fLoRAAlpha = fAlpha;
  pModel->fLoRAScale = (fAlpha / (float)nRank) / sqrtf((float)nLayers);

  /* Allocate scratch for low-rank dot products */
  if (pModel->pLoRA_Scratch)
    free(pModel->pLoRA_Scratch);
  pModel->pLoRA_Scratch = (float *)malloc((size_t)nRank * sizeof(float));

  /* Allocate layer activations buffer (2 slots per layer: x_norm and att_out)
   */
  if (pModel->pLayerActIn)
    free(pModel->pLayerActIn);
  pModel->pLayerActIn =
      (float *)calloc((size_t)nLayers * 2 * nEmbd, sizeof(float));

  /* Allocate gradient buffer */
  if (pModel->pGradH)
    free(pModel->pGradH);
  pModel->pGradH = (float *)calloc((size_t)nEmbd, sizeof(float));

  /* Allocate layer adapters */
  RingLoRALayerAdapter *pAdapters =
      (RingLoRALayerAdapter *)calloc(nLayers, sizeof(RingLoRALayerAdapter));
  if (!pAdapters)
    return 0;

  size_t nSizeA = (size_t)nRank * nEmbd;
  size_t nSizeB = (size_t)nEmbd * nRank;
  float fBound = 0.05f;

  for (uint32_t l = 0; l < nLayers; l++) {
    RingLoRALayerAdapter *pL = &pAdapters[l];
    pL->bActive = 1;

    pL->pA_Q = (float *)malloc(nSizeA * sizeof(float));
    pL->pB_Q = (float *)calloc(nSizeB, sizeof(float)); /* zero init */
    pL->pdA_Q = (float *)calloc(nSizeA, sizeof(float));
    pL->pdB_Q = (float *)calloc(nSizeB, sizeof(float));
    pL->pMA_Q = (float *)calloc(nSizeA, sizeof(float));
    pL->pVA_Q = (float *)calloc(nSizeA, sizeof(float));
    pL->pMB_Q = (float *)calloc(nSizeB, sizeof(float));
    pL->pVB_Q = (float *)calloc(nSizeB, sizeof(float));

    pL->pA_Out = (float *)malloc(nSizeA * sizeof(float));
    pL->pB_Out = (float *)calloc(nSizeB, sizeof(float)); /* zero init */
    pL->pdA_Out = (float *)calloc(nSizeA, sizeof(float));
    pL->pdB_Out = (float *)calloc(nSizeB, sizeof(float));
    pL->pMA_Out = (float *)calloc(nSizeA, sizeof(float));
    pL->pVA_Out = (float *)calloc(nSizeA, sizeof(float));
    pL->pMB_Out = (float *)calloc(nSizeB, sizeof(float));
    pL->pVB_Out = (float *)calloc(nSizeB, sizeof(float));

    /* Initialize A matrices with small uniform random weights */
    for (size_t i = 0; i < nSizeA; i++) {
      float r = ((float)rand() / (float)RAND_MAX) * 2.0f - 1.0f;
      pL->pA_Q[i] = r * fBound;
      r = ((float)rand() / (float)RAND_MAX) * 2.0f - 1.0f;
      pL->pA_Out[i] = r * fBound;
    }
  }

  pModel->aLoRALayers = (void *)pAdapters;
  pModel->bMultiLayerLoRA = 1;
  pModel->bLoRAEnabled = 1;
  pModel->nTrainTokens = 0;
  pModel->nStepAccumTokens = 0;

  printf("[MADAR AI] Multi-Layer LoRA Engine Initialized: %d Layers | Rank: %d "
         "| Alpha: %.1f | Scale: %.4f (Depth-Scaled)\n",
         nLayers, nRank, fAlpha, pModel->fLoRAScale);
  return 1;
}

RING_API float ring_model_train_token(RingModel *pModel, int nTargetToken) {
  if (!pModel || !pModel->bMultiLayerLoRA || !pModel->aLoRALayers ||
      !pModel->pLogits)
    return 0.0f;
  uint32_t nVocab = pModel->config.nVocab;
  int nEmbd = (int)pModel->config.nEmbd;
  int nLayers = (int)pModel->config.nLayers;
  int r = pModel->nLoRARank;
  float scale = pModel->fLoRAScale;

  if (nTargetToken < 0 || (uint32_t)nTargetToken >= nVocab)
    return 0.0f;

  /* 1. Compute Softmax over Logits & Target Cross-Entropy Loss */
  float maxLogit = pModel->pLogits[0];
  for (uint32_t i = 1; i < nVocab; i++) {
    if (pModel->pLogits[i] > maxLogit)
      maxLogit = pModel->pLogits[i];
  }

  float sumExp = 0.0f;
  for (uint32_t i = 0; i < nVocab; i++) {
    float diff = pModel->pLogits[i] - maxLogit;
    if (diff > -16.0f) {
      sumExp += expf(diff);
    }
  }
  float invSum = (sumExp > 0.0f) ? (1.0f / sumExp) : 0.0f;

  float pTarget = expf(pModel->pLogits[nTargetToken] - maxLogit) * invSum;
  if (pTarget < 1e-9f)
    pTarget = 1e-9f;
  float fLoss = -logf(pTarget);

  /* 2. Compute Backpropagated Gradient on Final Hidden State: grad_h = W_out^T
   * * (P - Target) */
  if (!pModel->pGradH)
    pModel->pGradH = (float *)malloc((size_t)nEmbd * sizeof(float));
  float *pGradH = pModel->pGradH;
  memset(pGradH, 0, (size_t)nEmbd * sizeof(float));

  float rowBufStack[4096];
  float *pRowBuf = (nEmbd <= 4096)
                       ? rowBufStack
                       : (float *)malloc((size_t)nEmbd * sizeof(float));
  if (!pRowBuf)
    return fLoss;

  /* Target token component: grad_z[y] = pTarget - 1.0f (Negative pull) */
  float gradTarget = pTarget - 1.0f;
  get_output_tensor_row_f32(pModel, (uint32_t)nTargetToken, pRowBuf);
  for (int d = 0; d < nEmbd; d++) {
    pGradH[d] += gradTarget * pRowBuf[d];
  }

  /* Candidate false-positive tokens (top competitors with significant
   * probability mass, max 8) */
  int nFalseCount = 0;
  for (uint32_t i = 0; i < nVocab && nFalseCount < 8; i++) {
    if (i == (uint32_t)nTargetToken)
      continue;
    float diff = pModel->pLogits[i] - maxLogit;
    if (diff > -4.0f) {
      float pFalse = expf(diff) * invSum;
      if (pFalse > 0.015f) {
        get_output_tensor_row_f32(pModel, i, pRowBuf);
        for (int d = 0; d < nEmbd; d++) {
          pGradH[d] += pFalse * pRowBuf[d];
        }
        nFalseCount++;
      }
    }
  }

  if (pRowBuf != rowBufStack)
    free(pRowBuf);

  /* Gradient clipping on grad_h to prevent exploding gradients */
  float gradNormSq = 0.0f;
  for (int d = 0; d < nEmbd; d++)
    gradNormSq += pGradH[d] * pGradH[d];
  float gradNorm = sqrtf(gradNormSq);
  if (gradNorm > 1.0f) {
    float clipScale = 1.0f / gradNorm;
    for (int d = 0; d < nEmbd; d++)
      pGradH[d] *= clipScale;
  }

  /* 3. Backpropagate into All Layer LoRA Adapters */
  RingLoRALayerAdapter *pAdapters = (RingLoRALayerAdapter *)pModel->aLoRALayers;
  float *pU = pModel->pLoRA_Scratch; /* [r] */
  float guStack[128];
  float *pGu =
      (r <= 128) ? guStack : (float *)malloc((size_t)r * sizeof(float));
  if (!pGu)
    return fLoss;

  for (int l = 0; l < nLayers; l++) {
    RingLoRALayerAdapter *pLayer = &pAdapters[l];
    if (!pLayer->bActive)
      continue;

    const float *x_norm = pModel->pLayerActIn + ((size_t)l * 2) * nEmbd;
    const float *att_out = pModel->pLayerActIn + ((size_t)l * 2 + 1) * nEmbd;

    /* --- Adapter Q --- */
    /* Forward u = A_Q * x_norm */
    for (int i = 0; i < r; i++) {
      const float *pRowA = pLayer->pA_Q + (size_t)i * nEmbd;
      float sum = 0.0f;
      for (int j = 0; j < nEmbd; j++)
        sum += pRowA[j] * x_norm[j];
      pU[i] = sum;
    }
    /* pdB_Q += scale * (pGradH * u^T) */
    for (int i = 0; i < nEmbd; i++) {
      float gi = pGradH[i] * scale;
      float *pRowdB = pLayer->pdB_Q + (size_t)i * r;
      for (int k = 0; k < r; k++) {
        pRowdB[k] += gi * pU[k];
      }
    }
    /* Backprop through B: g_u = scale * (B_Q^T * pGradH) */
    for (int k = 0; k < r; k++) {
      float sum = 0.0f;
      for (int i = 0; i < nEmbd; i++) {
        sum += pLayer->pB_Q[(size_t)i * r + k] * pGradH[i];
      }
      pGu[k] = sum * scale;
    }
    /* pdA_Q += g_u * x_norm^T */
    for (int k = 0; k < r; k++) {
      float gk = pGu[k];
      float *pRowdA = pLayer->pdA_Q + (size_t)k * nEmbd;
      for (int j = 0; j < nEmbd; j++) {
        pRowdA[j] += gk * x_norm[j];
      }
    }

    /* --- Adapter Out --- */
    /* Forward u = A_Out * att_out */
    for (int i = 0; i < r; i++) {
      const float *pRowA = pLayer->pA_Out + (size_t)i * nEmbd;
      float sum = 0.0f;
      for (int j = 0; j < nEmbd; j++)
        sum += pRowA[j] * att_out[j];
      pU[i] = sum;
    }
    /* pdB_Out += scale * (pGradH * u^T) */
    for (int i = 0; i < nEmbd; i++) {
      float gi = pGradH[i] * scale;
      float *pRowdB = pLayer->pdB_Out + (size_t)i * r;
      for (int k = 0; k < r; k++) {
        pRowdB[k] += gi * pU[k];
      }
    }
    /* Backprop through B: g_u = scale * (B_Out^T * pGradH) */
    for (int k = 0; k < r; k++) {
      float sum = 0.0f;
      for (int i = 0; i < nEmbd; i++) {
        sum += pLayer->pB_Out[(size_t)i * r + k] * pGradH[i];
      }
      pGu[k] = sum * scale;
    }
    /* pdA_Out += g_u * att_out^T */
    for (int k = 0; k < r; k++) {
      float gk = pGu[k];
      float *pRowdA = pLayer->pdA_Out + (size_t)k * nEmbd;
      for (int j = 0; j < nEmbd; j++) {
        pRowdA[j] += gk * att_out[j];
      }
    }
  }

  if (pGu != guStack)
    free(pGu);
  pModel->nTrainTokens++;
  pModel->nStepAccumTokens++;
  return fLoss;
}

RING_API void ring_model_optimizer_step(RingModel *pModel, float fLR,
                                        float fWeightDecay) {
  if (!pModel || !pModel->bMultiLayerLoRA || !pModel->aLoRALayers)
    return;
  int nLayers = (int)pModel->config.nLayers;
  int nEmbd = (int)pModel->config.nEmbd;
  int r = pModel->nLoRARank;
  size_t nSizeA = (size_t)r * nEmbd;
  size_t nSizeB = (size_t)nEmbd * r;
  float beta1 = 0.9f;
  float beta2 = 0.999f;
  float eps = 1e-8f;

  float invAccum = (pModel->nStepAccumTokens > 0)
                       ? (1.0f / (float)pModel->nStepAccumTokens)
                       : 1.0f;
  pModel->nStepAccumTokens = 0;

  RingLoRALayerAdapter *pAdapters = (RingLoRALayerAdapter *)pModel->aLoRALayers;

  for (int l = 0; l < nLayers; l++) {
    RingLoRALayerAdapter *pLayer = &pAdapters[l];
    if (!pLayer->bActive)
      continue;

#define UPDATE_TENSOR(W, dW, M, V, count, maxVal)                              \
  for (size_t i = 0; i < (count); i++) {                                       \
    float g = dW[i] * invAccum;                                                \
    if (g > 1.0f)                                                              \
      g = 1.0f;                                                                \
    else if (g < -1.0f)                                                        \
      g = -1.0f;                                                               \
    M[i] = beta1 * M[i] + (1.0f - beta1) * g;                                  \
    V[i] = beta2 * V[i] + (1.0f - beta2) * (g * g);                            \
    float mHat =                                                               \
        M[i] / (1.0f - powf(beta1, (float)pModel->nTrainTokens + 1.0f));       \
    float vHat =                                                               \
        V[i] / (1.0f - powf(beta2, (float)pModel->nTrainTokens + 1.0f));       \
    float step = mHat / (sqrtf(vHat) + eps);                                   \
    if (step > 2.0f)                                                           \
      step = 2.0f;                                                             \
    else if (step < -2.0f)                                                     \
      step = -2.0f;                                                            \
    float newW = W[i] - fLR * (step + fWeightDecay * W[i]);                    \
    if (newW > (maxVal))                                                       \
      newW = (maxVal);                                                         \
    else if (newW < -(maxVal))                                                 \
      newW = -(maxVal);                                                        \
    W[i] = newW;                                                               \
    dW[i] = 0.0f;                                                              \
  }

    UPDATE_TENSOR(pLayer->pA_Q, pLayer->pdA_Q, pLayer->pMA_Q, pLayer->pVA_Q,
                  nSizeA, 0.10f);
    UPDATE_TENSOR(pLayer->pB_Q, pLayer->pdB_Q, pLayer->pMB_Q, pLayer->pVB_Q,
                  nSizeB, 0.02f);
    UPDATE_TENSOR(pLayer->pA_Out, pLayer->pdA_Out, pLayer->pMA_Out,
                  pLayer->pVA_Out, nSizeA, 0.10f);
    UPDATE_TENSOR(pLayer->pB_Out, pLayer->pdB_Out, pLayer->pMB_Out,
                  pLayer->pVB_Out, nSizeB, 0.02f);

#undef UPDATE_TENSOR
  }
}

RING_API int ring_model_save_lora(RingModel *pModel, const char *cFolder) {
  if (!pModel || !pModel->bMultiLayerLoRA || !pModel->aLoRALayers || !cFolder)
    return 0;
  char path[1024];

#ifdef _WIN32
  char winCmd[1024];
  snprintf(winCmd, sizeof(winCmd), "if not exist \"%s\" mkdir \"%s\" 2>nul",
           cFolder, cFolder);
  system(winCmd);
#else
  char linCmd[1024];
  snprintf(linCmd, sizeof(linCmd), "mkdir -p \"%s\" 2>/dev/null", cFolder);
  system(linCmd);
#endif

  int nLayers = (int)pModel->config.nLayers;
  int nEmbd = (int)pModel->config.nEmbd;
  int r = pModel->nLoRARank;
  RingLoRALayerAdapter *pAdapters = (RingLoRALayerAdapter *)pModel->aLoRALayers;

  /* Save JSON metadata */
  snprintf(path, sizeof(path), "%s/adapter_config.json", cFolder);
  FILE *fp = fopen(path, "w");
  if (fp) {
    fprintf(fp,
            "{\n  \"layers\": %d,\n  \"lora_rank\": %d,\n  \"lora_alpha\": "
            "%.1f,\n  \"dim\": %d\n}\n",
            nLayers, r, pModel->fLoRAAlpha, nEmbd);
    fclose(fp);
  }

  for (int l = 0; l < nLayers; l++) {
    RingLoRALayerAdapter *pL = &pAdapters[l];
    if (!pL->bActive)
      continue;

    snprintf(path, sizeof(path), "%s/blk.%d.attn_q_lora_a.tensor", cFolder, l);
    save_f32_to_tensor_file(path, pL->pA_Q, r, nEmbd);

    snprintf(path, sizeof(path), "%s/blk.%d.attn_q_lora_b.tensor", cFolder, l);
    save_f32_to_tensor_file(path, pL->pB_Q, nEmbd, r);

    snprintf(path, sizeof(path), "%s/blk.%d.attn_out_lora_a.tensor", cFolder,
             l);
    save_f32_to_tensor_file(path, pL->pA_Out, r, nEmbd);

    snprintf(path, sizeof(path), "%s/blk.%d.attn_out_lora_b.tensor", cFolder,
             l);
    save_f32_to_tensor_file(path, pL->pB_Out, nEmbd, r);
  }

  printf("[MADAR AI] Multi-Layer LoRA Adapters saved to: %s (%d layers)\n",
         cFolder, nLayers);
  return 1;
}

RING_API int ring_model_load_lora_folder(RingModel *pModel,
                                         const char *cFolder) {
  if (!pModel || !cFolder)
    return 0;
  char path[1024];

  snprintf(path, sizeof(path), "%s/adapter_config.json", cFolder);
  FILE *fpConfig = fopen(path, "r");
  if (!fpConfig)
    return 0;

  char buf[1024];
  size_t nr = fread(buf, 1, sizeof(buf) - 1, fpConfig);
  buf[nr] = '\0';
  fclose(fpConfig);

  int nRank = 16;
  float fAlpha = 32.0f;
  char *pR = strstr(buf, "\"lora_rank\":");
  if (pR)
    nRank = atoi(pR + 12);
  char *pA = strstr(buf, "\"lora_alpha\":");
  if (pA)
    fAlpha = (float)atof(pA + 13);

  if (!ring_model_init_lora(pModel, nRank, fAlpha))
    return 0;

  int nLayers = (int)pModel->config.nLayers;
  int nEmbd = (int)pModel->config.nEmbd;
  RingLoRALayerAdapter *pAdapters = (RingLoRALayerAdapter *)pModel->aLoRALayers;

  int nLoadedCount = 0;
  for (int l = 0; l < nLayers; l++) {
    RingLoRALayerAdapter *pL = &pAdapters[l];
    int rA = 0, cA = 0, rB = 0, cB = 0;

    snprintf(path, sizeof(path), "%s/blk.%d.attn_q_lora_a.tensor", cFolder, l);
    float *pAQ = read_tensor_file_to_f32(path, &rA, &cA);
    snprintf(path, sizeof(path), "%s/blk.%d.attn_q_lora_b.tensor", cFolder, l);
    float *pBQ = read_tensor_file_to_f32(path, &rB, &cB);

    snprintf(path, sizeof(path), "%s/blk.%d.attn_out_lora_a.tensor", cFolder,
             l);
    float *pAOut = read_tensor_file_to_f32(path, &rA, &cA);
    snprintf(path, sizeof(path), "%s/blk.%d.attn_out_lora_b.tensor", cFolder,
             l);
    float *pBOut = read_tensor_file_to_f32(path, &rB, &cB);

    if (pAQ && pBQ) {
      memcpy(pL->pA_Q, pAQ, (size_t)nRank * nEmbd * sizeof(float));
      memcpy(pL->pB_Q, pBQ, (size_t)nEmbd * nRank * sizeof(float));
      free(pAQ);
      free(pBQ);
      nLoadedCount++;
    }
    if (pAOut && pBOut) {
      memcpy(pL->pA_Out, pAOut, (size_t)nRank * nEmbd * sizeof(float));
      memcpy(pL->pB_Out, pBOut, (size_t)nEmbd * nRank * sizeof(float));
      free(pAOut);
      free(pBOut);
    }
  }

  printf("[MADAR AI] Multi-Layer LoRA Loaded: %d/%d layers active from: %s\n",
         nLoadedCount, nLayers, cFolder);
  return 1;
}

/*
================================================================================
  LoRA Adapter Fusion Engine (Dynamic Low-Rank Weight Injection)
================================================================================
*/

static float *read_tensor_file_to_f32(const char *cFile, int *pRows,
                                      int *pCols) {
  FILE *fp = fopen(cFile, "rb");
  if (!fp)
    return NULL;
  int rows = 0, cols = 0;
  if (fread(&rows, sizeof(int), 1, fp) != 1 ||
      fread(&cols, sizeof(int), 1, fp) != 1) {
    fclose(fp);
    return NULL;
  }
  size_t count = (size_t)rows * cols;
  double *pTemp = (double *)malloc(count * sizeof(double));
  if (!pTemp) {
    fclose(fp);
    return NULL;
  }
  if (fread(pTemp, sizeof(double), count, fp) != count) {
    free(pTemp);
    fclose(fp);
    return NULL;
  }
  fclose(fp);
  float *pFloat = (float *)malloc(count * sizeof(float));
  if (!pFloat) {
    free(pTemp);
    return NULL;
  }
  for (size_t i = 0; i < count; i++) {
    pFloat[i] = (float)pTemp[i];
  }
  free(pTemp);
  if (pRows)
    *pRows = rows;
  if (pCols)
    *pCols = cols;
  return pFloat;
}

RING_API int ring_model_load_lora(RingModel *pModel, const char *cAdapterDir) {
  if (!pModel || !cAdapterDir)
    return 0;
  char path[1024];

  /* Free previous LoRA tensors if loaded */
  if (pModel->pLoRA_A_Q) {
    free(pModel->pLoRA_A_Q);
    pModel->pLoRA_A_Q = NULL;
  }
  if (pModel->pLoRA_B_Q) {
    free(pModel->pLoRA_B_Q);
    pModel->pLoRA_B_Q = NULL;
  }
  if (pModel->pLoRA_A_V) {
    free(pModel->pLoRA_A_V);
    pModel->pLoRA_A_V = NULL;
  }
  if (pModel->pLoRA_B_V) {
    free(pModel->pLoRA_B_V);
    pModel->pLoRA_B_V = NULL;
  }
  if (pModel->pLoRA_A_Out) {
    free(pModel->pLoRA_A_Out);
    pModel->pLoRA_A_Out = NULL;
  }
  if (pModel->pLoRA_B_Out) {
    free(pModel->pLoRA_B_Out);
    pModel->pLoRA_B_Out = NULL;
  }
  if (pModel->pLoRA_Scratch) {
    free(pModel->pLoRA_Scratch);
    pModel->pLoRA_Scratch = NULL;
  }

  int rA = 0, cA = 0, rB = 0, cB = 0;

  snprintf(path, sizeof(path), "%s/attn_q_proj_lora_a.tensor", cAdapterDir);
  pModel->pLoRA_A_Q = read_tensor_file_to_f32(path, &rA, &cA);

  snprintf(path, sizeof(path), "%s/attn_q_proj_lora_b.tensor", cAdapterDir);
  pModel->pLoRA_B_Q = read_tensor_file_to_f32(path, &rB, &cB);

  snprintf(path, sizeof(path), "%s/attn_v_proj_lora_a.tensor", cAdapterDir);
  pModel->pLoRA_A_V = read_tensor_file_to_f32(path, &rA, &cA);

  snprintf(path, sizeof(path), "%s/attn_v_proj_lora_b.tensor", cAdapterDir);
  pModel->pLoRA_B_V = read_tensor_file_to_f32(path, &rB, &cB);

  snprintf(path, sizeof(path), "%s/attn_out_proj_lora_a.tensor", cAdapterDir);
  pModel->pLoRA_A_Out = read_tensor_file_to_f32(path, &rA, &cA);

  snprintf(path, sizeof(path), "%s/attn_out_proj_lora_b.tensor", cAdapterDir);
  pModel->pLoRA_B_Out = read_tensor_file_to_f32(path, &rB, &cB);

  if (!pModel->pLoRA_A_Q || !pModel->pLoRA_B_Q) {
    return 0;
  }

  pModel->nLoRARank = rA; /* e.g. 16 */

  /* Read alpha from adapter_config.json if available */
  snprintf(path, sizeof(path), "%s/adapter_config.json", cAdapterDir);
  FILE *fpConfig = fopen(path, "r");
  float fAlpha = 32.0f;
  if (fpConfig) {
    char buf[1024];
    size_t nr = fread(buf, 1, sizeof(buf) - 1, fpConfig);
    buf[nr] = '\0';
    fclose(fpConfig);
    char *pAlpha = strstr(buf, "\"lora_alpha\":");
    if (pAlpha) {
      fAlpha = (float)atof(pAlpha + 13);
    }
  }
  if (fAlpha <= 0.0f)
    fAlpha = 32.0f;
  pModel->fLoRAScale =
      (pModel->nLoRARank > 0) ? (fAlpha / (float)pModel->nLoRARank) : 2.0f;

  pModel->pLoRA_Scratch =
      (float *)malloc((size_t)pModel->nLoRARank * sizeof(float));
  pModel->bLoRAEnabled = 1;

  printf("[MADAR AI] LoRA Adapter Successfully Merged! (Rank=%d, Alpha=%.1f, "
         "Scale=%.2f)\n",
         pModel->nLoRARank, (float)pModel->nLoRARank * pModel->fLoRAScale,
         pModel->fLoRAScale);
  return 1;
}

RING_API void ring_model_enable_lora(RingModel *pModel, int bEnable) {
  if (pModel) {
    pModel->bLoRAEnabled = bEnable ? 1 : 0;
  }
}

RING_API void ring_model_set_lora_scale(RingModel *pModel, float fScale) {
  if (pModel) {
    pModel->fLoRAScale = fScale;
  }
}

static void quantize_row_q4_0_fast(const float *x, RingGGUFBlockQ4_0 *y,
                                   int64_t k) {
  int64_t nb = k / 32;
  for (int64_t i = 0; i < nb; i++) {
    float amax = 0.0f;
    for (int l = 0; l < 32; l++) {
      float v = x[i * 32 + l];
      float av = fabsf(v);
      if (amax < av)
        amax = av;
    }
    float d = amax / -8.0f;
    float id = (d != 0.0f) ? (1.0f / d) : 0.0f;
    y[i].d = ggml_fp32_to_fp16(d);

    for (int l = 0; l < 16; l++) {
      float x0 = x[i * 32 + l] * id;
      float x1 = x[i * 32 + l + 16] * id;

      int xi0 = (int)(x0 + 8.5f);
      int xi1 = (int)(x1 + 8.5f);

      if (xi0 < 0)
        xi0 = 0;
      else if (xi0 > 15)
        xi0 = 15;
      if (xi1 < 0)
        xi1 = 0;
      else if (xi1 > 15)
        xi1 = 15;

      y[i].qs[l] = (uint8_t)(xi0 | (xi1 << 4));
    }
  }
}

RING_API int ring_model_export_merged_gguf(RingModel *pModel,
                                           const char *cOutGGUFPath) {
  if (!pModel || !pModel->pGGUF || !pModel->pGGUF->pMappedData ||
      !cOutGGUFPath) {
    return 0;
  }

  RingGGUF *pGGUF = pModel->pGGUF;
  FILE *fpOut = fopen(cOutGGUFPath, "wb");
  if (!fpOut) {
    printf("[MADAR GGUF] Error: Failed to open output file '%s' for writing!\n",
           cOutGGUFPath);
    return 0;
  }

  /* 1. Copy exact header and metadata table up to nDataOffset */
  if (fwrite(pGGUF->pMappedData, 1, (size_t)pGGUF->nDataOffset, fpOut) !=
      (size_t)pGGUF->nDataOffset) {
    fclose(fpOut);
    return 0;
  }

  printf("[MADAR GGUF] Exporting merged model with LoRA to: %s\n",
         cOutGGUFPath);
  printf("[MADAR GGUF] Processing %llu tensors...\n",
         (unsigned long long)pGGUF->nTensors);

  int nMergedCount = 0;
  for (uint64_t i = 0; i < pGGUF->nTensors; i++) {
    RingGGUFTensorInfo *pInfo = &pGGUF->aTensors[i];
    const char *pName = pInfo->pName ? pInfo->pName : "";
    const uint8_t *pRawSrc =
        (const uint8_t *)ring_gguf_get_tensor_data(pGGUF, pInfo);
    if (!pRawSrc) {
      fclose(fpOut);
      return 0;
    }

    int layerIdx = -1;
    const char *pBlk = strstr(pName, "blk.");
    if (pBlk) {
      layerIdx = atoi(pBlk + 4);
    }

    int bMergeQ = (strstr(pName, "attn_q") || strstr(pName, "q_proj"));
    int bMergeOut = (strstr(pName, "attn_output") ||
                     strstr(pName, "attn_out") || strstr(pName, "out_proj"));

    const float *pA = NULL;
    const float *pB = NULL;

    if (pModel->bMultiLayerLoRA && pModel->aLoRALayers && layerIdx >= 0 &&
        layerIdx < (int)pModel->config.nLayers) {
      RingLoRALayerAdapter *pAdapter =
          ((RingLoRALayerAdapter *)pModel->aLoRALayers) + layerIdx;
      if (pAdapter->bActive) {
        if (bMergeQ) {
          pA = pAdapter->pA_Q;
          pB = pAdapter->pB_Q;
        } else if (bMergeOut) {
          pA = pAdapter->pA_Out;
          pB = pAdapter->pB_Out;
        }
      }
    } else if (pModel->bLoRAEnabled) {
      if (bMergeQ) {
        pA = pModel->pLoRA_A_Q;
        pB = pModel->pLoRA_B_Q;
      } else if (bMergeOut) {
        pA = pModel->pLoRA_A_Out;
        pB = pModel->pLoRA_B_Out;
      }
    }

    if ((pA && pB) && pInfo->nType == RING_GGUF_TENSOR_Q4_0) {
      int r = pModel->nLoRARank;
      int inDim = (int)pInfo->aDims[0];
      int outDim = (int)pInfo->aDims[1];
      float scale = pModel->fLoRAScale;

      float *f32 = (float *)malloc((size_t)pInfo->nElements * sizeof(float));
      RingGGUFBlockQ4_0 *pDstBlocks =
          (RingGGUFBlockQ4_0 *)malloc((size_t)pInfo->nSize);

      if (f32 && pDstBlocks) {
        ring_gguf_dequantize_q4_0(pRawSrc, f32, pInfo->nElements);

        /* Add Delta W = scale * (B * A) */
        for (int row = 0; row < outDim; row++) {
          const float *pRowB = pB + (size_t)row * r;
          float *pRowF32 = f32 + (size_t)row * inDim;
          for (int col = 0; col < inDim; col++) {
            float sum = 0.0f;
            for (int k = 0; k < r; k++) {
              sum += pRowB[k] * pA[(size_t)k * inDim + col];
            }
            pRowF32[col] += scale * sum;
          }
        }

        quantize_row_q4_0_fast(f32, pDstBlocks, (int64_t)pInfo->nElements);
        fwrite(pDstBlocks, 1, (size_t)pInfo->nSize, fpOut);
        nMergedCount++;
      } else {
        fwrite(pRawSrc, 1, (size_t)pInfo->nSize, fpOut);
      }

      if (f32)
        free(f32);
      if (pDstBlocks)
        free(pDstBlocks);
    } else {
      /* Direct copy of unadapted tensor */
      fwrite(pRawSrc, 1, (size_t)pInfo->nSize, fpOut);
    }

    /* Preserve inter-tensor padding if present in original GGUF */
    uint64_t nextOffset = (i + 1 < pGGUF->nTensors)
                              ? pGGUF->aTensors[i + 1].nOffset
                              : (pGGUF->nFileSize - pGGUF->nDataOffset);
    uint64_t curEnd = pInfo->nOffset + pInfo->nSize;
    if (nextOffset > curEnd) {
      size_t nPad = (size_t)(nextOffset - curEnd);
      const uint8_t *pPadSrc = pGGUF->pMappedData + pGGUF->nDataOffset + curEnd;
      fwrite(pPadSrc, 1, nPad, fpOut);
    }
  }

  fclose(fpOut);
  printf("[MADAR GGUF] Merge complete! Successfully fused %d attention tensors "
         "into: %s\n",
         nMergedCount, cOutGGUFPath);
  return 1;
}

/*
================================================================================
  Transformer Forward Pass (One Token at Position `pos`)
================================================================================
*/

static inline float dot_fp32_fp16(const float *q, const ggml_fp16_t *k,
                                  int dim) {
#if defined(MADAR_AVX2)
  __m256 acc0 = _mm256_setzero_ps();
  __m256 acc1 = _mm256_setzero_ps();
  int d = 0;
  for (; d + 15 < dim; d += 16) {
    __m128i h0 = _mm_loadu_si128((const __m128i *)(k + d));
    __m128i h1 = _mm_loadu_si128((const __m128i *)(k + d + 8));
    acc0 = _mm256_fmadd_ps(_mm256_loadu_ps(q + d), _mm256_cvtph_ps(h0), acc0);
    acc1 =
        _mm256_fmadd_ps(_mm256_loadu_ps(q + d + 8), _mm256_cvtph_ps(h1), acc1);
  }
  for (; d + 7 < dim; d += 8) {
    __m128i h = _mm_loadu_si128((const __m128i *)(k + d));
    acc0 = _mm256_fmadd_ps(_mm256_loadu_ps(q + d), _mm256_cvtph_ps(h), acc0);
  }
  float s = hsum_float_8(_mm256_add_ps(acc0, acc1));
  for (; d < dim; d++)
    s += ggml_hw_fp16_to_fp32(k[d]) * q[d];
  return s;
#else
  float s = 0.0f;
  int d;
  for (d = 0; d < dim; d++)
    s += q[d] * fast_fp16_to_fp32(k[d]);
  return s;
#endif
}

static inline void add_scaled_fp16(float *out, float a, const ggml_fp16_t *v,
                                   int dim) {
#if defined(MADAR_AVX2)
  __m256 va = _mm256_set1_ps(a);
  int d = 0;
  for (; d + 7 < dim; d += 8) {
    __m128i h = _mm_loadu_si128((const __m128i *)(v + d));
    __m256 vf = _mm256_cvtph_ps(h);
    __m256 vo = _mm256_loadu_ps(out + d);
    _mm256_storeu_ps(out + d, _mm256_fmadd_ps(va, vf, vo));
  }
  for (; d < dim; d++)
    out[d] += a * ggml_hw_fp16_to_fp32(v[d]);
#else
  int d;
  for (d = 0; d < dim; d++)
    out[d] += a * fast_fp16_to_fp32(v[d]);
#endif
}

RING_API void ring_model_forward_ex(RingModel *pModel, int nToken, int nPos,
                                    int bComputeLogits) {
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

  if (!pModel || nToken < 0 || (uint32_t)nToken >= pModel->config.nVocab)
    return;

  nEmbd = (int)pModel->config.nEmbd;
  nHeadDim = (int)pModel->config.nHeadDim;
  nHeads = (int)pModel->config.nHeads;
  nHeadsKV = (int)pModel->config.nHeadsKV;
  nKVDim = (int)pModel->nKVDim;
  nFF = (int)pModel->config.nFF;
  groupSize = (nHeadsKV > 0) ? (nHeads / nHeadsKV) : 1;
  if (groupSize <= 0)
    groupSize = 1;
  eps = pModel->config.fNormEps;
  freqBase = pModel->config.fRopeFreqBase;

  /* 1. Embedding Lookup */
  pRawEmbd = (const uint8_t *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                        pModel->pTokenEmbd);
  if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0) {
    b4 = (const RingGGUFBlockQ4_0 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) *
                                                    sizeof(RingGGUFBlockQ4_0));
    ring_gguf_dequantize_q4_0(b4, pModel->pActX, nEmbd);
  } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_1) {
    const RingGGUFBlockQ4_1 *b4_1 =
        (const RingGGUFBlockQ4_1 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) *
                                                   sizeof(RingGGUFBlockQ4_1));
    ring_gguf_dequantize_q4_1(b4_1, pModel->pActX, nEmbd);
  } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0) {
    const RingGGUFBlockQ8_0 *b8 =
        (const RingGGUFBlockQ8_0 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) *
                                                   sizeof(RingGGUFBlockQ8_0));
    ring_gguf_dequantize_q8_0(b8, pModel->pActX, nEmbd);
  } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q6_K) {
    const RingGGUFBlockQ6_K *b6 =
        (const RingGGUFBlockQ6_K *)(pRawEmbd + (size_t)nToken * (nEmbd / 256) *
                                                   sizeof(RingGGUFBlockQ6_K));
    ring_gguf_dequantize_q6_k(b6, pModel->pActX, nEmbd);
  } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16) {
    f16 = (const ggml_fp16_t *)(pRawEmbd +
                                (size_t)nToken * nEmbd * sizeof(ggml_fp16_t));
    ring_gguf_dequantize_f16(f16, pModel->pActX, nEmbd);
  } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F32) {
    memcpy(pModel->pActX, pRawEmbd + (size_t)nToken * nEmbd * sizeof(float),
           nEmbd * sizeof(float));
  } else {
    printf("\n[MADAR AI] Warning: Unknown embedding tensor type: %u\n",
           pModel->pTokenEmbd->nType);
  }

  /* 2. Forward through Transformer Layers */
  for (l = 0; l < pModel->config.nLayers; l++) {
    layer = &pModel->aLayers[l];

    /* RMSNorm before Attention */
    attnNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                         layer->pAttnNorm);
    rmsnorm(pModel->pActXB, pModel->pActX, attnNormW, nEmbd, eps);

    /* Save layer input activation for Multi-Layer LoRA backward pass */
    if (pModel->pLayerActIn) {
      memcpy(pModel->pLayerActIn + ((size_t)l * 2) * nEmbd, pModel->pActXB,
             (size_t)nEmbd * sizeof(float));
    }

    /* Compute Q, K, V */
    matvec_multiply(pModel, layer->pAttnQ, pModel->pActXB, pModel->pActQ,
                    layer->pAttnQ_Bias);

    /* Multi-Layer LoRA injection into Q */
    if (pModel->bMultiLayerLoRA && pModel->aLoRALayers) {
      RingLoRALayerAdapter *pLAdapt =
          ((RingLoRALayerAdapter *)pModel->aLoRALayers) + l;
      if (pLAdapt->bActive && pLAdapt->pA_Q && pLAdapt->pB_Q) {
        int r = pModel->nLoRARank;
        float scale = pModel->fLoRAScale;
        float *h = pModel->pLoRA_Scratch;
        for (int i = 0; i < r; i++) {
          const float *pRowA = pLAdapt->pA_Q + (size_t)i * nEmbd;
          float sum = 0.0f;
          for (int j = 0; j < nEmbd; j++)
            sum += pRowA[j] * pModel->pActXB[j];
          h[i] = sum;
        }
        for (int i = 0; i < (int)(nHeads * nHeadDim); i++) {
          const float *pRowB = pLAdapt->pB_Q + (size_t)i * r;
          float sum = 0.0f;
          for (int j = 0; j < r; j++)
            sum += pRowB[j] * h[j];
          pModel->pActQ[i] += scale * sum;
        }
      }
    }

    matvec_multiply(pModel, layer->pAttnK, pModel->pActXB, pModel->pActK,
                    layer->pAttnK_Bias);
    matvec_multiply(pModel, layer->pAttnV, pModel->pActXB, pModel->pActV,
                    layer->pAttnV_Bias);

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
    validTokens =
        (nPos < (int)pModel->nMaxSeq) ? (nPos + 1) : (int)pModel->nMaxSeq;

    for (h = 0; h < nHeads; h++) {
      kvH = h / groupSize;
      if (kvH >= nHeadsKV)
        kvH = nHeadsKV - 1;

      qHead = pModel->pActQ + h * nHeadDim;
      outHead = pModel->pActAttOut + h * nHeadDim;

      for (t = 0; t < validTokens; t++) {
        tOffset =
            ((size_t)l * pModel->nMaxSeq + t) * nKVDim + (size_t)kvH * nHeadDim;
        kHead = pModel->pKVCache_K + tOffset;
        score = dot_fp32_fp16(qHead, kHead, nHeadDim);
        attScores[t] = score * scale;
      }

      softmax(attScores, validTokens);

      memset(outHead, 0, nHeadDim * sizeof(float));
      for (t = 0; t < validTokens; t++) {
        tOffset =
            ((size_t)l * pModel->nMaxSeq + t) * nKVDim + (size_t)kvH * nHeadDim;
        vHead = pModel->pKVCache_V + tOffset;
        add_scaled_fp16(outHead, attScores[t], vHead, nHeadDim);
      }
    }

    /* Attention Output Projection (SubLN in BitNet) */
    if (layer->pAttnSubNorm) {
      const float *subNormW = (const float *)ring_gguf_get_tensor_data(
          pModel->pGGUF, layer->pAttnSubNorm);
      if (subNormW) {
        rmsnorm(pModel->pActAttOut, pModel->pActAttOut, subNormW, nEmbd, eps);
      }
    }
    matvec_multiply(pModel, layer->pAttnOut, pModel->pActAttOut, attnOut, NULL);

    /* Save attention output activation for Multi-Layer LoRA backward pass */
    if (pModel->pLayerActIn) {
      memcpy(pModel->pLayerActIn + ((size_t)l * 2 + 1) * nEmbd,
             pModel->pActAttOut, (size_t)nEmbd * sizeof(float));
    }

    /* Multi-Layer LoRA injection into Attention Output */
    if (pModel->bMultiLayerLoRA && pModel->aLoRALayers) {
      RingLoRALayerAdapter *pLAdapt =
          ((RingLoRALayerAdapter *)pModel->aLoRALayers) + l;
      if (pLAdapt->bActive && pLAdapt->pA_Out && pLAdapt->pB_Out) {
        int r = pModel->nLoRARank;
        float scale = pModel->fLoRAScale;
        float *h = pModel->pLoRA_Scratch;
        for (int i = 0; i < r; i++) {
          const float *pRowA = pLAdapt->pA_Out + (size_t)i * nEmbd;
          float sum = 0.0f;
          for (int j = 0; j < nEmbd; j++)
            sum += pRowA[j] * pModel->pActAttOut[j];
          h[i] = sum;
        }
        for (int i = 0; i < nEmbd; i++) {
          const float *pRowB = pLAdapt->pB_Out + (size_t)i * r;
          float sum = 0.0f;
          for (int j = 0; j < r; j++)
            sum += pRowB[j] * h[j];
          attnOut[i] += scale * sum;
        }
      }
    }

    /* Residual Addition: x = x + attnOut */
    i = 0;
#if defined(MADAR_AVX2)
    for (; i + 7 < nEmbd; i += 8) {
      _mm256_storeu_ps(pModel->pActX + i,
                       _mm256_add_ps(_mm256_loadu_ps(pModel->pActX + i),
                                     _mm256_loadu_ps(attnOut + i)));
    }
#endif
    for (; i < nEmbd; i++) {
      pModel->pActX[i] += attnOut[i];
    }

    /* RMSNorm before FFN */
    ffnNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                        layer->pFFNNorm);
    rmsnorm(pModel->pActXB, pModel->pActX, ffnNormW, nEmbd, eps);

    /* SwiGLU / BitNet FFN: Attempt GPU Fused Pipeline First */
    if (!madar_gpu_ffn_fused(pModel, layer, pModel->pActXB, ffnOut)) {
      /* Fallback to CPU Multi-Threaded FFN */
      matvec_multiply_gpu(pModel, layer->pFFNGate, layer->pGPUBufGate,
                          pModel->pActXB, pModel->pActHB, NULL);
      matvec_multiply_gpu(pModel, layer->pFFNUp, layer->pGPUBufUp,
                          pModel->pActXB, pModel->pActHB2, NULL);

      if (pModel->config.bIsBitNet) {
        for (i = 0; i < nFF; i++) {
          g = pModel->pActHB[i];
          float relu_g = g > 0.0f ? g : 0.0f;
          pModel->pActHB[i] = (relu_g * relu_g) * pModel->pActHB2[i];
        }
        if (layer->pFFNSubNorm) {
          const float *subNormW = (const float *)ring_gguf_get_tensor_data(
              pModel->pGGUF, layer->pFFNSubNorm);
          if (subNormW) {
            rmsnorm(pModel->pActHB, pModel->pActHB, subNormW, nFF, eps);
          }
        }
      } else {
        for (i = 0; i < nFF; i++) {
          g = pModel->pActHB[i];
          silu_g = g / (1.0f + expf(-g));
          pModel->pActHB[i] = silu_g * pModel->pActHB2[i];
        }
      }

      matvec_multiply_gpu(pModel, layer->pFFNDown, layer->pGPUBufDown,
                          pModel->pActHB, ffnOut, NULL);
    }

    /* Residual Addition: x = x + ffnOut */
    i = 0;
#if defined(MADAR_AVX2)
    for (; i + 7 < nEmbd; i += 8) {
      _mm256_storeu_ps(pModel->pActX + i,
                       _mm256_add_ps(_mm256_loadu_ps(pModel->pActX + i),
                                     _mm256_loadu_ps(ffnOut + i)));
    }
#endif
    for (; i < nEmbd; i++) {
      pModel->pActX[i] += ffnOut[i];
    }
  }

  /* 3. Final Output RMSNorm & Logits (Only when requested) */
  if (bComputeLogits) {
    outNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                        pModel->pOutputNorm);
    rmsnorm(pModel->pActXB, pModel->pActX, outNormW, nEmbd, eps);

    /* 4. Output Projection to Logits */
    matvec_multiply_gpu(pModel, pModel->pOutput, pModel->pGPUBufOutputWeight,
                        pModel->pActXB, pModel->pLogits, NULL);
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
  uint32_t nVocab, i, j, m;
  float *logits;
  int bestToken;
  float maxLogit, invTemp, sumExp, r, accum;
  int topK = 40;
  int topIndices[40];
  float topLogits[40];
  float minTopLogit;
  int minTopIdx;
  float topP, cumProb, activeSum;
  uint32_t activeK;
  uint32_t r32;

  if (!pModel)
    return 0;

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

  /* Top-K Filtering (K = 40) to eliminate uniform tail noise across 151k
   * vocab
   */
  if (topK > (int)nVocab)
    topK = (int)nVocab;
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
    if (topLogits[j] > maxLogit)
      maxLogit = topLogits[j];
  }

  invTemp = 1.0f / fTemp;
  sumExp = 0.0f;
  for (j = 0; j < (uint32_t)topK; j++) {
    topLogits[j] = expf((topLogits[j] - maxLogit) * invTemp);
    sumExp += topLogits[j];
  }

  /* Sort topK candidates descending by probability */
  for (j = 0; j < (uint32_t)topK - 1; j++) {
    for (m = j + 1; m < (uint32_t)topK; m++) {
      if (topLogits[m] > topLogits[j]) {
        float tmpL = topLogits[j];
        topLogits[j] = topLogits[m];
        topLogits[m] = tmpL;
        int tmpI = topIndices[j];
        topIndices[j] = topIndices[m];
        topIndices[m] = tmpI;
      }
    }
  }

  /* Nucleus Filtering (Top-P = 0.90) to cut off long degenerative tails */
  topP = 0.90f;
  cumProb = 0.0f;
  activeSum = 0.0f;
  activeK = (uint32_t)topK;
  for (j = 0; j < (uint32_t)topK; j++) {
    cumProb += topLogits[j];
    activeSum += topLogits[j];
    if (cumProb >= topP * sumExp && j >= 1) {
      activeK = j + 1;
      break;
    }
  }

  /* 30-bit high resolution pseudo-random value */
  r32 = (((uint32_t)rand() & 0x7FFF) << 15) | ((uint32_t)rand() & 0x7FFF);
  r = ((float)r32 / (float)0x3FFFFFFF) * activeSum;

  accum = 0.0f;
  for (j = 0; j < activeK; j++) {
    accum += topLogits[j];
    if (accum >= r)
      return topIndices[j];
  }

  return topIndices[0];
}

/*
================================================================================
  Text Generation & Streaming Generator
================================================================================
*/

static void ring_model_forward_chunk(RingModel *pModel, const int *tokens,
                                     int nStartPos, int nChunkSize,
                                     int bComputeLastLogits) {
  int nEmbd, nHeadDim, nHeads, nHeadsKV, nKVDim, nFF, groupSize;
  float eps, freqBase, scale;
  uint32_t l;
  RingLayerWeights *layer;
  const float *attnNormW, *ffnNormW, *outNormW;
  float *actBatchX, *actBatchFFNIn, *actBatchFFNOut;
  int t, h, kvH, i, pos, seqIdx, validTokens;
  size_t kvOffset, tOffset;
  float *tokX, *qHead, *outHead;
  const ggml_fp16_t *kHead, *vHead;
  float *attScores = pModel->pAttScores;
  float score;
  const uint8_t *pRawEmbd;

  if (!pModel || !tokens || nChunkSize <= 0)
    return;

  nEmbd = (int)pModel->config.nEmbd;
  nHeadDim = (int)pModel->config.nHeadDim;
  nHeads = (int)pModel->config.nHeads;
  nHeadsKV = (int)pModel->config.nHeadsKV;
  nKVDim = (int)pModel->nKVDim;
  nFF = (int)pModel->config.nFF;
  groupSize = (nHeadsKV > 0) ? (nHeads / nHeadsKV) : 1;
  if (groupSize <= 0)
    groupSize = 1;
  eps = pModel->config.fNormEps;
  freqBase = pModel->config.fRopeFreqBase;
  scale = 1.0f / sqrtf((float)nHeadDim);

  actBatchX = (float *)malloc((size_t)nChunkSize * nEmbd * sizeof(float));
  actBatchFFNIn = (float *)malloc((size_t)nChunkSize * nEmbd * sizeof(float));
  actBatchFFNOut = (float *)malloc((size_t)nChunkSize * nEmbd * sizeof(float));
  if (!actBatchX || !actBatchFFNIn || !actBatchFFNOut) {
    if (actBatchX)
      free(actBatchX);
    if (actBatchFFNIn)
      free(actBatchFFNIn);
    if (actBatchFFNOut)
      free(actBatchFFNOut);
    for (t = 0; t < nChunkSize; t++) {
      int bLogits = (bComputeLastLogits && t == nChunkSize - 1) ? 1 : 0;
      ring_model_forward_ex(pModel, tokens[t], nStartPos + t, bLogits);
    }
    return;
  }

  /* 1. Embedding Lookup for all tokens in chunk */
  pRawEmbd = (const uint8_t *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                        pModel->pTokenEmbd);
  for (t = 0; t < nChunkSize; t++) {
    int nToken = tokens[t];
    tokX = actBatchX + (size_t)t * nEmbd;
    if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0) {
      const RingGGUFBlockQ4_0 *b4 =
          (const RingGGUFBlockQ4_0 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) *
                                                     sizeof(RingGGUFBlockQ4_0));
      ring_gguf_dequantize_q4_0(b4, tokX, nEmbd);
    } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_1) {
      const RingGGUFBlockQ4_1 *b4_1 =
          (const RingGGUFBlockQ4_1 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) *
                                                     sizeof(RingGGUFBlockQ4_1));
      ring_gguf_dequantize_q4_1(b4_1, tokX, nEmbd);
    } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0) {
      const RingGGUFBlockQ8_0 *b8 =
          (const RingGGUFBlockQ8_0 *)(pRawEmbd + (size_t)nToken * (nEmbd / 32) *
                                                     sizeof(RingGGUFBlockQ8_0));
      ring_gguf_dequantize_q8_0(b8, tokX, nEmbd);
    } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q6_K) {
      const RingGGUFBlockQ6_K *b6 =
          (const RingGGUFBlockQ6_K *)(pRawEmbd + (size_t)nToken *
                                                     (nEmbd / 256) *
                                                     sizeof(RingGGUFBlockQ6_K));
      ring_gguf_dequantize_q6_k(b6, tokX, nEmbd);
    } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16) {
      const ggml_fp16_t *f16 =
          (const ggml_fp16_t *)(pRawEmbd +
                                (size_t)nToken * nEmbd * sizeof(ggml_fp16_t));
      ring_gguf_dequantize_f16(f16, tokX, nEmbd);
    } else {
      const float *f32 =
          (const float *)(pRawEmbd + (size_t)nToken * nEmbd * sizeof(float));
      memcpy(tokX, f32, nEmbd * sizeof(float));
    }
  }

  /* 2. Process Layer-by-Layer across all tokens */
  for (l = 0; l < pModel->config.nLayers; l++) {
    layer = &pModel->aLayers[l];
    attnNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                         layer->pAttnNorm);
    ffnNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                        layer->pFFNNorm);

    /* Phase A: Multi-head Attention and KV caching for each token */
    for (t = 0; t < nChunkSize; t++) {
      pos = nStartPos + t;
      tokX = actBatchX + (size_t)t * nEmbd;

      rmsnorm(pModel->pActXB, tokX, attnNormW, nEmbd, eps);

      matvec_multiply(pModel, layer->pAttnQ, pModel->pActXB, pModel->pActQ,
                      layer->pAttnQ_Bias);
      matvec_multiply(pModel, layer->pAttnK, pModel->pActXB, pModel->pActK,
                      layer->pAttnK_Bias);
      matvec_multiply(pModel, layer->pAttnV, pModel->pActXB, pModel->pActV,
                      layer->pAttnV_Bias);

      apply_rope(pModel->pActQ, nHeads, nHeadDim, pos, freqBase);
      apply_rope(pModel->pActK, nHeadsKV, nHeadDim, pos, freqBase);

      seqIdx = pos % pModel->nMaxSeq;
      kvOffset = ((size_t)l * pModel->nMaxSeq + seqIdx) * nKVDim;
      for (i = 0; i < nKVDim; i++) {
        pModel->pKVCache_K[kvOffset + i] = ggml_fp32_to_fp16(pModel->pActK[i]);
        pModel->pKVCache_V[kvOffset + i] = ggml_fp32_to_fp16(pModel->pActV[i]);
      }

      validTokens =
          (pos < (int)pModel->nMaxSeq) ? (pos + 1) : (int)pModel->nMaxSeq;

      for (h = 0; h < nHeads; h++) {
        kvH = h / groupSize;
        if (kvH >= nHeadsKV)
          kvH = nHeadsKV - 1;

        qHead = pModel->pActQ + h * nHeadDim;
        outHead = pModel->pActAttOut + h * nHeadDim;

        for (int ti = 0; ti < validTokens; ti++) {
          tOffset = ((size_t)l * pModel->nMaxSeq + ti) * nKVDim +
                    (size_t)kvH * nHeadDim;
          kHead = pModel->pKVCache_K + tOffset;
          score = dot_fp32_fp16(qHead, kHead, nHeadDim);
          attScores[ti] = score * scale;
        }

        softmax(attScores, validTokens);

        memset(outHead, 0, nHeadDim * sizeof(float));
        for (int ti = 0; ti < validTokens; ti++) {
          tOffset = ((size_t)l * pModel->nMaxSeq + ti) * nKVDim +
                    (size_t)kvH * nHeadDim;
          vHead = pModel->pKVCache_V + tOffset;
          add_scaled_fp16(outHead, attScores[ti], vHead, nHeadDim);
        }
      }

      if (layer->pAttnSubNorm) {
        const float *subNormW = (const float *)ring_gguf_get_tensor_data(
            pModel->pGGUF, layer->pAttnSubNorm);
        if (subNormW) {
          rmsnorm(pModel->pActAttOut, pModel->pActAttOut, subNormW, nEmbd, eps);
        }
      }
      matvec_multiply(pModel, layer->pAttnOut, pModel->pActAttOut,
                      pModel->pActAttnProj, NULL);

      /* Residual Addition */
      i = 0;
#if defined(MADAR_AVX2)
      for (; i + 7 < nEmbd; i += 8) {
        _mm256_storeu_ps(
            tokX + i, _mm256_add_ps(_mm256_loadu_ps(tokX + i),
                                    _mm256_loadu_ps(pModel->pActAttnProj + i)));
      }
#endif
      for (; i < nEmbd; i++)
        tokX[i] += pModel->pActAttnProj[i];

      /* Pre-FFN RMSNorm into actBatchFFNIn */
      rmsnorm(actBatchFFNIn + (size_t)t * nEmbd, tokX, ffnNormW, nEmbd, eps);
    }

    /* Phase B: Fused FFN for the whole chunk */
    if (!madar_gpu_ffn_fused_batch(pModel, layer, actBatchFFNIn, actBatchFFNOut,
                                   nChunkSize)) {
      /* CPU Fallback for the chunk */
      for (t = 0; t < nChunkSize; t++) {
        const float *inXB = actBatchFFNIn + (size_t)t * nEmbd;
        float *outFFN = actBatchFFNOut + (size_t)t * nEmbd;
        matvec_multiply(pModel, layer->pFFNGate, inXB, pModel->pActHB, NULL);
        matvec_multiply(pModel, layer->pFFNUp, inXB, pModel->pActHB2,
                        layer->pFFNUp_Bias);
        if (pModel->config.bIsBitNet) {
          for (i = 0; i < nFF; i++) {
            float g = pModel->pActHB[i];
            float relu_g = g > 0.0f ? g : 0.0f;
            pModel->pActHB[i] = (relu_g * relu_g) * pModel->pActHB2[i];
          }
          if (layer->pFFNSubNorm) {
            const float *subNormW = (const float *)ring_gguf_get_tensor_data(
                pModel->pGGUF, layer->pFFNSubNorm);
            if (subNormW) {
              rmsnorm(pModel->pActHB, pModel->pActHB, subNormW, nFF, eps);
            }
          }
        } else {
          for (i = 0; i < nFF; i++) {
            float g = pModel->pActHB[i];
            pModel->pActHB[i] = (g / (1.0f + expf(-g))) * pModel->pActHB2[i];
          }
        }
        matvec_multiply(pModel, layer->pFFNDown, pModel->pActHB, outFFN,
                        layer->pFFNDown_Bias);
      }
    }

    /* Phase C: Residual Addition of FFN output */
    for (t = 0; t < nChunkSize; t++) {
      tokX = actBatchX + (size_t)t * nEmbd;
      float *outFFN = actBatchFFNOut + (size_t)t * nEmbd;
      i = 0;
#if defined(MADAR_AVX2)
      for (; i + 7 < nEmbd; i += 8) {
        _mm256_storeu_ps(tokX + i, _mm256_add_ps(_mm256_loadu_ps(tokX + i),
                                                 _mm256_loadu_ps(outFFN + i)));
      }
#endif
      for (; i < nEmbd; i++)
        tokX[i] += outFFN[i];
    }
  }

  /* 3. Compute Logits on last token if requested */
  if (bComputeLastLogits) {
    float *lastTokX = actBatchX + (size_t)(nChunkSize - 1) * nEmbd;
    memcpy(pModel->pActX, lastTokX, nEmbd * sizeof(float));
    outNormW = (const float *)ring_gguf_get_tensor_data(pModel->pGGUF,
                                                        pModel->pOutputNorm);
    rmsnorm(pModel->pActXB, pModel->pActX, outNormW, nEmbd, eps);
    matvec_multiply_gpu(pModel, pModel->pOutput, pModel->pGPUBufOutputWeight,
                        pModel->pActXB, pModel->pLogits, NULL);
  }

  free(actBatchX);
  free(actBatchFFNIn);
  free(actBatchFFNOut);
}

RING_API int ring_model_prefill(RingModel *pModel, const char *cPrompt,
                                int nMaxTokens, float fTemp) {
  int *promptTokens;
  int chunkSize, start;
  uint32_t maxSeq;

  if (!pModel || !cPrompt)
    return 0;
  maxSeq = pModel->nMaxSeq > 0 ? pModel->nMaxSeq : 8192;
  if (nMaxTokens <= 0)
    nMaxTokens = 64;
  if ((uint32_t)nMaxTokens > maxSeq)
    nMaxTokens = (int)maxSeq;

  promptTokens = (int *)malloc(maxSeq * sizeof(int));
  if (!promptTokens)
    return 0;

  pModel->nPromptTokens = ring_tokenizer_encode(pModel->pTokenizer, cPrompt,
                                                promptTokens, (int)maxSeq);
  if (pModel->nPromptTokens <= 0) {
    free(promptTokens);
    pModel->bGenFinished = 1;
    return 0;
  }

  ring_model_reset_kv(pModel);

  /* Evaluate Prompt in optimal chunks (Batch Size = 32) */
  for (start = 0; start < pModel->nPromptTokens; start += chunkSize) {
    chunkSize = (pModel->nPromptTokens - start > 32)
                    ? 32
                    : (pModel->nPromptTokens - start);
    int bComputeLogits = (start + chunkSize >= pModel->nPromptTokens) ? 1 : 0;
    ring_model_forward_chunk(pModel, promptTokens + start, start, chunkSize,
                             bComputeLogits);
  }

  free(promptTokens);

  pModel->nCurPos = pModel->nPromptTokens;
  pModel->nGenCount = 0;
  pModel->nMaxGenTokens = nMaxTokens;
  pModel->fCurrentTemp = fTemp;
  pModel->bGenFinished = 0;

  return pModel->nPromptTokens;
}

RING_API int ring_model_has_more(RingModel *pModel) {
  if (!pModel)
    return 0;
  return (!pModel->bGenFinished && pModel->nGenCount < pModel->nMaxGenTokens);
}

RING_API char *ring_model_step(RingModel *pModel) {
  int i, nextToken;
  int penaltyStart;
  char *tokenStr;
  int k, count;
  int t1, t2, t3;

  if (!pModel || pModel->bGenFinished ||
      pModel->nGenCount >= pModel->nMaxGenTokens ||
      (size_t)pModel->nGenCount >=
          (sizeof(pModel->aGenTokens) / sizeof(pModel->aGenTokens[0]))) {
    if (pModel && pModel->pTokenizer && pModel->pTokenizer->nUtf8BufLen > 0) {
      char flushBuf[16];
      int flushW = 0;
      ring_tokenizer_flush(pModel->pTokenizer, flushBuf, &flushW,
                           sizeof(flushBuf));
      if (flushW > 0) {
        flushBuf[flushW] = '\0';
        return _strdup(flushBuf);
      }
    }
    return _strdup("");
  }

  /* Repetition penalty with 256-token lookback window & frequency scaling */
  penaltyStart = (pModel->nGenCount > 256) ? (pModel->nGenCount - 256) : 0;
  for (i = penaltyStart; i < pModel->nGenCount; i++) {
    int prevTok = pModel->aGenTokens[i];
    int alreadyPenalized = 0;
    for (k = penaltyStart; k < i; k++) {
      if (pModel->aGenTokens[k] == prevTok) {
        alreadyPenalized = 1;
        break;
      }
    }
    if (alreadyPenalized)
      continue;

    count = 0;
    for (k = i; k < pModel->nGenCount; k++) {
      if (pModel->aGenTokens[k] == prevTok)
        count++;
    }

    if (prevTok >= 0 && (uint32_t)prevTok < pModel->config.nVocab) {
      /* Multiplicative penalty scaled by occurrence count */
      float fPenalty = 1.15f + 0.12f * (float)count;
      if (fPenalty > 2.5f)
        fPenalty = 2.5f;

      /* Extra penalty for immediate consecutive token repeat */
      if (pModel->nGenCount > 0 &&
          prevTok == pModel->aGenTokens[pModel->nGenCount - 1]) {
        fPenalty *= 1.4f;
        pModel->pLogits[prevTok] -= 3.0f;
      }

      if (pModel->pLogits[prevTok] > 0.0f) {
        pModel->pLogits[prevTok] /= fPenalty;
      } else {
        pModel->pLogits[prevTok] *= fPenalty;
      }
      /* Additive frequency/presence penalty */
      pModel->pLogits[prevTok] -= 0.35f * (float)count;
    }
  }

  /* N-Gram Repetition Loop Blockers */
  /* 1. 4-gram Repeat Blocker: If (t_{-3}, t_{-2}, t_{-1}) == (t_k, t_{k+1},
   * t_{k+2}), permanently ban t_{k+3} */
  if (pModel->nGenCount >= 3) {
    t1 = pModel->aGenTokens[pModel->nGenCount - 3];
    t2 = pModel->aGenTokens[pModel->nGenCount - 2];
    t3 = pModel->aGenTokens[pModel->nGenCount - 1];
    for (k = 0; k <= pModel->nGenCount - 4; k++) {
      if (pModel->aGenTokens[k] == t1 && pModel->aGenTokens[k + 1] == t2 &&
          pModel->aGenTokens[k + 2] == t3) {
        int banTok = pModel->aGenTokens[k + 3];
        if (banTok >= 0 && (uint32_t)banTok < pModel->config.nVocab) {
          pModel->pLogits[banTok] =
              -1e9f; /* Ban 4-gram repeat loop completely */
        }
      }
    }
  }

  /* 2. 3-gram Soft Penalty: If (t_{-2}, t_{-1}) == (t_k, t_{k+1}), penalize
   * t_{k+2} heavily */
  if (pModel->nGenCount >= 2) {
    t2 = pModel->aGenTokens[pModel->nGenCount - 2];
    t3 = pModel->aGenTokens[pModel->nGenCount - 1];
    for (k = 0; k <= pModel->nGenCount - 3; k++) {
      if (pModel->aGenTokens[k] == t2 && pModel->aGenTokens[k + 1] == t3) {
        int warnTok = pModel->aGenTokens[k + 2];
        if (warnTok >= 0 && (uint32_t)warnTok < pModel->config.nVocab) {
          if (pModel->pLogits[warnTok] > 0.0f) {
            pModel->pLogits[warnTok] /= 2.2f;
          } else {
            pModel->pLogits[warnTok] *= 2.2f;
          }
          pModel->pLogits[warnTok] -= 4.0f;
        }
      }
    }
  }

  /* Suppress immediate EOS on the very first generated token */
  if (pModel->nGenCount == 0) {
    if (pModel->pTokenizer->nEosToken >= 0 &&
        (uint32_t)pModel->pTokenizer->nEosToken < pModel->config.nVocab) {
      pModel->pLogits[pModel->pTokenizer->nEosToken] = -1e9f;
    }
    if (pModel->config.nVocab > 151645) {
      pModel->pLogits[151643] = -1e9f; /* <|endoftext|> */
      pModel->pLogits[151645] = -1e9f; /* <|im_end|> */
    }
  }

  nextToken = ring_model_sample(pModel, pModel->fCurrentTemp);

  /* Check Qwen & BitNet & Standard Stop Tokens */
  if (pModel->nGenCount > 0 && (nextToken == pModel->pTokenizer->nEosToken ||
                                nextToken == 151643 ||  /* <|endoftext|> */
                                nextToken == 151645 ||  /* <|im_end|> */
                                nextToken == 128001 ||  /* <|end_of_text|> */
                                nextToken == 128009)) { /* <|eot_id|> */
    pModel->bGenFinished = 1;
    if (pModel->pTokenizer && pModel->pTokenizer->nUtf8BufLen > 0) {
      char flushBuf[16];
      int flushW = 0;
      ring_tokenizer_flush(pModel->pTokenizer, flushBuf, &flushW,
                           sizeof(flushBuf));
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

  if (!tokenStr)
    return _strdup("");
  return tokenStr;
}

RING_API char *ring_model_generate_stream(RingModel *pModel,
                                          const char *cPrompt, int nMaxTokens,
                                          float fTemp, int bStreamStdout) {
  if (!ring_model_prefill(pModel, cPrompt, nMaxTokens, fTemp))
    return _strdup("");

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
  if (bStreamStdout && pModel->pTokenizer &&
      pModel->pTokenizer->nUtf8BufLen > 0) {
    char flushBuf[16];
    int flushW = 0;
    ring_tokenizer_flush(pModel->pTokenizer, flushBuf, &flushW,
                         sizeof(flushBuf));
    if (flushW > 0) {
      flushBuf[flushW] = '\0';
      fputs(flushBuf, stdout);
      fflush(stdout);
    }
  }

  return ring_tokenizer_decode_tokens(pModel->pTokenizer, pModel->aGenTokens,
                                      pModel->nGenCount);
}

RING_API char *ring_model_generate(RingModel *pModel, const char *cPrompt,
                                   int nMaxTokens, float fTemp) {
  return ring_model_generate_stream(pModel, cPrompt, nMaxTokens, fTemp, 0);
}

/*
================================================================================
  Ring Scripting VM APIs
================================================================================
*/

static void ring_model_gc_free(void *pRingState, void *pPointer) {
  (void)pRingState;
  if (pPointer) {
    ring_model_free((RingModel *)pPointer);
  }
}

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

  RING_API_RETMANAGEDCPOINTER(pModel, "MADAR_MODEL",
                              (void (*)(void *, void *))ring_model_gc_free);
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

  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISNUMBER(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  ring_model_set_threads(pModel, (int)RING_API_GETNUMBER(2));
}

RING_FUNC(ring_model_api_tokenize) {
  RingModel *pModel;
  int aTokens[2048];
  int n, i;
  List *pList;

  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);

  n = ring_tokenizer_encode(pModel->pTokenizer, RING_API_GETSTRING(2), aTokens,
                            2048);

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
    if (nTokens > 1024)
      nTokens = 1024;
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

  if (RING_API_PARACOUNT < 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
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

  if (RING_API_PARACOUNT < 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
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

static RingTensor *ring_model_embedding_bert(void *pRingState,
                                             RingModel *pModel,
                                             const int *aTokens, int nTokens) {
  int nEmbd = (int)pModel->config.nEmbd;
  int nLayers = (int)pModel->config.nLayers;
  int nHeads = (int)pModel->config.nHeads;
  int nHeadDim = (int)pModel->config.nHeadDim;
  int nFF = (int)pModel->config.nFF;
  float eps = pModel->config.fNormEps;
  float scale = 1.0f / sqrtf((float)nHeadDim);
  int S = nTokens;
  int t, l, h, i, j, d;

  if (pModel->nMaxSeq > 0 && S > (int)pModel->nMaxSeq) {
    S = (int)pModel->nMaxSeq;
  } else if (S > 8192) {
    S = 8192;
  }

  float *pSeqX = (float *)calloc((size_t)S * nEmbd, sizeof(float));
  float *pSeqQ = (float *)calloc((size_t)S * nEmbd, sizeof(float));
  float *pSeqK = (float *)calloc((size_t)S * nEmbd, sizeof(float));
  float *pSeqV = (float *)calloc((size_t)S * nEmbd, sizeof(float));
  float *pSeqAttOut = (float *)calloc((size_t)S * nEmbd, sizeof(float));
  float *pActHB = (float *)calloc(nFF, sizeof(float));
  float *pScores = (float *)calloc(S, sizeof(float));

  if (!pSeqX || !pSeqQ || !pSeqK || !pSeqV || !pSeqAttOut || !pActHB ||
      !pScores) {
    if (pSeqX)
      free(pSeqX);
    if (pSeqQ)
      free(pSeqQ);
    if (pSeqK)
      free(pSeqK);
    if (pSeqV)
      free(pSeqV);
    if (pSeqAttOut)
      free(pSeqAttOut);
    if (pActHB)
      free(pActHB);
    if (pScores)
      free(pScores);
    return NULL;
  }

  const uint8_t *pRawEmbd = (const uint8_t *)ring_gguf_get_tensor_data(
      pModel->pGGUF, pModel->pTokenEmbd);
  const void *pPosEmbdData =
      pModel->pPosEmbd
          ? ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pPosEmbd)
          : NULL;
  const void *pTypeData =
      pModel->pTokenTypes
          ? ring_gguf_get_tensor_data(pModel->pGGUF, pModel->pTokenTypes)
          : NULL;
  const float *pEmbNormW = pModel->pTokenEmbdNorm
                               ? (const float *)ring_gguf_get_tensor_data(
                                     pModel->pGGUF, pModel->pTokenEmbdNorm)
                               : NULL;
  const float *pEmbNormB = pModel->pTokenEmbdNorm_Bias
                               ? (const float *)ring_gguf_get_tensor_data(
                                     pModel->pGGUF, pModel->pTokenEmbdNorm_Bias)
                               : NULL;

  /* 1. Embedding lookup + Positional + Types + LayerNorm */
  for (t = 0; t < S; t++) {
    int tok = aTokens[t];
    float *xt = pSeqX + (size_t)t * nEmbd;

    if (tok >= 0 && (uint32_t)tok < pModel->config.nVocab) {
      if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q6_K) {
        const RingGGUFBlockQ6_K *b6 =
            (const RingGGUFBlockQ6_K *)(pRawEmbd +
                                        (size_t)tok * (nEmbd / 256) *
                                            sizeof(RingGGUFBlockQ6_K));
        ring_gguf_dequantize_q6_k(b6, xt, nEmbd);
      } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0) {
        const RingGGUFBlockQ4_0 *b4 =
            (const RingGGUFBlockQ4_0 *)(pRawEmbd +
                                        (size_t)tok * (nEmbd / 32) *
                                            sizeof(RingGGUFBlockQ4_0));
        ring_gguf_dequantize_q4_0(b4, xt, nEmbd);
      } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_1) {
        const RingGGUFBlockQ4_1 *b4_1 =
            (const RingGGUFBlockQ4_1 *)(pRawEmbd +
                                        (size_t)tok * (nEmbd / 32) *
                                            sizeof(RingGGUFBlockQ4_1));
        ring_gguf_dequantize_q4_1(b4_1, xt, nEmbd);
      } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0) {
        const RingGGUFBlockQ8_0 *b8 =
            (const RingGGUFBlockQ8_0 *)(pRawEmbd +
                                        (size_t)tok * (nEmbd / 32) *
                                            sizeof(RingGGUFBlockQ8_0));
        ring_gguf_dequantize_q8_0(b8, xt, nEmbd);
      } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16) {
        ring_gguf_dequantize_f16(
            (const ggml_fp16_t *)pRawEmbd + (size_t)tok * nEmbd, xt, nEmbd);
      } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F32) {
        memcpy(xt, (const float *)pRawEmbd + (size_t)tok * nEmbd,
               nEmbd * sizeof(float));
      }
    }

    /* Learned Absolute Position Embedding (RoBERTa padding offset = 2) */
    if (pPosEmbdData) {
      int posIdx = t + 2;
      if (posIdx >= (int)pModel->config.nCtx)
        posIdx = (int)pModel->config.nCtx - 1;
      const float *posVec =
          (const float *)pPosEmbdData + (size_t)posIdx * nEmbd;
      for (d = 0; d < nEmbd; d++)
        xt[d] += posVec[d];
    }

    /* Token Types */
    if (pTypeData) {
      const float *typeVec = (const float *)pTypeData;
      for (d = 0; d < nEmbd; d++)
        xt[d] += typeVec[d];
    }

    /* Embedding LayerNorm */
    layernorm(xt, xt, pEmbNormW, pEmbNormB, nEmbd, eps);
  }

  /* 2. Transformer Encoder Layers */
  for (l = 0; l < nLayers; l++) {
    RingLayerWeights *layer = &pModel->aLayers[l];
    const float *attnNormW = layer->pAttnNorm
                                 ? (const float *)ring_gguf_get_tensor_data(
                                       pModel->pGGUF, layer->pAttnNorm)
                                 : NULL;
    const float *attnNormB = layer->pAttnNorm_Bias
                                 ? (const float *)ring_gguf_get_tensor_data(
                                       pModel->pGGUF, layer->pAttnNorm_Bias)
                                 : NULL;
    const float *ffnNormW = layer->pFFNNorm
                                ? (const float *)ring_gguf_get_tensor_data(
                                      pModel->pGGUF, layer->pFFNNorm)
                                : NULL;
    const float *ffnNormB = layer->pFFNNorm_Bias
                                ? (const float *)ring_gguf_get_tensor_data(
                                      pModel->pGGUF, layer->pFFNNorm_Bias)
                                : NULL;

    /* A. Compute Q, K, V for all tokens */
    for (t = 0; t < S; t++) {
      matvec_multiply(pModel, layer->pAttnQ, pSeqX + (size_t)t * nEmbd,
                      pSeqQ + (size_t)t * nEmbd, layer->pAttnQ_Bias);
      matvec_multiply(pModel, layer->pAttnK, pSeqX + (size_t)t * nEmbd,
                      pSeqK + (size_t)t * nEmbd, layer->pAttnK_Bias);
      matvec_multiply(pModel, layer->pAttnV, pSeqX + (size_t)t * nEmbd,
                      pSeqV + (size_t)t * nEmbd, layer->pAttnV_Bias);
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
      matvec_multiply(pModel, layer->pAttnOut, attOut, pModel->pActAttnProj,
                      layer->pAttnOut_Bias);
      for (d = 0; d < nEmbd; d++) {
        xi[d] += pModel->pActAttnProj[d];
      }
      layernorm(xi, xi, attnNormW, attnNormB, nEmbd, eps);
    }

    /* D. FFN (GELU) + Residual + LayerNorm */
    for (i = 0; i < S; i++) {
      float *xi = pSeqX + (size_t)i * nEmbd;
      matvec_multiply_gpu(pModel, layer->pFFNUp, layer->pGPUBufUp, xi, pActHB,
                          layer->pFFNUp_Bias);
      for (d = 0; d < nFF; d++) {
        pActHB[d] = fast_gelu(pActHB[d]);
      }
      matvec_multiply_gpu(pModel, layer->pFFNDown, layer->pGPUBufDown, pActHB,
                          pModel->pActFFNOut, layer->pFFNDown_Bias);
      for (d = 0; d < nEmbd; d++) {
        xi[d] += pModel->pActFFNOut[d];
      }
      layernorm(xi, xi, ffnNormW, ffnNormB, nEmbd, eps);
    }
  }

  /* 3. Pooling: CLS token (token 0) or Mean */
  size_t aShape[1];
  aShape[0] = (size_t)nEmbd;
  RingTensor *pTensor =
      ring_tensor_new(pRingState, RING_TENSOR_TYPE_FLOAT32, 1, aShape);
  if (!pTensor) {
    free(pSeqX);
    free(pSeqQ);
    free(pSeqK);
    free(pSeqV);
    free(pSeqAttOut);
    free(pActHB);
    free(pScores);
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

RING_API RingTensor *ring_model_embedding(void *pRingState, RingModel *pModel,
                                          const char *cText) {
  int promptTokens[2048];
  int nPromptTokens, i, d;
  int nEmbd;
  size_t aShape[1];
  RingTensor *pTensor;
  float *pData;
  float *pMean;
  const float *outNormW;
  double sumSq, invNorm, invN;

  if (!pModel || !cText)
    return NULL;
  nEmbd = (int)pModel->config.nEmbd;
  if (nEmbd <= 0)
    return NULL;

  nPromptTokens =
      ring_tokenizer_encode(pModel->pTokenizer, cText, promptTokens, 2048);
  if (nPromptTokens <= 0)
    return NULL;

  if (pModel->config.bIsBert) {
    return ring_model_embedding_bert(pRingState, pModel, promptTokens,
                                     nPromptTokens);
  }

  pMean = (float *)calloc(nEmbd, sizeof(float));
  if (!pMean)
    return NULL;

  outNormW = pModel->pOutputNorm ? (const float *)ring_gguf_get_tensor_data(
                                       pModel->pGGUF, pModel->pOutputNorm)
                                 : NULL;

  ring_model_reset_kv(pModel);

  /* Forward all prompt tokens through Transformer layers and accumulate
   * hidden states for Mean Pooling */
  for (i = 0; i < nPromptTokens; i++) {
    ring_model_forward_ex(pModel, promptTokens[i], i, 0);

    if (outNormW) {
      rmsnorm(pModel->pActXB, pModel->pActX, outNormW, nEmbd,
              pModel->config.fNormEps);
    } else {
      memcpy(pModel->pActXB, pModel->pActX, nEmbd * sizeof(float));
    }

    /* Skip attention sink token at i=0 for significantly sharper semantic
     * contrast */
    if (nPromptTokens > 1 && i == 0)
      continue;

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

  /* Mean pooling average & L2-normalization for unit-vector cosine similarity
   */
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

  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
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

  RING_API_RETMANAGEDCPOINTER(pTensor, "tensor_t",
                              (void (*)(void *, void *))ring_tensor_delete);
}

typedef struct {
  double *data;
  int shape[4];
  int ndim;
  int rows;
  int cols;
  int size;
  int is_owner;
} MadarTensorBridge;

static void extract_token_embedding(RingModel *pModel, int tok, float *xt) {
  int nEmbd = (int)pModel->config.nEmbd;
  const uint8_t *pRawEmbd = (const uint8_t *)ring_gguf_get_tensor_data(
      pModel->pGGUF, pModel->pTokenEmbd);
  if (tok >= 0 && (uint32_t)tok < pModel->config.nVocab && pRawEmbd &&
      pModel->pTokenEmbd) {
    if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q4_0) {
      const RingGGUFBlockQ4_0 *b4 =
          (const RingGGUFBlockQ4_0 *)(pRawEmbd + (size_t)tok * (nEmbd / 32) *
                                                     sizeof(RingGGUFBlockQ4_0));
      ring_gguf_dequantize_q4_0(b4, xt, nEmbd);
    } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_Q8_0) {
      const RingGGUFBlockQ8_0 *b8 =
          (const RingGGUFBlockQ8_0 *)(pRawEmbd + (size_t)tok * (nEmbd / 32) *
                                                     sizeof(RingGGUFBlockQ8_0));
      ring_gguf_dequantize_q8_0(b8, xt, nEmbd);
    } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F16) {
      ring_gguf_dequantize_f16(
          (const ggml_fp16_t *)pRawEmbd + (size_t)tok * nEmbd, xt, nEmbd);
    } else if (pModel->pTokenEmbd->nType == RING_GGUF_TENSOR_F32) {
      memcpy(xt, (const float *)pRawEmbd + (size_t)tok * nEmbd,
             nEmbd * sizeof(float));
    } else {
      memset(xt, 0, nEmbd * sizeof(float));
    }
  } else {
    memset(xt, 0, nEmbd * sizeof(float));
  }
}

RING_FUNC(ring_model_api_forward) {
  RingModel *pModel;
  int nToken, nPos;
  int bComputeLogits = 1;
  if (RING_API_PARACOUNT < 3 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISNUMBER(2) || !RING_API_ISNUMBER(3)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  nToken = (int)RING_API_GETNUMBER(2);
  nPos = (int)RING_API_GETNUMBER(3);
  if (RING_API_PARACOUNT >= 4 && RING_API_ISNUMBER(4)) {
    bComputeLogits = (int)RING_API_GETNUMBER(4);
  }
  ring_model_forward_ex(pModel, nToken, nPos, bComputeLogits);
}

RING_FUNC(ring_model_api_forward_batch) {
  RingModel *pModel;
  List *pList;
  int nStartPos = 0;
  int nTokens, i, start, chunkSize;
  int *pTokens;

  if (RING_API_PARACOUNT < 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISLIST(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);

  pList = RING_API_GETLIST(2);
  nTokens = ring_list_getsize(pList);
  if (nTokens <= 0)
    return;

  if (RING_API_PARACOUNT >= 3 && RING_API_ISNUMBER(3)) {
    nStartPos = (int)RING_API_GETNUMBER(3);
  }

  pTokens = (int *)malloc((size_t)nTokens * sizeof(int));
  if (!pTokens)
    return;

  for (i = 0; i < nTokens; i++) {
    pTokens[i] = (int)ring_list_getdouble(pList, i + 1);
  }

  for (start = 0; start < nTokens; start += chunkSize) {
    chunkSize = (nTokens - start > 32) ? 32 : (nTokens - start);
    ring_model_forward_chunk(pModel, pTokens + start, nStartPos + start, chunkSize,
                             0);
  }

  pModel->nCurPos = nStartPos + nTokens;
  free(pTokens);
}

RING_FUNC(ring_trainer_api_fill_batch) {
  RingModel *pModel;
  MadarTensorBridge *pX;
  MadarTensorBridge *pdY;
  List *pTokensList;
  List *pIndicesList;
  double fLossScale;

  if (RING_API_PARACOUNT != 6 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISPOINTER(2) || !RING_API_ISPOINTER(3) || !RING_API_ISLIST(4) ||
      !RING_API_ISLIST(5) || !RING_API_ISNUMBER(6)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  pX = (MadarTensorBridge *)RING_API_GETCPOINTER(2, "tensor_t");
  pdY = (MadarTensorBridge *)RING_API_GETCPOINTER(3, "tensor_t");
  pTokensList = RING_API_GETLIST(4);
  pIndicesList = RING_API_GETLIST(5);
  fLossScale = RING_API_GETNUMBER(6);

  int nTargets = ring_list_getsize(pIndicesList);
  int nEmbd = (int)pModel->config.nEmbd;
  float *pCur = (float *)malloc((size_t)nEmbd * sizeof(float));
  float *pPrev = (float *)malloc((size_t)nEmbd * sizeof(float));

  if (!pCur || !pPrev) {
    if (pCur)
      free(pCur);
    if (pPrev)
      free(pPrev);
    RING_API_ERROR(RING_OOM);
    return;
  }

  for (int i = 0; i < nTargets; i++) {
    int nTokIdx = (int)ring_list_getdouble(pIndicesList, i + 1);
    int nTokID = (int)ring_list_getdouble(pTokensList, nTokIdx);
    int nPrevID = (nTokIdx > 1)
                      ? (int)ring_list_getdouble(pTokensList, nTokIdx - 1)
                      : nTokID;

    extract_token_embedding(pModel, nPrevID, pPrev);
    extract_token_embedding(pModel, nTokID, pCur);

    /* Compute zero-mean displacement vector */
    double sumDiff = 0.0;
    for (int d = 0; d < nEmbd; d++) {
      sumDiff += (double)(pCur[d] - pPrev[d]);
    }
    double meanDiff = sumDiff / (double)nEmbd;

    for (int d = 0; d < nEmbd; d++) {
      double vX = (double)pPrev[d];
      double vdY = ((double)(pCur[d] - pPrev[d]) - meanDiff) * fLossScale;
      pX->data[i * nEmbd + d] = vX;
      pdY->data[i * nEmbd + d] = vdY;
    }
  }

  free(pCur);
  free(pPrev);
  RING_API_RETNUMBER(1);
}

RING_FUNC(ring_model_api_get_token_embeddings) {
  RingModel *pModel;
  List *pTokensList;
  RingTensor *pTensor;
  int nTokens, t;
  size_t aShape[2];
  float *pData;
  int nEmbd;

  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISLIST(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);

  pTokensList = RING_API_GETLIST(2);
  nTokens = ring_list_getsize(pTokensList);
  if (nTokens <= 0) {
    RING_API_ERROR("Token list is empty!");
    return;
  }

  nEmbd = (int)pModel->config.nEmbd;
  aShape[0] = (size_t)nTokens;
  aShape[1] = (size_t)nEmbd;

  pTensor =
      ring_tensor_new(RING_API_STATE, RING_TENSOR_TYPE_FLOAT32, 2, aShape);
  if (!pTensor) {
    RING_API_ERROR("Failed to allocate tensor for embeddings!");
    return;
  }
  pData = (float *)ring_tensor_data(pTensor);

  for (t = 0; t < nTokens; t++) {
    int tok = (int)ring_list_getdouble(pTokensList, t + 1);
    float *xt = pData + (size_t)t * nEmbd;
    extract_token_embedding(pModel, tok, xt);
  }

  RING_API_RETMANAGEDCPOINTER(pTensor, "tensor_t",
                              (void (*)(void *, void *))ring_tensor_delete);
}

RING_FUNC(ring_model_api_prefill) {
  RingModel *pModel;
  const char *cPrompt;
  int nMaxTokens = 128;
  float fTemp = 0.7f;
  int nPromptTokens;

  if (RING_API_PARACOUNT < 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
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
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISNUMBER(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  bEnable = (int)RING_API_GETNUMBER(2);
  ring_model_set_gpu(pModel, bEnable);
}

RING_FUNC(ring_model_api_load_lora) {
  RingModel *pModel;
  const char *cDir;
  int res;
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  cDir = RING_API_GETSTRING(2);
  res = ring_model_load_lora(pModel, cDir);
  RING_API_RETNUMBER(res);
}

RING_FUNC(ring_model_api_enable_lora) {
  RingModel *pModel;
  int bEnable;
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISNUMBER(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  bEnable = (int)RING_API_GETNUMBER(2);
  ring_model_enable_lora(pModel, bEnable);
}

RING_FUNC(ring_model_api_set_lora_scale) {
  RingModel *pModel;
  float fScale;
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISNUMBER(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  fScale = (float)RING_API_GETNUMBER(2);
  ring_model_set_lora_scale(pModel, fScale);
}

RING_FUNC(ring_model_api_export_merged_gguf) {
  RingModel *pModel;
  const char *cOutGGUFPath;
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  cOutGGUFPath = RING_API_GETSTRING(2);
  int nRes = ring_model_export_merged_gguf(pModel, cOutGGUFPath);
  RING_API_RETNUMBER(nRes);
}

RING_FUNC(ring_model_api_get_dim) {
  RingModel *pModel;
  if (RING_API_PARACOUNT != 1 || !RING_API_ISPOINTER(1)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  RING_API_RETNUMBER((double)pModel->config.nEmbd);
}

RING_FUNC(ring_model_api_init_lora) {
  RingModel *pModel;
  int nRank;
  float fAlpha;
  if (RING_API_PARACOUNT < 1 || !RING_API_ISPOINTER(1)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  nRank = (RING_API_PARACOUNT >= 2 && RING_API_ISNUMBER(2))
              ? (int)RING_API_GETNUMBER(2)
              : 16;
  fAlpha = (RING_API_PARACOUNT >= 3 && RING_API_ISNUMBER(3))
               ? (float)RING_API_GETNUMBER(3)
               : 32.0f;
  int res = ring_model_init_lora(pModel, nRank, fAlpha);
  RING_API_RETNUMBER(res);
}

RING_FUNC(ring_model_api_train_token) {
  RingModel *pModel;
  int nTargetToken;
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISNUMBER(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  nTargetToken = (int)RING_API_GETNUMBER(2);
  float loss = ring_model_train_token(pModel, nTargetToken);
  RING_API_RETNUMBER((double)loss);
}

RING_FUNC(ring_model_api_optimizer_step) {
  RingModel *pModel;
  float fLR, fWeightDecay;
  if (RING_API_PARACOUNT < 1 || !RING_API_ISPOINTER(1)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  fLR = (RING_API_PARACOUNT >= 2 && RING_API_ISNUMBER(2))
            ? (float)RING_API_GETNUMBER(2)
            : 0.0003f;
  fWeightDecay = (RING_API_PARACOUNT >= 3 && RING_API_ISNUMBER(3))
                     ? (float)RING_API_GETNUMBER(3)
                     : 0.01f;
  ring_model_optimizer_step(pModel, fLR, fWeightDecay);
  RING_API_RETNUMBER(1);
}

RING_FUNC(ring_model_api_save_lora) {
  RingModel *pModel;
  const char *cFolder;
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  cFolder = RING_API_GETSTRING(2);
  int res = ring_model_save_lora(pModel, cFolder);
  RING_API_RETNUMBER(res);
}

RING_FUNC(ring_model_api_load_lora_folder) {
  RingModel *pModel;
  const char *cFolder;
  if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) ||
      !RING_API_ISSTRING(2)) {
    RING_API_ERROR(RING_API_BADPARATYPE);
    return;
  }
  pModel = (RingModel *)RING_API_GETCPOINTER(1, "MADAR_MODEL");
  RING_API_CHECKNULLPOINTER(pModel);
  cFolder = RING_API_GETSTRING(2);
  int res = ring_model_load_lora_folder(pModel, cFolder);
  RING_API_RETNUMBER(res);
}

RING_API void ring_inference_loadfunctions(void *pRingState) {
  RING_API_REGISTER("madar_model_open", ring_model_api_open);
  RING_API_REGISTER("madar_model_close", ring_model_api_close);
  RING_API_REGISTER("madar_model_set_threads", ring_model_api_set_threads);
  RING_API_REGISTER("madar_model_set_gpu", ring_model_api_set_gpu);
  RING_API_REGISTER("madar_model_get_dim", ring_model_api_get_dim);
  RING_API_REGISTER("madar_model_load_lora", ring_model_api_load_lora);
  RING_API_REGISTER("madar_model_enable_lora", ring_model_api_enable_lora);
  RING_API_REGISTER("madar_model_set_lora_scale",
                    ring_model_api_set_lora_scale);
  RING_API_REGISTER("madar_model_export_merged_gguf",
                    ring_model_api_export_merged_gguf);
  RING_API_REGISTER("madar_lora_init", ring_model_api_init_lora);
  RING_API_REGISTER("madar_lora_train_token", ring_model_api_train_token);
  RING_API_REGISTER("madar_lora_optimizer_step", ring_model_api_optimizer_step);
  RING_API_REGISTER("madar_lora_save", ring_model_api_save_lora);
  RING_API_REGISTER("madar_lora_load", ring_model_api_load_lora_folder);
  RING_API_REGISTER("madar_model_tokenize", ring_model_api_tokenize);
  RING_API_REGISTER("madar_model_detokenize", ring_model_api_detokenize);
  RING_API_REGISTER("madar_model_generate", ring_model_api_generate);
  RING_API_REGISTER("madar_model_generate_stream",
                    ring_model_api_generate_stream);
  RING_API_REGISTER("madar_model_prefill", ring_model_api_prefill);
  RING_API_REGISTER("madar_model_has_more", ring_model_api_has_more);
  RING_API_REGISTER("madar_model_step", ring_model_api_step);
  RING_API_REGISTER("madar_model_reset", ring_model_api_reset);
  RING_API_REGISTER("madar_is_arabic", ring_model_api_is_arabic);
  RING_API_REGISTER("madar_model_embedding", ring_model_api_embedding);
  RING_API_REGISTER("madar_model_get_token_embeddings",
                    ring_model_api_get_token_embeddings);
  RING_API_REGISTER("madar_model_forward", ring_model_api_forward);
  RING_API_REGISTER("madar_model_forward_batch",
                    ring_model_api_forward_batch);
  RING_API_REGISTER("madar_trainer_fill_batch", ring_trainer_api_fill_batch);
}
