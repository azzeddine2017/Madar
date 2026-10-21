# ====================================================================
# Madar AI - High-Level Machine Learning & LLM Inference Framework
# Declarative LLM wrappers, sampling, and chat template formatting
# ====================================================================


func model_open(cPath)
	if substr(lower(cPath), "deepseek") > 0
		oModel = new DeepSeekModel(cPath)
		return oModel
	ok
	oModel = new QwenModel(cPath)
	return oModel

func ai_open(cPath)
	return model_open(cPath)

func round(val, nDec)
	s = "" + val
	nDot = substr(s, ".")
	if nDot > 0 and len(s) > nDot + nDec
		return left(s, nDot + nDec)
	ok
	return s



class QwenModel
	hModel
	cLoadedPath = ""
	nThreads = 4
	fTemp = 0.7
	nMaxTokens = 64
	fTokensPerSec = 0.0

	func init(cFilePath)
		cLoadedPath = cFilePath
		hModel = madar_model_open(cFilePath)
		if isnull(hModel)
			raise("Failed to open model file: " + cFilePath)
		ok
		setThreads(nThreads)
		return self

	func setThreads(n)
		nThreads = n
		madar_model_set_threads(hModel, n)

	func setTemperature(temp)
		fTemp = temp

	func tokenize(cText)
		return madar_model_tokenize(hModel, cText)

	func detokenize(aTokens)
		return madar_model_detokenize(hModel, aTokens)

	func isArabic(cText)
		return madar_is_arabic(cText)

	func embedding(cText)
		return madar_model_embedding(hModel, cText)

	func get_embedding(cText)
		return embedding(cText)

	func formatChatPrompt(cUserMessage, cSystemMessage)
		# Official Qwen2.5 ChatML format
		if cSystemMessage = NULL or cSystemMessage = ""
			cSystemMessage = "You are Qwen, created by Alibaba Cloud. You are a helpful assistant."
		ok
		cPrompt = "<|im_start|>system" + nl + cSystemMessage + "<|im_end|>" + nl +
		          "<|im_start|>user" + nl + cUserMessage + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl
		return cPrompt

	func generate(cPrompt, nTokens)
		if nTokens != NULL and nTokens > 0
			nMaxTokens = nTokens
		ok
		t0 = clock()
		cOutput = madar_model_generate(hModel, cPrompt, nMaxTokens, fTemp)
		t1 = clock()
		nDurationSec = (t1 - t0) / clockspersecond()
		if nDurationSec > 0
			aGenTokens = tokenize(cOutput)
			fTokensPerSec = len(aGenTokens) / nDurationSec
		ok
		return cOutput

	func prefill(cPrompt, nTokens)
		if nTokens = NULL or nTokens <= 0 nTokens = nMaxTokens ok
		return madar_model_prefill(hModel, cPrompt, nTokens, fTemp)

	func hasMore()
		return madar_model_has_more(hModel)

	func step()
		return madar_model_step(hModel)

	func generateStream(cPrompt, nTokens)
		if nTokens != NULL and isnumber(nTokens) and nTokens > 0
			nMaxTokens = nTokens
		ok
		t0 = clock()
		cOutput = madar_model_generate_stream(hModel, cPrompt, nMaxTokens, fTemp)
		t1 = clock()
		nDurationSec = (t1 - t0) / clockspersecond()
		if nDurationSec > 0
			aGenTokens = tokenize(cOutput)
			fTokensPerSec = len(aGenTokens) / nDurationSec
		ok
		return cOutput

	func generateStreamCallback(cPrompt, nTokens, pCallback)
		if nTokens != NULL and isnumber(nTokens) and nTokens > 0
			nMaxTokens = nTokens
		ok
		t0 = clock()
		cOutput = ""
		prefill(cPrompt, nMaxTokens)
		while hasMore()
			cChunk = step()
			if cChunk != ""
				cOutput += cChunk
				if pCallback != NULL
					call pCallback(cChunk)
				ok
			ok
		end
		t1 = clock()
		nDurationSec = (t1 - t0) / clockspersecond()
		if nDurationSec > 0
			aGenTokens = tokenize(cOutput)
			fTokensPerSec = len(aGenTokens) / nDurationSec
		ok
		return cOutput

	func stream(cPrompt, nTokens, pCallback)
		return generateStreamCallback(cPrompt, nTokens, pCallback)

	func chat(cUserMessage, nTokens)
		cPrompt = formatChatPrompt(cUserMessage, "")
		return generate(cPrompt, nTokens)

	func chatStream(cUserMessage, nTokens)
		cPrompt = formatChatPrompt(cUserMessage, "")
		return generateStream(cPrompt, nTokens)

	func getTokensPerSecond()
		return fTokensPerSec

	func reset()
		madar_model_reset(hModel)

	func close()
		if not isnull(hModel)
			madar_model_close(hModel)
			hModel = NULL
		ok

class DeepSeekModel from QwenModel
	# DeepSeek-R1-Distill is built on Qwen2.5 architecture
	# Adds ChatML prompt formatting and reasoning <think> parser

	func formatChatPrompt(cUserMessage, cSystemMessage)
		# Official DeepSeek-R1 native format: <｜User｜>{message}<｜Assistant｜><think>\n
		cPrompt = "<｜User｜>" + cUserMessage + "<｜Assistant｜><think>" + nl
		return cPrompt

	func extractThinking(cResponse)
		nStart = substr(cResponse, "<think>")
		nEnd = substr(cResponse, "</think>")
		if nStart > 0 and nEnd > nStart
			return trim(substr(cResponse, nStart + 7, nEnd - nStart - 7))
		ok
		return ""

	func extractAnswer(cResponse)
		nEnd = substr(cResponse, "</think>")
		if nEnd > 0
			return trim(substr(cResponse, nEnd + 8))
		ok
		return trim(cResponse)


