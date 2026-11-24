/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Solvers - 2D Guillotine Cutting & Nesting Solver
* Description: High-speed Best-Short-Side Fit (BSSF) Guillotine packing algorithm
* for rectangular sheet nesting (glass, sheet metal, wood, carton).
*/

class Heuristic2DCuttingSolver

    /*
    * Function: solve
    * Description: Solves a 2D rectangular cutting stock problem with Guillotine cuts.
    * Inputs: oProblem (CuttingStock2D instance)
    * Outputs: Structured Solution Evaluation Map
    */
    func solve(oProblem) {
        nSheetW = oProblem.nSheetWidth
        nSheetH = oProblem.nSheetHeight
        nKerf   = oProblem.nBladeKerf
        bRotate = oProblem.bAllowRotation

        # Step 1: Expand pieces into individual rectangular units
        aExpandedPieces = []
        for p in oProblem.aDemands {
            nQty = 1
            if p[:qty] > 0 { nQty = p[:qty] }
            bCanRot = bRotate
            if p[:can_rotate] != NULL { bCanRot = p[:can_rotate] }

            for nQ = 1 to nQty {
                aExpandedPieces + [
                    :id         = p[:id],
                    :w          = 0.0 + p[:w],
                    :h          = 0.0 + p[:h],
                    :area       = (0.0 + p[:w]) * (0.0 + p[:h]),
                    :can_rotate = bCanRot
                ]
            }
        }

        # Step 2: Sort pieces by area descending (2D Best-Fit Decreasing)
        aExpandedPieces = sortPiecesByArea(aExpandedPieces)

        # Sheets structure: list of sheets
        # each sheet has: :placements = [], :free_rects = [ [:x, :y, :w, :h] ]
        aSheets = []

        nTotalPieces = len(aExpandedPieces)
        for nI = 1 to nTotalPieces {
            piece = aExpandedPieces[nI]
            pW = piece[:w]
            pH = piece[:h]

            bPlaced = false
            nBestSheet = 0
            nBestRectIdx = 0
            nBestShortSideFit = 999999999.0
            bBestRotated = false
            nBestPlacedW = pW
            nBestPlacedH = pH

            # Search across active sheets
            nSheetsCount = len(aSheets)
            for nS = 1 to nSheetsCount {
                aFree = aSheets[nS][:free_rects]
                nFreeCount = len(aFree)

                for nR = 1 to nFreeCount {
                    fr = aFree[nR]

                    # 1. Test normal orientation (pW, pH)
                    if fr[:w] >= pW and fr[:h] >= pH {
                        nRemW = fr[:w] - pW
                        nRemH = fr[:h] - pH
                        nShortSide = nRemW
                        if nRemH < nRemW { nShortSide = nRemH }
                        if nShortSide < nBestShortSideFit {
                            nBestShortSideFit = nShortSide
                            nBestSheet = nS
                            nBestRectIdx = nR
                            bBestRotated = false
                            nBestPlacedW = pW
                            nBestPlacedH = pH
                            bPlaced = true
                        }
                    }

                    # 2. Test rotated orientation (pH, pW) if allowed
                    if piece[:can_rotate] and fr[:w] >= pH and fr[:h] >= pW {
                        nRemW = fr[:w] - pH
                        nRemH = fr[:h] - pW
                        nShortSide = nRemW
                        if nRemH < nRemW { nShortSide = nRemH }
                        if nShortSide < nBestShortSideFit {
                            nBestShortSideFit = nShortSide
                            nBestSheet = nS
                            nBestRectIdx = nR
                            bBestRotated = true
                            nBestPlacedW = pH
                            nBestPlacedH = pW
                            bPlaced = true
                        }
                    }
                }
            }

            if bPlaced {
                # Place in best free rectangle of existing sheet
                placeInSheet(aSheets[nBestSheet], nBestRectIdx, piece, nBestPlacedW, nBestPlacedH, bBestRotated, nKerf)
            else
                # Open a new sheet
                oNewSheet = [
                    :index       = len(aSheets) + 1,
                    :placements  = [],
                    :free_rects  = [ [:x = 0.0, :y = 0.0, :w = nSheetW, :h = nSheetH] ]
                ]

                # Check if piece fits normal or rotated in fresh sheet
                bRot = false
                nPlW = pW
                nPlH = pH
                if pW > nSheetW or pH > nSheetH {
                    if piece[:can_rotate] and pH <= nSheetW and pW <= nSheetH {
                        bRot = true
                        nPlW = pH
                        nPlH = pW
                    }
                }

                placeInSheet(oNewSheet, 1, piece, nPlW, nPlH, bRot, nKerf)
                aSheets + oNewSheet
            }
        }

        return oProblem.evaluateLayout(aSheets)
    }

    private

    func placeInSheet(sheet, nRectIdx, piece, nPlacedW, nPlacedH, bRotated, nKerf) {
        fr = sheet[:free_rects][nRectIdx]
        del(sheet[:free_rects], nRectIdx)

        # Record placement coordinates
        sheet[:placements] + [
            :id      = piece[:id],
            :x       = fr[:x],
            :y       = fr[:y],
            :w       = nPlacedW,
            :h       = nPlacedH,
            :rotated = bRotated
        ]

        # Guillotine Cut Split (Shorter Axis Split heuristic)
        nRemW = fr[:w] - nPlacedW - nKerf
        nRemH = fr[:h] - nPlacedH - nKerf

        # Add split free rectangles if they have positive dimensions
        if nRemW > 0 and nPlacedH > 0 {
            sheet[:free_rects] + [
                :x = fr[:x] + nPlacedW + nKerf,
                :y = fr[:y],
                :w = nRemW,
                :h = nPlacedH
            ]
        }

        if nRemH > 0 and fr[:w] > 0 {
            sheet[:free_rects] + [
                :x = fr[:x],
                :y = fr[:y] + nPlacedH + nKerf,
                :w = fr[:w],
                :h = nRemH
            ]
        }
    }

    func sortPiecesByArea(aPieces) {
        # Standard Bubble/Insertion sort for descending area
        nLen = len(aPieces)
        for nI = 1 to nLen {
            for nJ = nI + 1 to nLen {
                if aPieces[nJ][:area] > aPieces[nI][:area] {
                    tmp = aPieces[nI]
                    aPieces[nI] = aPieces[nJ]
                    aPieces[nJ] = tmp
                }
            }
        }
        return aPieces
    }
