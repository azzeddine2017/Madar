# ====================================================================
# Madar AI - Simple & Declarative RAG Workflow
# (النمط الإعلاني المنظم للبحث الدلالي وتوليد الإجابة)
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"

# 1. تحديد مسار النموذج
cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
if not fexists(cModelPath)
	cModelPath = "../../models/qwen2.5-0.5b-instruct-q4_0.gguf"
ok

if not fexists(cModelPath)
	see "[ERROR] Model file not found in models/" + nl
	bye
ok

# فتح نموذج التضمين والتوليد (يمكن استخدام نفس النموذج أو نموذجين منفصلين)
embed_model = model_open(cModelPath)
llm         = embed_model
llm.setTemperature(0.2) # درجة حرارة منخفضة لضمان دقة الإجابة الحتمية والالتزام بالمرجع

# إعداد قاعدة المعرفة السريعة (يمكن إضافة ملفات نصية أو PDF عبر store.addPDF)
store = new VectorStore(embed_model)
store.addText("لحل خطأ نفاد الذاكرة في C، تأكد من استدعاء free() لكل مؤشر تم تخصيصه بـ malloc وتجنب تسريب الموارد.")
store.addText("لغة مدار تدعم المصفوفات الممتدة المتصلة ومحرك استنتاج ذكاء اصطناعي محلي خفيف الوزن فائق السرعة.")
store.addText("عاصمة الجمهورية العربية السورية هي مدينة دمشق وتعتبر من أقدم مدن العالم.")

# السؤال المراد البحث عنه
cQuestion = "كيف أصلح خطأ الذاكرة؟"
see nl + "السؤال: " + cQuestion + nl + nl

# 1. تحويل سؤال المستخدم إلى إحداثيات شعاعية (Embedding)
query_vector = embed_model.get_embedding(cQuestion)

# 2. قياس التشابه الرياضي بين السؤال والملفات المخزنة (عبر مصفوفات التينسور في C)
see "درجات التشابه الرياضي (Cosine Similarity):" + nl
aMatches = vector_search(query_vector, store, 3)
for m in aMatches
	see f"  - [{m[1]}] {m[2]}" + nl
next
see nl

best_chunk = aMatches[1][2]
see "المرجع الأعلى تطابقاً:" + nl
see ">>> " + best_chunk + nl + nl

# 3. تمرير النتيجة فقط للنموذج لتوليد إجابة حتمية بدون هلوسة
prompt = "<|im_start|>system" + nl + 
         "أجب باختصار ودقة بناءً على هذا المرجع فقط: " + best_chunk + "<|im_end|>" + nl +
         "<|im_start|>user" + nl + cQuestion + "<|im_end|>" + nl +
         "<|im_start|>assistant" + nl

see "إجابة النموذج:" + nl
response = llm.generateStream(prompt, 128)
see nl
