/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Modeler - Variable System
* Description: Represents continuous, integer, and binary decision variables
* in mathematical programming.
*/

# Variable Types
OPT_CONTINUOUS = 1  # Reals (x in R)
OPT_INTEGER    = 2  # Integers (x in Z)
OPT_BINARY     = 3  # Binary flags (x in {0, 1})

# Optimization Senses
OPT_MINIMIZE   = 1
OPT_MAXIMIZE   = -1

# Solver Status Codes
OPT_OPTIMAL    = 1
OPT_INFEASIBLE = 2
OPT_UNBOUNDED  = 3
OPT_ERROR      = 4

class OptVariable

    cName       = "x"
    nType       = OPT_CONTINUOUS
    nLowerBound = 0.0
    nUpperBound = 999999999999.0  # +Infinity default
    nIndex      = 1

    func init(cVarName, nVarType, nLB, nUB, nIdx) {
        if len(cVarName) > 0 { cName = cVarName }
        if nVarType > 0 { nType = nVarType }
        nLowerBound = 0.0 + nLB
        nUpperBound = 0.0 + nUB
        if nIdx > 0 { nIndex = nIdx }

        # Enforce binary bounds automatically
        if nType = OPT_BINARY {
            nLowerBound = 0.0
            nUpperBound = 1.0
        }
    }
