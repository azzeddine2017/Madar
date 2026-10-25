# ====================================================================
# Madar AI Agent: Long-Term Vector Memory & Persistent RAG Demo
# (الوكيل الذكي مع ذاكرة التضمين المتجهي طويلة الأمد واسترجاع المعرفة RAG)
# ====================================================================

load "stdlibCore.ring"
load "agent.ring"

see "====================================================================" + nl
see "  Madar AI: Agent Long-Term Vector Memory & RAG Demonstration" + nl
see "  (الوكيل الذكي: الذاكرة المتجهية الدائمة واسترجاع المعرفة في مدار)" + nl
see "====================================================================" + nl

# 1. Locate GGUF Model
cModelPath = "../../models/qwen2.5-0.5b-instruct-q4_0.gguf"
/* if not fexists(cModelPath)
	cModelPath = "../../models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf"
ok */
if not fexists(cModelPath)
	cModelPath = "../../models/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
ok

if not fexists(cModelPath)
	see "Error: Model file not found in models/" + nl
	bye
ok

# 1. Load Model
model = ai_open(cModelPath)
model.setTemperature(0.2)

# 2. Initialize Agent
agent = new AIAgent(model)
agent.bStream = 1

# 3. Setup Dedicated Test Memory File
cTestMemory = "agent_test_memory.bin"
agent.initMemory(cTestMemory)

see nl + "1. Inscribing Long-Term Facts into Episodic Vector Memory:" + nl
agent.remember("المستخدم يفضل البرمجة بلغة مدار والتركيز على الأداء العالي وAVX2")
agent.remember("مشروع مدار يدعم أنظمة التشغيل ويندوز ولينكس وماك")
agent.remember("المطور الرئيسي لمدار يحب القهوة العربية بدون سكر")
see "  Memory chunks stored: " + agent.oMemory.count() + nl

see nl + "--------------------------------------------------------------------" + nl
see "2. Testing Semantic Recall (Cosine Similarity):" + nl
see "  Query: 'ما هي تفضيلات المستخدم البرمجية؟'" + nl
aMatches = agent.recall("ما هي تفضيلات المستخدم البرمجية؟", 2)
for m in aMatches
	see "  -> [Similarity: " + round(m[1], 3) + "] " + m[2].cText + nl
next

see nl + "--------------------------------------------------------------------" + nl
see "3. Autonomous Agent Query with Automatic Memory Injection:" + nl
see "  User Prompt: 'ما هي لغة البرمجة التي أفضلها وما هي تفضيلاتي في الأداء؟'" + nl
see "  Agent Response > "
agent.query("ما هي لغة البرمجة التي أفضلها وما هي تفضيلاتي في الأداء؟")
see nl

see nl + "--------------------------------------------------------------------" + nl
see "4. Autonomous Tool Calling for Saving New Memory:" + nl
see "  User Prompt: 'تذكر أن رقم هاتفي للطوارئ هو 0555123456'" + nl
see "  Agent Response > "
agent.query("تذكر أن رقم هاتفي للطوارئ هو 0555123456")
see nl

see nl + "  Updated Memory chunks stored: " + agent.oMemory.count() + nl

# Clean up model
model.close()
see nl + "====================================================================" + nl
see "  Demo Completed Successfully!" + nl
see "====================================================================" + nl
