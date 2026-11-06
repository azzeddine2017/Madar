# ====================================================================
# Madar AI - Qwen2.5-Coder-1.5B (Fine-Tuned Bilingual Model)
# Standalone Inference Script (Optimized for low RAM usage)
# ====================================================================

load "madar_ai.ring"

cModelPath = "models/qwen2.5-coder-1.5b-ring-bilingual-merged.gguf"

if !fexists(cModelPath)
	? "Error: Model file not found: " + cModelPath
	bye
ok

? "===================================================================="
? "  Madar AI - Qwen2.5-Coder-1.5B (Ring Bilingual Specialist)"
? "===================================================================="
? "  Loading model: " + cModelPath
? "===================================================================="

oModel = model_open(cModelPath)
oModel.setThreads(4)
oModel.setTemperature(0.2)
oModel.setMaxTokens(256)

cSystemPrompt = "You are an expert Ring programming language engineer."

# Test 1: Arabic Ring Coding Prompt
cArabicPrompt = "اكتب دالة بلغة رينج لعكس نص والتحقق مما إذا كان palindrome مع مثال تطبيقي."
? ""
? "==================== [Test 1: Arabic Prompt] ===================="
? cArabicPrompt
? "-------------------- [Model Output] --------------------"
cFormattedPrompt1 = oModel.formatChatPrompt(cArabicPrompt, cSystemPrompt)
oModel.generateStream(cFormattedPrompt1, 160)
? ""
? "========================================================"

# Test 2: English Ring Coding Prompt
cEnglishPrompt = "Write a Ring function to calculate the factorial of a number with sample usage."
? ""
? "==================== [Test 2: English Prompt] ===================="
? cEnglishPrompt
? "-------------------- [Model Output] --------------------"
cFormattedPrompt2 = oModel.formatChatPrompt(cEnglishPrompt, cSystemPrompt)
oModel.generateStream(cFormattedPrompt2, 160)
? ""
? "========================================================"

