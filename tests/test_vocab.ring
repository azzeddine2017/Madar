load "madar_ai.ring"

cModel = "models/qwen2.5-0.5b-instruct-q4_0.gguf"

if not fexists(cModel)
	cModel = "models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf"
ok

m = new QwenModel(cModel)

see nl + "=== Tokenizer Test on: " + cModel + " ===" + nl
testText(m, "hello")
testText(m, "What is the capital of Algeria?")
testText(m, "ما هي عاصمة الجزائر؟")

m.close()

func testText(mObj, text)
	see nl + "--- Testing: [" + text + "] ---" + nl
	aTokens = mObj.tokenize(text)
	see "Tokens (" + len(aTokens) + "): "
	for t in aTokens see "" + t + " " next
	see nl
	cDec = mObj.detokenize(aTokens)
	see "Decoded: [" + cDec + "]" + nl
