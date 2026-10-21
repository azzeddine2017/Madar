# ====================================================================
#   Madar AI Suite - Real-Time Token Streaming & Generator Demo
#   (البث المباشر للرموز في الوقت الحقيقي ومولد الرموز التفاعلي)
# ====================================================================
load "stdlibCore.ring"
load "agent.ring"

cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
if not fexists(cModelPath)
	cModelPath = "models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf"
ok

if not fexists(cModelPath)
	see "Error: Model file not found in models/" + nl
	bye
ok

see "====================================================================" + nl
see "  Madar AI: Real-Time Token Streaming & Step-by-Step Generator" + nl
see "  (البث المباشر للرموز في الوقت الحقيقي ومولد الكلمات فائق السرعة)" + nl
see "====================================================================" + nl

model = new QwenModel(cModelPath)
model.setThreads(4)
model.setTemperature(0.6)

# --------------------------------------------------------------------
# 1. Native C High-Speed Direct Terminal Streaming
# --------------------------------------------------------------------
see nl + "1. Native C Fast Token Streaming (Direct to Terminal):" + nl
see "Prompt: ما هي لغة مدار وما أهم مميزاتها؟" + nl
see "Stream > "

cPrompt1 = model.formatChatPrompt("ما هي لغة مدار وما أهم مميزاتها باختصار؟", "أنت مساعد ذكي وموجز باللغة العربية.")
t0 = clock()
cResponse1 = model.generateStream(cPrompt1, 80)
t1 = clock()
see nl

nDurationSec = (t1 - t0) / clockspersecond()
aTokens = model.tokenize(cResponse1)
if nDurationSec > 0
	fSpeed = len(aTokens) / nDurationSec
	see "  [Performance: " + len(aTokens) + " tokens streamed in " + round(nDurationSec, 2) + "s (~" + round(fSpeed, 1) + " tokens/sec)]" + nl
ok

# --------------------------------------------------------------------
# 2. Custom Token-by-Token Callback Streaming
# --------------------------------------------------------------------
see nl + "--------------------------------------------------------------------" + nl
see "2. Custom Callback Token Interceptor (Ring Function Callback):" + nl
see "Prompt: اذكر ثلاثة مبادئ في علم البيانات." + nl
see "Callback Stream > "

cPrompt2 = model.formatChatPrompt("اذكر 3 مبادئ أساسية في علم البيانات باختصار.", "أنت مساعد علمي باللغة العربية.")
nTokenCount = 0

model.generateStreamCallback(cPrompt2, 70, func(cChunk) {
	nTokenCount++
	see cChunk
})
see nl + "  [Callback Event: intercepted " + nTokenCount + " individual token chunks in real-time]" + nl

# --------------------------------------------------------------------
# 3. Interactive Step-by-Step Generator API (prefill + hasMore + step)
# --------------------------------------------------------------------
see nl + "--------------------------------------------------------------------" + nl
see "3. Low-Level Generator Engine (model.prefill -> model.step):" + nl
see "Prompt: احسب 25 * 4 واعطني النتيجة." + nl
see "Generator Output > "

cPrompt3 = model.formatChatPrompt("كم حاصل ضرب 25 في 4؟", "أجب برقم فقط وباختصار.")
model.prefill(cPrompt3, 30)

nStepCount = 0
while model.hasMore()
	cToken = model.step()
	if cToken != ""
		nStepCount++
		see cToken
	ok
end
see nl + "  [Generator Steps: executed " + nStepCount + " autoregressive forward passes]" + nl

# --------------------------------------------------------------------
# 4. Autonomous Agent Real-Time Streaming (AIAgent.queryStream)
# --------------------------------------------------------------------
see nl + "--------------------------------------------------------------------" + nl
see "4. Autonomous AI Agent with Real-Time Response Streaming:" + nl
see "Agent Query: ما هو الوقت الحالي للنظام؟" + nl

agent = new AIAgent(model)
agent.queryStream("ما هو التاريخ والوقت الحالي للنظام؟")

see nl + "====================================================================" + nl
see "  Real-Time Token Streaming Demo Completed Successfully." + nl
see "====================================================================" + nl

