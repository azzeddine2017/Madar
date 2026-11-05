# ====================================================================
# Madar AI - Fast Local Adapter Training & Calibration
# Trains directional syntax adapter directly into adapters/ring_lora_cloud/final
# ====================================================================

load "madar_ai.ring"
load "madar_trainer.ring"

cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
cDataPath  = "data/ring_instruct_dataset.jsonl"
cOutputDir = "adapters/ring_lora_cloud/final"

# Resolve relative path if run from examples/ or tools/
if !fexists(cModelPath)
	if fexists("../../" + cModelPath)
		cModelPath = "../../" + cModelPath
		cDataPath  = "../../" + cDataPath
		cOutputDir = "../../" + cOutputDir
	elseif fexists("../" + cModelPath)
		cModelPath = "../" + cModelPath
		cDataPath  = "../" + cDataPath
		cOutputDir = "../" + cOutputDir
	ok
ok

? "===================================================================="
? "  Madar AI - Calibrating LoRA Adapter on Ring Instruction Dataset   "
? "===================================================================="

# 1. Load Base Model
? "1. Loading Base Model: " + cModelPath
oModel = model_open(cModelPath)
oModel.setThreads(4)

# 2. Ingest Dataset
? "2. Loading Dataset: " + cDataPath
oDataset = new MadarInstructDataset(cDataPath, "chatml")
? "   Total Available Samples: " + oDataset.size()

# Select 100 representative samples for balanced calibration
aAll = oDataset.aSamples
aSubset = []
nLimit = 100
if len(aAll) < nLimit nLimit = len(aAll) ok
for i = 1 to nLimit
	aSubset + aAll[i]
next
oDataset.aSamples = aSubset

# 3. Initialize Trainer
? "3. Initializing LoRA Trainer (Rank=16, Alpha=32.0)..."
oTrainer = new MadarLoRATrainer(oModel, oDataset, 16, 32.0, 0.0002) {
	nLogInterval  = 20
	nSaveInterval = 50
	cOutputDir    = "adapters/ring_lora_cloud"
}

# 4. Train 1 full epoch over the 100 samples
? "4. Training 1 Epoch (100 Steps)..."
oTrainer.train(1)

? ""
? "===================================================================="
? "  Calibration Complete! Adapter saved to: " + cOutputDir
? "===================================================================="
