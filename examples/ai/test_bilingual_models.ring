# ====================================================================
# Madar AI - Dual 1.5B Bilingual Model Comparison & Verification
# Evaluates Qwen2.5-Coder-1.5B vs DeepSeek-R1-Distill-1.5B (Merged GGUFs)
# ====================================================================

load "madar_ai.ring"

cModelQwen     = "models/qwen2.5-coder-1.5b-ring-bilingual-merged.gguf"
cModelDeepSeek = "models/deepseek-r1-distill-1.5b-ring-bilingual-merged.gguf"

# 1. Verify existence of models
bHaveQwen     = fexists(cModelQwen)
bHaveDeepSeek = fexists(cModelDeepSeek)

cStatusQwen = "NOT FOUND"
if bHaveQwen cStatusQwen = "READY" ok
cStatusDeepSeek = "NOT FOUND"
if bHaveDeepSeek cStatusDeepSeek = "READY" ok

? "===================================================================="
? "  Madar AI - Bilingual 1.5B Flagships Inference Test"
? "===================================================================="
? "  Qwen2.5-Coder Model    : " + cModelQwen + " [" + cStatusQwen + "]"
? "  DeepSeek-R1 Model      : " + cModelDeepSeek + " [" + cStatusDeepSeek + "]"
? "===================================================================="

if !bHaveQwen and !bHaveDeepSeek
	? "Notice: Downloaded merged GGUF models not yet detected in 'models/' directory."
	? "Please move the downloaded GGUF files to 'models/' once downloading finishes."
	bye
ok

# Test Prompts: Bilingual
cSystemPrompt = "You are an expert Ring programming language engineer."

cArabicPrompt = "اكتب دالة بلغة رينج لعكس نص والتحقق مما إذا كان palindrome مع مثال تطبيقي."
cEnglishPrompt = "Write a Ring function that calculates factorial of a number with sample usage."

# Run Qwen Coder evaluation
if bHaveQwen
	? ""
	? ">>> [1/2] Testing Qwen2.5-Coder-1.5B (Fine-Tuned Bilingual)..."
	oQwen = model_open(cModelQwen)
	oQwen.setThreads(4)
	oQwen.setTemperature(0.3)
	oQwen.setMaxTokens(256)

	? "--- [Prompt: Arabic] ---"
	? cArabicPrompt
	? "--- [Response] ---"
	cResp1 = oQwen.generate(cArabicPrompt, cSystemPrompt)
	? cResp1
	? ""
	? "--- [Prompt: English] ---"
	? cEnglishPrompt
	? "--- [Response] ---"
	cResp2 = oQwen.generate(cEnglishPrompt, cSystemPrompt)
	? cResp2
ok

# Run DeepSeek R1 evaluation
if bHaveDeepSeek
	? ""
	? ">>> [2/2] Testing DeepSeek-R1-Distill-1.5B (Fine-Tuned Bilingual)..."
	oR1 = model_open(cModelDeepSeek)
	oR1.setThreads(4)
	oR1.setTemperature(0.6)
	oR1.setMaxTokens(384)

	? "--- [Prompt: Arabic] ---"
	? cArabicPrompt
	? "--- [Response] ---"
	cResp1 = oR1.generate(cArabicPrompt, cSystemPrompt)
	? cResp1
	? ""
	? "--- [Prompt: English] ---"
	? cEnglishPrompt
	? "--- [Response] ---"
	cResp2 = oR1.generate(cEnglishPrompt, cSystemPrompt)
	? cResp2
ok

? ""
? "===================================================================="
? "  Bilingual Benchmark Completed Successfully!"
? "===================================================================="
