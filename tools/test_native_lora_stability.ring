# ====================================================================
# Madar AI - LoRA Stability & Convergence Test
# Tests native C multi-layer LoRA training loop over sequential samples
# ====================================================================

load "stdlibcore.ring"
load "madar_ai.ring"
load "madar_trainer.ring"

cModelPath = "models/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
if !fexists(cModelPath)
	cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
ok

cDataPath = "data/ring_instruct_bilingual.jsonl"
if !fexists(cDataPath)
	cDataPath = "data/ring_instruct_dataset.jsonl"
ok

? "===================================================================="
? "  Madar AI - Native LoRA Stability Verification Check                "
? "===================================================================="
? "1. Loading Base Model: " + cModelPath
oModel = model_open(cModelPath)
oModel.setThreads(4)

? "2. Loading Dataset: " + cDataPath
oDataset = new MadarInstructDataset(cDataPath, "chatml")
? "   Total Available Samples: " + oDataset.size()

# Subsample 8 samples for full-sequence, gradient-accumulated verification
aAll = oDataset.aSamples
aSubset = []
nLimit = 8
for i = 1 to nLimit
	aSubset + aAll[i]
next
oDataset.aSamples = aSubset

? "3. Initializing LoRA Trainer with Full Sequence & Gradient Accumulation..."
oTrainer = new MadarLoRATrainer(oModel, oDataset, 16, 32.0, 0.0002) {
	nGradAccum     = 4  # Accumulate over 4 samples (2 English + 2 Arabic)
	nMaxRespTokens = 0  # 0 = Train full response sequence (all code tokens)
	nLogInterval   = 4  # Log every batch of 4 samples
	nSaveInterval  = 8
	cOutputDir     = "adapters/test_stability"
}

? "4. Running Full-Sequence Training (8 Samples = 2 Batches of 4)..."
oTrainer.train(1)

? "===================================================================="
? "  Test Finished Successfully!                                        "
? "===================================================================="

