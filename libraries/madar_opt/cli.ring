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
    else
        runSingleOptimization(cOrdersPath, nStock, nKerf, cMethod, cOutCSV, cOutJSON)
    }
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
    ? "  --stock <mm>       Length of standard raw stock bar (default: 6000.0)"
    ? "  --kerf <mm>        Blade saw cut loss per cut (default: 4.0)"
    ? "  --method <str>     Solver algorithm: BFD, FFD, or GA (default: BFD)"
    ? "  --out_csv <file>   Output shopfloor CSV table (default: data/outputs/cutting_plan.csv)"
    ? "  --out_json <file>  Output machine JSON plan (default: data/outputs/cutting_plan.json)"
}
