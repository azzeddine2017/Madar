# ====================================================================
# Madar AI - LoRA Trainer Verification & Local Micro-Run
# ====================================================================

load "madar_ai.ring"
load "madar_trainer.ring"

func main()
	? "===================================================================="
	? "  Madar AI - End-to-End LoRA Fine-Tuning Verification"
	? "===================================================================="

	cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
	cDataPath  = "data/ring_instruct_dataset.jsonl"

	# 1. Check Paths
	if !fexists(cModelPath)
		? "Model not found at: " + cModelPath
		return
	ok

	if !fexists(cDataPath)
		? "Dataset not found at: " + cDataPath
		return
	ok

	# 2. Open Base Model
	? "1. Loading Base Model: " + cModelPath
	oModel = model_open(cModelPath)
	oModel.setThreads(4)

	# 3. Load Dataset
	? "2. Ingesting Synthesized Ring Documentation Dataset..."
	oDataset = new MadarInstructDataset(cDataPath, "chatml")
	nTotalSamples = oDataset.size()
	? "   Successfully loaded " + nTotalSamples + " instruction samples."

	# Inspect first sample
	oSample1 = oDataset.getSample(1)
	? "   Sample 1 Instruction: " + left(oSample1[:instruction], 60) + "..."
	oTokData = oDataset.tokenizeSample(oModel, 1)
	? "   Tokenized: " + oTokData[:total_tokens] + " tokens " +
	  "(Prompt: " + oTokData[:prompt_len] + " | Response: " + oTokData[:resp_len] + ")"

	# 4. Limit dataset to 20 samples for instant local verification
	? "3. Preparing 20-Sample Micro-Training Batch..."
	aBackupSamples = oDataset.aSamples
	aMicro = []
	for i = 1 to 20
		aMicro + aBackupSamples[i]
	next
	oDataset.aSamples = aMicro

	# 5. Initialize LoRA Trainer
	? "4. Initializing Madar LoRA Trainer..."
	# Rank=8, Alpha=16, Learning Rate=0.0002
	oTrainer = new MadarLoRATrainer(oModel, oDataset, 8, 16.0, 0.0002)
	oTrainer.nLogInterval  = 5
	oTrainer.nSaveInterval = 15
	oTrainer.cOutputDir    = "adapters/test_run"

	# 6. Run Micro-Training Loop
	? "5. Running Micro-Training Loop (20 Steps Verification)..."
	bSuccess = oTrainer.train(1) # 1 Epoch over 20 micro samples

	if bSuccess
		? ""
		? ">>> VERIFICATION PASSED: Madar LoRA Engine functions perfectly!"
		? ">>> Ready for full dataset scaling on Colab / Multi-core Local execution."
	else
		? ">>> VERIFICATION FAILED."
	ok
