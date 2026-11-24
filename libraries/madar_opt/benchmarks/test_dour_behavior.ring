/*
* Project: MadarOpt - Industrial Decision Intelligence
* File: benchmarks/test_dour_behavior.ring
* Description: Laboratory verification of Madar 'dour' Auto-JIT engine vs standard 'for',
* measured using Madar's hardware-monotonic nanosecond timers (nanotime / microtime).
*/

load "chronos.ring"

func main() {
    ? "===================================================================="
    ? "  MadarOpt: Laboratory Benchmark - 'dour' Auto-JIT & Nanotimers"
    ? "===================================================================="

    bJIT = jit_available()
    ? f"  [Madar Runtime] Auto-JIT Available on Host: {bJIT}"
    ? f"  [Madar Runtime] Initial JIT Auto-loops Count: {jit_autoloops()}"
    ? "--------------------------------------------------------------------"

    nIterations = 1000000 # 1 Million iterations

    # ------------------------------------------------------------------
    # Test 1: Pure Numeric Sum of Squares (s += x * x)
    # ------------------------------------------------------------------
    ? f"[Test 1: Pure Scalar Arithmetic (N = {nIterations})]"

    # 1A: Standard Ring 'for' loop (Interpreted)
    nStart = nanotime()
    nSumFor = 0
    for x = 1 to nIterations {
        nSumFor += (x * x)
    }
    nElapsedFor_ns = nanotime() - nStart
    nElapsedFor_ms = nElapsedFor_ns / 1000000.0

    ? f"  -> Standard 'for'  (Interpreted): {nElapsedFor_ms} ms ({nElapsedFor_ns} ns)"

    # 1B: Madar 'dour' loop (Auto-JIT)
    nStart = nanotime()
    nSumDour = 0
    dour x = 1 to nIterations {
        nSumDour += (x * x)
    }
    nElapsedDour_ns = nanotime() - nStart
    nElapsedDour_ms = nElapsedDour_ns / 1000000.0

    nJitCount = jit_autoloops()
    ? f"  -> Madar 'dour'   (Auto-JIT):    {nElapsedDour_ms} ms ({nElapsedDour_ns} ns)"
    ? f"  -> JIT Auto-loops Executed:      {nJitCount}"

    nSpeedup1 = 0.0
    if nElapsedDour_ns > 0 {
        nSpeedup1 = (0.0 + nElapsedFor_ns) / nElapsedDour_ns
    }
    ? f"  -> Pure Numeric Speedup:         {nSpeedup1}x FASTER via Auto-JIT!"
    ? "--------------------------------------------------------------------"

    # ------------------------------------------------------------------
    # Test 2: Accumulating Array Elements (aList[x])
    # ------------------------------------------------------------------
    nListSize = 100000 # 100k elements
    ? f"[Test 2: Numeric List Summation (N = {nListSize} items)]"

    aData = list(nListSize)
    for i = 1 to nListSize {
        aData[i] = 1.5 + (i % 10)
    }

    # 2A: Standard 'for' over list
    nStart = nanotime()
    nSumListFor = 0.0
    for i = 1 to nListSize {
        nSumListFor += aData[i]
    }
    nElapsedListFor_ns = nanotime() - nStart
    nElapsedListFor_ms = nElapsedListFor_ns / 1000000.0
    ? f"  -> Standard 'for'  (List Access): {nElapsedListFor_ms} ms ({nElapsedListFor_ns} ns)"

    # 2B: Madar 'dour' over list
    nStart = nanotime()
    nSumListDour = 0.0
    dour i = 1 to nListSize {
        nSumListDour += aData[i]
    }
    nElapsedListDour_ns = nanotime() - nStart
    nElapsedListDour_ms = nElapsedListDour_ns / 1000000.0
    ? f"  -> Madar 'dour'   (List Access): {nElapsedListDour_ms} ms ({nElapsedListDour_ns} ns)"

    # ------------------------------------------------------------------
    # Test 3: Chronos High-Precision Object Stopwatch
    # ------------------------------------------------------------------
    ? "--------------------------------------------------------------------"
    ? "[Test 3: Madar Chronos OOP Microsecond Benchmarking]"
    oTimer = new Chronos()
    nSumTest = 0
    dour x = 1 to 500000 {
        nSumTest += x
    }
    oTimer.stop()
    ? f"  -> Chronos Elapsed: {oTimer.elapsed()} ({oTimer.elapsed_us()} microseconds)"
    ? "===================================================================="
}

