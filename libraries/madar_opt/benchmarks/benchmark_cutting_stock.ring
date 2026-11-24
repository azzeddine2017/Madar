/*
* Project: MadarOpt - Industrial Decision Intelligence
* File: benchmarks/benchmark_cutting_stock.ring
* Description: Scientific benchmark for 1D Cutting Stock Optimization.
* Compares Naive baseline vs BFD Heuristic vs Genetic Algorithm on realistic factory orders.
*/

load "../madar_opt.ring"
load "chronos.ring"

func main() {
    decimals(2)
    ? "===================================================================="
    ? "  MadarOpt: Industrial Cutting Stock Optimization Benchmark"
    ? "  Target: Aluminum & Profile Manufacturing Plant"
    ? "  Timing Engine: Madar Hardware-Monotonic Nanotimer (nanotime)"
    ? "===================================================================="

    # Factory Parameters:
    # Standard Raw Stock Length: 6000 mm (6 meters)
    # Circular Saw Blade Kerf: 4 mm per cut
    nStockLength = 6000.0
    nBladeKerf   = 4.0

    # Benchmark Work Order: Classic High-Variance Factory Order
    # Demonstrating Bin Packing Heuristic Advantage:
    # 20 pieces of 3200 mm (cannot pair with each other in 6000 mm bar)
    # 20 pieces of 2750 mm (pairs perfectly with 3200 mm: 3200 + 2750 = 5950 mm <= 6000)
    # 20 pieces of 1400 mm
    # 20 pieces of 1300 mm
    aDemands = []
    # If cut naively in arrival sequence:
    dour i = 1 to 20 { aDemands + 2750.0 }
    dour i = 1 to 20 { aDemands + 1400.0 }
    dour i = 1 to 20 { aDemands + 1300.0 }
    dour i = 1 to 20 { aDemands + 3200.0 }

    oProblem = new CuttingStock1D(nStockLength, aDemands, nBladeKerf)

    nTotalPieces = len(aDemands)
    nTotalDemand = oProblem.totalDemandLength()
    nTheoryMin   = oProblem.theoreticalMinimumBars()

    ? f"  [Work Order] Total Demanded Pieces: {nTotalPieces}"
    ? f"  [Work Order] Total Linear Demand:   {nTotalDemand} mm ({nTotalDemand / 1000.0} meters)"
    ? f"  [Raw Stock]  Standard Bar Length:   {nStockLength} mm (Blade Kerf: {nBladeKerf} mm)"
    ? f"  [Lower Bound] Theoretical Min Bars: {nTheoryMin} bars"
    ? "--------------------------------------------------------------------"

    # --- Benchmark 0: Naive Sequential First-Fit (Traditional Manual Cutting) ---
    nStartNs = nanotime()
    oSolverHeuristic = new HeuristicCuttingSolver
    aResNaive = oSolverHeuristic.solveFFD(oProblem)
    nTimeNaive_us = (nanotime() - nStartNs) / 1000.0
    nTimeNaive_ms = nTimeNaive_us / 1000.0

    ? "[Baseline: Naive Manual Cutting (Arbitrary Order)]"
    ? f"  -> Stock Bars Used:    {aResNaive[:bars_used]} bars"
    ? f"  -> Total Scrap Waste:   {aResNaive[:total_waste_mm]} mm ({aResNaive[:total_waste_mm] / 1000.0} meters)"
    ? f"  -> Waste Ratio:         {aResNaive[:waste_percentage]}%"
    ? f"  -> Execution Latency:   {nTimeNaive_us} us ({nTimeNaive_ms} ms)"
    ? "--------------------------------------------------------------------"

    # --- Benchmark 1: Best-Fit Decreasing (BFD Heuristic) ---
    nStartNs = nanotime()
    aResBFD = oSolverHeuristic.solveBFD(oProblem)
    nTimeBFD_us = (nanotime() - nStartNs) / 1000.0
    nTimeBFD_ms = nTimeBFD_us / 1000.0

    ? "[Strategy 1: MadarOpt Best-Fit Decreasing (BFD Heuristic)]"
    ? f"  -> Stock Bars Used:    {aResBFD[:bars_used]} bars"
    ? f"  -> Total Scrap Waste:   {aResBFD[:total_waste_mm]} mm ({aResBFD[:total_waste_mm] / 1000.0} meters)"
    ? f"  -> Waste Ratio:         {aResBFD[:waste_percentage]}%"
    ? f"  -> Execution Latency:   {nTimeBFD_us} us ({nTimeBFD_ms} ms)"
    ? "--------------------------------------------------------------------"

    # --- Benchmark 2: Genetic Algorithm Metaheuristic ---
    nStartNs = nanotime()
    oSolverGA = new GeneticCuttingSolver
    oSolverGA.nPopulationSize = 30
    oSolverGA.nGenerations    = 30
    oSolverGA.bVerbose        = false
    aResGA = oSolverGA.solve(oProblem)
    nTimeGA_us = (nanotime() - nStartNs) / 1000.0
    nTimeGA_ms = nTimeGA_us / 1000.0

    ? "[Strategy 2: MadarOpt Genetic Algorithm (Evolutionary Search)]"
    ? f"  -> Stock Bars Used:    {aResGA[:bars_used]} bars"
    ? f"  -> Total Scrap Waste:   {aResGA[:total_waste_mm]} mm ({aResGA[:total_waste_mm] / 1000.0} meters)"
    ? f"  -> Waste Ratio:         {aResGA[:waste_percentage]}%"
    ? f"  -> Execution Latency:   {nTimeGA_us} us ({nTimeGA_ms} ms)"
    ? "===================================================================="
    ? "  [Industrial Economics & Direct ROI]"
    nPricePerBar = 45.0 # USD per standard raw bar
    nCostNaive = aResNaive[:bars_used] * nPricePerBar
    nCostBFD   = aResBFD[:bars_used] * nPricePerBar
    nCostGA    = aResGA[:bars_used] * nPricePerBar
    nSavings   = nCostNaive - nCostBFD
    nWasteSaved = (aResNaive[:total_waste_mm] - aResBFD[:total_waste_mm]) / 1000.0

    ? f"  Manual Shopfloor Cost:   ${nCostNaive} USD ({aResNaive[:bars_used]} bars)"
    ? f"  MadarOpt Optimized Cost:  ${nCostBFD} USD ({aResBFD[:bars_used]} bars)"
    ? f"  Direct Financial Savings: ${nSavings} USD on a single work order!"
    ? f"  Raw Material Saved:      {nWasteSaved} linear meters of metal."
    ? "===================================================================="
}
