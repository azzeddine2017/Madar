/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: I/O - Plan & Artifact Exporter
* Description: Exports production-ready deterministic cutting schedules to CSV and JSON
* for ERP, MES, and CNC machines.
*/

class OptPlanExporter

    /*
    * Function: exportCSV
    * Description: Writes an actionable shopfloor cutting table to CSV.
    * Columns: Bar_Index, Piece_Count, Total_Used_mm, Scrap_Waste_mm, Waste_Percent, Cutting_Pattern
    * Inputs: aSolution (Map), cOutputPath (String), nStockLength, nKerf
    */
    func exportCSV(aSolution, cOutputPath, nStockLength, nKerf) {
        aBins = aSolution[:bins]
        nBinsCount = len(aBins)

        cOut = "Bar_Index,Piece_Count,Total_Used_mm,Scrap_Waste_mm,Waste_Percent,Cutting_Pattern" + nl

        for nB = 1 to nBinsCount {
            aItems = aBins[nB]
            nCount = len(aItems)

            nUsed = 0.0
            cPattern = ""
            for nK = 1 to nCount {
                nUsed += aItems[nK]
                if nK > 1 {
                    cPattern += " + "
                }
                cPattern += "" + aItems[nK]
            }

            if nCount > 1 and nKerf > 0 {
                nUsed += (nCount - 1) * nKerf
            }

            nScrap = nStockLength - nUsed
            nWastePct = 0.0
            if nStockLength > 0 {
                nWastePct = (nScrap / nStockLength) * 100.0
            }

            cLine = "" + nB + "," + nCount + "," + nUsed + "," + nScrap + "," + nWastePct + ",'" + cPattern + "'" + nl
            cOut += cLine
        }

        write(cOutputPath, cOut)
        return true
    }

    /*
    * Function: exportJSON
    * Description: Writes standard JSON schema representation of the cutting schedule.
    * Inputs: aSolution (Map), cOutputPath (String), nStockLength, nKerf
    */
    func exportJSON(aSolution, cOutputPath, nStockLength, nKerf) {
        cQ = char(34)
        aBins = aSolution[:bins]
        nBinsCount = len(aBins)

        cJSON = "{" + nl
        cJSON += '  ' + cQ + 'engine' + cQ + ': ' + cQ + 'MadarOpt 0.1.0-alpha' + cQ + ',' + nl
        cJSON += '  ' + cQ + 'summary' + cQ + ': {' + nl
        cJSON += '    ' + cQ + 'bars_used' + cQ + ': ' + aSolution[:bars_used] + ',' + nl
        cJSON += '    ' + cQ + 'theoretical_minimum' + cQ + ': ' + aSolution[:theoretical_min] + ',' + nl
        cJSON += '    ' + cQ + 'total_stock_mm' + cQ + ': ' + aSolution[:total_stock_mm] + ',' + nl
        cJSON += '    ' + cQ + 'total_demand_mm' + cQ + ': ' + aSolution[:total_demand_mm] + ',' + nl
        cJSON += '    ' + cQ + 'total_waste_mm' + cQ + ': ' + aSolution[:total_waste_mm] + ',' + nl
        cJSON += '    ' + cQ + 'waste_percentage' + cQ + ': ' + aSolution[:waste_percentage] + nl
        cJSON += '  },' + nl
        cJSON += '  ' + cQ + 'cutting_schedule' + cQ + ': [' + nl

        for nB = 1 to nBinsCount {
            aItems = aBins[nB]
            nCount = len(aItems)

            nUsed = 0.0
            cItemsArr = "["
            for nK = 1 to nCount {
                nUsed += aItems[nK]
                if nK > 1 {
                    cItemsArr += ", "
                }
                cItemsArr += "" + aItems[nK]
            }
            cItemsArr += "]"

            if nCount > 1 and nKerf > 0 {
                nUsed += (nCount - 1) * nKerf
            }
            nScrap = nStockLength - nUsed

            cJSON += '    {' + nl
            cJSON += '      ' + cQ + 'bar_index' + cQ + ': ' + nB + ',' + nl
            cJSON += '      ' + cQ + 'piece_count' + cQ + ': ' + nCount + ',' + nl
            cJSON += '      ' + cQ + 'total_used_mm' + cQ + ': ' + nUsed + ',' + nl
            cJSON += '      ' + cQ + 'scrap_mm' + cQ + ': ' + nScrap + ',' + nl
            cJSON += '      ' + cQ + 'cuts' + cQ + ': ' + cItemsArr + nl

            if nB < nBinsCount {
                cJSON += '    },' + nl
            else
                cJSON += '    }' + nl
            }
        }

        cJSON += '  ]' + nl
        cJSON += '}' + nl

        write(cOutputPath, cJSON)
        return true
    }

    /*
    * Function: exportLayout2DCSV
    * Description: Writes 2D rectangular sheet layout coordinates to CSV.
    * Columns: Sheet_Index,Piece_ID,X,Y,Width,Height,Rotated
    * Inputs: aSolution (Map), cOutputPath (String)
    */
    func exportLayout2DCSV(aSolution, cOutputPath) {
        aSheets = aSolution[:sheets]
        nSheetsCount = len(aSheets)

        cOut = "Sheet_Index,Piece_ID,X,Y,Width,Height,Rotated" + nl

        for nS = 1 to nSheetsCount {
            sheet = aSheets[nS]
            aPlacements = sheet[:placements]
            nPlCount = len(aPlacements)

            for nP = 1 to nPlCount {
                pl = aPlacements[nP]
                cRot = "0"
                if pl[:rotated] {
                    cRot = "1"
                }
                cLine = "" + nS + "," + pl[:id] + "," + pl[:x] + "," + pl[:y] + "," + pl[:w] + "," + pl[:h] + "," + cRot + nl
                cOut += cLine
            }
        }

        write(cOutputPath, cOut)
        return true
    }

    /*
    * Function: exportLayout2DJSON
    * Description: Writes 2D nesting layout to structured JSON.
    * Inputs: aSolution (Map), cOutputPath (String)
    */
    func exportLayout2DJSON(aSolution, cOutputPath) {
        cQ = char(34)
        aSheets = aSolution[:sheets]
        nSheetsCount = len(aSheets)

        cJSON = "{" + nl
        cJSON += '  ' + cQ + 'engine' + cQ + ': ' + cQ + 'MadarOpt 0.1.0-alpha' + cQ + ',' + nl
        cJSON += '  ' + cQ + 'summary' + cQ + ': {' + nl
        cJSON += '    ' + cQ + 'sheets_used' + cQ + ': ' + aSolution[:sheets_used] + ',' + nl
        cJSON += '    ' + cQ + 'theoretical_min' + cQ + ': ' + aSolution[:theoretical_min] + ',' + nl
        cJSON += '    ' + cQ + 'total_stock_area' + cQ + ': ' + aSolution[:total_stock_area] + ',' + nl
        cJSON += '    ' + cQ + 'total_demand_area' + cQ + ': ' + aSolution[:total_demand_area] + ',' + nl
        cJSON += '    ' + cQ + 'total_scrap_area' + cQ + ': ' + aSolution[:total_scrap_area] + ',' + nl
        cJSON += '    ' + cQ + 'waste_percentage' + cQ + ': ' + aSolution[:waste_percentage] + nl
        cJSON += '  },' + nl
        cJSON += '  ' + cQ + 'sheets' + cQ + ': [' + nl

        for nS = 1 to nSheetsCount {
            sheet = aSheets[nS]
            aPlacements = sheet[:placements]
            nPlCount = len(aPlacements)

            cJSON += '    {' + nl
            cJSON += '      ' + cQ + 'sheet_index' + cQ + ': ' + nS + ',' + nl
            cJSON += '      ' + cQ + 'piece_count' + cQ + ': ' + nPlCount + ',' + nl
            cJSON += '      ' + cQ + 'placements' + cQ + ': [' + nl

            for nP = 1 to nPlCount {
                pl = aPlacements[nP]
                cRot = "false"
                if pl[:rotated] {
                    cRot = "true"
                }

                cJSON += '        {' + nl
                cJSON += '          ' + cQ + 'id' + cQ + ': ' + cQ + pl[:id] + cQ + ',' + nl
                cJSON += '          ' + cQ + 'x' + cQ + ': ' + pl[:x] + ',' + nl
                cJSON += '          ' + cQ + 'y' + cQ + ': ' + pl[:y] + ',' + nl
                cJSON += '          ' + cQ + 'w' + cQ + ': ' + pl[:w] + ',' + nl
                cJSON += '          ' + cQ + 'h' + cQ + ': ' + pl[:h] + ',' + nl
                cJSON += '          ' + cQ + 'rotated' + cQ + ': ' + cRot + nl

                if nP < nPlCount {
                    cJSON += '        },' + nl
                else
                    cJSON += '        }' + nl
                }
            }

            cJSON += '      ]' + nl
            if nS < nSheetsCount {
                cJSON += '    },' + nl
            else
                cJSON += '    }' + nl
            }
        }

        cJSON += '  ]' + nl
        cJSON += '}' + nl

        write(cOutputPath, cJSON)
        return true
    }
