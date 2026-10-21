# =========================================================
# Madar AI Test Suite: Qwen2.5 Transformer & BPE Tokenizer
# Validates Tokenizer encode/decode and LLM Generation Loop
# =========================================================

load "../test_harness.ring"
load "madar_ai.ring"

suite("Madar AI - GGUF BPE Tokenizer & Qwen Pipeline")


# 1. Create a Synthetic GGUF with Tokenizer Metadata
cTokGGUF = "test_tok.gguf"

# Vocab array: ["<|endoftext|>", "Hello", "Ġworld", "!", "ما", "Ġهي", "Ġعاصمة", "Ġالجزائر", "?"]
aVocab = ["<|endoftext|>", "Hello", char(196) + char(160) + "world", "!", 
          "ما", char(196) + char(160) + "هي", char(196) + char(160) + "عاصمة", char(196) + char(160) + "الجزائر", "?"]
nVocabCount = len(aVocab)

cVocabArray = u32Bytes(8) + u64Bytes(nVocabCount) # String array (type 8)
for s in aVocab
	cVocabArray += ggufStr(s)
next

cKV1 = ggufStr("tokenizer.ggml.tokens") + u32Bytes(9) + cVocabArray # Array (type 9)
cKV2 = ggufStr("tokenizer.ggml.bos_token_id") + u32Bytes(4) + u32Bytes(0)
cKV3 = ggufStr("tokenizer.ggml.eos_token_id") + u32Bytes(4) + u32Bytes(0)

cHeader = "GGUF" + u32Bytes(3) + u64Bytes(0) + u64Bytes(3) # 0 tensors, 3 KVs
cBinary = cHeader + cKV1 + cKV2 + cKV3

write(cTokGGUF, cBinary)

# 2. Test Tokenizer Load & Tokenize / Detokenize
hGGUF = gguf_open(cTokGGUF)
assert_true(hGGUF != NULL, "gguf_open loads tokenizer test model")

# Encode test
aTokens = gguf_tokenize(hGGUF, "Hello world!")
assert_true(len(aTokens) >= 1, "gguf_tokenize returned token IDs for 'Hello world!'")

# Detokenize single token
cWord = gguf_detokenize(hGGUF, 1)
assert_equal("Hello", cWord, "gguf_detokenize(1) returns 'Hello'")

# Detokenize list
cDecoded = gguf_detokenize(hGGUF, [1, 2, 3])
assert_equal("Hello world!", cDecoded, "gguf_detokenize([1, 2, 3]) decodes to 'Hello world!'")

gguf_close(hGGUF)
remove(cTokGGUF)

# 3. Test Full Qwen Model (Qwen-3B preferred, 0.5B fallback)
aQwenPaths = [
	"models/qwen2.5-0.5b-instruct-q4_0.gguf",
	"../../models/qwen2.5-0.5b-instruct-q4_0.gguf",
	"../models/qwen2.5-0.5b-instruct-q4_0.gguf"
]
cModelPath = ""
for p in aQwenPaths
	if fexists(p)
		cModelPath = p
		exit
	ok
next

if fexists(cModelPath)
	see nl + "  [INFO] Found Qwen Model: " + cModelPath + nl

	# Validate low-level GGUF parsing first
	hCheck = gguf_open(cModelPath)
	assert_true(hCheck != NULL, "gguf_open loaded Qwen GGUF model")
	if hCheck != NULL
		see "  [INFO] Model Architecture: " + gguf_architecture(hCheck) + nl
		see "  [INFO] Metadata Count    : " + gguf_metadata_count(hCheck) + nl
		see "  [INFO] Tensor Count      : " + gguf_tensor_count(hCheck) + nl
		gguf_close(hCheck)
	ok

	see "  [INFO] Initializing QwenModel with 4 CPU threads..." + nl

	model = new QwenModel(cModelPath)
	model.setThreads(4)
	assert_true(model.hModel != NULL, "QwenModel initialized successfully")

	# Test Tokenizer on Arabic prompt
	cPrompt = "ما هي عاصمة الجزائر؟"
	aPromptTokens = model.tokenize(cPrompt)
	assert_true(len(aPromptTokens) > 0, "Arabic prompt tokenized into " + len(aPromptTokens) + " tokens")

	# Test Generation
	see "  [INFO] Running generation (max 16 tokens)..." + nl
	t0 = clock()
	cResponse = model.generate(cPrompt, 16)
	t1 = clock()
	nSec = (t1 - t0) / clockspersecond()

	see "  [OUTPUT] " + cResponse + nl
	see "  [PERF] Generation Time: " + nSec + "s" + nl
	if nSec > 0
		see "  [PERF] Speed: " + (len(model.tokenize(cResponse)) / nSec) + " tokens/sec" + nl
	ok
	assert_true(len(cResponse) > 0, "Model generated non-empty text response")

	model.close()
else
	see nl + "  [NOTE] Full model not present at models/qwen2.5-0.5b-instruct-q4_0.gguf." + nl
	see "         Run 'tools\\download_model.bat' to download and test live generation." + nl
ok

test_summary()

# Helper functions to build binary GGUF structures
func u32Bytes(n)
	return char(n & 255) + char((n >> 8) & 255) + char((n >> 16) & 255) + char((n >> 24) & 255)

func u64Bytes(n)
	return u32Bytes(n) + u32Bytes(0)

func f32Bytes(f)
	# Default 0.0 float representation (4 null bytes)
	return char(0) + char(0) + char(0) + char(0)

func ggufStr(str)
	return u64Bytes(len(str)) + str
