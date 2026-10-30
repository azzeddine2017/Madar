# ====================================================================
#   Madar AI Suite - Function Calling & AI Agent Demo
#   (عرض استدعاء الأدوات والوكيل الذكي في مدار)
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
	? "  Madar AI Agent: Function Calling & Autonomous Tool Execution"
	? "  (الوكيل الذكي في مدار: استدعاء الدوال التلقائي والأدوات البرمجية)"
	? "===================================================================="
	? f"  [Model] {cModelPath}"

	oModel = new QwenModel(cModelPath)
	oModel.setThreads(4)

	oAgent = new AIAgent(oModel)
	oAgent.bStream = 1  # Real-Time Token Streaming Enabled

	# Register custom application tools
	oAgent.registerTool("currency_rate", "Returns exchange rate between two currencies", ["from_curr", "to_curr"], func(args) {
		return "Exchange Rate 1 USD = 134.50 DZD (Algerian Dinar)"
	})

	? nl + "1. Query: What is the current system date and time?"
	oAgent.query("ما هو التاريخ والوقت الحالي للنظام؟")

	? nl + "--------------------------------------------------------------------"
	? "2. Query: Complex Mathematical Calculation"
	oAgent.query("احسب لي ناتج العملية الحسابية بدقة: 1450 * 32 + 890")

	? nl + "--------------------------------------------------------------------"
	? "3. Query: Custom Application Tool (Currency Rate)"
	oAgent.query("كم سعر صرف الدولار مقابل الدينار الجزائري؟")

	? nl + "--------------------------------------------------------------------"
	? "4. Query: Table Analytics & C-Tensor Data Query (DataFrame Integration)"
	oAgent.query("ما هو أعلى راتب في جدول الموظفين؟")

	? nl + "===================================================================="
	? "  Agent Demo Completed Successfully."
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
