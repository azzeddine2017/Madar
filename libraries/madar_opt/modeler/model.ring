/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Modeler - Optimization Model Representation
* Description: Mathematical formulation model supporting decision variables,
* linear constraints, objectives, and compilation into continuous RingTensors.
*/

load "variable.ring"
load "constraint.ring"
load "simplex_solver.ring"
load "milp_branch_bound.ring"

class OptModel

    cModelName        = "GenericModel"
    aVariables        = []
    aConstraints      = []
    aObjectiveCoeffs  = []
    nObjectiveSense   = OPT_MINIMIZE

    func init(cName) {
        if len(cName) > 0 { cModelName = cName }
        aVariables       = []
        aConstraints     = []
        aObjectiveCoeffs = []
        nObjectiveSense  = OPT_MINIMIZE
    }

    /*
    * Function: addVariable
    * Description: Adds a single decision variable.
    * Inputs: cName, nType (OPT_CONTINUOUS, OPT_INTEGER, OPT_BINARY), nLB, nUB
    * Outputs: OptVariable instance
    */
    func addVariable(cName, nType, nLB, nUB) {
        nIdx = len(aVariables) + 1
        oVar = new OptVariable(cName, nType, nLB, nUB, nIdx)
        aVariables + oVar
        return oVar
    }

    /*
    * Function: addVariables
    * Description: Adds a vector of N decision variables with a common prefix.
    * Outputs: List of OptVariable instances
    */
    func addVariables(cPrefix, nCount, nType, nLB, nUB) {
        aList = []
        for nI = 1 to nCount {
            cVarName = f"{cPrefix}_{nI}"
            aList + addVariable(cVarName, nType, nLB, nUB)
        }
        return aList
    }

    /*
    * Function: setObjective
    * Description: Sets the linear objective coefficients vector and sense.
    * Inputs: aCoeffs (List of Numbers), nSense (OPT_MINIMIZE or OPT_MAXIMIZE)
    */
    func setObjective(aCoeffs, nSense) {
        if isList(aCoeffs) { aObjectiveCoeffs = aCoeffs }
        if nSense != 0 { nObjectiveSense = nSense }
    }

    /*
    * Function: addConstraint
    * Description: Adds a linear constraint: sum(a_j * x_j) (<= | >= | ==) b
    * Inputs: aCoeffs (List of Numbers), cSense ("<=", ">=", "=="), nRHS (Number), cName (String)
    * Outputs: OptConstraint instance
    */
    func addConstraint(aCoeffs, cSense, nRHS, cName) {
        nIdx = len(aConstraints) + 1
        oConstr = new OptConstraint(aCoeffs, cSense, nRHS, cName, nIdx)
        aConstraints + oConstr
        return oConstr
    }

    /*
    * Function: isPureLP
    * Description: Returns true if all variables in the model are continuous.
    */
    func isPureLP() {
        for v in aVariables {
            if v.nType != OPT_CONTINUOUS {
                return false
            }
        }
        return true
    }

    /*
    * Function: compileToTensors
    * Description: Compiles variables, constraints, and objective into RingTensors.
    * Outputs: Map containing continuous Tensors: :A, :b, :c
    */
    func compileToTensors() {
        nM = len(aConstraints)
        nN = len(aVariables)

        if nM = 0 or nN = 0 {
            return []
        }

        # Build Constraint Matrix A [M, N]
        tA = tensor([nM, nN], "Float32")
        tensor_fill(tA, 0.0)
        for nI = 1 to nM {
            aRowCoeffs = aConstraints[nI].aCoefficients
            nRowLen = len(aRowCoeffs)
            for nJ = 1 to nN {
                if nJ <= nRowLen {
                    tensor_set(tA, nI, nJ, 0.0 + aRowCoeffs[nJ])
                }
            }
        }

        # Build RHS Vector b [M, 1]
        aRHS = []
        for nI = 1 to nM {
            aRHS + (0.0 + aConstraints[nI].nRHS)
        }
        tB = tensor_from_list(aRHS, "Float32")
        tB = tensor_reshape(tB, [nM, 1])

        # Build Objective Vector c [N, 1]
        aObj = []
        for nJ = 1 to nN {
            nVal = 0.0
            if nJ <= len(aObjectiveCoeffs) {
                nVal = 0.0 + aObjectiveCoeffs[nJ]
            }
            # If Maximizing, negate coefficients for minimization standard form: min -c^T x
            if nObjectiveSense = OPT_MAXIMIZE {
                nVal = -1.0 * nVal
            }
            aObj + nVal
        }
        tC = tensor_from_list(aObj, "Float32")
        tC = tensor_reshape(tC, [nN, 1])

        return [
            :A = tA,
            :b = tB,
            :c = tC,
            :rows = nM,
            :cols = nN
        ]
    }

    /*
    * Function: solve
    * Description: General optimization solver dispatcher.
    * Automatically routes to Simplex LP or Branch-and-Bound MILP.
    */
    func solve() {
        if isPureLP() {
            oSolver = new OptSimplexSolver
            return oSolver.solve(self)
        else
            oSolver = new OptBranchBoundSolver
            return oSolver.solve(self)
        }
    }
