# ====================================================================
# Madar AI - Interactive Terminal Chat Assistant
# Real-time local inference using DeepSeek-R1 or Qwen2.5 (GGUF Q4_0)
# ====================================================================
load "stdlibCore.ring"
load "madar_ai.ring"
load "chronos.ring"

func main {
	# 1. Locate Available Models (Multi-path fallback)
	bPreferQwen = false
	bPreferDeepSeek = false

	for arg in sysargv {
		cLower = lower(arg)
		if substr(cLower, "qwen") > 0 { bPreferQwen = true }
		if substr(cLower, "deepseek") > 0 or substr(cLower, "r1") > 0 { bPreferDeepSeek = true }
	}

	if bPreferDeepSeek {
		aCandidateNames = [
			"deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
			"deepseek-r1-distill-qwen-7b-q4_0.gguf",
			"qwen2.5-0.5b-instruct-q4_0.gguf"
		]
	} else {
		aCandidateNames = [
			"qwen2.5-0.5b-instruct-q4_0.gguf",
			"qwen2.5-coder-1.5b-instruct-q4_0.gguf",
			"qwen2.5-3b-instruct-q4_0.gguf",
			"deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
			"qwen2.5-7b-instruct-q4_0.gguf"
		]
	}

	cModelPath = findModel(aCandidateNames)

	if cModelPath = "" {
		? nl + "===================================================================="
		? "  [ERROR] No AI model found in models/ directory!"
		? "===================================================================="
		? "  Please download a model first using one of the helper scripts:"
		? "    - tools\download_model.bat      (Qwen-3B / 0.5B)"
		? "    - tools\download_deepseek.bat   (DeepSeek-R1    ~1.1 GB)"
		? "===================================================================="
		bye
	}

	bIsDeepSeek = (substr(lower(cModelPath), "deepseek") > 0)

	# 2. Initialize Model
	? nl + "===================================================================="
	? "  Madar AI - Local Interactive Chat Terminal (مدار للذكاء الاصطناعي)"
	? "===================================================================="
	? f"  Loading model from: {cModelPath}"

	oTimer = new Chronos()
	oTimer.reset()

	if bIsDeepSeek {
		oModel = new DeepSeekModel(cModelPath)
	} else {
		oModel = new QwenModel(cModelPath)
	}
	oModel.setThreads(4)
	oModel.setTemperature(0.3)
	oTimer.stop()

	? f"  Hardware: {oModel.nThreads} CPU Threads (Active)"
	? f"  Model initialized successfully in {oTimer.elapsed()}."
	? "  Commands: 'exit' | 'reset' | '/gpu on|off' | '/tokens <N>' | '/temp <0.0-1.0>'"
	? "===================================================================="

	if bIsDeepSeek {
		nChatMaxTokens = 2048
	} else {
		nChatMaxTokens = 1024
	}

	# 3. Interactive REPL Chat Loop
	while true {
		? nl + "User > "
		give cInput
		cInput = trim(cInput)

		if cInput = "" {
			loop
		}

		cLower = lower(cInput)

		if cLower = "exit" or cLower = "quit" {
			? "  Exiting Madar Chat. Goodbye!"
			bye
		}

		if cLower = "reset" {
			oModel.resetChat()
			? "  [System] Chat history reset successfully."
			loop
		}

		if substr(cLower, "/tokens") = 1 {
			aParts = split(cInput, " ")
			if len(aParts) >= 2 {
				nChatMaxTokens = 0 + aParts[2]
				if nChatMaxTokens < 16 { nChatMaxTokens = 16 }
				if nChatMaxTokens > 4096 { nChatMaxTokens = 4096 }
				? f"  [System] Max tokens set to {nChatMaxTokens}"
			} else {
				? f"  [System] Current max tokens: {nChatMaxTokens}"
			}
			loop
		}

		if substr(cLower, "/gpu") = 1 {
			aParts = split(cInput, " ")
			if len(aParts) >= 2 {
				cMode = lower(aParts[2])
				if cMode = "off" or cMode = "0" {
					oModel.setGPU(0)
					? "  [System] GPU Acceleration disabled (Running CPU AVX2)."
				} else {
					oModel.setGPU(1)
					? "  [System] GPU Acceleration enabled."
				}
			} else {
				? "  [System] Usage: /gpu on | /gpu off"
			}
			loop
		}

		if substr(cLower, "/temp") = 1 {
			aParts = split(cInput, " ")
			if len(aParts) >= 2 {
				fNewTemp = 0.0 + aParts[2]
				oModel.setTemperature(fNewTemp)
				? f"  [System] Temperature set to {fNewTemp}"
			} else {
				? f"  [System] Current temperature: {oModel.fTemp}"
			}
			loop
		}

		see nl + "AI > "
		oTimer.reset()
		cResponse = oModel.chatStream(cInput, nChatMaxTokens)
		nGenNs = oTimer.stop()
		? ""

		# Performance metrics
		aTokens = oModel.tokenize(cResponse)
		nTokensCount = len(aTokens)
		nGenSec = nGenNs / 1000000000.0

		if nGenSec > 0 {
			fSpeed = nTokensCount / nGenSec
			? nl + f"  [Stats: {nTokensCount} tokens in {round(nGenSec, 2)}s (~{round(fSpeed, 1)} tokens/sec | {oTimer.elapsed()})]"
		}
	}
}

# --------------------------------------------------------------------
# Helper Functions
# --------------------------------------------------------------------
func findModel(aCandidates) {
	aSearchDirs = ["models/", "../../models/", "../models/", "../../../models/"]
	for cName in aCandidates {
		for cDir in aSearchDirs {
			cFullPath = cDir + cName
			if fexists(cFullPath) { return cFullPath }
		}
	}
	return ""
}
