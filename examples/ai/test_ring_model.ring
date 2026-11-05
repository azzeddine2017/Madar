# ====================================================================
# Madar AI - Test Standalone Exported Ring Language Model
# Evaluates models/qwen2.5-0.5b-ring-instruct-q4_0.gguf on Ring coding tasks
# ====================================================================

load "madar_ai.ring"

? "===================================================================="
? "  Madar AI - Standalone Merged Ring Model Evaluation               "
? "===================================================================="

cModelPath = "models/qwen2.5-0.5b-ring-instruct-q4_0.gguf"

if !fexists(cModelPath)
	if fexists("models/qwen2.5-0.5b-ring-instruct-merged.gguf")
		cModelPath = "models/qwen2.5-0.5b-ring-instruct-merged.gguf"
	elseif fexists("../../" + cModelPath)
		cModelPath = "../../" + cModelPath
	elseif fexists("../" + cModelPath)
		cModelPath = "../" + cModelPath
	ok
ok

? "Loading Standalone Model: " + cModelPath
t0 = clock()
oModel = model_open(cModelPath)
t1 = clock()
? "Model Loaded in " + round((t1 - t0) / clockspersecond(), 2) + "s"

oModel.setTemperature(0.2)
oModel.setMaxTokens(130)
oModel.setThreads(4)

aTestPrompts = [
	"Write a Ring code example to reverse a string and check if it is a palindrome.",
	"Write a Ring program to calculate the factorial of a number using a function.",
	"Write a Ring code example to create a list of numbers from 1 to 5 and print their squares."
]

for i = 1 to len(aTestPrompts)
	cQuery = aTestPrompts[i]
	? ""
	? "--------------------------------------------------------------------"
	? ">>> [PROMPT " + i + "]: " + cQuery
	? "--------------------------------------------------------------------"
	cPrompt = oModel.formatChatPrompt(cQuery, "You are an expert Ring language AI programmer.")
	
	tStart = clock()
	cOutput = oModel.generate(cPrompt, 130)
	tEnd = clock()
	nDuration = (tEnd - tStart) / clockspersecond()
	
	? cOutput
	? ""
	? "  [Generation Time: " + round(nDuration, 2) + "s | Speed: " + round(oModel.tokensPerSecond(), 1) + " tok/s]"
next

? ""
? "===================================================================="
? "  Evaluation Complete!                                               "
? "===================================================================="

