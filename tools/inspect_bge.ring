load "stdlibCore.ring"

cModelPath = "models/bge-m3-q4_0.gguf"
hGGUF = gguf_open(cModelPath)
if isnull(hGGUF)
	see "[ERROR] Failed to open GGUF" + nl
	bye
ok

see "=== BGE-M3 Tokenizer Inspection ===" + nl
aTokens = gguf_metadata_get(hGGUF, "tokenizer.ggml.tokens")
if islist(aTokens)
	see "Total Vocab: " + len(aTokens) + nl
	see "First 10 tokens:" + nl
	for i = 1 to 10
		see "  [" + (i-1) + "] = '" + aTokens[i] + "'" + nl
	next
ok

gguf_close(hGGUF)
