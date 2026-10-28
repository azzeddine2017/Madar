# ====================================================================
#   MadarAgent - Intent Registry (سجل تعريف النوايا والمهام)
#   تحديد النوايا المباشرة (Zero-LLM)، الأدوات الحتمية، والمهارات الموجهة
# ====================================================================


class IntentItem
	cName         = ""
	cType         = "scoped_skill"  # direct_response | direct_tool | scoped_skill
	aTriggers     = []              # Natural language examples (Ar / En)
	cResponse     = ""              # For direct_response
	cToolName     = ""              # For direct_tool
	cExtractRegex = ""              # Regex pattern for parameter extraction
	cSkillName    = ""              # For scoped_skill
	aScopedTools  = []              # List of tool names to inject into LLM
	bNeedsRag     = false           # Whether to retrieve from Knowledge Base

class IntentRegistry
	aIntents = []

	func init()
		registerDefaults()
		return self

	func registerDefaults()
		aIntents = []

		# 1. Direct Response: Identity & About Madar (Zero-LLM)
		oIdentity = new IntentItem {
			cName     = "identity"
			cType     = "direct_response"
			aTriggers = [
				"من أنت",
				"من انت",
				"عرف بنفسك",
				"عرفني بنفسك",
				"من تكون",
				"ما هو مدار",
				"ما هي قدراتك",
				"who are you",
				"what is madar",
				"what can you do"
			]
			cResponse = "أنا 'مدار' (MadarAgent) — وكيل ذكاء اصطناعي محلي فائق السرعة، مبني بالكامل بلغة رينج (Ring 1.27) ومدعوم بتسريع العتاد وقواعد المعرفة الدلالية (Semantic RAG & Routing)."
		}
		addIntent(oIdentity)

		# 2. Direct Response: Greetings (Zero-LLM)
		oGreeting = new IntentItem {
			cName     = "greeting"
			cType     = "direct_response"
			aTriggers = [
				"مرحبا",
				"السلام عليكم",
				"أهلاً وسهلاً",
				"صباح الخير",
				"مساء الخير",
				"hello",
				"hi there",
				"hey",
				"greetings"
			]
			cResponse = "أهلاً بك! أنا في خدمتك. كيف يمكنني مساعدتك اليوم في مشاريعك أو البرمجة بلغة رينج؟"
		}
		addIntent(oGreeting)

		# 3. Direct Tool: Arithmetic Calculator (Zero-LLM)
		oCalc = new IntentItem {
			cName         = "direct_calc"
			cType         = "direct_tool"
			cToolName     = "calc"
			cExtractRegex = "(?i)(?:احسب|كم ناتج|ما حاصل|calc(?:ulate)?)\s*:?\s*([0-9\.\s\+\-\*\/\(\)\^\%]+)"
			aTriggers     = [
				"احسب ناتج",
				"كم حاصل ضرب",
				"حل المعادلة الرياضية",
				"calculate math expression",
				"calc 50 * 20",
				"احسب 1500 / 3"
			]
		}
		addIntent(oCalc)

		# 4. Scoped Skill: Ring Programming Expert (Targeted LLM + RAG + Code Tools)
		oRingCoder = new IntentItem {
			cName        = "ring_coding"
			cType        = "scoped_skill"
			cSkillName   = "ring_coder"
			bNeedsRag    = true
			aScopedTools = ["run_ring_code", "read_file", "write_file"]
			aTriggers    = [
				"كيف أكتب كلاس في رينج",
				"عندي خطأ في كود رينج",
				"اكتب دالة أو سكريبت بلغة ring",
				"أريد مثال برمجي في لغة رينج",
				"ما هو سنتاكس لغة رينج",
				"how to write a class in ring",
				"syntax error in ring code",
				"write a ring script",
				"ring programming language example"
			]
		}
		addIntent(oRingCoder)

		# 5. Scoped Skill: File Management & System (Targeted Tools, No RAG)
		oFiles = new IntentItem {
			cName        = "system_files"
			cType        = "scoped_skill"
			cSkillName   = ""
			bNeedsRag    = false
			aScopedTools = ["read_file", "write_file", "list_files"]
			aTriggers    = [
				"اقرأ محتوى الملف",
				"اعرض لي الملفات الموجودة",
				"احفظ هذا النص في ملف",
				"list directory files",
				"read file content",
				"create a text file"
			]
		}
		addIntent(oFiles)

		# 6. Scoped Skill: Memory & Facts (Targeted Remember Tool)
		oMemory = new IntentItem {
			cName        = "remember_memory"
			cType        = "scoped_skill"
			cSkillName   = ""
			bNeedsRag    = false
			aScopedTools = ["remember_fact"]
			aTriggers    = [
				"تذكر أن اسمي",
				"احفظ في الذاكرة هذه المعلومة",
				"تذكر هذا الأمر دائماً",
				"remember that my preference",
				"save this fact to memory"
			]
		}
		addIntent(oMemory)

	func addIntent(oItem)
		aIntents + oItem

	func getIntent(cName)
		for item in aIntents
			if lower(trim(item.cName)) = lower(trim(cName))
				return item
			ok
		next
		return NULL
