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

    /*
    * Function: loadOrders2DCSV
    * Description: Reads CSV file containing 2D rectangular manufacturing cutting orders.
    * Expected format:
    * item_id,width,height,quantity,can_rotate
    * G101,800.0,600.0,4,1
    * Inputs: cFilePath (String)
    * Outputs: List of Piece Maps
    */
    func loadOrders2DCSV(cFilePath) {
        if !fexists(cFilePath) {
            ? f"[MadarOpt Error] 2D Orders file not found: {cFilePath}"
            return []
        }

        cContent = read(cFilePath)
        aLines = split(cContent, nl)
        aPieces = []

        nLineCount = len(aLines)
        for nL = 1 to nLineCount {
            cLine = trim(aLines[nL])
            if len(cLine) = 0 or substr(cLine, "#") = 1 {
                continue
            }

            aParts = split(cLine, ",")
            if len(aParts) >= 3 {
                cFirst = lower(trim(aParts[1]))
                if cFirst = "item_id" or cFirst = "id" or cFirst = "width" {
                    continue
                }

                cID   = trim(aParts[1])
                nW    = 0.0 + trim(aParts[2])
                nH    = 0.0 + trim(aParts[3])
                nQty  = 1
                bRot  = true

                if len(aParts) >= 4 {
                    nQty = 0 + trim(aParts[4])
                }
                if len(aParts) >= 5 {
                    bRot = (trim(aParts[5]) = "1" or lower(trim(aParts[5])) = "true")
                }

                if nW > 0 and nH > 0 and nQty > 0 {
                    aPieces + [
                        :id         = cID,
                        :w          = nW,
                        :h          = nH,
                        :qty        = nQty,
                        :can_rotate = bRot
                    ]
                }
            }
        }

        return aPieces
    }
