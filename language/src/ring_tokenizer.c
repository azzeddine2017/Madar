/*
**  Madar - High-Performance AI-Native Runtime
**  GGUF Byte-Pair Encoding (BPE) Tokenizer
**  Pure ANSI C / C99 Implementation
*/

#include "ring.h"
#include "ring_tokenizer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/*
================================================================================
  Hash Helpers
================================================================================
*/

static uint32_t tokenizer_hash_str(const char *str) {
	uint32_t hash = 2166136261u;
	while (*str) {
		hash ^= (unsigned char)(*str++);
		hash *= 16777619u;
	}
	return hash;
}

static uint32_t tokenizer_hash_pair(int id1, int id2) {
	uint32_t h = (uint32_t)id1 * 2654435761u;
	h ^= (uint32_t)id2 * 2246822519u;
	return h;
}

static uint32_t next_power_of_two(uint32_t n) {
	if (n < 16) return 16;
	n--;
	n |= n >> 1;
	n |= n >> 2;
	n |= n >> 4;
	n |= n >> 8;
	n |= n >> 16;
	return n + 1;
}

/*
================================================================================
  GPT-2 / Qwen Byte-Level BPE Reversible Mapping (bytes_to_unicode)
================================================================================
*/

typedef struct GPT2ByteMap {
	char utf8[4];
	int len;
} GPT2ByteMap;

static GPT2ByteMap s_gpt2_byte_to_utf8[256];
static uint8_t s_gpt2_code_to_byte[1024];
static int s_gpt2_init_done = 0;

static void gpt2_init_mapping(void) {
	int bs[256];
	int cs[256];
	int count = 0;
	int b, i, n;

	if (s_gpt2_init_done) return;

	/* Safe printable ASCII and Latin-1 ranges */
	for (b = '!'; b <= '~'; b++) { bs[count] = b; cs[count] = b; count++; }
	for (b = 161; b <= 172; b++) { bs[count] = b; cs[count] = b; count++; }
	for (b = 174; b <= 255; b++) { bs[count] = b; cs[count] = b; count++; }

	n = 0;
	for (b = 0; b < 256; b++) {
		int found = 0;
		for (i = 0; i < count; i++) {
			if (bs[i] == b) { found = 1; break; }
		}
		if (!found) {
			bs[count] = b;
			cs[count] = 256 + n;
			count++;
			n++;
		}
	}

	memset(s_gpt2_code_to_byte, 0, sizeof(s_gpt2_code_to_byte));
	for (i = 0; i < 256; i++) {
		b = bs[i];
		int code = cs[i];
		if (code < 1024) {
			s_gpt2_code_to_byte[code] = (uint8_t)b;
		}
		if (code < 128) {
			s_gpt2_byte_to_utf8[b].utf8[0] = (char)code;
			s_gpt2_byte_to_utf8[b].utf8[1] = '\0';
			s_gpt2_byte_to_utf8[b].len = 1;
		} else {
			s_gpt2_byte_to_utf8[b].utf8[0] = (char)(0xC0 | (code >> 6));
			s_gpt2_byte_to_utf8[b].utf8[1] = (char)(0x80 | (code & 0x3F));
			s_gpt2_byte_to_utf8[b].utf8[2] = '\0';
			s_gpt2_byte_to_utf8[b].len = 2;
		}
	}
	s_gpt2_init_done = 1;
}

/*
================================================================================
  Tokenizer Lifecycle
================================================================================
*/

