# ====================================================================
#   Madar AI - Semantic Knowledge Base Builder (BGE-M3 Powered)
#   بناء قاعدة المعرفة الدائمة للغة رينج باستخدام نموذج التضمين العالمي BGE-M3
# ====================================================================

load "stdlibcore.ring"
load "madar_ai.ring"
load "rag.ring"

see nl + "====================================================================" + nl
see "  Madar AI - High-Precision Ring Knowledge Base Builder" + nl
see "  Powered by: BAAI/bge-m3 (Dense Multi-Lingual Embeddings, 1024-Dim)" + nl
see "====================================================================" + nl

# 1. Locate BGE-M3 Embedding Model
cModelPath = "models/bge-m3-q4_0.gguf"
if not fexists(cModelPath)
	cModelPath = "../../models/bge-m3-q4_0.gguf"
ok
if not fexists(cModelPath)
	cModelPath = "../models/bge-m3-q4_0.gguf"
ok

if not fexists(cModelPath)
	see f"  [ERROR] BGE-M3 model not found at 'models/bge-m3-q4_0.gguf'!" + nl
	see "  Please ensure bge-m3-q4_0.gguf exists in the models/ folder." + nl
	bye
ok

see f"  Loading Embedding Model: {cModelPath}" + nl
t0 = clock()
embedModel = ai_open(cModelPath)
t1 = clock()
see f"  Embedding Model initialized in {round((t1 - t0) / clockspersecond(), 2)}s" + nl

store = new VectorStore(embedModel)


# --------------------------------------------------------------------
# 3. Target Curated Knowledge Files (Ring-Lang-Skill References)
# --------------------------------------------------------------------
aTargetDocs = [
	# Core Language References (High Density, Zero Fluff)
	["docs/ring-lang-skill/references/core.md",                  "Core Syntax & Keywords"],
	["docs/ring-lang-skill/references/builtins.md",              "Built-in Functions (258 Functions)"],
	["docs/ring-lang-skill/references/functions.md",             "Functions, Parameters & Scopes"],
	["docs/ring-lang-skill/references/lists.md",                 "Lists, Arrays, Matrices & Hashes"],
	["docs/ring-lang-skill/references/strings.md",               "String Manipulation & Conversions"],
	["docs/ring-lang-skill/references/oop.md",                   "OOP, Classes, Methods & Object Scopes"],
	["docs/ring-lang-skill/references/ring_syntax_pitfalls_session.md", "Syntax Pitfalls & Style 3 Traps"],
	["docs/ring-lang-skill/references/ring_execution_pitfalls.md",       "Execution Model & Ordering"],
	["docs/ring-lang-skill/references/errors.md",                "Compiler & Runtime Errors Reference"],
	["docs/ring-lang-skill/references/ring_threads_libraries.md","Threads & Concurrency Extensions"],
	["docs/ring-lang-skill/SKILL.md",                           "Ring 1.27 Fast Cheatsheet"],
	# Modern Madar Extensions
	["docs/FSTRINGS.md",                                         "Madar Feature: F-Strings"],
	["docs/COMPREHENSIONS.md",                                   "Madar Feature: List Comprehensions"],
	["docs/DOUR_LOOPS.md",                                       "Madar Feature: Dour Loop Optimization"],
	["docs/DEFAULT_ARGS.md",                                     "Madar Feature: Default Arguments"],
	["docs/SLICING.md",                                          "Madar Feature: Advanced Python Slicing"]
]

see nl + "  [Processing Knowledge Sources]..." + nl
nTotalChunks = 0

for aDoc in aTargetDocs
	cRelPath = aDoc[1]
	cTitle   = aDoc[2]

	cPath = cRelPath
	if not fexists(cPath) and fexists(f"../../{cRelPath}")
		cPath = f"../../{cRelPath}"
	elseif not fexists(cPath) and fexists(f"../{cRelPath}")
		cPath = f"../{cRelPath}"
	ok

	if fexists(cPath)
		cContent = read(cPath)
		aFileChunks = chunkRingMarkdown(cContent, cTitle)

		t0 = clock()
		nDocChunks = 0
		for ch in aFileChunks
			store.addText(ch, f"{JustFileName(cPath)}_c{nDocChunks + 1}", ["source" = cRelPath, "title" = cTitle])
			nDocChunks++
		next
		t1 = clock()
		nSec = round((t1 - t0) / clockspersecond(), 2)

		see f"  + [{JustFileName(cPath)}] -> {nDocChunks} semantic chunks ({nSec}s) [{cTitle}]" + nl
		nTotalChunks += nDocChunks
	else
		see f"  - [Warning] Source file not found: {cRelPath}" + nl
	ok
next

# --------------------------------------------------------------------
# 4. Save to Persistent Binary Storage
# --------------------------------------------------------------------
aOutputs = [
	"examples/ai/agent_memory.bin",
	"examples/agent_chat/agent_memory.bin",
	"agent_memory.bin"
]

see nl + f"  [Indexing Complete] Total: {nTotalChunks} high-density chunks generated." + nl
for cOut in aOutputs
	cDest = cOut
	if not direxists(JustFilePath(cDest)) and fexists(f"../../{cDest}")
		cDest = f"../../{cDest}"
	elseif not direxists(JustFilePath(cDest)) and fexists(f"../{cDest}")
		cDest = f"../{cDest}"
	ok

	cDir = JustFilePath(cDest)
	if cDir = "" or direxists(cDir)
		store.saveBinary(cDest)
		see f"  Saved memory to: {cDest}" + nl
	ok
next

see nl + "====================================================================" + nl
see "  Success! Ring Knowledge Base is fully built and ready for Madar AI." + nl
see "====================================================================" + nl

# --------------------------------------------------------------------
# 2. Specialized Code-Aware Markdown Chunker
# - Splits strictly at Section Headers (## and ###)
# - NEVER cuts inside code blocks (``` ... ```)
# - Injects breadcrumb context [Document > Header] into every chunk
# --------------------------------------------------------------------
func chunkRingMarkdown(cContent, cDocTitle, nMaxChars = 1400, nMinChars = 40)
	aLines = split(cContent, nl)
	aChunks = []
	cBuffer = ""
	cCurrentHeader = cDocTitle
	bInCodeBlock = false

	for line in aLines
		sTrim = trim(line)

		# Track code blocks to never break across fences
		if len(sTrim) >= 3 and left(sTrim, 3) = "```"
			bInCodeBlock = !bInCodeBlock
		ok

		# Check if this line is a section header (outside of code blocks)
		bIsHeader = false
		if !bInCodeBlock and len(sTrim) >= 3
			if left(sTrim, 3) = "## " or (len(sTrim) >= 4 and left(sTrim, 4) = "### ")
				bIsHeader = true
			ok
		ok

		if bIsHeader
			if len(trim(cBuffer)) >= nMinChars
				aChunks + trim(cBuffer)
				cBuffer = ""
			ok
			cCurrentHeader = sTrim
			cBuffer = "[" + cDocTitle + " > " + sTrim + "]" + nl + nl
		else
			# Section split when buffer gets long and we hit an empty line outside code
			if len(cBuffer) >= nMaxChars and sTrim = "" and !bInCodeBlock
				if len(trim(cBuffer)) >= nMinChars
					aChunks + trim(cBuffer)
					cBuffer = "[" + cDocTitle + " > " + cCurrentHeader + " (cont.)]" + nl + nl
				ok
			else
				cBuffer += line + nl
			ok
		ok
	next

	if len(trim(cBuffer)) >= nMinChars
		aChunks + trim(cBuffer)
	ok

	return aChunks
