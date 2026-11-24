/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Core Numerical Kernel
* Description: High-speed numerical calculations, array reductions, and JIT-accelerated kernels.
*/

class OptNumericalKernel

    /*
    * Function: sumVector
    * Description: Computes the sum of a numerical list using Madar accelerated dour loop.
    * Inputs: aVector (List of Numbers)
    * Outputs: Number (Sum)
    */
    func sumVector(aVector) {
        nSum = 0.0
        nLen = len(aVector)
        if nLen = 0 {
            return 0.0
        }
        dour nI = 1 to nLen {
            nSum += aVector[nI]
        }
        return nSum
    }

    /*
    * Function: sumSquares
    * Description: Computes sum of squares (L2 norm component).
    * Inputs: aVector (List of Numbers)
    * Outputs: Number
    */
    func sumSquares(aVector) {
        nSum = 0.0
        nLen = len(aVector)
        if nLen = 0 {
            return 0.0
        }
        dour nI = 1 to nLen {
            nVal = aVector[nI]
            nSum += (nVal * nVal)
        }
        return nSum
    }

    /*
    * Function: sumRange
    * Description: Pure scalar arithmetic summation (triggers native Madar Auto-JIT compilation).
    * Inputs: nStart, nEnd
    * Outputs: Number
    */
    func sumRange(nStart, nEnd) {
        nTotal = 0
        dour nX = nStart to nEnd {
            nTotal += nX
        }
        return nTotal
    }

    /*
    * Function: sortDescending
    * Description: Sorts a numeric list in descending order (critical for BFD/FFD heuristics).
    * Inputs: aList (List of Numbers)
    * Outputs: List (Sorted Descending)
    */
    func sortDescending(aList) {
        aSorted = sort(aList)
        aResult = []
        nLen = len(aSorted)
        dour nI = nLen to 1 step -1 {
            aResult + aSorted[nI]
        }
        return aResult
    }

    /*
    * Function: dotProduct
    * Description: Calculates dot product between two numerical vectors.
    * Inputs: aVec1, aVec2 (Lists of Numbers of equal length)
    * Outputs: Number
    */
    func dotProduct(aVec1, aVec2) {
        nDot = 0.0
        nLen = len(aVec1)
        if nLen != len(aVec2) or nLen = 0 {
            return 0.0
        }
        dour nI = 1 to nLen {
            nDot += (aVec1[nI] * aVec2[nI])
        }
        return nDot
    }