RING_API RingTokenizer *ring_tokenizer_create(RingGGUF *pGGUF) {
	RingTokenizer *pTok;
	RingGGUFKV *pKvTokens, *pKvScores, *pKvMerges, *pKvBos, *pKvEos;
	uint32_t i, hIdx;
	char **ppTokens;
	const char *s;
	RingTokenEntry *pEntry;
	size_t sLen;
	char hex[3];
	unsigned int byteVal;
	unsigned char b;
	char **ppMerges;
	const char *mergeLine, *space, *strB;
	size_t lenA;
	char strA[256];
	int idA, idB, mergedId;
	char mergedStr[512];
	uint32_t mHash;
	RingMergeEntry *pMEntry;

	if (!pGGUF) return NULL;

	pKvTokens = ring_gguf_find_kv(pGGUF, "tokenizer.ggml.tokens");
	if (!pKvTokens || pKvTokens->value.nType != RING_GGUF_TYPE_ARRAY ||
		pKvTokens->value.val.arr.nItemType != RING_GGUF_TYPE_STRING) {
		printf("\n[MADAR TOKENIZER] Error: 'tokenizer.ggml.tokens' not found or invalid in GGUF metadata!\n");
		if (pKvTokens) {
			printf("  [DEBUG] KV Type=%d (expected %d), ItemType=%d (expected %d)\n",
				pKvTokens->value.nType, RING_GGUF_TYPE_ARRAY,
				pKvTokens->value.val.arr.nItemType, RING_GGUF_TYPE_STRING);
		}
		return NULL;
	}

	pTok = (RingTokenizer *)calloc(1, sizeof(RingTokenizer));
	if (!pTok) {
		printf("\n[MADAR TOKENIZER] Error: Out of memory allocating RingTokenizer struct!\n");
		return NULL;
	}

	pTok->pGGUF = pGGUF;
	pTok->nVocabSize = (uint32_t)pKvTokens->value.val.arr.nCount;
	pTok->aTokens = (char **)pKvTokens->value.val.arr.pItems;
	ppTokens = pTok->aTokens;

	/* Scores (optional) */
	pKvScores = ring_gguf_find_kv(pGGUF, "tokenizer.ggml.scores");
	if (pKvScores && pKvScores->value.nType == RING_GGUF_TYPE_ARRAY &&
		pKvScores->value.val.arr.nItemType == RING_GGUF_TYPE_FLOAT32) {
		pTok->aScores = (float *)pKvScores->value.val.arr.pItems;
	}

	/* Special Tokens */
	pTok->nBosToken = -1;
	pKvBos = ring_gguf_find_kv(pGGUF, "tokenizer.ggml.bos_token_id");
	if (pKvBos) {
		if (pKvBos->value.nType == RING_GGUF_TYPE_UINT32) pTok->nBosToken = (int)pKvBos->value.val.u32;
		else if (pKvBos->value.nType == RING_GGUF_TYPE_INT32) pTok->nBosToken = pKvBos->value.val.i32;
	}

	pTok->nEosToken = -1;
	pKvEos = ring_gguf_find_kv(pGGUF, "tokenizer.ggml.eos_token_id");
	if (pKvEos) {
		if (pKvEos->value.nType == RING_GGUF_TYPE_UINT32) pTok->nEosToken = (int)pKvEos->value.val.u32;
		else if (pKvEos->value.nType == RING_GGUF_TYPE_INT32) pTok->nEosToken = pKvEos->value.val.i32;
	}

	/* Build Vocabulary Hash Table */
	pTok->nBuckets = next_power_of_two(pTok->nVocabSize * 2);
	pTok->nBucketMask = pTok->nBuckets - 1;
	pTok->aBuckets = (RingTokenEntry **)calloc(pTok->nBuckets, sizeof(RingTokenEntry *));
	if (!pTok->aBuckets) {
		free(pTok);
		return NULL;
	}

	/* Initialize byte-to-token table */
	for (i = 0; i < 256; i++) {
		pTok->aByteToToken[i] = -1;
	}

	/* Populate hash table and byte mapping */
	for (i = 0; i < pTok->nVocabSize; i++) {
		s = ppTokens[i];
		if (!s) continue;

		hIdx = tokenizer_hash_str(s) & pTok->nBucketMask;
		pEntry = (RingTokenEntry *)malloc(sizeof(RingTokenEntry));
		if (pEntry) {
			pEntry->pStr = ppTokens[i];
			pEntry->nId = (int)i;
			pEntry->fScore = pTok->aScores ? pTok->aScores[i] : 0.0f;
			pEntry->pNext = pTok->aBuckets[hIdx];
			pTok->aBuckets[hIdx] = pEntry;
		}

		/* Byte tokens: e.g. "<0x0A>" or single byte */
		sLen = strlen(s);
		if (sLen == 6 && s[0] == '<' && s[1] == '0' && s[2] == 'x' && s[5] == '>') {
			hex[0] = s[3];
			hex[1] = s[4];
			hex[2] = '\0';
			byteVal = 0;
			if (sscanf(hex, "%x", &byteVal) == 1 && byteVal < 256) {
				pTok->aByteToToken[byteVal] = (int)i;
			}
		} else if (sLen == 1) {
			b = (unsigned char)s[0];
			if (pTok->aByteToToken[b] == -1) {
				pTok->aByteToToken[b] = (int)i;
			}
		}

		/* Detect GPT-2/Qwen style 'Ġ' (0xC4 0xA0) */
		if (strstr(s, "\xc4\xa0") != NULL) {
			pTok->bIsByteLevelBPE = true;
		}
	}

	/* Initialize GPT-2 byte mapping and map all 256 bytes to tokens */
	gpt2_init_mapping();
	for (i = 0; i < 256; i++) {
		if (pTok->aByteToToken[i] == -1) {
			pTok->aByteToToken[i] = ring_tokenizer_find_token(pTok, s_gpt2_byte_to_utf8[i].utf8);
		}
	}

	/* Populate BPE Merges Table */
	pKvMerges = ring_gguf_find_kv(pGGUF, "tokenizer.ggml.merges");
	if (pKvMerges && pKvMerges->value.nType == RING_GGUF_TYPE_ARRAY &&
		pKvMerges->value.val.arr.nItemType == RING_GGUF_TYPE_STRING) {
		ppMerges = (char **)pKvMerges->value.val.arr.pItems;
		pTok->nMergesCount = (uint32_t)pKvMerges->value.val.arr.nCount;
		pTok->nMergeBuckets = next_power_of_two(pTok->nMergesCount * 2);
		pTok->nMergeBucketMask = pTok->nMergeBuckets - 1;
		pTok->aMergeBuckets = (RingMergeEntry **)calloc(pTok->nMergeBuckets, sizeof(RingMergeEntry *));

		if (pTok->aMergeBuckets) {
			for (i = 0; i < pTok->nMergesCount; i++) {
				mergeLine = ppMerges[i];
				if (!mergeLine) continue;

				/* Merge lines are typically: "tokenA tokenB" */
				space = strchr(mergeLine, ' ');
				if (!space) continue;

				lenA = space - mergeLine;
				strB = space + 1;

				if (lenA < sizeof(strA)) {
					strncpy(strA, mergeLine, lenA);
					strA[lenA] = '\0';

					idA = ring_tokenizer_find_token(pTok, strA);
					idB = ring_tokenizer_find_token(pTok, strB);

					if (idA >= 0 && idB >= 0) {
						/* Find merged token ID */
						snprintf(mergedStr, sizeof(mergedStr), "%s%s", strA, strB);
						mergedId = ring_tokenizer_find_token(pTok, mergedStr);

						mHash = tokenizer_hash_pair(idA, idB) & pTok->nMergeBucketMask;
						pMEntry = (RingMergeEntry *)malloc(sizeof(RingMergeEntry));
						if (pMEntry) {
							pMEntry->id1 = idA;
							pMEntry->id2 = idB;
							pMEntry->nRank = (int)i;
							pMEntry->nMergedId = mergedId;
							pMEntry->pNext = pTok->aMergeBuckets[mHash];
							pTok->aMergeBuckets[mHash] = pMEntry;
						}
					}
				}
			}
		}
	}

	return pTok;
}

