# ====================================================================
# Madar Benchmark: Base Model vs Hugging Face Fine-Tuned Model
# Objective side-by-side comparison on identical Ring programming prompts
# ====================================================================

load "stdlibcore.ring"
load "madar_ai.ring"

cBaseModelPath = "models/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
cHFModelPath   = "models/qwen2.5-coder-1.5b-ring-hf-q4_0.gguf"

aPrompts = [
	[
		:title  = "Test 1: Ring Class with Properties & Methods (English)",
		:prompt = "<|im_start|>system" + nl + "You are an expert software engineer specialized in the Ring programming language." + "<|im_end|>" + nl +
		          "<|im_start|>user" + nl + "Write a Ring code example demonstrating how to create a class with properties and methods." + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl
	],
	[
		:title  = "Test 2: Sum Function with Example (Arabic)",
		:prompt = "<|im_start|>system" + nl + "You are an expert software engineer specialized in the Ring programming language." + "<|im_end|>" + nl +
		          "<|im_start|>user" + nl + "اكتب دالة بلغة رينج لحساب مجموع عناصر مصفوفة مع مثال عملي" + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl
	],
	[
		:title  = "Test 3: Reverse String Function (English)",
		:prompt = "<|im_start|>system" + nl + "You are an expert software engineer specialized in the Ring programming language." + "<|im_end|>" + nl +
		          "<|im_start|>user" + nl + "Write a Ring program to reverse a string and check if it is a palindrome." + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl
	]
]

# ---------------------------------------------------------
# Part 1: Evaluate Base Pretrained Model
# ---------------------------------------------------------
? "===================================================================="
? "  [1/2] RUNNING BASE MODEL (Pre-trained Qwen2.5-Coder-1.5B)         "
? "===================================================================="
oBase = model_open(cBaseModelPath)
oBase.setThreads(4)

aBaseOutputs = []
for p in aPrompts
	? ">>> Generating for: " + p[:title]
	cOut = oBase.generate(p[:prompt], 128)
	aBaseOutputs + cOut
next
oBase.close()

# ---------------------------------------------------------
# Part 2: Evaluate Hugging Face Fine-Tuned Model
# ---------------------------------------------------------
? ""
? "===================================================================="
? "  [2/2] RUNNING HUGGING FACE FINE-TUNED MODEL (LoRA 3 Epochs)      "
? "===================================================================="
oHF = model_open(cHFModelPath)
oHF.setThreads(4)

aHFOutputs = []
for p in aPrompts
	? ">>> Generating for: " + p[:title]
	cOut = oHF.generate(p[:prompt], 128)
	aHFOutputs + cOut
next
oHF.close()

# ---------------------------------------------------------
# Part 3: Print Direct Side-by-Side Comparison
# ---------------------------------------------------------
? ""
? "####################################################################"
? "  HEAD-TO-HEAD COMPARISON: BASE MODEL vs HUGGING FACE FINE-TUNED    "
? "####################################################################"

for i = 1 to len(aPrompts)
	? ""
	? "===================================================================="
	? "  PROMPT: " + aPrompts[i][:title]
	? "===================================================================="
	? "--- [A] BASE MODEL OUTPUT ---"
	? aBaseOutputs[i]
	? ""
	? "--- [B] HUGGING FACE FINE-TUNED MODEL OUTPUT ---"
	? aHFOutputs[i]
	? "===================================================================="
next

