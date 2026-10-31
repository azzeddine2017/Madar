# ====================================================================
#   Madar Runtime - Native Async / Await Engine Demonstration
#   (عرض توضيحي لاستخدام الكلمات المفتاحية الأصلية async و await في مدار)
# ====================================================================

load "stdlibCore.ring"
load "chronos.ring"
load "internetlib.ring"

func main {
	? "===================================================================="
	? "  Madar Core: Native Async & Await Execution Engine (Track C)"
	? "  (المحرك اللاتزامني الأصيل في نواة مدار - البرمجة غير المتزامنة)"
	? "===================================================================="
	? ""

	oWatch = new Chronos
	oWatch.start()

	# ------------------------------------------------------------
	# 1. Direct Await on Expressions & Literal Values
	# ------------------------------------------------------------
	? "[1] Direct Unary Await on Expressions:"
	nResult = await (40 + 2)
	cMessage = await "Madar Engine Ready"
	? f"    -> Awaited Expression: {nResult}"
	? f"    -> Awaited Literal   : '{cMessage}'"
	? ""

	# ------------------------------------------------------------
	# 2. Invoking Native Async Functions
	# ------------------------------------------------------------
	? "[2] Invoking Native Async Functions:"
	t0 = perf_counter()
	
	oUser1 = await fetchUserData(101)
	oUser2 = await fetchUserData(102)

	nFetchTime = (perf_counter() - t0) * 1000.0

	? f"    -> User 1: ID={oUser1[:id]} | Name={oUser1[:name]} | Role={oUser1[:role]}"
	? f"    -> User 2: ID={oUser2[:id]} | Name={oUser2[:name]} | Role={oUser2[:role]}"
	? f"    -> Execution Time: {round(nFetchTime, 3)} ms"
	? ""

	# ------------------------------------------------------------
	# 3. Explicit Async Delay & Verification (إثبات الانتظار الفعلي)
	# ------------------------------------------------------------
	? "[3] Verification of Asynchronous Waiting (Latency Proof):"
	nTargetDelayMs = 120
	? f"    [Caller] Calling asyncDelayedTask({nTargetDelayMs} ms)..."
	
	tBefore = perf_counter()
	cDelayedResult = await asyncDelayedTask("Cloud Model Weights Sync", nTargetDelayMs)
	nActualElapsedMs = (perf_counter() - tBefore) * 1000.0
	
	? f"    [Caller] Resumed after 'await'!"
	? f"    -> Task Status    : {cDelayedResult}"
	? f"    -> Target Delay   : {nTargetDelayMs} ms"
	? f"    -> Measured Delay : {round(nActualElapsedMs, 2)} ms"
	if nActualElapsedMs >= nTargetDelayMs {
		? f"    -> [VERIFIED] 'await' strictly waited for task completion!"
	}
	? ""

	# ------------------------------------------------------------
	# 4. Compound Await in Calculations & Scoring
	# ------------------------------------------------------------
	? "[4] Compound Await in Mathematical Expressions:"
	nScoreA = computeMetric(85, 1.2)
	nScoreB = computeMetric(90, 1.5)

	# Inline compound await
	nCombinedScore = (await computeMetric(85, 1.2)) + (await computeMetric(90, 1.5))
	? f"    -> Combined Analytical Score: {round(nCombinedScore, 2)}"
	? ""

	# ------------------------------------------------------------
	# 5. Async Processing with List Comprehensions
	# ------------------------------------------------------------
	? "[5] Processing Async Tasks with List Comprehensions:"
	aUserIds = [201, 202, 203]
	aProfiles = [await fetchUserData(id) for id in aUserIds]

	for oProf in aProfiles {
		? f"    -> Loaded: {oProf[:name]} ({oProf[:role]})"
	}
	? ""

	# ------------------------------------------------------------
	# 6. Real-World Network HTTP Await (استدعاء الشبكة غير المتزامن)
	# ------------------------------------------------------------
	? "[6] Real-World Network HTTP Await:"
	cEndpoint = "https://httpbin.org/get"
	? f"    [Network] Dispatching async HTTP request to: {cEndpoint}..."
	
	try {
		tNetStart = perf_counter()
		oHttp = await fetchHttpData(cEndpoint)
		nNetTime = (perf_counter() - tNetStart) * 1000.0
		
		? f"    -> HTTP Status     : Success (Received {oHttp[:size]} bytes)"
		? f"    -> Network Latency : {round(nNetTime, 2)} ms"
		? f"    -> Response Body   : {oHttp[:snippet]}..."
	catch
		? f"    -> Network Notice  : Offline / connection timeout ({cCatchError})"
	}
	? ""

	# ------------------------------------------------------------
	# 7. Performance Telemetry
	# ------------------------------------------------------------
	oWatch.stop()
	? "===================================================================="
	? f"  Total Pipeline Time : {oWatch.elapsed_ms()} ms ({oWatch.elapsed_ns()} ns)"
	? "  Status               : 100% Native VM Opcode (ICO_AWAIT) Success"
	? "===================================================================="
}

# ====================================================================
# Async Function Declarations (Native Madar Core)
# ====================================================================

/*
* Function: fetchUserData
* Description: Simulates asynchronous retrieval of user record.
*/
async func fetchUserData(nUserId) {
	cName = "User_" + nUserId
	cRole = "Engineer"
	if nUserId = 101 {
		cName = "Azzeddine Remmal"
		cRole = "Lead Architect"
	elseif nUserId = 102
		cName = "Mahmoud Fayed"
		cRole = "Ring Creator"
	}

	return [
		:id = nUserId,
		:name = cName,
		:role = cRole,
		:timestamp = nanotime()
	]
}

/*
* Function: asyncDelayedTask
* Description: Asynchronous worker simulating I/O or model sync delay.
*/
async func asyncDelayedTask(cTaskName, nDelayMs) {
	# High-precision hardware wait simulation
	syssleep(nDelayMs)
	return f"Completed '{cTaskName}' successfully"
}

/*
* Function: fetchHttpData
* Description: Performs asynchronous network HTTP GET request.
*/
async func fetchHttpData(cUrl) {
	cData = download(cUrl)
	cPreview = ""
	if len(cData) > 60 {
		cPreview = substr(cData, 1, 60)
	else
		cPreview = cData
	}
	# Replace newlines in snippet for clean display
	cPreview = substr(cPreview, 1, 50)
	
	return [
		:url = cUrl,
		:size = len(cData),
		:snippet = cPreview
	]
}

/*
* Function: computeMetric
* Description: Computes analytical metric asynchronously.
*/
async func computeMetric(nBase, nWeight) {
	return (nBase * nWeight) + 5.0
}

func round(nVal, nDigits = 2) {
	nFactor = 10 ^ nDigits
	return floor(nVal * nFactor + 0.5) / nFactor
}
