# ====================================================================
# Madar AI + AlQalam: Next-Gen Hybrid RAG & Vector Persistence Demo
# (دمج مدار مع مكتبة القلم: بحث هجين، قراءة PDF، وحفظ ثنائي فائق السرعة)
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"
load "alqalam.ring"

# 1. إعداد النموذج والمؤقت عالي الدقة
see nl + "====================================================================" + nl
see "  Madar AI + AlQalam: High-Performance Hybrid Search Engine" + nl
see "  (محرك مدار والقلم: البحث الهجين، حفظ المتجهات بالقرص، والسرعة الفائقة)" + nl
see "====================================================================" + nl

cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
if not fexists(cModelPath) cModelPath = "../../models/qwen2.5-0.5b-instruct-q4_0.gguf" ok

oTimer = new QalamChronos()
oTimer.reset()

see "تحميل النموذج اللغوي... "
llm = model_open(cModelPath)
llm.setTemperature(0.2)
see "[تم في: " + oTimer.elapsed() + "]" + nl

store = new VectorStore(llm)

# 2. ميزة الحفظ والاسترجاع الثنائي (Binary Persistence)
cBinFile = "knowledge_cache.bin"

if fexists(cBinFile)
	see f"استرجاع قاعدة المعرفة المحفوظة ثنائياً من ({cBinFile})... "
	oTimer.reset()
	nLoaded = store.loadBinary(cBinFile)
	see "[تم استرجاع " + nLoaded + " مقطع في: " + oTimer.elapsed() + "]" + nl
else
	see "فهرسة المعرفة الأولية واستخراج المتجهات... "
	oTimer.reset()
	store.addText("لحل خطأ نفاد الذاكرة في C، تأكد من استدعاء free() لكل مؤشر تم تخصيصه بـ malloc وتجنب تسريب الموارد.")
	store.addText("لغة مدار تدعم المصفوفات الممتدة المتصلة ومحرك استنتاج ذكاء اصطناعي محلي خفيف الوزن فائق السرعة.")
	store.addText("تستخدم مكتبة AlQalam هياكل C++17 و OpenMP لتسريع العمليات الحسابية والبحث بآلاف المرات.")
	store.addText("عاصمة الجمهورية العربية السورية هي مدينة دمشق وتعتبر من أقدم مدن التاريخ.")
	see "[تم التضمين في: " + oTimer.elapsed() + "]" + nl

	# حفظ الذاكرة الشعاعية ثنائياً للمرات القادمة
	see f"حفظ المتجهات في ملف ثنائي ({cBinFile})... "
	store.saveBinary(cBinFile)
	see "[تم الحفظ بنجاح]" + nl
ok

# 3. ميزة البحث الهجين (Hybrid Search: دلالي + لفظي عبر AlQalam)
cQuestion = "كيف أصلح خطأ الذاكرة؟"
see nl + "--------------------------------------------------------------------" + nl
see "السؤال: " + cQuestion + nl

oTimer.reset()
aHybridResults = store.hybridSearch(cQuestion, 3, 0.7)
nSearchElapsed = oTimer.elapsed()

see "نتائج البحث الهجين (Semantic 70% + Lexical 30%) [زمن البحث: " + nSearchElapsed + "]:" + nl
for res in aHybridResults
	fTotal = res[1]
	chunk  = res[2]
	fSem   = res[3]
	fLex   = res[4]
	see f"  - [المجموع: {fTotal}] (دلالي: {fSem} | لفظي: {fLex}) " + substr(chunk.cText, 1, 60) + "..." + nl
next

best_chunk = aHybridResults[1][2].cText
see nl + "المرجع الأعلى تطابقاً:" + nl
see ">>> " + best_chunk + nl + nl

# 4. توليد الإجابة الحتمية عبر Prompt مجمّع بـ QalamInk
rag = new RAGPipeline(llm, store)
prompt = "<|im_start|>system" + nl + 
         "أجب دائماً باللغة العربية الفصحى باختصار ودقة بناءً على هذا المرجع فقط: " + best_chunk + "<|im_end|>" + nl +
         "<|im_start|>user" + nl + cQuestion + "<|im_end|>" + nl +
         "<|im_start|>assistant" + nl

see "إجابة النموذج:" + nl
oTimer.reset()
response = llm.generateStream(prompt, 128)
see nl + "[زمن التوليد: " + oTimer.elapsed() + "]" + nl
see "====================================================================" + nl
