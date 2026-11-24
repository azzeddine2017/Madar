/*
* Project: MadarOpt - Industrial Decision Intelligence & Optimization Engine
* File: madar_opt.ring
* Description: Central entry-point and loader for MadarOpt library.
*/

load "core/numerical_kernel.ring"
load "core/tensor_kernel.ring"
load "problems/cutting_stock_1d.ring"
load "solvers/heuristic_solver.ring"
load "solvers/genetic_solver.ring"
load "io/data_loader.ring"
load "io/plan_exporter.ring"

/*
* Function: madaropt_version
* Description: Returns current version of MadarOpt engine.
*/
func madaropt_version() {
    return "0.1.0-alpha"
}

/*
* Function: madaropt_solve_cutting_stock
* Description: Quick facade function to solve 1D cutting stock problems with automatic solver selection.
* Inputs: nStockLength, aDemands, nBladeKerf, cMethod ("BFD", "FFD", "GA")
* Outputs: Structured Solution Evaluation Map
*/
func madaropt_solve_cutting_stock(nStockLength, aDemands, nBladeKerf, cMethod) {
    oProblem = new CuttingStock1D(nStockLength, aDemands, nBladeKerf)
    if cMethod = "GA" {
        oSolver = new GeneticCuttingSolver
        return oSolver.solve(oProblem)
    elseif cMethod = "FFD"
        oSolver = new HeuristicCuttingSolver
        return oSolver.solveFFD(oProblem)
    else
        # Default: Best-Fit Decreasing (BFD)
        oSolver = new HeuristicCuttingSolver
        return oSolver.solveBFD(oProblem)
    }
}

