# ====================================================================
#   Madar AI Suite - Function Calling & AI Agent Demo
#   (عرض استدعاء الأدوات والوكيل الذكي في مدار)
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
see "  Madar AI Agent: Function Calling & Autonomous Tool Execution" + nl
see "  (الوكيل الذكي في مدار: استدعاء الدوال التلقائي والأدوات البرمجية)" + nl
see "====================================================================" + nl

model = new QwenModel(cModelPath)
model.setThreads(4)

agent = new AIAgent(model)

# Register custom application tools
agent.registerTool("currency_rate", "Returns exchange rate between two currencies", ["from_curr", "to_curr"], func(args) {
	return "Exchange Rate 1 USD = 134.50 DZD (Algerian Dinar)"
})

see nl + "1. Query: What is the current system date and time?" + nl
res1 = agent.query("ما هو التاريخ والوقت الحالي للنظام؟")
see "Agent Response: " + res1 + nl

see nl + "--------------------------------------------------------------------" + nl
see "2. Query: Complex Mathematical Calculation" + nl
res2 = agent.query("احسب لي ناتج العملية الحسابية بدقة: 1450 * 32 + 890")
see "Agent Response: " + res2 + nl

see nl + "--------------------------------------------------------------------" + nl
see "3. Query: Custom Application Tool (Currency Rate)" + nl
res3 = agent.query("كم سعر صرف الدولار مقابل الدينار الجزائري؟")
see "Agent Response: " + res3 + nl

see nl + "====================================================================" + nl
see "  Agent Demo Completed Successfully." + nl
see "====================================================================" + nl
