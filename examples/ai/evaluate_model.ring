# ====================================================================
# Madar AI - Model Evaluation Benchmark
# Tests Ring syntax comprehension and code generation
# ====================================================================

load "madar_ai.ring"

func main()
	? "===================================================================="
	? "  Madar AI - Ring Code Generation Evaluation Benchmark"
	? "===================================================================="

	cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
	if !fexists(cModelPath)
		? "Model not found at: " + cModelPath
		return
	ok

	oModel = model_open(cModelPath)
	oModel.setThreads(4)
	oModel.setMaxTokens(256)
	oModel.setTemperature(0.2)

	aTestQuestions = [
		"Write a simple Ring function to reverse a string and print it.",
		"How do I create and iterate through a list in Ring?",
		"Write a Ring class named Rectangle with width, height and area() method."
	]

	for i = 1 to len(aTestQuestions)
		cQ = aTestQuestions[i]
		? ""
		? "--------------------------------------------------------------------"
		? f"Test Case [{i}]: {cQ}"
		? "--------------------------------------------------------------------"
		cPrompt = oModel.formatChatPrompt(cQ, "You are an expert Ring language programmer. Output valid Ring code.")
		cResp = oModel.generate(cPrompt, 200)
		? cResp
		? ""
		? f"Tokens/sec: {round(oModel.tokensPerSecond(), 2)}"
	next

	? "===================================================================="
	? "  Benchmark Completed."
	? "===================================================================="

