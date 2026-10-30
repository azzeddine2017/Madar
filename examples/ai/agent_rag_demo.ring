# ====================================================================
# Madar AI Agent: Long-Term Vector Memory & Persistent RAG Demo
# (الوكيل الذكي مع ذاكرة التضمين المتجهي طويلة الأمد واسترجاع المعرفة RAG)
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
		? "[ERROR] Model file not found in models/ directory!"
		? "Please download a supported model using 'tools\download_model.bat'."
		bye
	}

	? "===================================================================="
	? "  Madar AI: Agent Long-Term Vector Memory & RAG Demonstration"
	? "  (الوكيل الذكي: الذاكرة المتجهية الدائمة واسترجاع المعرفة في مدار)"
	? "===================================================================="
	? f"  [Model] {cModelPath}"

	oTimer = new Chronos()

	# 1. Load Model
	oModel = ai_open(cModelPath)
	oModel.setTemperature(0.2)

	# 2. Initialize Agent
	oAgent = new AIAgent(oModel)
	oAgent.bStream = 1

	# 3. Setup Dedicated Test Memory File
	cTestMemory = "agent_test_memory.bin"
	oAgent.initMemory(cTestMemory)

	? nl + "1. Inscribing Long-Term Facts into Episodic Vector Memory:"
	oAgent.remember("المستخدم يفضل البرمجة بلغة مدار والتركيز على الأداء العالي وAVX2")
	oAgent.remember("مشروع مدار يدعم أنظمة التشغيل ويندوز ولينكس وماك")
	oAgent.remember("المطور الرئيسي لمدار يحب القهوة العربية بدون سكر")
	? f"  Memory chunks stored: {oAgent.oMemory.count()}"

	? nl + "--------------------------------------------------------------------"
	? "2. Testing Semantic Recall (Cosine Similarity):"
	? "  Query: 'ما هي تفضيلات المستخدم البرمجية؟'"
	oTimer.reset()
	aMatches = oAgent.recall("ما هي تفضيلات المستخدم البرمجية؟", 2)
	oTimer.stop()

	for m in aMatches {
		? f"  -> [Similarity: {round(m[1], 3)}] {m[2].cText}"
	}
	? f"  [Recall completed in {oTimer.elapsed()}]"

	? nl + "--------------------------------------------------------------------"
	? "3. Autonomous Agent Query with Automatic Memory Injection:"
	? "  User Prompt: 'ما هي لغة البرمجة التي أفضلها وما هي تفضيلاتي في الأداء؟'"
	see "  Agent Response > "
	oAgent.query("ما هي لغة البرمجة التي أفضلها وما هي تفضيلاتي في الأداء؟")
	? ""

	? nl + "--------------------------------------------------------------------"
	? "4. Autonomous Tool Calling for Saving New Memory:"
	? "  User Prompt: 'تذكر أن رقم هاتفي للطوارئ هو 0555123456'"
	see "  Agent Response > "
	oAgent.query("تذكر أن رقم هاتفي للطوارئ هو 0555123456")
	? ""

	? f"  Updated Memory chunks stored: {oAgent.oMemory.count()}"

	# Clean up model
	oModel.close()
	? nl + "===================================================================="
	? "  Demo Completed Successfully!"
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
