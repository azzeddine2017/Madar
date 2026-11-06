# ====================================================================
# Madar AI - Bilingual 1.5B Flagships CLI Runner
# Executes one model at a time to preserve memory footprint
# ====================================================================

load "madar_ai.ring"

cChoice = "qwen"
if len(sysargv) >= 2
	cArg = lower(sysargv[2])
	if substr(cArg, "deepseek") > 0 or substr(cArg, "r1") > 0 or cArg = "2"
		cChoice = "deepseek"
	elseif substr(cArg, "qwen") > 0 or substr(cArg, "coder") > 0 or cArg = "1"
		cChoice = "qwen"
	ok
ok

if cChoice = "qwen"
	cModelPath = "models/qwen2.5-coder-1.5b-ring-bilingual-merged.gguf"
	cModelName = "Qwen2.5-Coder-1.5B (Bilingual Ring Specialist)"
	fTemp = 0.2
	nMaxTok = 256
else
	cModelPath = "models/deepseek-r1-distill-1.5b-ring-bilingual-merged.gguf"
	cModelName = "DeepSeek-R1-Distill-1.5B (Reasoning & Ring Bilingual)"
	fTemp = 0.6
	nMaxTok = 384
ok

if !fexists(cModelPath)
	? "Error: Target model not found: " + cModelPath
	bye
ok

? "===================================================================="
? "  Madar AI - Single Model Inference Runner"
? "  Active Model: " + cModelName
? "  File        : " + cModelPath
? "===================================================================="

oModel = model_open(cModelPath)
oModel.setThreads(4)
oModel.setTemperature(fTemp)
oModel.setMaxTokens(nMaxTok)

cSystemPrompt = "You are an expert Ring programming language engineer."

# Test 1: Arabic
cArabicPrompt = "اكتب دالة بلغة رينج لعكس نص والتحقق مما إذا كان palindrome مع مثال تطبيقي."
? ""
? "==================== [Arabic Prompt] ===================="
? cArabicPrompt
? "-------------------- [Output] --------------------"
oModel.generateStream(cArabicPrompt, cSystemPrompt)
? ""
? "========================================================"

# Test 2: English
cEnglishPrompt = "Write a Ring function to calculate the factorial of a number with sample usage."
? ""
? "==================== [English Prompt] ===================="
? cEnglishPrompt
? "-------------------- [Output] --------------------"
oModel.generateStream(cEnglishPrompt, cSystemPrompt)
? ""
? "========================================================"
