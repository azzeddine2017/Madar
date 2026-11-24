/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Modeler - Generalized Two-Phase Simplex LP Solver
* Description: Textbook canonical Two-Phase Simplex algorithm for arbitrary
* continuous linear programming problems (minimization, maximization, equalities, inequalities).
*/

load "chronos.ring"

class OptSimplexSolver

    nMaxIterations = 5000
    nEpsilon       = 0.00000001

    /*
    * Function: solve
    * Description: Solves an OptModel containing continuous linear constraints.
    * Inputs: oModel (OptModel instance)
    * Outputs: Solution Map (:status, :objective_value, :variables, :iterations, :latency_us)
    */
    func solve(oModel) {
        nStartNs = nanotime()

        aVars = oModel.aVariables
        aConstrs = oModel.aConstraints
        nN = len(aVars)
        nM = len(aConstrs)

        if nN = 0 or nM = 0 {
            return [
                :status          = OPT_ERROR,
                :objective_value = 0.0,
                :variables       = [],
                :message         = "Empty model"
            ]
        }

        # -------------------------------------------------------------
        # Step 1: Pre-process constraints & count slack/surplus/artificials
        # -------------------------------------------------------------
        aProcessedConstrs = []
        nSlacks = 0
        nSurplus = 0
        nArtificials = 0

        for nI = 1 to nM {
            cSense = aConstrs[nI].cSense
            nRHS = aConstrs[nI].nRHS
            aCoeffs = []
            for nJ = 1 to nN {
                nVal = 0.0
                if nJ <= len(aConstrs[nI].aCoefficients) {
                    nVal = aConstrs[nI].aCoefficients[nJ]
                }
                aCoeffs + nVal
            }

            if nRHS < 0.0 {
                nRHS = -1.0 * nRHS
                for nJ = 1 to nN {
                    aCoeffs[nJ] = -1.0 * aCoeffs[nJ]
                }
                if cSense = "<=" {
                    cSense = ">="
                elseif cSense = ">="
                    cSense = "<="
                }
            }

            if cSense = "<=" {
                nSlacks++
            elseif cSense = ">="
                nSurplus++
                nArtificials++
            else # "=="
                nArtificials++
            }

            aProcessedConstrs + [
                :coeffs = aCoeffs,
                :sense  = cSense,
                :rhs    = nRHS
            ]
        }

        nTotalVars = nN + nSlacks + nSurplus + nArtificials
        nRHSCol = nTotalVars + 1

        # Allocate Tableau [(nM + 1) rows, (nTotalVars + 1) cols]
        aTableau = []
        for nI = 1 to (nM + 1) {
            aRow = []
            for nJ = 1 to nRHSCol {
                aRow + 0.0
            }
            aTableau + aRow
        }

        # Setup Constraint Rows and Basis tracking
        aBasis = []
        nCurSlack = nN + 1
        nCurSurplus = nN + nSlacks + 1
        nCurArt = nN + nSlacks + nSurplus + 1

        for nI = 1 to nM {
            p = aProcessedConstrs[nI]
            for nJ = 1 to nN {
                aTableau[nI][nJ] = p[:coeffs][nJ]
            }
            aTableau[nI][nRHSCol] = p[:rhs]

            if p[:sense] = "<=" {
                aTableau[nI][nCurSlack] = 1.0
                aBasis + nCurSlack
                nCurSlack++
            elseif p[:sense] = ">="
                aTableau[nI][nCurSurplus] = -1.0
                nCurSurplus++
                aTableau[nI][nCurArt] = 1.0
                aBasis + nCurArt
                nCurArt++
            else # "=="
                aTableau[nI][nCurArt] = 1.0
                aBasis + nCurArt
                nCurArt++
            }
        }

        nIterations = 0
        nNonArtCols = nN + nSlacks + nSurplus

        # -------------------------------------------------------------
        # Step 2: Phase 1 (if artificial variables are present)
        # -------------------------------------------------------------
        if nArtificials > 0 {
            nArtStart = nN + nSlacks + nSurplus + 1
            nArtEnd   = nTotalVars

            # Phase 1 Objective: Minimize W = Sum(artificials).
            # Canonical reduced costs for non-basic columns: T[M+1][j] = -Sum(A[i][j]) for artificial rows
            for nI = 1 to nM {
                if aBasis[nI] >= nArtStart and aBasis[nI] <= nArtEnd {
                    for nJ = 1 to nNonArtCols {
                        aTableau[nM + 1][nJ] -= aTableau[nI][nJ]
                    }
                    aTableau[nM + 1][nRHSCol] -= aTableau[nI][nRHSCol]
                }
            }
            # Artificial columns themselves have 0 reduced cost in canonical form
            for nJ = nArtStart to nArtEnd {
                aTableau[nM + 1][nJ] = 0.0
            }

            # Simplex Pivots for Phase 1 (only non-artificial columns may enter)
            while nIterations < nMaxIterations {
                nIterations++
                nQ = selectEnteringCol(aTableau, nM + 1, nNonArtCols)
                if nQ = 0 {
                    exit
                }

                nP = selectLeavingRow(aTableau, nM, nQ, nRHSCol)
                if nP = 0 {
                    return [
                        :status          = OPT_INFEASIBLE,
                        :objective_value = 0.0,
                        :variables       = [],
                        :message         = "Phase 1 unbounded"
                    ]
                }

                pivot(aTableau, nM + 1, nRHSCol, nP, nQ)
                aBasis[nP] = nQ
            }

            # Phase 1 feasibility check: optimal artificial sum must be 0
            nPhase1Val = fabs(aTableau[nM + 1][nRHSCol])
            if nPhase1Val > 0.0001 {
                return [
                    :status          = OPT_INFEASIBLE,
                    :objective_value = 0.0,
                    :variables       = [],
                    :iterations      = nIterations,
                    :message         = "Constraints are mutually contradictory (Infeasible)"
                ]
            }
        }

        # -------------------------------------------------------------
        # Step 3: Phase 2 (Original Objective Optimization)
        # -------------------------------------------------------------
        # Define objective coefficients in minimization form:
        # If model is OPT_MAXIMIZE, min (-c^T x)
        aObjMin = []
        for nJ = 1 to nTotalVars {
            nC = 0.0
            if nJ <= nN and nJ <= len(oModel.aObjectiveCoeffs) {
                nC = 0.0 + oModel.aObjectiveCoeffs[nJ]
                if oModel.nObjectiveSense = OPT_MAXIMIZE {
                    nC = -1.0 * nC
                }
            }
            aObjMin + nC
        }

        # Compute initial canonical reduced costs: c_bar_j = c_j - sum(c_B * A_ij)
        for nJ = 1 to nNonArtCols {
            nSumCB_A = 0.0
            for nI = 1 to nM {
                nBasicVar = aBasis[nI]
                nCB = aObjMin[nBasicVar]
                nSumCB_A += (nCB * aTableau[nI][nJ])
            }
            aTableau[nM + 1][nJ] = aObjMin[nJ] - nSumCB_A
        }

        # Compute initial objective value: Z_0 = sum(c_B * b_i)
        nInitZ = 0.0
        for nI = 1 to nM {
            nBasicVar = aBasis[nI]
            nCB = aObjMin[nBasicVar]
            nInitZ += (nCB * aTableau[nI][nRHSCol])
        }
        aTableau[nM + 1][nRHSCol] = nInitZ

        # Simplex Pivots for Phase 2
        while nIterations < nMaxIterations {
            nIterations++
            nQ = selectEnteringCol(aTableau, nM + 1, nNonArtCols)
            if nQ = 0 {
                # Optimal solution reached!
                exit
            }

            nP = selectLeavingRow(aTableau, nM, nQ, nRHSCol)
            if nP = 0 {
                return [
                    :status          = OPT_UNBOUNDED,
                    :objective_value = 0.0,
                    :variables       = [],
                    :iterations      = nIterations,
                    :message         = "Objective function is unbounded (tends to infinity)"
                ]
            }

            pivot(aTableau, nM + 1, nRHSCol, nP, nQ)
            aBasis[nP] = nQ
        }

        # -------------------------------------------------------------
        # Step 4: Extract Optimal Solution & Metrics
        # -------------------------------------------------------------
        aVarVals = []
        for nJ = 1 to nN {
            aVarVals + 0.0
        }

        for nI = 1 to nM {
            nVarIdx = aBasis[nI]
            if nVarIdx <= nN {
                aVarVals[nVarIdx] = aTableau[nI][nRHSCol]
            }
        }

        # Objective value directly computed from decision variables
        nFinalZ = 0.0
        for nJ = 1 to nN {
            if nJ <= len(oModel.aObjectiveCoeffs) {
                nFinalZ += (oModel.aObjectiveCoeffs[nJ] * aVarVals[nJ])
            }
        }

        nElapsedUs = (nanotime() - nStartNs) / 1000.0

        return [
            :status          = OPT_OPTIMAL,
            :objective_value = nFinalZ,
            :variables       = aVarVals,
            :iterations      = nIterations,
            :latency_us      = nElapsedUs,
            :latency_ms      = nElapsedUs / 1000.0
        ]
    }

    private

    func selectEnteringCol(aTableau, nObjRow, nLimitCols) {
        nMinVal = -nEpsilon
        nBestCol = 0
        for nJ = 1 to nLimitCols {
            if aTableau[nObjRow][nJ] < nMinVal {
                nMinVal = aTableau[nObjRow][nJ]
                nBestCol = nJ
            }
        }
        return nBestCol
    }

    func selectLeavingRow(aTableau, nRows, nCol, nRHSCol) {
        nMinRatio = 999999999999.0
        nBestRow = 0
        for nI = 1 to nRows {
            nEntry = aTableau[nI][nCol]
            if nEntry > nEpsilon {
                nRatio = aTableau[nI][nRHSCol] / nEntry
                if nRatio < nMinRatio {
                    nMinRatio = nRatio
                    nBestRow = nI
                }
            }
        }
        return nBestRow
    }

    func pivot(aTableau, nTotalRows, nTotalCols, nP, nQ) {
        nPivotVal = aTableau[nP][nQ]

        # Normalize pivot row
        for nJ = 1 to nTotalCols {
            aTableau[nP][nJ] = aTableau[nP][nJ] / nPivotVal
        }

        # Eliminate pivot column from all other rows (including objective row)
        for nI = 1 to nTotalRows {
            if nI != nP {
                nFactor = aTableau[nI][nQ]
                if fabs(nFactor) > nEpsilon {
                    for nJ = 1 to nTotalCols {
                        aTableau[nI][nJ] -= (nFactor * aTableau[nP][nJ])
                    }
                }
            }
        }
    }
