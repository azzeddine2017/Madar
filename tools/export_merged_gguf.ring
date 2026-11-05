# ====================================================================
# Madar AI - GGUF LoRA Weight Fusion & Model Exporter
# Permanently fuses LoRA adapter weights directly into a standalone GGUF file
# ====================================================================

load "madar_ai.ring"

? "===================================================================="
? "  Madar AI - Standalone GGUF LoRA Fusion & Exporter                  "
? "===================================================================="

cBaseModel = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
cAdapter   = "adapters/ring_lora_cloud/final"
cOutModel  = "models/qwen2.5-0.5b-ring-instruct-q4_0.gguf"
fScale     = 0.005

# Path resolution if run from subdirectory
if !fexists(cBaseModel)
	if fexists("../../" + cBaseModel)
		cBaseModel = "../../" + cBaseModel
		cAdapter   = "../../" + cAdapter
		cOutModel  = "../../" + cOutModel
	elseif fexists("../" + cBaseModel)
		cBaseModel = "../" + cBaseModel
		cAdapter   = "../" + cAdapter
		cOutModel  = "../" + cOutModel
	ok
ok

# 1. Open Base Model
? "1. Loading Base Model: " + cBaseModel
oModel = model_open(cBaseModel)
oModel.setThreads(4)

# 2. Attach and Load LoRA Adapter
? "2. Fusing LoRA Adapter from: " + cAdapter
bSuccess = oModel.loadLoRA(cAdapter)
if !bSuccess
	? "Error: Failed to load LoRA adapter!"
	bye
ok

# 3. Apply Calibrated Scale
oModel.setLoRAScale(fScale)
? "   Applied LoRA Scaling Factor: " + fScale

# 4. Export Standalone Merged GGUF File
? "3. Exporting Permanently Fused Model to: " + cOutModel
t0 = clock()
nRes = oModel.exportMergedGGUF(cOutModel)
t1 = clock()

if nRes = 1
	nSec = (t1 - t0) / clockspersecond()
	? "   Successfully exported in " + round(nSec, 2) + "s!"
else
	? "Error: GGUF export failed!"
	bye
ok
oModel.close()

# 5. Verification: Load the Exported GGUF Directly (Without LoRA!)
? ""
? "===================================================================="
? "4. Verifying Standalone Exported GGUF Model (Zero LoRA Loading)...   "
? "===================================================================="
oFusedModel = model_open(cOutModel)
oFusedModel.setTemperature(0.2)
oFusedModel.setMaxTokens(120)
oFusedModel.setThreads(4)

cQuery = "Write a Ring code example to reverse a string and check if it is a palindrome."
cPrompt = oFusedModel.formatChatPrompt(cQuery, "You are an expert Ring language AI programmer.")

? ">>> Running Inference on Standalone Merged GGUF:"
cOutput = oFusedModel.generate(cPrompt, 100)
? cOutput
? ""
? "===================================================================="
? "  Export & Verification Complete: Standalone GGUF Ready for Use!     "
? "===================================================================="
