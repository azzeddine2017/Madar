# ====================================================================
# Madar AI - Native GGUF Inference Test for Qwen2.5-Coder LoRA
# Model: models/qwen2.5-coder-1.5b-ring-hf-q4_0.gguf
# ====================================================================

load "madar_ai.ring"

func main
	cModelPath = "models/qwen2.5-coder-1.5b-ring-hf-q4_0.gguf"
	
	? "===================================================================="
	? "  Madar AI - Native GGUF Inference Benchmark & Evaluation"
	? "===================================================================="
	? f"  Model File : {cModelPath}"
	
	if not fexists(cModelPath)
		? f"[ERROR] Model file not found: {cModelPath}"
		return
	ok

	t0 = clock()
	oModel = model_open(cModelPath)
	t1 = clock()
	nLoadTime = (t1 - t0) / clockspersecond()
	? f"  Model Loaded Successfully in {nLoadTime} seconds."
	
	# Enable GPU Acceleration if available
	try
		oModel.setGPU(true)
		? "  [GPU] OpenCL Acceleration: Enabled"
	catch
		? "  [GPU] Running on CPU"
	done

	oModel.setTemperature(0.2)
	oModel.setThreads(4)

	cSysPrompt = "You are Madar AI, an expert code generator specialized in the Ring programming language."

	# ----------------------------------------------------------------
	# Test 1: Arabic Instruction (Array sum)
	# ----------------------------------------------------------------
	cPrompt1 = "اكتب دالة بلغة رينج لحساب مجموع عناصر مصفوفة مع مثال عملي"
	run_prompt(oModel, cPrompt1, cSysPrompt, 180)

	# ----------------------------------------------------------------
	# Test 2: English Instruction (OOP Class)
	# ----------------------------------------------------------------
	cPrompt2 = "Write a Ring code example demonstrating how to create a class with properties and methods."
	run_prompt(oModel, cPrompt2, cSysPrompt, 220)

	# ----------------------------------------------------------------
	# Test 3: Modern Madar Syntax (List Comprehensions)
	# ----------------------------------------------------------------
	cPrompt3 = "اكتب كود بلغة رينج لإنشاء قائمة بمربعات الأعداد الفردية فقط من 1 إلى 20"
	run_prompt(oModel, cPrompt3, cSysPrompt, 180)

	? "===================================================================="
	? "  All Inference Tests Completed Successfully!"
	? "===================================================================="

func run_prompt(oModel, cUserPrompt, cSysPrompt, nMaxTokens)
	? nl + "--------------------------------------------------------------------"
	? f"[PROMPT]: {cUserPrompt}"
	? "--------------------------------------------------------------------"
	
	cChatPrompt = oModel.formatChatPrompt(cUserPrompt, cSysPrompt)
	
	t0 = clock()
	cResponse = oModel.generate(cChatPrompt, nMaxTokens)
	t1 = clock()
	nDuration = (t1 - t0) / clockspersecond()
	
	? "[RESPONSE]:"
	? cResponse
	? "--------------------------------------------------------------------"
	fSpeed = oModel.tokensPerSecond()
	? f"Generated in {nDuration}s | Speed: {fSpeed} tokens/sec"

