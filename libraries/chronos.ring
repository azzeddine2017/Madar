# =========================================================
# Madar Chronos: High-Resolution Performance Profiler
# Modern Stopwatch & Nanosecond Benchmark Utilities for Ring/Madar
# =========================================================

/*
* Class: Chronos
* High-resolution nanosecond stopwatch using hardware performance counters
*/
class Chronos {
	nStartNs = 0
	nEndNs = 0
	bIsRunning = false

	func init() {
		reset()
	}

	func start() {
		nStartNs = nanotime()
		nEndNs = 0
		bIsRunning = true
		return self
	}

	func stop() {
		nEndNs = nanotime()
		bIsRunning = false
		return elapsed_ns()
	}

	func reset() {
		nStartNs = nanotime()
		nEndNs = 0
		bIsRunning = true
		return self
	}

	func elapsed_ns() {
		if bIsRunning {
			return nanotime() - nStartNs
		}
		return nEndNs - nStartNs
	}

	func elapsed_us() {
		return elapsed_ns() / 1000.0
	}

	func elapsed_ms() {
		return elapsed_ns() / 1000000.0
	}

	func elapsed_sec() {
		return elapsed_ns() / 1000000000.0
	}

	func elapsed() {
		return formatTime(elapsed_ns())
	}

	private

	func formatTime(nNs) {
		if nNs < 1000 {
			return "" + nNs + " ns"
		elseif nNs < 1000000
			return "" + (nNs / 1000.0) + " us"
		elseif nNs < 1000000000
			return "" + (nNs / 1000000.0) + " ms"
		else
			return "" + (nNs / 1000000000.0) + " s"
		}
	}
}

/*
* Function: benchmark
* High-resolution execution benchmark for functions and code blocks
*/
func benchmark(cLabel, nRuns, fBlock) {
	? f"=== Benchmark: [{cLabel}] ({nRuns} runs) ==="
	oTimer = new Chronos()
	oTimer.start()
	for i = 1 to nRuns {
		call fBlock()
	}
	nTotal = oTimer.stop()
	nAvg = nTotal / nRuns
	? f"  Total Time: {oTimer.elapsed()}"
	? f"  Avg / run : {nAvg} ns"
	return nAvg
}