RING_API void ring_tokenizer_delete(RingTokenizer *pTok) {
	uint32_t i;
	RingTokenEntry *p, *nextP;
	RingMergeEntry *m, *nextM;

	if (!pTok) return;

	if (pTok->aBuckets) {
		for (i = 0; i < pTok->nBuckets; i++) {
			p = pTok->aBuckets[i];
			while (p) {
				nextP = p->pNext;
				free(p);
				p = nextP;
			}
		}
		free(pTok->aBuckets);
	}

	if (pTok->aMergeBuckets) {
		for (i = 0; i < pTok->nMergeBuckets; i++) {
			m = pTok->aMergeBuckets[i];
			while (m) {
				nextM = m->pNext;
				free(m);
				m = nextM;
			}
		}
		free(pTok->aMergeBuckets);
	}

	free(pTok);
}

/*
================================================================================
  Token Lookup
================================================================================
*/

RING_API int ring_tokenizer_find_token(RingTokenizer *pTok, const char *cStr) {
	uint32_t hIdx;
	RingTokenEntry *p;

	if (!pTok || !cStr || !pTok->aBuckets) return -1;
	hIdx = tokenizer_hash_str(cStr) & pTok->nBucketMask;
	p = pTok->aBuckets[hIdx];
	while (p) {
		if (strcmp(p->pStr, cStr) == 0) {
			return p->nId;
		}
		p = p->pNext;
	}
	return -1;
}

