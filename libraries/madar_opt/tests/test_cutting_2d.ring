/*
* Project: MadarOpt - Industrial Decision Intelligence
* Test Suite: 2D Rectangular Cutting Stock & Nesting with Generalized MILP
*/

load "../madar_opt.ring"

func main() {
    ? "===================================================================="
    ? "  MadarOpt Test Suite: 2D Cutting Stock & Generalized Model"
    ? "===================================================================="

    nPassed = 0
    nTotal = 4

    # ---------------------------------------------------------------
    # Test 1: Geometric Guillotine Nesting (Best-Short-Side Fit)
    # ---------------------------------------------------------------
    ? "Test 1: Geometric Guillotine Nesting on Standard Sheet..."
    nSheetW = 2440.0
    nSheetH = 1220.0
    nKerf   = 3.0
    bRotate = true

    aPieces = [
        [:id = "P1", :w = 1200.0, :h = 600.0, :qty = 4, :can_rotate = true],
        [:id = "P2", :w = 800.0,  :h = 500.0, :qty = 2, :can_rotate = true]
    ]

    oProblem = new CuttingStock2D(nSheetW, nSheetH, aPieces, nKerf, bRotate)
    oSolver = new Heuristic2DCuttingSolver
    aSol = oSolver.solve(oProblem)

    nSheets = aSol[:sheets_used]
    nTheoMin = aSol[:theoretical_min]

    if nSheets >= nTheoMin and nSheets <= 3 {
        # Verify placements count
        nTotalPlaced = 0
        bInsideBounds = true
        for s in aSol[:sheets] {
            for pl in s[:placements] {
                nTotalPlaced++
                if pl[:x] + pl[:w] > nSheetW + 0.001 or pl[:y] + pl[:h] > nSheetH + 0.001 {
                    bInsideBounds = false
                }
            }
        }

        if nTotalPlaced = 6 and bInsideBounds {
            ? f"  [PASS] Nested {nTotalPlaced} pieces across {nSheets} sheets (Theo Min: {nTheoMin}, Scrap: {aSol[:waste_percentage]}%)"
            nPassed++
        else
            ? f"  [FAIL] Placements mismatch: placed={nTotalPlaced}, bounds={bInsideBounds}"
        }
    else
        ? f"  [FAIL] Unexpected sheets used: {nSheets} (Theo Min: {nTheoMin})"
    }

    # ---------------------------------------------------------------
    # Test 2: Rotation Freedom Handling
    # ---------------------------------------------------------------
    ? "Test 2: Rotational Freedom Constraint Handling..."
    # Sheet 1000 x 500. Piece 400 x 800.
    # Without rotation: w=400 <= 1000, h=800 > 500 -> Cannot fit unless rotated!
    aPiecesRot = [
        [:id = "ROT_TEST", :w = 400.0, :h = 800.0, :qty = 1, :can_rotate = true]
    ]
    oProbRot = new CuttingStock2D(1000.0, 500.0, aPiecesRot, 0.0, true)
    aSolRot = oSolver.solve(oProbRot)

    if aSolRot[:sheets_used] = 1 {
        pl = aSolRot[:sheets][1][:placements][1]
        if pl[:rotated] and pl[:w] = 800.0 and pl[:h] = 400.0 {
            ? "  [PASS] Piece automatically rotated 90 deg (800x400) to fit sheet (1000x500)"
            nPassed++
        else
            ? f"  [FAIL] Piece not properly rotated: w={pl[:w]}, h={pl[:h]}, rot={pl[:rotated]}"
        }
    else
        ? f"  [FAIL] Failed to place piece with rotation: sheets={aSolRot[:sheets_used]}"
    }

    # ---------------------------------------------------------------
    # Test 3: Generalized Modeler MILP Formulation (CuttingStock2D -> OptModel)
    # ---------------------------------------------------------------
    ? "Test 3: Generalized Algebraic MILP Formulation & Branch-and-Bound..."
    # Given candidate cutting patterns for 2 piece types (A, B)
    # Demand: A = 10, B = 8
    # Pattern 1: produces 3 of A, 1 of B
    # Pattern 2: produces 1 of A, 3 of B
    # Pattern 3: produces 2 of A, 2 of B
    aCandidatePatterns = [
        [:id = "PAT_1", :cuts = [:A = 3.0, :B = 1.0]],
        [:id = "PAT_2", :cuts = [:A = 1.0, :B = 3.0]],
        [:id = "PAT_3", :cuts = [:A = 2.0, :B = 2.0]]
    ]
    aDemandsMILP = [
        [:id = "A", :w = 500.0, :h = 400.0, :qty = 10, :can_rotate = true],
        [:id = "B", :w = 600.0, :h = 300.0, :qty = 8,  :can_rotate = true]
    ]
    oProbMILP = new CuttingStock2D(2000.0, 1000.0, aDemandsMILP, 2.0, true)
    oMILPModel = oProbMILP.toPatternMILP(aCandidatePatterns)

    oBBSolver = new OptBranchBoundSolver
    aBBSol = oBBSolver.solve(oMILPModel)

    if aBBSol[:status] = OPT_OPTIMAL {
        nMinSheets = aBBSol[:objective_value]
        # Theoretical integer optimum: Pat1 * 3 (9A, 3B) + Pat2 * 2 (2A, 6B) = 11A, 9B -> 5 sheets
        # Or Pat1 * 2 (6A, 2B) + Pat2 * 1 (1A, 3B) + Pat3 * 2 (4A, 4B) -> 5 sheets
        if nMinSheets = 5.0 {
            ? f"  [PASS] Generalized MILP solved exactly: Min Sheets = {nMinSheets} (Status: OPTIMAL, Nodes: {aBBSol[:nodes_explored]})"
            nPassed++
        else
            ? f"  [FAIL] Unexpected MILP objective: {nMinSheets} (expected 5.0)"
        }
    else
        ? f"  [FAIL] MILP solver failed with status: {aBBSol[:status]}"
    }

    # ---------------------------------------------------------------
    # Test 4: 2D Layout Export to CSV & JSON
    # ---------------------------------------------------------------
    ? "Test 4: Layout Artifact Export (CSV & JSON)..."
    cTestCSV = "../data/outputs/test_layout_2d.csv"
    cTestJSON = "../data/outputs/test_layout_2d.json"

    oExporter = new OptPlanExporter
    oExporter.exportLayout2DCSV(aSol, cTestCSV)
    oExporter.exportLayout2DJSON(aSol, cTestJSON)

    if fexists(cTestCSV) and fexists(cTestJSON) {
        cCSVContent = read(cTestCSV)
        cJSONContent = read(cTestJSON)
        if len(cCSVContent) > 50 and len(cJSONContent) > 50 {
            ? "  [PASS] 2D Shopfloor CSV & CNC/MES JSON successfully generated"
            nPassed++
        else
            ? "  [FAIL] Generated files are unexpectedly short or empty"
        }
    else
        ? "  [FAIL] Export files not found on disk"
    }

    # ---------------------------------------------------------------
    # Summary
    # ---------------------------------------------------------------
    ? "===================================================================="
    ? f"  RESULTS: {nPassed}/{nTotal} Tests Passed Successfully."
    ? "===================================================================="

    if nPassed < nTotal {
        bye 1
    }
}
