/*
 * Q6_K Diagnostic Test
 * Tests the output.weight (Q6_K) tensor computation directly
 * to verify that logits are computed correctly.
 */

load "madar_ai.ring"

cModelPath = ""

# Find a model
aModels = [
	"../../models/qwen2.5-0.5b-instruct-q4_0.gguf",
	"../../models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
	"models/qwen2.5-0.5b-instruct-q4_0.gguf",
	"models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf"
]

for cPath in aModels
	if fexists(cPath)
		cModelPath = cPath
		exit
	ok
next

if cModelPath = ""
	see "No model found!" + nl
	bye
ok

see "=== Q6_K Diagnostic Test ===" + nl
see "Model: " + cModelPath + nl + nl

model = new QwenModel(cModelPath)
model.setThreads(4)

# Test 1: Simple tokenization
see "--- Test 1: Tokenization ---" + nl
cTest = "Hello"
aTokens = model.tokenize(cTest)
see "Tokens for '" + cTest + "': "
for i = 1 to len(aTokens)
	see "" + aTokens[i]
	if i < len(aTokens) see ", " ok
next
see nl + nl

# Test 2: Generate with very low temperature (greedy) to check if logits are deterministic
see "--- Test 2: Greedy Generation (temp=0.0) ---" + nl
model.setTemperature(0.0)
cPrompt = "<|im_start|>system" + nl + "You are a helpful assistant." + "<|im_end|>" + nl +
          "<|im_start|>user" + nl + "What is 2+2?" + "<|im_end|>" + nl +
          "<|im_start|>assistant" + nl
cResult = model.generate(cPrompt, 20)
see "Prompt: What is 2+2?" + nl
see "Response: [" + cResult + "]" + nl
see "Speed: " + model.fTokensPerSec + " tokens/sec" + nl + nl

# Test 3: Simple English prompt
see "--- Test 3: Simple English ---" + nl
model.setTemperature(0.0)
cPrompt2 = "<|im_start|>system" + nl + "You are a helpful assistant." + "<|im_end|>" + nl +
           "<|im_start|>user" + nl + "Hello" + "<|im_end|>" + nl +
           "<|im_start|>assistant" + nl
cResult2 = model.generate(cPrompt2, 20)
see "Prompt: Hello" + nl
see "Response: [" + cResult2 + "]" + nl
see "Speed: " + model.fTokensPerSec + " tokens/sec" + nl + nl

# Test 4: Arabic prompt
see "--- Test 4: Arabic ---" + nl
model.setTemperature(0.0)
cPrompt3 = model.formatChatPrompt("مرحبا", "")
cResult3 = model.generate(cPrompt3, 20)
see "Prompt: مرحبا" + nl
see "Response: [" + cResult3 + "]" + nl
see "Speed: " + model.fTokensPerSec + " tokens/sec" + nl + nl

model.close()
see "=== Done ===" + nl