static RingMergeEntry *tokenizer_find_merge(RingTokenizer *pTok, int id1, int id2) {
	uint32_t hIdx;
	RingMergeEntry *p;

	if (!pTok || !pTok->aMergeBuckets) return NULL;
	hIdx = tokenizer_hash_pair(id1, id2) & pTok->nMergeBucketMask;
	p = pTok->aMergeBuckets[hIdx];
	while (p) {
		if (p->id1 == id1 && p->id2 == id2) return p;
		p = p->pNext;
	}
	return NULL;
}

/*
================================================================================
  BPE Encode & Decode
================================================================================
*/

#define DEEPSEEK_TAG_USER "<\xef\xbd\x9c" "User\xef\xbd\x9c>"
#define DEEPSEEK_TAG_ASST "<\xef\xbd\x9c" "Assistant\xef\xbd\x9c>"

static int is_special_tag(const char *s, size_t rem, int *outLen, int *outId) {
	if (rem >= 12 && strncmp(s, "<|im_start|>", 12) == 0) {
		*outLen = 12; *outId = 151644; return 1;
	}
	if (rem >= 10 && strncmp(s, "<|im_end|>", 10) == 0) {
		*outLen = 10; *outId = 151645; return 1;
	}
	if (rem >= 13 && strncmp(s, "<|endoftext|>", 13) == 0) {
		*outLen = 13; *outId = 151643; return 1;
	}
	if (rem >= sizeof(DEEPSEEK_TAG_USER) - 1 && strncmp(s, DEEPSEEK_TAG_USER, sizeof(DEEPSEEK_TAG_USER) - 1) == 0) {
		*outLen = (int)(sizeof(DEEPSEEK_TAG_USER) - 1); *outId = 151644; return 1;
	}
	if (rem >= sizeof(DEEPSEEK_TAG_ASST) - 1 && strncmp(s, DEEPSEEK_TAG_ASST, sizeof(DEEPSEEK_TAG_ASST) - 1) == 0) {
		*outLen = (int)(sizeof(DEEPSEEK_TAG_ASST) - 1); *outId = 151645; return 1;
	}
	if (rem >= 7 && strncmp(s, "<think>", 7) == 0) {
		*outLen = 7; *outId = 151648; return 1;
	}
	if (rem >= 8 && strncmp(s, "</think>", 8) == 0) {
		*outLen = 8; *outId = 151649; return 1;
	}
	return 0;
}

