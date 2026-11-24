/*
* Project: MadarOpt
* File: libraries/madar_opt/tests/test_modeler.ring
* Description: Automated verification for the Generalized Algebraic Modeler,
* Simplex LP Solver (Phase 1 & Phase 2), and Branch-and-Bound MILP Solver.
*/

load "../madar_opt.ring"

func main() {
    ? "=========================================================="
    ? "  MadarOpt: Generalized Mathematical Modeler Test Suite"
    ? "=========================================================="

    # -------------------------------------------------------------
    # Test 1: Classical Linear Program (George Dantzig Product Mix)
    # Maximize Z = 3*x1 + 5*x2
    # s.t.  x1 <= 4
    #       2*x2 <= 12  (x2 <= 6)
    #       3*x1 + 2*x2 <= 18
    # -------------------------------------------------------------
    ? "[Test 1: Classical 2-Variable Product Mix LP (Maximization)]"
    oModel1 = new OptModel("ProductMix")
    x1 = oModel1.addVariable("x1", OPT_CONTINUOUS, 0, 100)
    x2 = oModel1.addVariable("x2", OPT_CONTINUOUS, 0, 100)

    oModel1.setObjective([3.0, 5.0], OPT_MAXIMIZE)
    oModel1.addConstraint([1.0, 0.0], "<=", 4.0, "c_x1_cap")
    oModel1.addConstraint([0.0, 2.0], "<=", 12.0, "c_x2_cap")
    oModel1.addConstraint([3.0, 2.0], "<=", 18.0, "c_assembly_time")

    aRes1 = oModel1.solve()

    if aRes1[:status] != OPT_OPTIMAL {
        ? "FAIL: Model 1 was not optimal. Status: " + aRes1[:status]
        bye 1
    }

    nObj1 = aRes1[:objective_value]
    nX1   = aRes1[:variables][1]
    nX2   = aRes1[:variables][2]

    # Verify analytical solution: x1 = 2, x2 = 6, Z = 36
    if fabs(nObj1 - 36.0) > 0.0001 or fabs(nX1 - 2.0) > 0.0001 or fabs(nX2 - 6.0) > 0.0001 {
        ? f"FAIL: Solution mismatch! Expected Z=36, x1=2, x2=6. Got: Z={nObj1}, x1={nX1}, x2={nX2}"
        bye 1
    }
    ? f"  [PASS] Dantzig LP: Optimal Z = {nObj1} (x1 = {nX1}, x2 = {nX2}) in {aRes1[:latency_us]} us"

    # -------------------------------------------------------------
    # Test 2: Minimization LP with '>=' Constraints (Two-Phase Simplex)
    # Minimize Z = 2*x1 + 3*x2
    # s.t.  x1 + x2 >= 4
    #       x1 + 2*x2 >= 5
    # -------------------------------------------------------------
    ? "[Test 2: Two-Phase Simplex with Artificial Variables (Minimization)]"
    oModel2 = new OptModel("NutritionCost")
    oModel2.addVariables("Nutrient", 2, OPT_CONTINUOUS, 0, 100)
    oModel2.setObjective([2.0, 3.0], OPT_MINIMIZE)
    oModel2.addConstraint([1.0, 1.0], ">=", 4.0, "c_req1")
    oModel2.addConstraint([1.0, 2.0], ">=", 5.0, "c_req2")

    aRes2 = oModel2.solve()
    if aRes2[:status] != OPT_OPTIMAL {
        ? "FAIL: Model 2 was not optimal. Status: " + aRes2[:status]
        bye 1
    }

    nObj2 = aRes2[:objective_value]
    nVar1 = aRes2[:variables][1]
    nVar2 = aRes2[:variables][2]

    # Expected: x1 = 3, x2 = 1, Z = 2(3) + 3(1) = 9.0
    if fabs(nObj2 - 9.0) > 0.0001 or fabs(nVar1 - 3.0) > 0.0001 or fabs(nVar2 - 1.0) > 0.0001 {
        ? f"FAIL: Solution mismatch! Expected Z=9, x1=3, x2=1. Got: Z={nObj2}, x1={nVar1}, x2={nVar2}"
        bye 1
    }
    ? f"  [PASS] Two-Phase LP: Optimal Min Z = {nObj2} (x1 = {nVar1}, x2 = {nVar2}) in {aRes2[:latency_us]} us"

    # -------------------------------------------------------------
    # Test 3: Mixed-Integer Programming (Branch-and-Bound Knapsack)
    # Maximize Z = 5*x1 + 6*x2
    # s.t.  2*x1 + 3*x2 <= 7
    # where x1, x2 in Z+ (Integers)
    # -------------------------------------------------------------
    ? "[Test 3: Mixed-Integer LP - Branch-and-Bound (Knapsack)]"
    oModel3 = new OptModel("IntegerKnapsack")
    oModel3.addVariable("x1", OPT_INTEGER, 0, 10)
    oModel3.addVariable("x2", OPT_INTEGER, 0, 10)
    oModel3.setObjective([5.0, 6.0], OPT_MAXIMIZE)
    oModel3.addConstraint([2.0, 3.0], "<=", 7.0, "c_capacity")

    aRes3 = oModel3.solve()
    if aRes3[:status] != OPT_OPTIMAL {
        ? "FAIL: Model 3 was not optimal. Status: " + aRes3[:status]
        bye 1
    }

    nObj3 = aRes3[:objective_value]
    nI1   = aRes3[:variables][1]
    nI2   = aRes3[:variables][2]

    # Expected Integer Optimum: x1 = 2, x2 = 1, Z = 5(2) + 6(1) = 16.0 (weight = 2*2 + 3*1 = 7)
    if fabs(nObj3 - 16.0) > 0.0001 or fabs(nI1 - 2.0) > 0.0001 or fabs(nI2 - 1.0) > 0.0001 {
        ? f"FAIL: Integer Solution mismatch! Expected Z=16, x1=2, x2=1. Got: Z={nObj3}, x1={nI1}, x2={nI2}"
        bye 1
    }
    ? f"  [PASS] Branch-and-Bound: Integer Z = {nObj3} (x1 = {nI1}, x2 = {nI2}) in {aRes3[:latency_us]} us ({aRes3[:nodes_explored]} nodes)"

    # -------------------------------------------------------------
    # Test 4: Binary Decision Program (0/1 Project Selection)
    # Maximize Z = 10*x1 + 15*x2 + 25*x3
    # s.t.  100*x1 + 200*x2 + 300*x3 <= 400 (Budget)
    #       x1 + x2 + x3 <= 2 (Max 2 projects)
    # where x1, x2, x3 in {0, 1} (Binary)
    # -------------------------------------------------------------
    ? "[Test 4: Binary 0/1 Combinatorial Decision Selection]"
    oModel4 = new OptModel("ProjectSelection")
    oModel4.addVariables("Proj", 3, OPT_BINARY, 0, 1)
    oModel4.setObjective([10.0, 15.0, 25.0], OPT_MAXIMIZE)
    oModel4.addConstraint([100.0, 200.0, 300.0], "<=", 400.0, "c_budget")
    oModel4.addConstraint([1.0, 1.0, 1.0], "<=", 2.0, "c_max_projects")

    aRes4 = oModel4.solve()
    if aRes4[:status] != OPT_OPTIMAL {
        ? "FAIL: Model 4 was not optimal. Status: " + aRes4[:status]
        bye 1
    }

    nObj4 = aRes4[:objective_value]
    nP1   = aRes4[:variables][1]
    nP2   = aRes4[:variables][2]
    nP3   = aRes4[:variables][3]

    # Expected: Pick Project 1 and 3 (Cost 400, Value 35) -> x1=1, x2=0, x3=1, Z=35
    if fabs(nObj4 - 35.0) > 0.0001 or fabs(nP1 - 1.0) > 0.0001 or fabs(nP2 - 0.0) > 0.0001 or fabs(nP3 - 1.0) > 0.0001 {
        ? f"FAIL: Binary mismatch! Expected Z=35 (1, 0, 1). Got: Z={nObj4} ({nP1}, {nP2}, {nP3})"
        bye 1
    }
    ? f"  [PASS] Binary 0/1 Decision: Optimal Z = {nObj4} (P1={nP1}, P2={nP2}, P3={nP3}) in {aRes4[:latency_us]} us"

    ? "=========================================================="
    ? "  ALL MATHEMATICAL MODELER TESTS PASSED PERFECTLY! (4/4)  "
    ? "=========================================================="
}
