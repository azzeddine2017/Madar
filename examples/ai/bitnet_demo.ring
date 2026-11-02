# ====================================================================
#   Madar AI Suite - BitNet b1.58 (1.58-bit Native LLM Demo)
#   (استعراض محرك بيت-نت فائق السرعة والخالي من الضرب في مدار)
# ====================================================================
load "stdlibCore.ring"
load "agent.ring"
load "chronos.ring"

func main {
	cModelPath = findBitNetModel()

	? "===================================================================="
	? "  Madar AI: BitNet b1.58 Architecture & Inference Engine"
	? "  (المحرك الأصلي لنماذج 1.58-بت الثلاثية: {-1, 0, +1} الخالية من الضرب)"
	? "===================================================================="

	if cModelPath = "" {
		? "  [INFO] No BitNet GGUF model found in models/ directory."
		? "  To download Microsoft's official BitNet b1.58 (2B-4T I2_S GGUF):"
		? "    Run: tools\download_bitnet.bat"
		? "===================================================================="
		bye
	}

	? f"  [Model Path] {cModelPath}"

	# 1. Inspect GGUF Metadata & Tensor Architecture
	oGGUF = gguf_open(cModelPath)
	if !ispointer(oGGUF) {
		? "  [ERROR] Failed to open GGUF model file!"
		bye
	}

	nVersion    = gguf_version(oGGUF)
	nTensors    = gguf_tensor_count(oGGUF)
	nKV         = gguf_metadata_count(oGGUF)
	cArch       = gguf_architecture(oGGUF)

	? f"  [GGUF Specs] Version: {nVersion} | Architecture: {cArch} | Tensors: {nTensors} | Metadata KVs: {nKV}"

	# 2. Analyze Quantization Formats & Memory Savings
	aTensorNames = gguf_tensor_names(oGGUF)
	nI2SCount = 0
	nOtherCount = 0
	nTotalElements = 0

	for cName in aTensorNames {
		aInfo = gguf_tensor_info(oGGUF, cName)
		if aInfo[2] = "I2_S" {
			nI2SCount++
			nTotalElements += aInfo[5]
		else
			nOtherCount++
		}
	}

	? f"  [Quantization Breakdown] I2_S Tensors: {nI2SCount} | Other Tensors (Norm/Embd): {nOtherCount}"
	? f"  [Ternary Parameters] Approximately {round(nTotalElements / 1000000, 2)} Million weights packed in 1.58-bit"

	# Calculate theoretical memory footprint:
	# FP16 footprint = nTotalElements * 2 bytes
	# Q4_0 footprint = nTotalElements * 0.5625 bytes
	# I2_S footprint = nTotalElements * 0.25 bytes (32 bytes per 128 weights = 2 bits/weight)
	nFP16MB = (nTotalElements * 2.0) / (1024 * 1024)
	nQ4MB   = (nTotalElements * 0.5625) / (1024 * 1024)
	nI2SMB  = (nTotalElements * 0.25) / (1024 * 1024)

	? "--------------------------------------------------------------------"
	? "  [RAM Memory Bandwidth Comparison for Weight Matrices]:"
	? f"    * Uncompressed FP16 : {round(nFP16MB, 1)} MB (Baseline)"
	? f"    * Standard Q4_0     : {round(nQ4MB, 1)} MB (3.5x compression)"
	? f"    * Madar BitNet I2_S : {round(nI2SMB, 1)} MB (8.0x compression - DDR3L Friendly!)"
	? "--------------------------------------------------------------------"

	gguf_close(oGGUF)

	# 3. Initialize Model and Run Inference
	? "  Initializing Madar High-Performance Inference Engine..."
	oTimer = new Chronos()
	oTimer.start()

	oModel = new BitNetModel(cModelPath)
	oModel.setThreads(4)
	oModel.setTemperature(0.6)
	
	nLoadTime = oTimer.elapsed()
	? f"  [Engine Ready in {nLoadTime}]"
	? "--------------------------------------------------------------------"

	cPrompt = "Explain in two sentences why ternary weights without multiplication are fast."
	? f"Prompt: {cPrompt}"
	see "BitNet > "

	oGenTimer = new Chronos()
	oGenTimer.start()
	cResponse = oModel.generateStream(cPrompt, 128)
	nGenTimeSec = oGenTimer.elapsed_sec()

	aTokens = oModel.tokenize(cResponse)
	nTokensCount = len(aTokens)
	fTokensPerSec = 0.0
	fMsPerToken = 0.0
	if nGenTimeSec > 0 and nTokensCount > 0 {
		fTokensPerSec = nTokensCount / nGenTimeSec
		fMsPerToken = (nGenTimeSec / nTokensCount) * 1000.0
	}

	? nl + "--------------------------------------------------------------------"
	? "  [Inference & Token Performance Metrics]:"
	? f"    * Generated Tokens : {nTokensCount} tokens"
	? f"    * Generation Time  : {round(nGenTimeSec, 2)} s"
	? f"    * Speed (Tokens/s) : {round(fTokensPerSec, 2)} T/s"
	? f"    * Latency          : {round(fMsPerToken, 2)} ms/token"
	? "===================================================================="
}

func findBitNetModel {
	aCandidates = [
		"../../models/bitnet-b1.58-2b-4t-i2_s.gguf",
		"../models/bitnet-b1.58-2b-4t-i2_s.gguf",
		"models/bitnet-b1.58-2b-4t-i2_s.gguf",
		"../../models/ggml-model-i2_s.gguf",
		"../models/ggml-model-i2_s.gguf",
		"models/ggml-model-i2_s.gguf"
	]
	for cPath in aCandidates {
		if fexists(cPath) {
			return cPath
		}
	}
	return ""
}

