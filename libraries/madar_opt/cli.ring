/*
* Project: MadarOpt - Industrial Decision Intelligence
* File: cli.ring
* Description: Enterprise Headless CLI Runner with What-If Scenario Simulation.
* Usage:
*   Standard Single Run: ring cli.ring [--orders <csv>] [--stock <mm>] [--kerf <mm>]
*   What-If Simulation:  ring cli.ring --simulate [--scenarios <json>] [--orders <csv>]
*/

load "madar_opt.ring"
load "chronos.ring"

func main() {
    decimals(2)
    aArgs = sysargv

    # Default parameters (Strict Data Directory Isolation)
    cOrdersPath    = "data/inputs/sample_orders.csv"
    cScenariosPath = "data/inputs/scenarios.json"
    nStock         = 6000.0
    nKerf          = 4.0
    cMethod        = "BFD"
    cOutCSV        = "data/outputs/cutting_plan.csv"
    cOutJSON       = "data/outputs/cutting_plan.json"
    bSimulateMode  = false
    b2DMode        = false
    nSheetW        = 2440.0
    nSheetH        = 1220.0
    bRotate        = true

    # CLI argument parser
    nArgCount = len(aArgs)
    for nI = 1 to nArgCount {
        cArg = aArgs[nI]
        if cArg = "--orders" and nI < nArgCount {
            cOrdersPath = aArgs[nI + 1]
        elseif cArg = "--scenarios" and nI < nArgCount
            cScenariosPath = aArgs[nI + 1]
        elseif cArg = "--simulate" or cArg = "-s"
            bSimulateMode = true
        elseif cArg = "--2d"
            b2DMode = true
        elseif cArg = "--sheet_w" and nI < nArgCount
            nSheetW = 0.0 + aArgs[nI + 1]
        elseif cArg = "--sheet_h" and nI < nArgCount
            nSheetH = 0.0 + aArgs[nI + 1]
        elseif cArg = "--no_rotate"
            bRotate = false
        elseif cArg = "--stock" and nI < nArgCount
            nStock = 0.0 + aArgs[nI + 1]
        elseif cArg = "--kerf" and nI < nArgCount
            nKerf = 0.0 + aArgs[nI + 1]
        elseif cArg = "--method" and nI < nArgCount
            cMethod = upper(aArgs[nI + 1])
        elseif cArg = "--out_csv" and nI < nArgCount
            cOutCSV = aArgs[nI + 1]
        elseif cArg = "--out_json" and nI < nArgCount
            cOutJSON = aArgs[nI + 1]
        elseif cArg = "-h" or cArg = "--help"
            printHelp()
            return
        }
    }

    # Mode Dispatcher
    if bSimulateMode {
        runWhatIfSimulation(cOrdersPath, cScenariosPath, cMethod)
    elseif b2DMode
        if cOrdersPath = "data/inputs/sample_orders.csv" {
            cOrdersPath = "data/inputs/sample_orders_2d.csv"
        }
        if cOutCSV = "data/outputs/cutting_plan.csv" {
            cOutCSV = "data/outputs/layout_2d.csv"
        }
        if cOutJSON = "data/outputs/cutting_plan.json" {
            cOutJSON = "data/outputs/layout_2d.json"
        }
        run2DOptimization(cOrdersPath, nSheetW, nSheetH, nKerf, bRotate, cOutCSV, cOutJSON)
    else
        runSingleOptimization(cOrdersPath, nStock, nKerf, cMethod, cOutCSV, cOutJSON)
    }
}

func run2DOptimization(cOrdersPath, nSheetW, nSheetH, nKerf, bRotate, cOutCSV, cOutJSON) {
    ? "===================================================================="
    ? "  MadarOpt: 2D Rectangular Nesting & Guillotine Cutting Engine"
    ? "  High-Performance BSSF Guillotine Solver (v0.1.0-alpha)"
    ? "===================================================================="

    oLoader = new OptDataLoader
    aPieces = oLoader.loadOrders2DCSV(cOrdersPath)
    nPieceTypes = len(aPieces)

    if nPieceTypes = 0 {
        ? f"[MadarOpt Error] No valid 2D pieces loaded from: {cOrdersPath}"
        bye 1
    }

    oProblem = new CuttingStock2D(nSheetW, nSheetH, aPieces, nKerf, bRotate)
    nTheoryMin = oProblem.theoreticalMinimumSheets()
    nTotalDemandArea = oProblem.totalDemandArea()

    # Count total individual pieces
    nTotalUnits = 0
    for p in aPieces {
        nTotalUnits += p[:qty]
    }

    ? f"  [Input Work Order] Ingested {nPieceTypes} piece types ({nTotalUnits} total units) from '{cOrdersPath}'"
    ? f"  [Total Surface]    {nTotalDemandArea} mm^2 demand area ({nTotalDemandArea / 1000000.0} m^2)"
    ? f"  [Stock Profile]    Standard sheet: {nSheetW} x {nSheetH} mm (Kerf: {nKerf} mm)"
    ? f"  [Lower Bound]      Theoretical optimal minimum: {nTheoryMin} sheets"
    ? f"  [Rotation Freedom] Allowed: {bRotate}"
    ? "--------------------------------------------------------------------"

    nStartNs = nanotime()
    oSolver = new Heuristic2DCuttingSolver
    aSolution = oSolver.solve(oProblem)
    nElapsedUs = (nanotime() - nStartNs) / 1000.0
    nElapsedMs = nElapsedUs / 1000.0

    oExporter = new OptPlanExporter
    oExporter.exportLayout2DCSV(aSolution, cOutCSV)
    oExporter.exportLayout2DJSON(aSolution, cOutJSON)

    ? "[Optimization Results]"
    ? f"  -> Raw Stock Sheets Required: {aSolution[:sheets_used]} sheets"
    ? f"  -> Total Scrap Waste:         {aSolution[:total_scrap_area]} mm^2 ({aSolution[:total_scrap_area] / 1000000.0} m^2)"
    ? f"  -> Overall Waste Ratio:       {aSolution[:waste_percentage]}%"
    ? f"  -> Solver Latency:            {nElapsedUs} us ({nElapsedMs} ms)"
    ? "--------------------------------------------------------------------"
    ? "[Production Artifacts Generated]"
    ? f"  [OK] Shopfloor 2D Layout Table (CSV): {cOutCSV}"
    ? f"  [OK] CNC/MES Nesting Schema    (JSON): {cOutJSON}"
    ? "===================================================================="
}

