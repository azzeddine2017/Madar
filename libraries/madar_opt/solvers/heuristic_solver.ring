/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Solvers - High-Speed Deterministic Heuristics
* Description: Production-grade Best-Fit Decreasing (BFD) and First-Fit Decreasing (FFD)
* combinatorial optimization algorithms for cutting stock and bin packing.
*/

class HeuristicCuttingSolver

    /*
    * Function: solveBFD
    * Description: Best-Fit Decreasing (BFD) algorithm.
    * Places item into the bin that minimizes the resulting scrap space.
    * Inputs: oProblem (CuttingStock1D instance)
    * Outputs: Structured Solution Evaluation Map
    */
    func solveBFD(oProblem) {
        aItems = oProblem.aDemands
        nStock = oProblem.nStockLength
        nKerf  = oProblem.nBladeKerf

        # Sort items descending for optimal packing bounds
        aItemsSorted = sort(aItems)
        aDescending = []
        nLen = len(aItemsSorted)
        for nI = nLen to 1 step -1 {
            aDescending + aItemsSorted[nI]
        }

        aBins = []
        aRemaining = []

        nItemsCount = len(aDescending)
        for nI = 1 to nItemsCount {
            nItem = aDescending[nI]
            nBestBin = 0
            nMinSpaceLeft = nStock + 1.0

            nBinsCount = len(aBins)
            for nB = 1 to nBinsCount {
                nRequired = nItem
                if len(aBins[nB]) > 0 and nKerf > 0 {
                    nRequired += nKerf
                }
                if aRemaining[nB] >= nRequired {
                    nSpaceAfter = aRemaining[nB] - nRequired
                    if nSpaceAfter < nMinSpaceLeft {
                        nMinSpaceLeft = nSpaceAfter
                        nBestBin = nB
                    }
                }
            }

            if nBestBin > 0 {
                nRequired = nItem
                if len(aBins[nBestBin]) > 0 and nKerf > 0 {
                    nRequired += nKerf
                }
                aBins[nBestBin] + nItem
                aRemaining[nBestBin] -= nRequired
            else
                # Open new stock bar
                aBins + [nItem]
                aRemaining + (nStock - nItem)
            }
        }

        return oProblem.evaluateSolution(aBins)
    }

    /*
    * Function: solveFFD
    * Description: First-Fit Decreasing (FFD) algorithm.
    * Places item in the first opened bin with sufficient remaining capacity.
    * Inputs: oProblem (CuttingStock1D instance)
    * Outputs: Structured Solution Evaluation Map
    */
    func solveFFD(oProblem) {
        aItems = oProblem.aDemands
        nStock = oProblem.nStockLength
        nKerf  = oProblem.nBladeKerf

        # Sort items descending
        aItemsSorted = sort(aItems)
        aDescending = []
        nLen = len(aItemsSorted)
        for nI = nLen to 1 step -1 {
            aDescending + aItemsSorted[nI]
        }

        aBins = []
        aRemaining = []

        nItemsCount = len(aDescending)
        for nI = 1 to nItemsCount {
            nItem = aDescending[nI]
            bPlaced = false

            nBinsCount = len(aBins)
            for nB = 1 to nBinsCount {
                nRequired = nItem
                if len(aBins[nB]) > 0 and nKerf > 0 {
                    nRequired += nKerf
                }
                if aRemaining[nB] >= nRequired {
                    aBins[nB] + nItem
                    aRemaining[nB] -= nRequired
                    bPlaced = true
                    exit
                }
            }

            if !bPlaced {
                aBins + [nItem]
                aRemaining + (nStock - nItem)
            }
        }

        return oProblem.evaluateSolution(aBins)
    }

