/*
* Project: MadarOpt
* File: libraries/madar_opt/tests/test_opt.ring
* Description: Automated regression tests for MadarOpt library components.
*/

load "../madar_opt.ring"

func main() {
    ? "Running MadarOpt automated tests..."

    # Test 1: Version check
    cVer = madaropt_version()
    if cVer != "0.1.0-alpha" {
        ? "FAIL: Version mismatch"
        bye 1
    }
    ? "  [PASS] Version check: " + cVer

    # Test 2: Numerical kernel vector sum
    oKernel = new OptNumericalKernel
    nSum = oKernel.sumVector([10.0, 20.0, 30.0, 40.0])
    if nSum != 100.0 {
        ? "FAIL: sumVector mismatch"
        bye 1
    }
    ? "  [PASS] Numerical Kernel: sumVector = 100"

    # Test 3: Problem formulation
    oProblem = new CuttingStock1D(6000.0, [3000.0, 3000.0, 2000.0, 4000.0], 0.0)
    if oProblem.theoreticalMinimumBars() != 2 {
        ? "FAIL: theoreticalMinimumBars mismatch"
        bye 1
    }
    ? "  [PASS] Problem Formulation: theoreticalMinimumBars = 2"

    # Test 4: BFD Heuristic Solver
    oSolver = new HeuristicCuttingSolver
    aRes = oSolver.solveBFD(oProblem)
    if aRes[:bars_used] != 2 {
        ? "FAIL: BFD should pack perfectly into 2 bars"
        bye 1
    }
    if aRes[:waste_percentage] != 0.0 {
        ? "FAIL: Waste percentage should be 0.0%"
        bye 1
    }
    ? "  [PASS] Heuristic BFD: 2 bars used with 0% waste"

    # Test 5: Facade function
    aFacadeRes = madaropt_solve_cutting_stock(6000.0, [3000.0, 3000.0, 2000.0, 4000.0], 0.0, "BFD")
    if aFacadeRes[:bars_used] != 2 {
        ? "FAIL: Facade solver failed"
        bye 1
    }
    ? "  [PASS] Facade API: madaropt_solve_cutting_stock executed successfully"

    # Test 6: RingTensor Hardware Acceleration Kernel
    oTensorKernel = new OptTensorKernel
    tD = oTensorKernel.createDemandTensor([1000.0, 2000.0])
    tA = oTensorKernel.createZeroMatrix(1, 2)
    tensor_set(tA, 1, 1, 1.0)
    tensor_set(tA, 1, 2, 1.0)
    tFill = oTensorKernel.evaluateStockFillLevels(tA, tD)
    if tensor_get(tFill, 1, 1) != 3000.0 {
        ? "FAIL: RingTensor GEMM evaluation failed"
        bye 1
    }
    ? "  [PASS] RingTensor Kernel: In-Core GEMM evaluated 3000.0 mm fill correctly"

    # Test 7: Multi-Scenario What-If Engine
    oScenarioEngine = new OptScenarioEngine
    aSimMatrix = oScenarioEngine.simulate([3000.0, 3000.0, 2000.0, 4000.0], "../data/inputs/scenarios.json", "BFD")
    if aSimMatrix[:scenarios_count] < 3 {
        ? "FAIL: Scenario simulation failed to evaluate scenarios"
        bye 1
    }
    ? "  [PASS] What-If Engine: Successfully simulated " + aSimMatrix[:scenarios_count] + " scenarios"

    ? "================================================="
    ? "  ALL MADAROPT TESTS PASSED SUCCESSFULLY! (7/7)   "
    ? "================================================="
}