func runWhatIfSimulation(cOrdersPath, cScenariosPath, cMethod) {
    ? "===================================================================="
    ? "  MadarOpt: Enterprise What-If Scenario Simulation Engine"
    ? "  Multi-Scenario Decision Intelligence & Cost Variance Analysis"
    ? "===================================================================="

    oLoader = new OptDataLoader
    aDemands = oLoader.loadOrdersCSV(cOrdersPath)
    nPieceCount = len(aDemands)

    if nPieceCount = 0 {
        ? f"[MadarOpt Error] No valid pieces loaded from: {cOrdersPath}"
        bye 1
    }

    oEngine = new OptScenarioEngine
    nStartAll = nanotime()
    aMatrix = oEngine.simulate(aDemands, cScenariosPath, cMethod)
    nTotalSimTimeMs = ((nanotime() - nStartAll) / 1000.0) / 1000.0

    if len(aMatrix) = 0 {
        bye 1
    }

    # Export Comparison Artifacts
    oReporter = new OptDecisionReporter
    cCompCSV = "data/outputs/scenario_comparison.csv"
    cBriefJSON = "data/outputs/executive_decision_brief.json"
    oReporter.exportComparisonCSV(aMatrix, cCompCSV)
    oReporter.exportExecutiveBriefJSON(aMatrix, cBriefJSON)

    # Export Winner Detailed Plan
    cWinnerID = aMatrix[:recommended_winner]
    aEvals = aMatrix[:evaluations]
    for e in aEvals {
        if e[:id] = cWinnerID {
            oExporter = new OptPlanExporter
            oExporter.exportCSV(e[:solution], "data/outputs/cutting_plan.csv", e[:stock_length_mm], e[:blade_kerf_mm])
            oExporter.exportJSON(e[:solution], "data/outputs/cutting_plan.json", e[:stock_length_mm], e[:blade_kerf_mm])
            exit
        }
    }

    # Print Executive Side-by-Side Dashboard
    ? f"  [Project]           {aMatrix[:project]}"
    ? f"  [Work Order]         Ingested {nPieceCount} pieces ({aMatrix[:total_demand_mm]} mm)"
    ? f"  [Scenarios Evaluated] {aMatrix[:scenarios_count]} candidate scenarios in {nTotalSimTimeMs} ms"
    ? "------------------------------------------------------------------------------------------------"
    ? "  Scenario ID           Stock(mm)  Bars   Waste(mm)  Waste(%)   Total Cost   Cost Delta   Status"
    ? "------------------------------------------------------------------------------------------------"

    for e in aEvals {
        cStatus = "Alternative"
        cDeltaStr = f"+${e[:cost_delta_usd]}"
        if e[:id] = cWinnerID {
            cStatus = "★ WINNER"
        }
        if e[:cost_delta_usd] = 0.0 {
            cDeltaStr = "$0.00 (BASE)"
            if e[:id] != cWinnerID {
                cStatus = "BASELINE"
            }
        elseif e[:cost_delta_usd] < 0.0
            cDeltaStr = f"-${-1.0 * e[:cost_delta_usd]}"
        }

        ? f"  {padRight(e[:id], 20)} {padRight(''+e[:stock_length_mm], 10)} {padRight(''+e[:bars_used], 6)} {padRight(''+e[:total_waste_mm], 10)} {padRight(''+e[:waste_percentage]+'%', 10)} ${padRight(''+e[:total_cost_usd], 11)} {padRight(cDeltaStr, 12)} {cStatus}"
    }

    ? "------------------------------------------------------------------------------------------------"
    ? f"  [Decision Recommendation] Recommended Winner: '{aMatrix[:recommended_winner]}'"
    ? f"  [Cheapest Financial]     Option: '{aMatrix[:cheapest_scenario]}'"
    ? f"  [Greenest / Min Scrap]   Option: '{aMatrix[:greenest_scenario]}'"
    ? "------------------------------------------------------------------------------------------------"
    ? "[Production Decision Artifacts]"
    ? f"  [OK] Multi-Scenario Comparison (CSV): {cCompCSV}"
    ? f"  [OK] Executive Decision Brief   (JSON): {cBriefJSON}"
    ? "  [OK] Winning Production Plan    (CSV): data/outputs/cutting_plan.csv"
    ? "  [OK] Winning Production Plan   (JSON): data/outputs/cutting_plan.json"
    ? "===================================================================="
}