RING_API int ring_tokenizer_encode(RingTokenizer *pTok, const char *cText, int *aOutTokens, int nMaxTokens) {
	int nTokens = 0;
	size_t tLen, i, rem, checkLen, l, gpt2Len;
	int matchedLen, matchedId, id;
	char buf[128];
	char *gpt2Str = NULL;
	const char *workText;
	size_t workLen;
	int bestIdx, bestRank, bestMergedId, j;
	RingMergeEntry *m;
	int tagLen, tagId;

	if (!pTok || !cText || !aOutTokens || nMaxTokens <= 0) return 0;
	tLen = strlen(cText);
	if (tLen == 0) return 0;

	gpt2_init_mapping();

	/* If Byte-Level BPE (Qwen, GPT-2), convert raw bytes to GPT-2 Unicode string, keeping special tags untouched */
	if (pTok->bIsByteLevelBPE) {
		gpt2Str = (char *)malloc(tLen * 2 + 1);
		if (gpt2Str) {
			gpt2Len = 0;
			for (i = 0; i < tLen; i++) {
				tagLen = 0; tagId = 0;
				if (cText[i] == '<' && is_special_tag(cText + i, tLen - i, &tagLen, &tagId)) {
					memcpy(gpt2Str + gpt2Len, cText + i, tagLen);
					gpt2Len += tagLen;
					i += tagLen - 1;
				} else {
					unsigned char b = (unsigned char)cText[i];
					const GPT2ByteMap *map = &s_gpt2_byte_to_utf8[b];
					memcpy(gpt2Str + gpt2Len, map->utf8, map->len);
					gpt2Len += map->len;
				}
			}
			gpt2Str[gpt2Len] = '\0';
			workText = gpt2Str;
			workLen = gpt2Len;
		} else {
			workText = cText;
			workLen = tLen;
		}
	} else {
		workText = cText;
		workLen = tLen;
	}

	/* Step 1: Initial tokenization (Greedy Longest Match with single character fallback) */
	i = 0;
	while (i < workLen && nTokens < nMaxTokens) {
		matchedLen = 0;
		matchedId = -1;

		/* Check for standard control / special ChatML and DeepSeek tokens */
		tagLen = 0; tagId = 0;
		if (workText[i] == '<' && is_special_tag(workText + i, workLen - i, &tagLen, &tagId)) {
			aOutTokens[nTokens++] = tagId;
			i += tagLen;
			continue;
		}

		rem = workLen - i;
		checkLen = rem > 64 ? 64 : rem;

		for (l = checkLen; l >= 1; l--) {
			memcpy(buf, workText + i, l);
			buf[l] = '\0';
			id = ring_tokenizer_find_token(pTok, buf);
			if (id >= 0) {
				matchedId = id;
				matchedLen = (int)l;
				break;
			}
		}

		if (matchedId >= 0 && matchedLen > 0) {
			aOutTokens[nTokens++] = matchedId;
			i += matchedLen;
		} else {
			/* Fallback to single character/byte token */
			unsigned char c1 = (unsigned char)workText[i];
			size_t cLen = 1;
			if ((c1 & 0xE0) == 0xC0) cLen = 2;
			else if ((c1 & 0xF0) == 0xE0) cLen = 3;

			if (i + cLen <= workLen) {
				memcpy(buf, workText + i, cLen);
				buf[cLen] = '\0';
				id = ring_tokenizer_find_token(pTok, buf);
				if (id >= 0) {
					aOutTokens[nTokens++] = id;
				} else if (pTok->aByteToToken[c1] >= 0) {
					aOutTokens[nTokens++] = pTok->aByteToToken[c1];
				}
				i += cLen;
			} else {
				if (pTok->aByteToToken[c1] >= 0) {
					aOutTokens[nTokens++] = pTok->aByteToToken[c1];
				}
				i++;
			}
		}
	}

	if (gpt2Str) free(gpt2Str);

	/* Step 2: Iterative BPE Merge Loop (Special control tokens protected from merging) */
	if (pTok->aMergeBuckets && pTok->nMergesCount > 0) {
		while (nTokens >= 2) {
			bestIdx = -1;
			bestRank = 1000000000;
			bestMergedId = -1;

			for (j = 0; j < nTokens - 1; j++) {
				if (aOutTokens[j] >= 151643 || aOutTokens[j + 1] >= 151643) continue;
				m = tokenizer_find_merge(pTok, aOutTokens[j], aOutTokens[j + 1]);
				if (m && m->nRank < bestRank) {
					bestRank = m->nRank;
					bestIdx = j;
					bestMergedId = m->nMergedId;
				}
			}

			if (bestIdx == -1 || bestMergedId < 0) break;

			/* Merge best pair */
			aOutTokens[bestIdx] = bestMergedId;
			for (j = bestIdx + 1; j < nTokens - 1; j++) {
				aOutTokens[j] = aOutTokens[j + 1];
			}
			nTokens--;
		}
	}

	return nTokens;
}

