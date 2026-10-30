# ====================================================================
# Madar AI - Simple & Declarative RAG Workflow
# (النمط الإعلاني المنظم للبحث الدلالي وتوليد الإجابة)
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"
load "chronos.ring"

func main {
	# 1. تحديد مسار النموذج متعدد المسارات
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
	? "  Madar AI: Declarative RAG Workflow"
	? "  (النمط الإعلاني للبحث الدلالي وتوليد الإجابة بمدار)"
	? "===================================================================="
	? f"  [Model] {cModelPath}"

	oTimer = new Chronos()

	# فتح نموذج التضمين والتوليد
	oEmbedModel = model_open(cModelPath)
	oLLM = oEmbedModel
	oLLM.setTemperature(0.2) # درجة حرارة منخفضة لضمان دقة الإجابة الحتمية والالتزام بالمرجع

	# إعداد قاعدة المعرفة السريعة
	oStore = new VectorStore(oEmbedModel)
	oStore.addText("لحل خطأ نفاد الذاكرة في C، تأكد من استدعاء free() لكل مؤشر تم تخصيصه بـ malloc وتجنب تسريب الموارد.")
	oStore.addText("لغة مدار تدعم المصفوفات الممتدة المتصلة ومحرك استنتاج ذكاء اصطناعي محلي خفيف الوزن فائق السرعة.")
	oStore.addText("عاصمة الجمهورية العربية السورية هي مدينة دمشق وتعتبر من أقدم مدن العالم.")

	# السؤال المراد البحث عنه
	cQuestion = "كيف أصلح خطأ الذاكرة؟"
	? nl + f"السؤال: {cQuestion}" + nl

	# 1. تحويل سؤال المستخدم إلى إحداثيات شعاعية (Embedding)
	oTimer.reset()
	query_vector = oEmbedModel.get_embedding(cQuestion)
	oTimer.stop()
	? f"  [Embedding generated in {oTimer.elapsed()}]"

	# 2. قياس التشابه الرياضي بين السؤال والملفات المخزنة (عبر مصفوفات التينسور في C)
	? nl + "درجات التشابه الرياضي (Cosine Similarity):"
	oTimer.reset()
	aMatches = vector_search(query_vector, oStore, 3)
	oTimer.stop()

	for m in aMatches {
		? f"  - [{round(m[1], 4)}] {m[2]}"
	}
	? f"  [Vector search finished in {oTimer.elapsed()}]"

	best_chunk = aMatches[1][2]
	? nl + "المرجع الأعلى تطابقاً:"
	? f">>> {best_chunk}" + nl

	# 3. تمرير النتيجة فقط للنموذج لتوليد إجابة حتمية بدون هلوسة
	cPrompt = "<|im_start|>system" + nl + 
	          "أجب دائماً باللغة العربية الفصحى باختصار ودقة بناءً على هذا المرجع فقط: " + best_chunk + "<|im_end|>" + nl +
	          "<|im_start|>user" + nl + cQuestion + "<|im_end|>" + nl +
	          "<|im_start|>assistant" + nl

	see "إجابة النموذج: "
	oTimer.reset()
	cResponse = oLLM.generateStream(cPrompt, 128)
	oTimer.stop()
	? ""
	? f"  [Response generated in {oTimer.elapsed()}]"

	? nl + "===================================================================="
	? "  Declarative RAG Completed Successfully."
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