func runSingleOptimization(cOrdersPath, nStock, nKerf, cMethod, cOutCSV, cOutJSON) {
    ? "===================================================================="
    ? "  MadarOpt: Enterprise Production Optimization Engine"
    ? "  Headless Decision Intelligence Runner (v0.1.0-alpha)"
    ? "===================================================================="

    oLoader = new OptDataLoader
    aDemands = oLoader.loadOrdersCSV(cOrdersPath)
    nPieceCount = len(aDemands)

    if nPieceCount = 0 {
        ? f"[MadarOpt Error] No valid cutting pieces loaded from: {cOrdersPath}"
        bye 1
    }

    oProblem = new CuttingStock1D(nStock, aDemands, nKerf)
    nTheoryMin = oProblem.theoreticalMinimumBars()
    nTotalDemand = oProblem.totalDemandLength()

    ? f"  [Input Work Order] Ingested {nPieceCount} pieces from '{cOrdersPath}'"
    ? f"  [Total Material]   {nTotalDemand} mm linear demand ({nTotalDemand / 1000.0} meters)"
    ? f"  [Stock Profile]    Standard bar length: {nStock} mm (Kerf: {nKerf} mm)"
    ? f"  [Lower Bound]      Theoretical optimal minimum: {nTheoryMin} bars"
    ? f"  [Solver Strategy]  Executing: {cMethod}"
    ? "--------------------------------------------------------------------"

    nStartNs = nanotime()
    aSolution = madaropt_solve_cutting_stock(nStock, aDemands, nKerf, cMethod)
    nElapsedUs = (nanotime() - nStartNs) / 1000.0
    nElapsedMs = nElapsedUs / 1000.0

    oExporter = new OptPlanExporter
    oExporter.exportCSV(aSolution, cOutCSV, nStock, nKerf)
    oExporter.exportJSON(aSolution, cOutJSON, nStock, nKerf)

    ? "[Optimization Results]"
    ? f"  -> Raw Stock Bars Required: {aSolution[:bars_used]} bars"
    ? f"  -> Total Scrap Waste:       {aSolution[:total_waste_mm]} mm ({aSolution[:total_waste_mm] / 1000.0} meters)"
    ? f"  -> Overall Waste Ratio:     {aSolution[:waste_percentage]}%"
    ? f"  -> Solver Latency:          {nElapsedUs} us ({nElapsedMs} ms)"
    ? "--------------------------------------------------------------------"
    ? "[Production Artifacts Generated]"
    ? f"  [OK] Shopfloor Cutting Table (CSV): {cOutCSV}"
    ? f"  [OK] Machine-Readable Plan   (JSON): {cOutJSON}"
    ? "===================================================================="
}

func padRight(cStr, nWidth) {
    cRes = "" + cStr
    while len(cRes) < nWidth {
        cRes += " "
    }
    return cRes
}

func printHelp() {
    ? "MadarOpt CLI - Enterprise Cutting Stock Optimizer & Scenario Engine"
    ? "Usage: ring cli.ring [options]"
    ? "Options:"
    ? "  --simulate, -s     Run multi-scenario What-If simulation mode"
    ? "  --scenarios <file> Path to scenarios JSON (default: data/inputs/scenarios.json)"
    ? "  --orders <file>    Path to input orders CSV (default: data/inputs/sample_orders.csv)"
    ? "  --stock <mm>       Length of standard raw stock bar for 1D (default: 6000.0)"
    ? "  --2d               Run 2D rectangular cutting & nesting mode"
    ? "  --sheet_w <mm>     Width of 2D raw stock sheet (default: 2440.0)"
    ? "  --sheet_h <mm>     Height of 2D raw stock sheet (default: 1220.0)"
    ? "  --no_rotate        Disallow 90-degree piece rotation in 2D nesting"
    ? "  --kerf <mm>        Blade/laser saw cut loss per cut (default: 4.0 for 1D, 3.0 for 2D)"
    ? "  --method <str>     Solver algorithm: BFD, FFD, or GA (default: BFD)"
    ? "  --out_csv <file>   Output shopfloor CSV table (default: data/outputs/cutting_plan.csv or layout_2d.csv)"
    ? "  --out_json <file>  Output machine JSON plan (default: data/outputs/cutting_plan.json or layout_2d.json)"
}
