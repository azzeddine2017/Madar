/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: I/O - Enterprise Data Ingestion (CSV / Orders)
* Description: Ingests production work orders, ERP cutting lists, and raw stock inventories.
*/

load "stdlibcore.ring"

class OptDataLoader

    /*
    * Function: loadOrdersCSV
    * Description: Reads CSV file containing manufacturing cutting orders.
    * Expected format:
    * item_id,length,quantity
    * P101,2450.0,10
    * Inputs: cFilePath (String)
    * Outputs: List of Numbers (Expanded individual piece lengths)
    */
    func loadOrdersCSV(cFilePath) {
        if !fexists(cFilePath) {
            ? f"[MadarOpt Error] Orders file not found: {cFilePath}"
            return []
        }

        cContent = read(cFilePath)
        aLines = split(cContent, nl)
        aExpandedDemands = []

        nLineCount = len(aLines)
        for nL = 1 to nLineCount {
            cLine = trim(aLines[nL])
            # Skip empty lines and comment/header lines
            if len(cLine) = 0 or substr(cLine, "#") = 1 {
                continue
            }

            aParts = split(cLine, ",")
            if len(aParts) >= 2 {
                # Check if line is header (e.g. "item_id,length...")
                cFirst = lower(trim(aParts[1]))
                if cFirst = "item_id" or cFirst = "id" or cFirst = "length" {
                    continue
                }

                # Try parsing columns: [item_id, length, quantity] or [length, quantity]
                nLength = 0.0
                nQty    = 1

                if len(aParts) >= 3 {
                    nLength = 0.0 + trim(aParts[2])
                    nQty    = 0 + trim(aParts[3])
                else
                    nLength = 0.0 + trim(aParts[1])
                    nQty    = 0 + trim(aParts[2])
                }

                if nLength > 0 and nQty > 0 {
                    for nQ = 1 to nQty {
                        aExpandedDemands + nLength
                    }
                }
            }
        }

        return aExpandedDemands
    }
