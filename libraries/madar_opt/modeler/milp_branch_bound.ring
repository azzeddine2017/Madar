/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Modeler - Mixed-Integer Linear Programming (MILP) Solver
* Description: Branch-and-Bound exact algorithm for discrete, integer,
* and binary combinatorial optimization problems.
*/

load "simplex_solver.ring"

class OptBranchBoundSolver

    nMaxNodes = 500
    nIntegralityTol = 0.0001

    /*
    * Function: solve
    * Description: Solves a mixed-integer or binary linear programming model.
    * Inputs: oModel (OptModel instance)
    * Outputs: Solution Map (:status, :objective_value, :variables, :nodes_explored)
    */
    func solve(oModel) {
        nStartNs = nanotime()
        nSense = oModel.nObjectiveSense

        nBestObj = 999999999999.0
        if nSense = OPT_MAXIMIZE {
            nBestObj = -999999999999.0
        }
        aBestVars = []
        bFoundInteger = false
        nNodesExplored = 0

        # Queue of models to solve [oCurrentModel]
        aQueue = [cloneModel(oModel)]
        oSolver = new OptSimplexSolver

        while len(aQueue) > 0 and nNodesExplored < nMaxNodes {
            nNodesExplored++
            # Pop node (Depth-First / FIFO Search)
            oNode = aQueue[1]
            del(aQueue, 1)

            # Solve LP Relaxation
            aLPRes = oSolver.solve(oNode)

            # If infeasible or unbounded, prune by infeasibility
            if aLPRes[:status] != OPT_OPTIMAL {
                loop
            }

            nNodeObj = aLPRes[:objective_value]
            aNodeVars = aLPRes[:variables]

            # Prune by bound: if LP relaxation is already worse than best integer solution
            if nSense = OPT_MINIMIZE and nNodeObj >= nBestObj {
                loop
            }
            if nSense = OPT_MAXIMIZE and nNodeObj <= nBestObj {
                loop
            }

            # Check integrality of variables
            nBranchVar = 0
            nBranchVal = 0.0

            nVarCount = len(oNode.aVariables)
            for nJ = 1 to nVarCount {
                v = oNode.aVariables[nJ]
                if v.nType = OPT_INTEGER or v.nType = OPT_BINARY {
                    nVal = aNodeVars[nJ]
                    nRounded = floor(nVal + 0.5)
                    if fabs(nVal - nRounded) > nIntegralityTol {
                        nBranchVar = nJ
                        nBranchVal = nVal
                        exit
                    }
                }
            }

            # If all integer variables are integer, we found a valid integer solution!
            if nBranchVar = 0 {
                if !bFoundInteger {
                    bFoundInteger = true
                    nBestObj = nNodeObj
                    aBestVars = aNodeVars
                elseif nSense = OPT_MAXIMIZE and nNodeObj > nBestObj
                    nBestObj = nNodeObj
                    aBestVars = aNodeVars
                elseif nSense = OPT_MINIMIZE and nNodeObj < nBestObj
                    nBestObj = nNodeObj
                    aBestVars = aNodeVars
                }
                loop
            }

            # Otherwise, Branch on variable nBranchVar:
            # Child 1: x_k <= floor(nBranchVal)
            # Child 2: x_k >= ceil(nBranchVal)
            nFloorVal = floor(nBranchVal)
            nCeilVal  = ceil(nBranchVal)

            # Branch Left
            oLeft = cloneModel(oNode)
            aCoeffLeft = []
            for nK = 1 to nVarCount {
                nValK = 0.0
                if nK = nBranchVar { nValK = 1.0 }
                aCoeffLeft + nValK
            }
            oLeft.addConstraint(aCoeffLeft, "<=", nFloorVal, "branch_left")
            aQueue + oLeft

            # Branch Right
            oRight = cloneModel(oNode)
            aCoeffRight = []
            for nK = 1 to nVarCount {
                nValK = 0.0
                if nK = nBranchVar { nValK = 1.0 }
                aCoeffRight + nValK
            }
            oRight.addConstraint(aCoeffRight, ">=", nCeilVal, "branch_right")
            aQueue + oRight
        }

        nElapsedUs = (nanotime() - nStartNs) / 1000.0

        if !bFoundInteger {
            return [
                :status          = OPT_INFEASIBLE,
                :objective_value = 0.0,
                :variables       = [],
                :nodes_explored  = nNodesExplored,
                :latency_us      = nElapsedUs,
                :message         = "No integer solution exists within bounds"
            ]
        }

        # Round final integer variables to clean integers
        for nJ = 1 to len(oModel.aVariables) {
            v = oModel.aVariables[nJ]
            if v.nType = OPT_INTEGER or v.nType = OPT_BINARY {
                aBestVars[nJ] = floor(aBestVars[nJ] + 0.5)
            }
        }

        return [
            :status          = OPT_OPTIMAL,
            :objective_value = nBestObj,
            :variables       = aBestVars,
            :nodes_explored  = nNodesExplored,
            :latency_us      = nElapsedUs,
            :latency_ms      = nElapsedUs / 1000.0
        ]
    }

    private

    func cloneModel(oSrc) {
        oCopy = new OptModel(oSrc.cModelName)
        for v in oSrc.aVariables {
            oCopy.addVariable(v.cName, v.nType, v.nLowerBound, v.nUpperBound)
        }
        oCopy.setObjective(oSrc.aObjectiveCoeffs, oSrc.nObjectiveSense)
        for c in oSrc.aConstraints {
            oCopy.addConstraint(c.aCoefficients, c.cSense, c.nRHS, c.cName)
        }
        return oCopy
    }
