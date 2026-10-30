# ====================================================================
#   Madar AI Suite - Real-Time Token Streaming & Generator Demo
#   (البث المباشر للرموز في الوقت الحقيقي ومولد الرموز التفاعلي)
# ====================================================================
load "stdlibCore.ring"
load "agent.ring"
load "chronos.ring"

func main {
	cModelPath = findModel([
		"qwen2.5-0.5b-instruct-q4_0.gguf",
		"deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"qwen2.5-coder-1.5b-instruct-q4_0.gguf"
	])

	if cModelPath = "" {
		? "[ERROR] No GGUF model found in models/ directory!"
		? "Please run 'tools\download_model.bat' to download a supported model."
		bye
	}

	? "===================================================================="
	? "  Madar AI: Real-Time Token Streaming & Step-by-Step Generator"
	? "  (البث المباشر للرموز في الوقت الحقيقي ومولد الكلمات فائق السرعة)"
	? "===================================================================="
	? f"  [Model] {cModelPath}"

	oModel = new QwenModel(cModelPath)
	oModel.setThreads(4)
	oModel.setTemperature(0.6)

	oTimer = new Chronos()

	# --------------------------------------------------------------------
	# 1. Native C High-Speed Direct Terminal Streaming
	# --------------------------------------------------------------------
	? nl + "1. Native C Fast Token Streaming (Direct to Terminal):"
	? "Prompt: ما هي لغة مدار وما أهم مميزاتها باختصار؟"
	see "Stream > "

	cPrompt1 = oModel.formatChatPrompt("ما هي لغة مدار وما أهم مميزاتها باختصار؟", "أنت مساعد ذكي وموجز باللغة العربية.")

	oTimer.reset()
	cResponse1 = oModel.generateStream(cPrompt1, 80)
	nDurationNs = oTimer.stop()
	? ""

	aTokens = oModel.tokenize(cResponse1)
	nTokens = len(aTokens)
	nDurationSec = nDurationNs / 1000000000.0

	if nDurationSec > 0 {
		fSpeed = nTokens / nDurationSec
		? f"  [Performance: {nTokens} tokens streamed in {round(nDurationSec, 2)}s (~{round(fSpeed, 1)} tokens/sec | {oTimer.elapsed()})]"
	}

	# --------------------------------------------------------------------
	# 2. Custom Token-by-Token Callback Streaming
	# --------------------------------------------------------------------
	? nl + "--------------------------------------------------------------------"
	? "2. Custom Callback Token Interceptor (Ring Function Callback):"
	? "Prompt: اذكر ثلاثة مبادئ أساسية في علم البيانات."
	see "Callback Stream > "

	cPrompt2 = oModel.formatChatPrompt("اذكر 3 مبادئ أساسية في علم البيانات باختصار.", "أنت مساعد علمي باللغة العربية.")
	nTokenCount = 0

	oTimer.reset()
	oModel.generateStreamCallback(cPrompt2, 70, func(cChunk) {
		nTokenCount++
		see cChunk
	})
	oTimer.stop()
	? ""
	? f"  [Callback Event: intercepted {nTokenCount} individual token chunks in {oTimer.elapsed()}]"

	# --------------------------------------------------------------------
	# 3. Interactive Step-by-Step Generator API (prefill + hasMore + step)
	# --------------------------------------------------------------------
	? nl + "--------------------------------------------------------------------"
	? "3. Low-Level Generator Engine (model.prefill -> model.step):"
	? "Prompt: كم حاصل ضرب 25 في 4؟"
	see "Generator Output > "

	cPrompt3 = oModel.formatChatPrompt("كم حاصل ضرب 25 في 4؟", "أجب برقم فقط وباختصار.")

	oTimer.reset()
	oModel.prefill(cPrompt3, 30)

	nStepCount = 0
	while oModel.hasMore() {
		cToken = oModel.step()
		if cToken != "" {
			nStepCount++
			see cToken
		}
	}
	oTimer.stop()
	? ""
	? f"  [Generator Steps: executed {nStepCount} autoregressive forward passes in {oTimer.elapsed()}]"

	# --------------------------------------------------------------------
	# 4. Autonomous Agent Real-Time Streaming (AIAgent.queryStream)
	# --------------------------------------------------------------------
	? nl + "--------------------------------------------------------------------"
	? "4. Autonomous AI Agent with Real-Time Response Streaming:"
	? "Agent Query: ما هو التاريخ والوقت الحالي للنظام؟"

	oAgent = new AIAgent(oModel)
	oAgent.queryStream("ما هو التاريخ والوقت الحالي للنظام؟")

	? nl + "===================================================================="
	? "  Real-Time Token Streaming Demo Completed Successfully."
	? "===================================================================="
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
