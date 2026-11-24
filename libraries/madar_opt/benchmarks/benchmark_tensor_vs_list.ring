/*
* Project: MadarOpt - Industrial Decision Intelligence
* File: benchmarks/benchmark_tensor_vs_list.ring
* Description: Scientific Benchmark comparing Interpreted List loops vs Native RingTensor GEMM
* for evaluating candidate solutions in combinatorial optimization.
*/

load "../madar_opt.ring"
load "chronos.ring"

func main() {
    decimals(2)
    ? "===================================================================="
    ? "  MadarOpt: RingTensor AVX2/SIMD Acceleration Benchmark"
    ? "  Evaluating Candidate Solutions in Operations Research"
    ? "===================================================================="

    nBars  = 40    # 40 Stock Bars
    nItems = 80    # 80 Work-order Pieces
    nEvals = 1000  # 1,000 Candidate Evaluations (typical Genetic Algorithm run)

    ? f"  [Problem Scale] Bars: {nBars} | Demands: {nItems} items"
    ? f"  [Evaluation Workload] {nEvals} candidate solution evaluations"
    ? f"  [Total Dot Operations] {nBars * nItems * nEvals} arithmetic multiply-adds"
    ? "--------------------------------------------------------------------"

    # Setup dummy demand vector:
    aDemands = []
    for i = 1 to nItems {
        aDemands + (1000.0 + (i * 25.0))
    }

    # Setup dummy assignment matrix [nBars, nItems] (List of Lists):
    aMatrixList = []
    for b = 1 to nBars {
        aRow = []
        for i = 1 to nItems {
            # Sparsely assign 2 items per bar
            if (i % nBars) = (b - 1) {
                aRow + 1.0
            else
                aRow + 0.0
            }
        }
        aMatrixList + aRow
    }

    # Setup RingTensor equivalents:
    oKernel = new OptTensorKernel
    tDemands = oKernel.createDemandTensor(aDemands)
    tAssignment = oKernel.createZeroMatrix(nBars, nItems)

    for b = 1 to nBars {
        for i = 1 to nItems {
            if aMatrixList[b][i] = 1.0 {
                tensor_set(tAssignment, b, i, 1.0)
            }
        }
    }

    # ------------------------------------------------------------------
    # Method 1: Standard Ring List Nested Loops (Interpreted)
    # ------------------------------------------------------------------
    ? "[Method 1: Standard Interpreted List Loops]"
    nStartNs = nanotime()
    nTotalFillSumList = 0.0

    for eval = 1 to nEvals {
        for b = 1 to nBars {
            nBarFill = 0.0
            aRow = aMatrixList[b]
            for i = 1 to nItems {
                nBarFill += (aRow[i] * aDemands[i])
            }
            nTotalFillSumList += nBarFill
        }
    }
    nTimeList_ns = nanotime() - nStartNs
    nTimeList_ms = nTimeList_ns / 1000000.0

    ? f"  -> Execution Time: {nTimeList_ms} ms ({nTimeList_ns} ns)"
    ? f"  -> Checksum:       {nTotalFillSumList}"
    ? "--------------------------------------------------------------------"

    # ------------------------------------------------------------------
    # Method 2: Native RingTensor In-Core GEMM (AVX2 / Continuous C Memory)
    # ------------------------------------------------------------------
    ? "[Method 2: Madar Native RingTensor (In-Core GEMM)]"
    nStartNs = nanotime()
    nTotalFillSumTensor = 0.0

    for eval = 1 to nEvals {
        tFill = oKernel.evaluateStockFillLevels(tAssignment, tDemands)
        nTotalFillSumTensor += tensor_sum(tFill)
    }
    nTimeTensor_ns = nanotime() - nStartNs
    nTimeTensor_ms = nTimeTensor_ns / 1000000.0

    ? f"  -> Execution Time: {nTimeTensor_ms} ms ({nTimeTensor_ns} ns)"
    ? f"  -> Checksum:       {nTotalFillSumTensor}"
    ? "--------------------------------------------------------------------"

    # ------------------------------------------------------------------
    # Performance Analysis & Speedup
    # ------------------------------------------------------------------
    nSpeedup = 0.0
    if nTimeTensor_ns > 0 {
        nSpeedup = (0.0 + nTimeList_ns) / nTimeTensor_ns
    }
    ? "===================================================================="
    ? "  [Performance Verdict]"
    ? f"  Standard Ring Lists: {nTimeList_ms} ms"
    ? f"  Madar RingTensor:     {nTimeTensor_ms} ms"
    ? f"  Hardware Acceleration Factor: {nSpeedup}x FASTER via RingTensor!"
    ? "===================================================================="
}

