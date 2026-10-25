# ====================================================================
#   Madar AI - Documentation & Ring Knowledge Base Ingestion Script
#   (أداة فهرسة وثائق مدار ولغة رينج وتخزينها في الذاكرة الدائمة)
# ====================================================================

load "madar_ai.ring"
load "rag.ring"

see nl + "====================================================================" + nl
see "  Madar AI - Ring Knowledge Ingestion Tool" + nl
see "  (أداة بناء وتحديث قاعدة المعرفة الدائمة للوكيل الذكي)" + nl
see "====================================================================" + nl

cModelPath = "models/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
if not fexists(cModelPath)
	cModelPath = "../../models/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
ok
if not fexists(cModelPath)
	cModelPath = "../models/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
ok

if not fexists(cModelPath)
	see f"  [ERROR] Model file not found in models/ directory!\n"
	bye
ok

see f"  Model: {cModelPath}\n"
model = new QwenModel(cModelPath)
model.setThreads(4)
model.setGPU(1)

store = new VectorStore(model)

cOutputFile = "agent_memory.bin"
# If running from root directory
if direxists("examples/agent_chat")
	cOutputFile = "examples/agent_chat/agent_memory.bin"
ok

# Ingest target documentation
aDocs = [
	"README.md",
	"docs/COMPREHENSIONS.md",
	"docs/DEFAULT_ARGS.md",
	"docs/DOUR_LOOPS.md",
	"docs/FSTRINGS.md",
	"docs/SLICING.md",
	"docs/AI_ENGINE.md",
	"docs/ARCHITECTURE.md"
]

nTotalChunks = 0
for doc in aDocs
	cPath = doc
	if not fexists(cPath) and fexists(f"../../{doc}")
		cPath = f"../../{doc}"
	elseif not fexists(cPath) and fexists(f"../{doc}")
		cPath = f"../{doc}"
	ok

	if fexists(cPath)
		t0 = clock()
		nAdded = store.addDocument(cPath)
		t1 = clock()
		nSec = round((t1 - t0) / clockspersecond(), 2)
		nTotalChunks += nAdded
		see f"  [Indexed] {doc} -> {nAdded} chunks ({nSec}s)\n"
	else
		see f"  [Warning] File not found: {doc}\n"
	ok
next

# Save binary memory file
store.saveBinary(cOutputFile)
see nl + f"  [Success] Saved {store.count()} knowledge chunks to '{cOutputFile}'\n"
if cOutputFile != "agent_memory.bin"
	store.saveBinary("agent_memory.bin")
ok
see "====================================================================" + nl
