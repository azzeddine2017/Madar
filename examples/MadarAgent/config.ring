# ====================================================================
#   MadarAgent - Configuration & Model Auto-Discovery
#   إعدادات الوكيل الذكي واكتشاف النماذج المثبتة آلياً
# ====================================================================

load "stdlibcore.ring"

class AgentConfig
	cModelPath       = ""
	cEmbeddingPath   = ""
	cBaseKbPath      = "memory/ring_kb.bin"
	cWorkingKbPath   = "memory/user_memory.bin"
	cSkillsDir       = "agentSkills"
	nTemperature     = 0.30
	nMaxContext      = 8192
	nMaxGenTokens    = 1500
	bGPU             = true
	bDebug           = true
	nRagTopK         = 1
	nRagMaxChars     = 800
	# History & Sliding Window Controls
	bUseSlidingWindow = true
	nHistoryWindow    = 2
	# Semantic Intent Router Controls
	cIntentCachePath  = "memory/intent_cache.bin"
	nIntentThreshold  = 0.52

	func init(aArgs = [])
		discoverModels(aArgs)
		return self

	func discoverModels(aArgs)
		# 1. Search Directories for Models
		aCandidateDirs = [
			"models",
			"../models",
			"../../models",
			"."
		]

		# Detect Embedding Model (BGE-M3 preferred)
		for dirPath in aCandidateDirs
			cPath = dirPath + "/bge-m3-q4_0.gguf"
			if fexists(cPath)
				cEmbeddingPath = cPath
				exit
			ok
		next

		# Detect LLM Generation Model based on user arg or auto-selection
		cUserChoice = ""
		if len(aArgs) > 2
			cUserChoice = lower(trim(aArgs[3]))
		else
			raise("User specified a filter " +nl+
				"'ring main.ring coder' or " +nl+
				"'ring main.ring qwen' or " +nl+
				"'ring main.ring 0.5b' or " +nl+
				"'ring main.ring deepseek'")
		ok

		aPreferredModels = [
			"qwen2.5-coder-3b-instruct-q4_k_m.gguf",
			"qwen2.5-1.5b-instruct-q4_k_m.gguf",
			"DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
			"qwen2.5-0.5b-instruct-q4_k_m.gguf"
		]

		for dirPath in aCandidateDirs
			if cUserChoice != ""
				# User specified a filter (e.g. 'coder', 'qwen', '0.5b', 'deepseek')
				if direxists(dirPath)
					aFiles = dir(dirPath)
					for f in aFiles
						cName = lower(f[1])
						if substr(cName, ".gguf") > 0 and substr(cName, cUserChoice) > 0 and substr(cName, "bge") = 0
							cModelPath = dirPath + "/" + f[1]
							exit 2
						ok
					next
				ok
			else
				# Auto-match from preferred list
				for mName in aPreferredModels
					cCandidate = dirPath + "/" + mName
					if fexists(cCandidate)
						cModelPath = cCandidate
						exit 2
					ok
				next
			ok
		next
