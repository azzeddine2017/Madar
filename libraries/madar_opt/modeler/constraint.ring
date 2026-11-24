/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Modeler - Constraint Representation
* Description: Represents linear constraints of the canonical form:
* sum(a_j * x_j) (<= | >= | ==) b
*/

class OptConstraint

    cName         = "c"
    aCoefficients = []    # Numeric weights per variable [a1, a2, ..., an]
    cSense        = "<="  # "<=", ">=", or "=="
    nRHS          = 0.0   # Right-hand side scalar limit b
    nIndex        = 1

    func init(aCoeffs, cOp, nRightSide, cConstrName, nIdx) {
        if isList(aCoeffs) { aCoefficients = aCoeffs }
        if len(cOp) > 0 { cSense = cOp }
        nRHS = 0.0 + nRightSide
        if len(cConstrName) > 0 { cName = cConstrName }
        if nIdx > 0 { nIndex = nIdx }
    }

