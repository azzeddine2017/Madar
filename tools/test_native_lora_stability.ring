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

# Subsample 15 samples for quick diagnostic test
aAll = oDataset.aSamples
aSubset = []
nLimit = 15
for i = 1 to nLimit
	aSubset + aAll[i]
next
oDataset.aSamples = aSubset

? "3. Initializing LoRA Trainer (Rank=16, Alpha=32.0, LR=0.0002)..."
oTrainer = new MadarLoRATrainer(oModel, oDataset, 16, 32.0, 0.0002) {
	nLogInterval  = 1
	nSaveInterval = 10
	cOutputDir    = "adapters/test_stability"
}

? "4. Running 1 Epoch (15 Steps with LogInterval=1)..."
oTrainer.train(1)

? "===================================================================="
? "  Test Finished Successfully!                                        "
? "===================================================================="

