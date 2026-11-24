/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Core Tensor Acceleration Kernel (RingTensor)
* Description: In-core SIMD/AVX2 continuous memory tensors for batched solution evaluation,
* GEMM matrix transformations, and high-speed Operations Research reductions.
*/

class OptTensorKernel

    /*
    * Function: createDemandTensor
    * Description: Converts a list of item demands into a column vector [N, 1] tensor.
    * Inputs: aDemands (List of Numbers)
    * Outputs: RingTensor [N, 1] (Float32)
    */
    func createDemandTensor(aDemands) {
        nLen = len(aDemands)
        tVec = tensor_from_list(aDemands, "Float32")
        tCol = tensor_reshape(tVec, [nLen, 1])
        return tCol
    }

    /*
    * Function: createZeroMatrix
    * Description: Allocates an [nRows, nCols] continuous float tensor filled with 0.0.
    */
    func createZeroMatrix(nRows, nCols) {
        tMat = tensor([nRows, nCols], "Float32")
        tensor_fill(tMat, 0.0)
        return tMat
    }

    /*
    * Function: evaluateStockFillLevels
    * Description: Evaluates total filled lengths of all stock bars in a single hardware GEMM operation.
    * Mathematical Formulation: Y = A * w
    * where:
    *   A = [M, N] Binary/Integer Assignment Matrix (M bars, N items)
    *   w = [N, 1] Item Demand Lengths Column Vector
    *   Y = [M, 1] Output Vector containing total filled length in each bar
    * Inputs: tAssignment [M, N], tDemands [N, 1]
    * Outputs: RingTensor [M, 1] (Fill levels per bar)
    */
    func evaluateStockFillLevels(tAssignment, tDemands) {
        return tensor_matmul(tAssignment, tDemands)
    }

    /*
    * Function: computeTotalScrap
    * Description: Computes total scrap across all M bars given stock length and filled vector Y.
    * Total Scrap = M * nStockLength - Sum(Y)
    * Inputs: tUsedLevels [M, 1], nStockLength (Number)
    * Outputs: Number (Total scrap mm)
    */
    func computeTotalScrap(tUsedLevels, nStockLength) {
        aShape = tensor_shape(tUsedLevels)
        nBarsCount = aShape[1]
        nTotalStock = nBarsCount * nStockLength
        nTotalDemand = tensor_sum(tUsedLevels)
        return (nTotalStock - nTotalDemand)
    }

    /*
    * Function: calculateDistanceMatrix
    * Description: Computes N x N Euclidean distance matrix for VRP / Logistics from coordinates.
    * Inputs: aCoordinates (List of [X, Y] pairs)
    * Outputs: RingTensor [N, N] (Float32)
    */
    func calculateDistanceMatrix(aCoordinates) {
        nN = len(aCoordinates)
        tDist = tensor([nN, nN], "Float32")
        tensor_fill(tDist, 0.0)

        for nI = 1 to nN {
            nX1 = aCoordinates[nI][1]
            nY1 = aCoordinates[nI][2]
            for nJ = nI + 1 to nN {
                nX2 = aCoordinates[nJ][1]
                nY2 = aCoordinates[nJ][2]
                nDx = nX1 - nX2
                nDy = nY1 - nY2
                nDist = sqrt((nDx * nDx) + (nDy * nDy))
                tensor_set(tDist, nI, nJ, nDist)
                tensor_set(tDist, nJ, nI, nDist)
            }
        }
        return tDist
    }