RING_API int ring_tokenizer_decode(RingTokenizer *pTok, int nTokenId, char *cOutBuf, int nMaxLen) {
	const char *src;
	int w = 0;
	size_t r = 0, sLen;
	char hex[3];
	unsigned int byteVal;

	if (!pTok || nTokenId < 0 || (uint32_t)nTokenId >= pTok->nVocabSize || !cOutBuf || nMaxLen <= 1) {
		if (cOutBuf && nMaxLen > 0) cOutBuf[0] = '\0';
		return 0;
	}

	src = pTok->aTokens[nTokenId];
	if (!src) {
		cOutBuf[0] = '\0';
		return 0;
	}

	sLen = strlen(src);

	/* Check for hex byte token: "<0xHH>" */
	if (sLen == 6 && src[0] == '<' && src[1] == '0' && src[2] == 'x' && src[5] == '>') {
		hex[0] = src[3];
		hex[1] = src[4];
		hex[2] = '\0';
		byteVal = 0;
		if (sscanf(hex, "%x", &byteVal) == 1 && w + 1 < nMaxLen) {
			cOutBuf[w++] = (char)byteVal;
			cOutBuf[w] = '\0';
			return w;
		}
	}

	gpt2_init_mapping();

	if (pTok->bIsByteLevelBPE) {
		while (r < sLen && w + 1 < nMaxLen) {
			unsigned char c1 = (unsigned char)src[r];
			if (c1 < 128) {
				cOutBuf[w++] = (char)s_gpt2_code_to_byte[c1];
				r++;
			} else if ((c1 & 0xE0) == 0xC0 && r + 1 < sLen) {
				unsigned char c2 = (unsigned char)src[r + 1];
				int code = ((c1 & 0x1F) << 6) | (c2 & 0x3F);
				if (code < 1024 && (code == 256 || s_gpt2_code_to_byte[code] != 0)) {
					cOutBuf[w++] = (char)s_gpt2_code_to_byte[code];
				} else {
					cOutBuf[w++] = (char)c1;
					if (w + 1 < nMaxLen) cOutBuf[w++] = (char)c2;
				}
				r += 2;
			} else {
				cOutBuf[w++] = (char)c1;
				r++;
			}
		}
	} else {
		while (r < sLen && w + 1 < nMaxLen) {
			unsigned char c1 = (unsigned char)src[r];
			if (c1 == 0xC4 && r + 1 < sLen && (unsigned char)src[r + 1] == 0xA0) {
				cOutBuf[w++] = ' ';
				r += 2;
			} else if (c1 == 0xC4 && r + 1 < sLen && (unsigned char)src[r + 1] == 0x8A) {
				cOutBuf[w++] = '\n';
				r += 2;
			} else {
				cOutBuf[w++] = src[r++];
			}
		}
	}

	cOutBuf[w] = '\0';
	return w;
}

