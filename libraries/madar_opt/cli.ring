/*
* Project: MadarOpt - Industrial Decision Intelligence
* File: cli.ring
* Description: Enterprise Headless CLI Runner for automated ERP/MES integration.
* Usage: ring cli.ring [--orders <file>] [--stock <mm>] [--kerf <mm>] [--method <BFD|FFD|GA>]
*/

load "madar_opt.ring"
load "chronos.ring"

func main() {
    decimals(2)
    aArgs = sysargv

    # Default parameters
    cOrdersPath = "data/sample_orders.csv"
    nStock      = 6000.0
    nKerf       = 4.0
    cMethod     = "BFD"
    cOutCSV     = "cutting_plan.csv"
    cOutJSON    = "cutting_plan.json"

    # Simple CLI argument parser
    nArgCount = len(aArgs)
    for nI = 1 to nArgCount {
        cArg = aArgs[nI]
        if cArg = "--orders" and nI < nArgCount {
            cOrdersPath = aArgs[nI + 1]
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

    ? "===================================================================="
    ? "  MadarOpt: Enterprise Production Optimization Engine"
    ? "  Headless Decision Intelligence Runner (v0.1.0-alpha)"
    ? "===================================================================="

    # Step 1: Data Ingestion
    oLoader = new OptDataLoader
    aDemands = oLoader.loadOrdersCSV(cOrdersPath)
    nPieceCount = len(aDemands)

    if nPieceCount = 0 {
        ? f"[MadarOpt Error] No valid cutting pieces loaded from: {cOrdersPath}"
        bye 1
    }

    # Step 2: Formulation & Solving
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
    nElapsedNs = nanotime() - nStartNs
    nElapsedUs = nElapsedNs / 1000.0
    nElapsedMs = nElapsedUs / 1000.0

    # Step 3: Export Deterministic Production Artifacts
    oExporter = new OptPlanExporter
    oExporter.exportCSV(aSolution, cOutCSV, nStock, nKerf)
    oExporter.exportJSON(aSolution, cOutJSON, nStock, nKerf)

    # Step 4: Executive Summary Output
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

func printHelp() {
    ? "MadarOpt CLI - Enterprise Cutting Stock Optimizer"
    ? "Usage: ring cli.ring [options]"
    ? "Options:"
    ? "  --orders <file>    Path to input orders CSV (default: data/sample_orders.csv)"
    ? "  --stock <mm>       Length of standard raw stock bar (default: 6000.0)"
    ? "  --kerf <mm>        Blade saw cut loss per cut (default: 4.0)"
    ? "  --method <str>     Solver algorithm: BFD, FFD, or GA (default: BFD)"
    ? "  --out_csv <file>   Output shopfloor CSV table (default: cutting_plan.csv)"
    ? "  --out_json <file>  Output machine JSON plan (default: cutting_plan.json)"
}

