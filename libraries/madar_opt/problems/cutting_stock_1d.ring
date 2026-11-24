/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Problems - 1D Cutting Stock / Bin Packing
* Description: Mathematical formulation for linear stock cutting (bars, pipes, beams, rolls).
*/

class CuttingStock1D {

    # Problem parameters
    nStockLength = 6000.0  # Standard bar/stock length in mm
    aDemands     = []      # List of demanded piece lengths [mm]
    nBladeKerf   = 0.0     # Blade/saw cutting loss per cut [mm]

    func init(nStock, aItems, nKerf) {
        if nStock > 0 {
            nStockLength = 0.0 + nStock
        }
        if isList(aItems) {
            aDemands = aItems
        }
        if nKerf > 0 {
            nBladeKerf = 0.0 + nKerf
        }
    }

    /*
    * Function: totalDemandLength
    * Description: Sum of all requested cut lengths.
    */
    func totalDemandLength() {
        nTotal = 0.0
        nLen = len(aDemands)
        for nI = 1 to nLen {
            nTotal += aDemands[nI]
        }
        return nTotal
    }

    /*
    * Function: theoreticalMinimumBars
    * Description: Lower bound on stock bars needed (totalDemand / stockLength).
    */
    func theoreticalMinimumBars() {
        nDemand = totalDemandLength()
        if nDemand <= 0 or nStockLength <= 0 {
            return 0
        }
        nMin = ceil(nDemand / nStockLength)
        return nMin
    }

    /*
    * Function: evaluateSolution
    * Description: Evaluates a proposed bin assignment solution.
    * Inputs: aBins (List of Lists, each inner list contains pieces cut from that stock bar)
    * Outputs: List containing detailed metrics
    */
    func evaluateSolution(aBins) {
        nBinsCount = len(aBins)
        nDemandSum = totalDemandLength()
        nTotalStockUsed = nBinsCount * nStockLength
        nTotalWaste = nTotalStockUsed - nDemandSum
        nWastePercent = 0.0
        if nTotalStockUsed > 0 {
            nWastePercent = (nTotalWaste / nTotalStockUsed) * 100.0
        }

        # Analyze bin scraps
        aScraps = []
        for nB = 1 to nBinsCount {
            aBinItems = aBins[nB]
            nBinSum = 0.0
            nItemsCount = len(aBinItems)
            for nK = 1 to nItemsCount {
                nBinSum += aBinItems[nK]
            }
            # Account for blade kerf cuts
            if nItemsCount > 1 and nBladeKerf > 0 {
                nBinSum += (nItemsCount - 1) * nBladeKerf
            }
            nScrap = nStockLength - nBinSum
            aScraps + nScrap
        }

        return [
            :bars_used        = nBinsCount,
            :theoretical_min  = theoreticalMinimumBars(),
            :total_stock_mm   = nTotalStockUsed,
            :total_demand_mm  = nDemandSum,
            :total_waste_mm   = nTotalWaste,
            :waste_percentage = nWastePercent,
            :scraps           = aScraps,
            :bins             = aBins
        ]
    }
}