RING_API char *ring_tokenizer_decode_tokens(RingTokenizer *pTok, const int *aTokens, int nTokenCount) {
	size_t allocSize, curLen = 0;
	char *outStr, *newStr;
	char buf[256];
	int i, len;

	if (!pTok || !aTokens || nTokenCount <= 0) return _strdup("");
	allocSize = (size_t)nTokenCount * 64 + 1;
	outStr = (char *)malloc(allocSize);
	if (!outStr) return _strdup("");

	outStr[0] = '\0';

	for (i = 0; i < nTokenCount; i++) {
		len = ring_tokenizer_decode(pTok, aTokens[i], buf, sizeof(buf));
		if (len > 0) {
			if (curLen + (size_t)len + 1 > allocSize) {
				allocSize = (curLen + (size_t)len + 1) * 2;
				newStr = (char *)realloc(outStr, allocSize);
				if (!newStr) break;
				outStr = newStr;
			}
			memcpy(outStr + curLen, buf, len);
			curLen += len;
			outStr[curLen] = '\0';
		}
	}

	return outStr;
}

/*
================================================================================
  Ring Scripting VM APIs
================================================================================
*/

RING_FUNC(ring_tokenizer_api_tokenize) {
	RingGGUF *pGGUF;
	const char *cText;
	RingTokenizer *pTok;
	int aTokens[2048];
	int nTokens, i;
	List *pList;

	if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1) || !RING_API_ISSTRING(2)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	RING_API_CHECKNULLPOINTER(pGGUF);
	cText = RING_API_GETSTRING(2);

	pTok = ring_tokenizer_create(pGGUF);
	if (!pTok) {
		RING_API_ERROR("Failed to create tokenizer from GGUF model metadata!");
		return;
	}

	nTokens = ring_tokenizer_encode(pTok, cText, aTokens, 2048);
	pList = RING_API_NEWLIST;
	for (i = 0; i < nTokens; i++) {
		ring_list_adddouble(pList, (double)aTokens[i]);
	}

	ring_tokenizer_delete(pTok);
	RING_API_RETLIST(pList);
}

RING_FUNC(ring_tokenizer_api_detokenize) {
	RingGGUF *pGGUF;
	RingTokenizer *pTok;
	int aTokens[2048];
	int nTokens = 0, i;
	char *outText;
	List *pList;

	if (RING_API_PARACOUNT != 2 || !RING_API_ISPOINTER(1)) {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pGGUF = (RingGGUF *)RING_API_GETCPOINTER(1, "GGUF");
	RING_API_CHECKNULLPOINTER(pGGUF);

	if (RING_API_ISNUMBER(2)) {
		aTokens[0] = (int)RING_API_GETNUMBER(2);
		nTokens = 1;
	} else if (RING_API_ISLIST(2)) {
		pList = RING_API_GETLIST(2);
		nTokens = ring_list_getsize(pList);
		if (nTokens > 2048) nTokens = 2048;
		for (i = 1; i <= nTokens; i++) {
			aTokens[i - 1] = (int)ring_list_getdouble(pList, i);
		}
	} else {
		RING_API_ERROR(RING_API_BADPARATYPE);
		return;
	}

	pTok = ring_tokenizer_create(pGGUF);
	if (!pTok) {
		RING_API_ERROR("Failed to create tokenizer from GGUF model metadata!");
		return;
	}

	outText = ring_tokenizer_decode_tokens(pTok, aTokens, nTokens);
	RING_API_RETSTRING(outText);

	free(outText);
	ring_tokenizer_delete(pTok);
}

RING_API void ring_tokenizer_loadfunctions(void *pRingState) {
	RING_API_REGISTER("gguf_tokenize", ring_tokenizer_api_tokenize);
	RING_API_REGISTER("gguf_detokenize", ring_tokenizer_api_detokenize);
}
