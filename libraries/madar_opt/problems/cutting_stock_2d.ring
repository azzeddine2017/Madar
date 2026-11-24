/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Problems - 2D Rectangular Cutting Stock & Nesting
* Description: Mathematical formulation for sheet metal, glass, plywood/MDF,
* and corrugated box cutting with guillotine constraints and rotation freedom.
*/

class CuttingStock2D

    # Standard Sheet Dimensions (e.g. 2440 x 1220 mm standard plywood / sheet metal)
    nSheetWidth    = 2440.0
    nSheetHeight   = 1220.0
    aDemands       = []      # List of items: [:id, :w, :h, :qty, :can_rotate]
    nBladeKerf     = 3.0     # Laser/saw kerf cut width in mm
    bAllowRotation = true    # Allow 90-degree rotation

    func init(nWidth, nHeight, aPieces, nKerf, bRotate) {
        if nWidth > 0 { nSheetWidth = 0.0 + nWidth }
        if nHeight > 0 { nSheetHeight = 0.0 + nHeight }
        if isList(aPieces) { aDemands = aPieces }
        if nKerf >= 0 { nBladeKerf = 0.0 + nKerf }
        bAllowRotation = bRotate
    }

    /*
    * Function: totalDemandArea
    * Description: Computes the aggregate area required by all demanded rectangular pieces.
    */
    func totalDemandArea() {
        nTotal = 0.0
        for p in aDemands {
            nArea = p[:w] * p[:h]
            nQty = 1
            if p[:qty] > 0 { nQty = p[:qty] }
            nTotal += (nArea * nQty)
        }
        return nTotal
    }

    /*
    * Function: sheetArea
    * Description: Computes the surface area of a single raw stock sheet.
    */
    func sheetArea() {
        return nSheetWidth * nSheetHeight
    }

    /*
    * Function: theoreticalMinimumSheets
    * Description: Lower bound on the number of sheets needed: ceil(TotalArea / SheetArea).
    */
    func theoreticalMinimumSheets() {
        nDemand = totalDemandArea()
        nSheet = sheetArea()
        if nDemand <= 0 or nSheet <= 0 {
            return 0
        }
        return ceil(nDemand / nSheet)
    }

    /*
    * Function: toPatternMILP
    * Description: Generates a Generalized Algebraic Model (OptModel) using pattern columns.
    * Inputs: aCandidatePatterns (List of patterns, where each pattern has :cuts map of piece_id -> count)
    * Outputs: OptModel ready to be solved by Simplex/MILP
    */
    func toPatternMILP(aCandidatePatterns) {
        nPatCount = len(aCandidatePatterns)
        nPieceTypes = len(aDemands)

        oModel = new OptModel("2D_Pattern_Cutting_MILP")

        # Variable lambda_k: number of times pattern k is cut (Integer)
        aPatternVars = oModel.addVariables("Pattern", nPatCount, OPT_INTEGER, 0, 1000)

        # Objective: Minimize total sheets cut: Min Sum(lambda_k)
        aObjCoeffs = []
        for nK = 1 to nPatCount {
            aObjCoeffs + 1.0
        }
        oModel.setObjective(aObjCoeffs, OPT_MINIMIZE)

        # Constraints: for each demanded piece type i, Sum(Pattern_k[i] * lambda_k) >= Demand[i]
        for nI = 1 to nPieceTypes {
            p = aDemands[nI]
            cPieceID = p[:id]
            nRequiredQty = 0.0 + p[:qty]

            aRow = []
            for nK = 1 to nPatCount {
                pat = aCandidatePatterns[nK]
                nCountInPat = 0.0
                if pat[:cuts][cPieceID] != NULL {
                    nCountInPat = 0.0 + pat[:cuts][cPieceID]
                }
                aRow + nCountInPat
            }

            oModel.addConstraint(aRow, ">=", nRequiredQty, f"demand_{cPieceID}")
        }

        return oModel
    }

    /*
    * Function: evaluateLayout
    * Description: Evaluates a 2D nesting packing layout across sheets.
    * Inputs: aSheets (List of sheets, each containing :placements list of placed rectangles)
    * Outputs: Structured metrics map
    */
    func evaluateLayout(aSheets) {
        nSheetsCount = len(aSheets)
        nTotDemandArea = totalDemandArea()
        nTotStockArea = nSheetsCount * sheetArea()
        nScrapArea = nTotStockArea - nTotDemandArea
        nWastePct = 0.0
        if nTotStockArea > 0 {
            nWastePct = (nScrapArea / nTotStockArea) * 100.0
        }

        return [
            :sheets_used         = nSheetsCount,
            :theoretical_min     = theoreticalMinimumSheets(),
            :total_stock_area    = nTotStockArea,
            :total_demand_area   = nTotDemandArea,
            :total_scrap_area    = nScrapArea,
            :waste_percentage    = nWastePct,
            :sheets              = aSheets
        ]
    }
