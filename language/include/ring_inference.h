/*
**  Madar - High-Performance AI-Native Runtime
**  Lightweight Transformer & Qwen Inference Engine
**  Pure ANSI C / C99 Implementation
*/

#ifndef ring_inference_h
#define ring_inference_h

#ifndef ring_h
#include "ring.h"
#endif

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
	int bIsBert;       /* 1 if BERT/XLM-RoBERTa encoder architecture */
	int bIsBitNet;     /* 1 if BitNet b1.58 SubLN architecture with ReLU^2 */
	int nPoolingType;  /* 1=mean, 2=cls */
} RingModelConfig;

typedef struct RingLayerWeights {
	RingGGUFTensorInfo *pAttnNorm;
	RingGGUFTensorInfo *pAttnNorm_Bias;
	RingGGUFTensorInfo *pAttnQ;
	RingGGUFTensorInfo *pAttnQ_Bias;
	RingGGUFTensorInfo *pAttnK;
	RingGGUFTensorInfo *pAttnK_Bias;
	RingGGUFTensorInfo *pAttnV;
	RingGGUFTensorInfo *pAttnV_Bias;
	RingGGUFTensorInfo *pAttnOut;
	RingGGUFTensorInfo *pAttnOut_Bias;
	RingGGUFTensorInfo *pAttnSubNorm;   /* BitNet inner attention SubLN */

	RingGGUFTensorInfo *pFFNNorm;
	RingGGUFTensorInfo *pFFNNorm_Bias;
	RingGGUFTensorInfo *pFFNGate;
	RingGGUFTensorInfo *pFFNUp;
	RingGGUFTensorInfo *pFFNUp_Bias;
	RingGGUFTensorInfo *pFFNSubNorm;    /* BitNet FFN SubLN */
	RingGGUFTensorInfo *pFFNDown;
	RingGGUFTensorInfo *pFFNDown_Bias;

	/* Pre-mapped GPU Zero-Copy Buffers */
	void *pGPUBufGate;
	void *pGPUBufUp;
	void *pGPUBufDown;
} RingLayerWeights;

typedef struct RingLoRALayerAdapter {
	int bActive;
	float *pA_Q;    /* [nRank * nEmbd] */
	float *pB_Q;    /* [nEmbd * nRank] */
	float *pA_Out;  /* [nRank * nEmbd] */
	float *pB_Out;  /* [nEmbd * nRank] */
	float *pdA_Q;   /* Gradient Accumulators */
	float *pdB_Q;
	float *pdA_Out;
	float *pdB_Out;
	float *pMA_Q;   /* AdamW 1st moment (Mean) */
	float *pVA_Q;   /* AdamW 2nd moment (Variance) */
	float *pMB_Q;
	float *pVB_Q;
	float *pMA_Out;
	float *pVA_Out;
	float *pMB_Out;
	float *pVB_Out;
} RingLoRALayerAdapter;

typedef struct RingModel {
	RingGGUF *pGGUF;
	RingTokenizer *pTokenizer;
	RingModelConfig config;
	int nThreads; /* Default: 2 */

	/* Model Weights */
	RingGGUFTensorInfo *pTokenEmbd;
	RingGGUFTensorInfo *pPosEmbd;
	RingGGUFTensorInfo *pTokenTypes;
	RingGGUFTensorInfo *pTokenEmbdNorm;
	RingGGUFTensorInfo *pTokenEmbdNorm_Bias;
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
	void *pGPUKernelQ4_1;
	void *pGPUKernelQ8;
	void *pGPUKernelQ6;
	void *pGPUKernelQ4Batch;
	void *pGPUKernelSiLUBatch;
	void *pGPUKernelI2_S;
	void *pGPUKernelI2_SBatch;
	void *pGPUBufX;
	void *pGPUBufY;
	void *pGPUBufGate;
	void *pGPUBufUp;
	void *pGPUBufDown;
	void *pGPUBufOutputWeight;
	size_t nGPUBufXSize;
	size_t nGPUBufYSize;
	size_t nGPUBufFFNSize;

	/* Step-by-Step Generator & Streaming State */
	int aGenTokens[8192];
	int nPromptTokens;
	int nGenCount;
	int nMaxGenTokens;
	int nCurPos;
	float fCurrentTemp;
	int bGenFinished;

	/* LoRA Adapter Fusion (Zero-Copy Native Merge) */
	int bLoRAEnabled;
	float fLoRAScale;
	int nLoRARank;
	float *pLoRA_A_Q;     /* [nRank * nEmbd] */
	float *pLoRA_B_Q;     /* [nEmbd * nRank] */
	float *pLoRA_A_V;     /* [nRank * nEmbd] */
	float *pLoRA_B_V;     /* [nEmbd * nRank] */
	float *pLoRA_A_Out;   /* [nRank * nEmbd] */
	float *pLoRA_B_Out;   /* [nEmbd * nRank] */
	float *pLoRA_Scratch; /* [nRank] */
	/* Multi-Layer LoRA Causal Training Engine */
	int bMultiLayerLoRA;
	float fLoRAAlpha;
	void *aLoRALayers;                 /* RingLoRALayerAdapter [nLayers] */
	float *pLayerActIn;                /* [nLayers * nEmbd] */
	float *pGradH;                     /* [nEmbd] */
	uint64_t nTrainTokens;
	uint32_t nStepAccumTokens;
	uint64_t nOptimizerSteps;
} RingModel;

/* Inference Engine Lifecycle */
RING_API RingModel *ring_model_load(const char *cFileName);
RING_API void ring_model_free(RingModel *pModel);

/* Model Configuration & State */
RING_API void ring_model_set_threads(RingModel *pModel, int nThreads);
RING_API void ring_model_set_gpu(RingModel *pModel, int bEnable);
RING_API void ring_model_reset_kv(RingModel *pModel);
RING_API int ring_model_load_lora(RingModel *pModel, const char *cAdapterDir);
RING_API void ring_model_enable_lora(RingModel *pModel, int bEnable);
RING_API void ring_model_set_lora_scale(RingModel *pModel, float fScale);
RING_API int ring_model_export_merged_gguf(RingModel *pModel, const char *cOutGGUFPath);

/* Native Multi-Layer LoRA Causal Training */
RING_API int ring_model_init_lora(RingModel *pModel, int nRank, float fAlpha);
RING_API float ring_model_train_token(RingModel *pModel, int nTargetToken);
RING_API void ring_model_optimizer_step(RingModel *pModel, float fLR, float fWeightDecay);
RING_API int ring_model_save_lora(RingModel *pModel, const char *cFolder);
RING_API int ring_model_load_lora_folder(RingModel *pModel, const char *cFolder);

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
