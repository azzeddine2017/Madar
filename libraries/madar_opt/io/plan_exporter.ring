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
