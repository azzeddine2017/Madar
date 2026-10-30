# ====================================================================
# Madar AI - BGE-M3 Embedding & Dual-Model RAG Pipeline
# بحث دلالي فائق الدقة باستخدام BGE-M3 + توليد الإجابة بـ Qwen
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"
load "chronos.ring"

func main {
	cBgePath = findModel([
		"bge-m3-q4_0.gguf",
		"bge-m3.gguf"
	])

	if cBgePath = "" {
		? "[ERROR] BGE-M3 model not found in models/ directory!"
		? "Please download 'bge-m3-q4_0.gguf' to models/ to run dense vector RAG."
		bye
	}

	? "========================================================"
	? "  Madar AI - BGE-M3 Embedding & RAG Pipeline"
	? "========================================================"
	? f"  [Embedding Model] {cBgePath}"

	oTimer = new Chronos()

	# 1. فتح نموذج BGE-M3 لإنتاج التضمينات الشعاعية (1024-dim Normalized Embeddings)
	? nl + "[1/3] Loading BGE-M3 Embedding Engine..."
	oTimer.reset()
	oEmbedModel = model_open(cBgePath)
	oEmbedModel.setThreads(4)
	oTimer.stop()
	? f"  -> Model loaded in {oTimer.elapsed()}"

	# 2. بناء قاعدة المعرفة وتضمين المستندات عبر BGE-M3
	? nl + "[2/3] Building Knowledge Base (VectorStore with BGE-M3)..."
	oStore = new VectorStore(oEmbedModel)

	oStore.addText("لحل خطأ نفاد الذاكرة في لغة C، تأكد من استدعاء free() لكل مؤشر تم تخصيصه بـ malloc وتجنب تسريب الموارد واستخدم أدوات الفحص مثل AddressSanitizer.")
	oStore.addText("تدعم لغة مدار محرك استنتاج محلي فائق السرعة وخفيف الوزن للنماذج التوليدية ونماذج التضمين الشعاعي دون أي مكتبات خارجية.")
	oStore.addText("عاصمة الجمهورية العربية السورية هي مدينة دمشق وتعد من أقدم العواصم المأهولة في التاريخ.")
	oStore.addText("خوارزمية البحث الثنائي Binary Search تتطلب مصفوفة مرتبة مسبقاً وتعمل بتعقيد زمني قدره O(log n).")

	? f"  -> Indexed {oStore.count()} document chunks into high-density 1024-dim space."

	# 3. استعلام البحث الدلالي
	cQuestion = "كيف أعالج تسريب الذاكرة البرمجية؟"
	? nl + f"[3/3] Semantic Search Query: '{cQuestion}'"

	oTimer.reset()
	query_vec = oEmbedModel.get_embedding(cQuestion)
	oTimer.stop()
	? f"  -> Query embedded into 1024-dim vector in {oTimer.elapsed()}"

	? nl + "Top Matching Results (Cosine Similarity):"
	oTimer.reset()
	aMatches = vector_search(query_vec, oStore, 3)
	oTimer.stop()
	? f"  -> Vector search finished in {oTimer.elapsed()}"

	for m in aMatches {
		? f"  [{round(m[1], 4)}] {m[2]}"
	}

	best_chunk = aMatches[1][2]
	? nl + "Top Reference Chunk:"
	? f">>> {best_chunk}" + nl

	# 4. توليد الإجابة الحتمية عبر نموذج التوليد (اختياري إذا توفر Qwen)
	cGenPath = findModel([
		"qwen2.5-0.5b-instruct-q4_0.gguf",
		"deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"qwen2.5-coder-1.5b-instruct-q4_0.gguf"
	])

	if cGenPath != "" {
		? f"Generating Final Answer with Qwen LLM ({cGenPath})..."
		oGenLLM = model_open(cGenPath)
		oGenLLM.setTemperature(0.3)

		cPrompt = "<|im_start|>system" + nl +
		          "أجب دائماً باللغة العربية الفصحى بدقة بالاعتماد على هذا المرجع فقط: " + best_chunk + "<|im_end|>" + nl +
		          "<|im_start|>user" + nl + cQuestion + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl

		see "Answer: "
		oTimer.reset()
		oGenLLM.generateStream(cPrompt, 128)
		oTimer.stop()
		? ""
		? f"  [Generation completed in {oTimer.elapsed()}]"
	}

	? "========================================================"
	? "  BGE-M3 RAG Pipeline Completed Successfully!"
	? "========================================================"
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
