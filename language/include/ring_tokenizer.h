/*
**  Madar - High-Performance AI-Native Runtime
**  GGUF Byte-Pair Encoding (BPE) Tokenizer
**  Pure ANSI C / C99 Implementation
*/

#ifndef ring_tokenizer_h
#define ring_tokenizer_h

#include "ring_gguf.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RingTokenEntry {
	char *pStr;
	int nId;
	float fScore;
	struct RingTokenEntry *pNext;
} RingTokenEntry;

typedef struct RingMergeEntry {
	int id1;
	int id2;
	int nRank;
	int nMergedId;
	struct RingMergeEntry *pNext;
} RingMergeEntry;

typedef struct RingTokenizer {
	RingGGUF *pGGUF;
	uint32_t nVocabSize;
	char **aTokens;
	float *aScores;
	int nBosToken;
	int nEosToken;
	int nPadToken;
	bool bIsByteLevelBPE; /* true if uses GPT-2/Qwen style byte tokens or 'Ġ' */

	/* Vocabulary string -> ID hash table */
	RingTokenEntry **aBuckets;
	uint32_t nBuckets;
	uint32_t nBucketMask;

	/* BPE Merge rules table: (id1, id2) -> merged */
	RingMergeEntry **aMergeBuckets;
	uint32_t nMergeBuckets;
	uint32_t nMergeBucketMask;
	uint32_t nMergesCount;

	/* Direct raw byte -> Token ID (0..255) */
	int aByteToToken[256];
} RingTokenizer;

/* Tokenizer Lifecycle */
RING_API RingTokenizer *ring_tokenizer_create(RingGGUF *pGGUF);
RING_API void ring_tokenizer_delete(RingTokenizer *pTok);

/* Tokenizer Core Operations */
RING_API int ring_tokenizer_find_token(RingTokenizer *pTok, const char *cStr);
RING_API int ring_tokenizer_encode(RingTokenizer *pTok, const char *cText, int *aOutTokens, int nMaxTokens);
RING_API int ring_tokenizer_decode(RingTokenizer *pTok, int nTokenId, char *cOutBuf, int nMaxLen);
RING_API char *ring_tokenizer_decode_tokens(RingTokenizer *pTok, const int *aTokens, int nTokenCount);

/* VM Registration */
RING_API void ring_tokenizer_loadfunctions(void *pRingState);

#ifdef __cplusplus
}
#endif

#endif /* ring_tokenizer_h */
