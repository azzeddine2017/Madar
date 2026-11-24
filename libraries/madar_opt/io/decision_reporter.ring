/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: I/O - Decision Reporter
* Description: Exports multi-scenario comparison tables (CSV) and executive briefs (JSON)
* to dedicated output directories.
*/

class OptDecisionReporter

    /*
    * Function: exportComparisonCSV
    * Description: Generates side-by-side comparison CSV for all simulated scenarios.
    * Inputs: aMatrix (Decision Matrix Map), cOutputPath (String)
    */
    func exportComparisonCSV(aMatrix, cOutputPath) {
        aEvals = aMatrix[:evaluations]
        nTotal = len(aEvals)

        cOut = "Scenario_ID,Name,Supplier,Stock_mm,Unit_Price_USD,Bars_Used,Total_Waste_mm,Waste_Percent,Total_Cost_USD,Cost_Delta_USD,Savings_Percent,Latency_ms,Status" + nl

        cWinner = aMatrix[:recommended_winner]

        for nI = 1 to nTotal {
            e = aEvals[nI]
            cStatus = "Alternative"
            if e[:id] = cWinner {
                cStatus = "RECOMMENDED_WINNER"
            elseif e[:cost_delta_usd] = 0.0
                cStatus = "BASELINE"
            }

            nSavingsPct = -1.0 * e[:cost_delta_percent]

            cLine = "" + e[:id] + ",'" + e[:name] + "','" + e[:supplier] + "'," + e[:stock_length_mm] + "," + e[:price_per_bar_usd] + "," + e[:bars_used] + "," + e[:total_waste_mm] + "," + e[:waste_percentage] + "," + e[:total_cost_usd] + "," + e[:cost_delta_usd] + "," + nSavingsPct + "," + e[:latency_ms] + "," + cStatus + nl
            cOut += cLine
        }

        write(cOutputPath, cOut)
        return true
    }

    /*
    * Function: exportExecutiveBriefJSON
    * Description: Generates C-suite and ERP-ready JSON executive decision brief.
    * Inputs: aMatrix (Decision Matrix Map), cOutputPath (String)
    */
    func exportExecutiveBriefJSON(aMatrix, cOutputPath) {
        cQ = char(34)
        aEvals = aMatrix[:evaluations]
        nTotal = len(aEvals)
        cWinner = aMatrix[:recommended_winner]

        cJSON = "{" + nl
        cJSON += '  ' + cQ + 'decision_intelligence_report' + cQ + ': {' + nl
        cJSON += '    ' + cQ + 'project' + cQ + ': ' + cQ + aMatrix[:project] + cQ + ',' + nl
        cJSON += '    ' + cQ + 'baseline_scenario_id' + cQ + ': ' + cQ + aMatrix[:baseline_scenario_id] + cQ + ',' + nl
        cJSON += '    ' + cQ + 'recommended_winner' + cQ + ': ' + cQ + cWinner + cQ + ',' + nl
        cJSON += '    ' + cQ + 'cheapest_scenario' + cQ + ': ' + cQ + aMatrix[:cheapest_scenario] + cQ + ',' + nl
        cJSON += '    ' + cQ + 'greenest_scenario' + cQ + ': ' + cQ + aMatrix[:greenest_scenario] + cQ + ',' + nl
        cJSON += '    ' + cQ + 'total_linear_demand_mm' + cQ + ': ' + aMatrix[:total_demand_mm] + ',' + nl
        cJSON += '    ' + cQ + 'total_pieces_demanded' + cQ + ': ' + aMatrix[:demanded_pieces] + ',' + nl
        cJSON += '    ' + cQ + 'scenarios_evaluated' + cQ + ': ' + aMatrix[:scenarios_count] + nl
        cJSON += '  },' + nl
        cJSON += '  ' + cQ + 'scenarios' + cQ + ': [' + nl

        for nI = 1 to nTotal {
            e = aEvals[nI]
            cJSON += '    {' + nl
            cJSON += '      ' + cQ + 'id' + cQ + ': ' + cQ + e[:id] + cQ + ',' + nl
            cJSON += '      ' + cQ + 'name' + cQ + ': ' + cQ + e[:name] + cQ + ',' + nl
            cJSON += '      ' + cQ + 'supplier' + cQ + ': ' + cQ + e[:supplier] + cQ + ',' + nl
            cJSON += '      ' + cQ + 'stock_length_mm' + cQ + ': ' + e[:stock_length_mm] + ',' + nl
            cJSON += '      ' + cQ + 'price_per_bar_usd' + cQ + ': ' + e[:price_per_bar_usd] + ',' + nl
            cJSON += '      ' + cQ + 'bars_used' + cQ + ': ' + e[:bars_used] + ',' + nl
            cJSON += '      ' + cQ + 'total_waste_mm' + cQ + ': ' + e[:total_waste_mm] + ',' + nl
            cJSON += '      ' + cQ + 'waste_percentage' + cQ + ': ' + e[:waste_percentage] + ',' + nl
            cJSON += '      ' + cQ + 'total_cost_usd' + cQ + ': ' + e[:total_cost_usd] + ',' + nl
            cJSON += '      ' + cQ + 'cost_delta_usd' + cQ + ': ' + e[:cost_delta_usd] + ',' + nl
            cJSON += '      ' + cQ + 'latency_ms' + cQ + ': ' + e[:latency_ms] + nl

            if nI < nTotal {
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
