/*
**  Madar - High-Performance AI-Native Runtime
**  Lightweight Transformer & Qwen Inference Engine
**  Pure ANSI C / C99 Implementation
*/

#ifndef ring_inference_h
#define ring_inference_h

#include "ring_gguf.h"
#include "ring_tokenizer.h"
#include "ring_tensor.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RingModelConfig {
	char cArch[32];
	uint32_t nVocab;
	uint32_t nCtx;
	uint32_t nEmbd;
	uint32_t nLayers;
	uint32_t nHeads;
	uint32_t nHeadsKV;
	uint32_t nHeadDim;
	uint32_t nFF;
	float fNormEps;
	float fRopeFreqBase;
} RingModelConfig;

typedef struct RingLayerWeights {
	RingGGUFTensorInfo *pAttnNorm;
	RingGGUFTensorInfo *pAttnQ;
	RingGGUFTensorInfo *pAttnQ_Bias;
	RingGGUFTensorInfo *pAttnK;
	RingGGUFTensorInfo *pAttnK_Bias;
	RingGGUFTensorInfo *pAttnV;
	RingGGUFTensorInfo *pAttnV_Bias;
	RingGGUFTensorInfo *pAttnOut;

	RingGGUFTensorInfo *pFFNNorm;
	RingGGUFTensorInfo *pFFNGate;
	RingGGUFTensorInfo *pFFNUp;
	RingGGUFTensorInfo *pFFNDown;

	/* Pre-mapped GPU Zero-Copy Buffers */
	void *pGPUBufGate;
	void *pGPUBufUp;
	void *pGPUBufDown;
} RingLayerWeights;

typedef struct RingModel {
	RingGGUF *pGGUF;
	RingTokenizer *pTokenizer;
	RingModelConfig config;
	int nThreads; /* Default: 2 */

	/* Model Weights */
	RingGGUFTensorInfo *pTokenEmbd;
	RingLayerWeights *aLayers;
	RingGGUFTensorInfo *pOutputNorm;
	RingGGUFTensorInfo *pOutput;

	/* KV Cache (Compressed FP16) */
	uint32_t nMaxSeq;      /* Max context in KV cache, e.g. 2048 */
	uint32_t nKVDim;       /* nHeadsKV * nHeadDim */
	ggml_fp16_t *pKVCache_K;     /* [nLayers * nMaxSeq * nKVDim] (16-bit FP16) */
	ggml_fp16_t *pKVCache_V;     /* [nLayers * nMaxSeq * nKVDim] (16-bit FP16) */
	float *pAttScores;           /* [nMaxSeq] Attention scores scratch buffer */

	/* Working Activation Buffers */
	float *pActX;          /* [nEmbd] */
	float *pActXB;         /* [nEmbd] */
	float *pActQ;          /* [nHeads * nHeadDim] */
	float *pActK;          /* [nHeadsKV * nHeadDim] */
	float *pActV;          /* [nHeadsKV * nHeadDim] */
	float *pActAttOut;     /* [nHeads * nHeadDim] Attention Head Output */
	float *pActHB;         /* [nFF] */
	float *pActHB2;        /* [nFF] */
	float *pActAttnProj;   /* [nEmbd] Attention Projection Output */
	float *pActFFNOut;     /* [nEmbd] Feed Forward Output */
	float *pLogits;        /* [nVocab] */

#define RING_MODEL_MAX_WORKERS 7

	/* Worker Thread Pool for Parallel MatVec */
	int nWorkerCount;
	void *hWorkerThreads[RING_MODEL_MAX_WORKERS];
	void *hStartEvents[RING_MODEL_MAX_WORKERS];
	void *hDoneEvents[RING_MODEL_MAX_WORKERS];
	void *pWorkerTasks[RING_MODEL_MAX_WORKERS];
	volatile int bWorkerShutdown;

	/* GPU Acceleration (OpenCL Engine) */
	int bGPUEnabled;
	void *pGPUContext;
	void *pGPUQueue;
	void *pGPUKernelQ4;
	void *pGPUKernelQ8;
	void *pGPUKernelQ6;
	void *pGPUBufX;
	void *pGPUBufY;
	void *pGPUBufOutputWeight;
	size_t nGPUBufXSize;
	size_t nGPUBufYSize;

	/* Step-by-Step Generator & Streaming State */
	int aGenTokens[2048];
	int nPromptTokens;
	int nGenCount;
	int nMaxGenTokens;
	int nCurPos;
	float fCurrentTemp;
	int bGenFinished;
} RingModel;

/* Inference Engine Lifecycle */
RING_API RingModel *ring_model_load(const char *cFileName);
RING_API void ring_model_free(RingModel *pModel);

/* Model Configuration & State */
RING_API void ring_model_set_threads(RingModel *pModel, int nThreads);
RING_API void ring_model_set_gpu(RingModel *pModel, int bEnable);
RING_API void ring_model_reset_kv(RingModel *pModel);

/* Forward Evaluation & Sampling */
RING_API void ring_model_forward(RingModel *pModel, int nToken, int nPos);
RING_API void ring_model_forward_ex(RingModel *pModel, int nToken, int nPos, int bComputeLogits);
RING_API int ring_model_sample(RingModel *pModel, float fTemp);
RING_API char *ring_model_generate(RingModel *pModel, const char *cPrompt, int nMaxTokens, float fTemp);
RING_API char *ring_model_generate_stream(RingModel *pModel, const char *cPrompt, int nMaxTokens, float fTemp, int bStreamStdout);
RING_API int ring_model_prefill(RingModel *pModel, const char *cPrompt, int nMaxTokens, float fTemp);
RING_API char *ring_model_step(RingModel *pModel);
RING_API int ring_model_has_more(RingModel *pModel);
RING_API RingTensor *ring_model_embedding(void *pRingState, RingModel *pModel, const char *cText);

/* VM Registration */
RING_API void ring_inference_loadfunctions(void *pRingState);

#ifdef __cplusplus
}
#endif

#endif /* ring_inference_h */
