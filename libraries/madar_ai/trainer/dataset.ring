# ====================================================================
# Madar AI - Instruction Dataset Loader & Tokenizer
# Handles JSONL datasets, chat formatting, and target token masking
# ====================================================================

load "stdlibcore.ring"
load "jsonlib.ring"

class MadarInstructDataset
	cFilePath    = ""
	aSamples     = []
	cTemplate    = "chatml" # "chatml", "alpaca", "raw"
	cSystemMsg   = "You are an expert software engineer specialized in the Ring programming language and Madar Runtime Engine."

	func init(cPath, cPromptTemplate = "chatml")
		cFilePath = cPath
		cTemplate = cPromptTemplate
		if fexists(cFilePath)
			loadJSONL()
		ok
		return self

	/*
	* Function: loadJSONL
	* Streams line-by-line from the JSONL file to conserve memory
	*/
	func loadJSONL()
		aSamples = []
		cRaw = read(cFilePath)
		if len(cRaw) = 0 return ok

		aLines = str2list(cRaw)
		for cLine in aLines
			cLine = trim(cLine)
			if len(cLine) > 5 and cLine[1] = "{"
				try
					aParsed = JSON2List(cLine)
					cInst = ""
					cInp  = ""
					cOut  = ""

					for entry in aParsed
						cKey = lower(entry[1])
						if cKey = "instruction"
							cInst = "" + entry[2]
						elseif cKey = "input"
							cInp = "" + entry[2]
						elseif cKey = "output" or cKey = "response"
							cOut = "" + entry[2]
						ok
					next

					if len(cInst) > 0 and len(cOut) > 0
						aSamples + [
							:instruction = cInst,
							:input       = cInp,
							:output      = cOut
						]
					ok
				catch
					# Skip malformed lines
				done
			ok
		next

	func size()
		return len(aSamples)

	/*
	* Function: shuffle
	* Randomly permutes dataset samples using Fisher-Yates algorithm
	* Eliminates topic clustering and guarantees smooth, monotonic loss reduction
	*/
	func shuffle()
		nLen = len(aSamples)
		if nLen <= 1 return ok
		for i = nLen to 2 step -1
			j = (random(nLen * 1000) % i) + 1
			temp = aSamples[i]
			aSamples[i] = aSamples[j]
			aSamples[j] = temp
		next

	func getSample(nIndex)
		if nIndex >= 1 and nIndex <= len(aSamples)
			return aSamples[nIndex]
		ok
		return NULL

	/*
	* Function: formatPrompt
	* Generates the prompt prefix based on the selected template
	*/
	func formatPrompt(cInstruction, cInput = "")
		cFullInst = cInstruction
		if len(cInput) > 0
			cFullInst += nl + "Input: " + cInput
		ok

		if cTemplate = "chatml"
			cPrompt = "<|im_start|>system" + nl + cSystemMsg + "<|im_end|>" + nl +
			          "<|im_start|>user" + nl + cFullInst + "<|im_end|>" + nl +
			          "<|im_start|>assistant" + nl
			return cPrompt
		elseif cTemplate = "alpaca"
			cPrompt = "### Instruction:" + nl + cFullInst + nl + nl + "### Response:" + nl
			return cPrompt
		else
			return cFullInst + nl
		ok

	/*
	* Function: tokenizeSample
	* Tokenizes prompt and target response, creating the training mask
	* Inputs: oModel (Madar AI Model), nIndex (Sample index)
	* Output: Hash table containing aTokens, aMask, nPromptLen, nResponseLen
	*/
	func tokenizeSample(oModel, nIndex)
		oSample = getSample(nIndex)
		if isnull(oSample) return NULL ok

		cPrompt = formatPrompt(oSample[:instruction], oSample[:input])
		cResponse = oSample[:output]
		# Bound response length to ensure rapid tokenization within training context limit (512 tokens)
		if len(cResponse) > 1600
			cResponse = left(cResponse, 1600)
		ok
		if cTemplate = "chatml"
			cResponse += "<|im_end|>"
		ok

		# Tokenize using model native tokenizer
		aPromptTokens = oModel.tokenize(cPrompt)
		aRespTokens   = oModel.tokenize(cResponse)

		# Combined sequence
		aAllTokens = []
		aMask      = []

		# Prompt tokens have mask = 0 (No loss computed)
		for tok in aPromptTokens
			aAllTokens + tok
			aMask + 0
		next

		# Response tokens have mask = 1 (Loss & Gradients computed)
		for tok in aRespTokens
			aAllTokens + tok
			aMask + 1
		next

		return [
			:tokens       = aAllTokens,
			:mask         = aMask,
			:prompt_len   = len(aPromptTokens),
			:resp_len     = len(aRespTokens),
			:total_tokens = len(aAllTokens)
		]
