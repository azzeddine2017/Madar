# ====================================================================
# Madar AI - Interactive Terminal Chat Assistant
# Real-time local inference using DeepSeek-R1 or Qwen2.5 (GGUF Q4_0)
# ====================================================================
load "stdlibCore.ring"
load "madar_ai.ring"

# 1. Locate Available Models (Qwen-3B or DeepSeek-R1-1.5B)
cModelPath = ""
bIsDeepSeek = false

bPreferQwen = false
for arg in sysargv
	if substr(lower(arg), "qwen") > 0
		bPreferQwen = true
	ok
next

if bPreferQwen
	aCandidates = [
		/*"models/qwen2.5-7b-instruct-q4_0.gguf",
		"../../models/qwen2.5-7b-instruct-q4_0.gguf",
		"models/qwen2.5-coder-1.5b-instruct-q4_0.gguf",
		"../../models/qwen2.5-coder-1.5b-instruct-q4_0.gguf",
		"models/qwen2.5-3b-instruct-q4_0.gguf",
		"../../models/qwen2.5-3b-instruct-q4_0.gguf",
		"models/qwen2.5-coder-3b-instruct-q4_0.gguf",
		"../../models/qwen2.5-coder-3b-instruct-q4_0.gguf",*/
		"models/qwen2.5-0.5b-instruct-q4_0.gguf",
		"../../models/qwen2.5-0.5b-instruct-q4_0.gguf"
	]
else
	aCandidates = [
		"models/deepseek-r1-distill-qwen-7b-q4_0.gguf",
		"../../models/deepseek-r1-distill-qwen-7b-q4_0.gguf",
		"models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"../../models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"models/qwen2.5-7b-instruct-q4_0.gguf",
		"../../models/qwen2.5-7b-instruct-q4_0.gguf"
	]
ok

for cCandidate in aCandidates
	if fexists(cCandidate)
		cModelPath = cCandidate
		if substr(cCandidate, "deepseek") > 0
			bIsDeepSeek = true
		ok
		exit
	ok
next

if cModelPath = ""
	see nl + "====================================================================" + nl
	see "  [ERROR] No AI model found in models/ directory!" + nl
	see "====================================================================" + nl
	see "  Please download a model first using one of the helper scripts:" + nl
	see "    - tools\download_model.bat      (Qwen-3B        ~1.9 GB, Recommended)" + nl
	see "    - tools\download_deepseek.bat   (DeepSeek-R1    ~1.1 GB)" + nl
	see "====================================================================" + nl
	bye
ok

# 2. Initialize Model
see nl + "====================================================================" + nl
see "  Madar AI - Local Interactive Chat Terminal (مدار للذكاء الاصطناعي)" + nl
see "====================================================================" + nl
see "  Loading model from: " + cModelPath + nl

t0 = clock()
if bIsDeepSeek
	model = new DeepSeekModel(cModelPath)
else
	model = new QwenModel(cModelPath)
ok
model.setThreads(4)
model.setTemperature(0.3) # Default to 0.6 for natural dialogue
t1 = clock()
nLoadSec = (t1 - t0) / clockspersecond()

see "  Hardware: " + model.nThreads + " CPU Threads (Active)" + nl
see "  Model initialized successfully in " + nLoadSec + " seconds." + nl
see "  Commands: 'exit' | 'reset' | '/gpu on|off' | '/tokens <N>' | '/temp <0.0-1.0>'" + nl
see "====================================================================" + nl

if bIsDeepSeek
	nChatMaxTokens = 1024
else
	nChatMaxTokens = 512
ok

# 3. Interactive REPL Chat Loop
while true
	see nl + "User > "
	give cInput
	cInput = trim(cInput)

	if cInput = ""
		loop
	ok

	cLower = lower(cInput)
	if cLower = "exit" or cLower = "quit" or cLower = "bye"
		see nl + "Goodbye! (وداعاً من مدار للذكاء الاصطناعي)" + nl
		model.close()
		exit
	ok

	if cLower = "reset" or cLower = "clear"
		model.reset()
		see "  [System] Context memory has been reset." + nl
		loop
	ok

	if substr(cLower, "/tokens") = 1
		aParts = split(cInput, " ")
		if len(aParts) >= 2
			nChatMaxTokens = 0 + aParts[2]
			if nChatMaxTokens < 16 nChatMaxTokens = 16 ok
			if nChatMaxTokens > 1024 nChatMaxTokens = 1024 ok
			see "  [System] Max tokens set to " + nChatMaxTokens + nl
		else
			see "  [System] Current max tokens: " + nChatMaxTokens + nl
		ok
		loop
	ok

	if substr(cLower, "/gpu") = 1
		aParts = split(cInput, " ")
		if len(aParts) >= 2
			cMode = lower(aParts[2])
			if cMode = "off" or cMode = "0"
				model.setGPU(0)
				see "  [System] GPU Acceleration disabled (Running CPU AVX2)." + nl
			else
				model.setGPU(1)
				see "  [System] GPU Acceleration enabled." + nl
			ok
		else
			see "  [System] Usage: /gpu on | /gpu off" + nl
		ok
		loop
	ok

	if substr(cLower, "/temp") = 1
		aParts = split(cInput, " ")
		if len(aParts) >= 2
			fNewTemp = 0.0 + aParts[2]
			model.setTemperature(fNewTemp)
			see "  [System] Temperature set to " + fNewTemp + nl
		else
			see "  [System] Current temperature: " + model.fTemp + nl
		ok
		loop
	ok

	see nl + "AI > "
	t0 = clock()
	cResponse = model.chatStream(cInput, nChatMaxTokens)
	t1 = clock()
	see nl
	nGenSec = (t1 - t0) / clockspersecond()

	# Performance metrics
	aTokens = model.tokenize(cResponse)
	nTokensCount = len(aTokens)
	if nGenSec > 0
		fSpeed = nTokensCount / nGenSec
		see nl + "  [Stats: " + nTokensCount + " tokens in " + nGenSec + "s (" + fSpeed + " tokens/sec)]" + nl
	ok
end
