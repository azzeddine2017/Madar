# ====================================================================
# Madar AI - BGE-M3 Embedding & Dual-Model RAG Pipeline
# بحث دلالي فائق الدقة باستخدام BGE-M3 + توليد الإجابة بـ Qwen
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"

cBgePath = "models/bge-m3-q4_0.gguf"
if not fexists(cBgePath)
	cBgePath = "../../models/bge-m3-q4_0.gguf"
ok

if not fexists(cBgePath)
	see "[ERROR] BGE-M3 model not found at: " + cBgePath + nl
	bye
ok

see "========================================================" + nl
see "  Madar AI - BGE-M3 Embedding & RAG Pipeline" + nl
see "========================================================" + nl

# 1. فتح نموذج BGE-M3 لإنتاج التضمينات الشعاعية (1024-dim Normalized Embeddings)
see "[1/3] Loading BGE-M3 Embedding Engine..." + nl
t0 = clock()
embed_model = model_open(cBgePath)
embed_model.setThreads(4)
t1 = clock()
see "  -> Model loaded in " + ((t1 - t0) / clockspersecond()) + "s" + nl + nl

# 2. بناء قاعدة المعرفة وتضمين المستندات عبر BGE-M3
see "[2/3] Building Knowledge Base (VectorStore with BGE-M3)..." + nl
store = new VectorStore(embed_model)

store.addText("لحل خطأ نفاد الذاكرة في لغة C، تأكد من استدعاء free() لكل مؤشر تم تخصيصه بـ malloc وتجنب تسريب الموارد واستخدم أدوات الفحص مثل AddressSanitizer.")
store.addText("تدعم لغة مدار محرك استنتاج محلي فائق السرعة وخفيف الوزن للنماذج التوليدية ونماذج التضمين الشعاعي دون أي مكتبات خارجية.")
store.addText("عاصمة الجمهورية العربية السورية هي مدينة دمشق وتعد من أقدم العواصم المأهولة في التاريخ.")
store.addText("خوارزمية البحث الثنائي Binary Search تتطلب مصفوفة مرتبة مسبقاً وتعمل بتعقيد زمني قدره O(log n).")

see "  -> Indexed " + store.count() + " document chunks." + nl + nl

# 3. استعلام البحث الدلالي
cQuestion = "كيف أعالج تسريب الذاكرة البرمجية؟"
see "[3/3] Semantic Search Query: '" + cQuestion + "'" + nl

t0 = clock()
query_vec = embed_model.get_embedding(cQuestion)
t1 = clock()
see "  -> Query embedded in " + ((t1 - t0) / clockspersecond()) + "s" + nl

see nl + "Top Matching Results (Cosine Similarity):" + nl
aMatches = vector_search(query_vec, store, 3)
for m in aMatches
	see f"  [{m[1]}] {m[2]}" + nl
next
see nl

best_chunk = aMatches[1][2]
see "Top Reference Chunk:" + nl
see ">>> " + best_chunk + nl + nl

# 4. توليد الإجابة الحتمية عبر نموذج التوليد (اختياري إذا توفر Qwen)
cGenPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
if not fexists(cGenPath)
	cGenPath = "../../models/qwen2.5-0.5b-instruct-q4_0.gguf"
ok

if fexists(cGenPath)
	see "Generating Final Answer with Qwen LLM..." + nl
	llm = model_open(cGenPath)
	llm.setTemperature(0.3)

	prompt = "<|im_start|>system" + nl +
	         "أجب دائماً باللغة العربية الفصحى بدقة بالاعتماد على هذا المرجع فقط: " + best_chunk + "<|im_end|>" + nl +
	         "<|im_start|>user" + nl + cQuestion + "<|im_end|>" + nl +
	         "<|im_start|>assistant" + nl

	see "Answer: "
	llm.generateStream(prompt, 128)
	see nl
ok

see "========================================================" + nl
see "  BGE-M3 RAG Pipeline Completed Successfully!" + nl
see "========================================================" + nl
