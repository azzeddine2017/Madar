# ====================================================================
# Madar AI - Multi-Layer Bilingual Ring LoRA Fine-Tuning & GGUF Fusion
# Pure Native Madar / Ring Engine (Zero Python / Zero Node.js)
# ====================================================================

load "madar_ai.ring"
load "madar_trainer.ring"

func main()
	decimals(6)
	? "===================================================================="
	? "  Madar AI - Multi-Layer Causal LM LoRA Fine-Tuner"
	? "  Engine: Native Ring + Madar C Core (Zero Python Dependency)"
	? "===================================================================="

	# Parse Command Line Arguments or use defaults
	# Usage: ring train_ring_bilingual_lora.ring [model_path] [data_path] [epochs]
	cModelPath = "models/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
	cDataPath  = "data/ring_instruct_bilingual.jsonl"
	nEpochs    = 3
	nRank      = 16
	fAlpha     = 16.0
	fLR        = 0.00005

	aArgs = sysargv
	nScriptArgIdx = 0
	for i = 1 to len(aArgs)
		if substr(lower(aArgs[i]), "train_ring_bilingual_lora.ring") > 0
			nScriptArgIdx = i
			exit
		ok
	next

	if nScriptArgIdx > 0
		if len(aArgs) >= nScriptArgIdx + 1 and aArgs[nScriptArgIdx + 1] != ""
			cModelPath = aArgs[nScriptArgIdx + 1]
		ok
		if len(aArgs) >= nScriptArgIdx + 2 and aArgs[nScriptArgIdx + 2] != ""
			cDataPath = aArgs[nScriptArgIdx + 2]
		ok
		if len(aArgs) >= nScriptArgIdx + 3 and aArgs[nScriptArgIdx + 3] != ""
			nEpochs = 0 + aArgs[nScriptArgIdx + 3]
		ok
	ok

	if !fexists(cModelPath)
		? "[ERROR] Base model not found: " + cModelPath
		return
	ok

	if !fexists(cDataPath)
		? "[ERROR] Dataset not found: " + cDataPath
		return
	ok

	# 1. Initialize Base Model
	? ">>> [1/4] Loading Base Model: " + cModelPath
	oModel = model_open(cModelPath)
	oModel.setThreads(4)

	# 2. Ingest Dataset
	? ">>> [2/4] Ingesting Bilingual Dataset: " + cDataPath
	oDataset = new MadarInstructDataset(cDataPath, "chatml")
	nTotalSamples = oDataset.size()
	? "    Ingested " + nTotalSamples + " high-quality bilingual Ring instructions."

	# 3. Setup Multi-Layer LoRA Trainer
	? ">>> [3/4] Initializing Multi-Layer LoRA Trainer across all layers..."
	oTrainer = new MadarLoRATrainer(oModel, oDataset, nRank, fAlpha, fLR)
	oTrainer.nEpochs       = nEpochs
	oTrainer.nMaxSeqLen    = 384
	oTrainer.nLogInterval  = 10
	oTrainer.nSaveInterval = 200

	cModelBase = "qwen2.5-coder-1.5b"
	if substr(lower(cModelPath), "deepseek") > 0
		cModelBase = "deepseek-r1-distill-1.5b"
	ok
	cAdapterOut = "adapters/" + cModelBase + "_ring_lora"
	oTrainer.cOutputDir = cAdapterOut

	# 4. Train with True Cross-Entropy Backpropagation
	? ">>> [4/4] Starting Multi-Layer Causal LM Training Loop..."
	t0 = clock()
	bSuccess = oTrainer.train(nEpochs)
	t1 = clock()
	fTotalTime = (t1 - t0) / clockspersecond()

	if bSuccess
		? ""
		? "===================================================================="
		? "  Training Completed Successfully in " + round(fTotalTime, 2) + "s"
		? "===================================================================="
		cGGUFOut = "models/" + cModelBase + "-ring-bilingual-merged.gguf"
		? ">>> Exporting standalone fused model to: " + cGGUFOut
		oModel.exportMergedGGUF(cGGUFOut)
		? ">>> Standalone GGUF Model is ready for production inference!"
	else
		? "[ERROR] Training terminated with errors."
	ok
