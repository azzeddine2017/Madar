/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Core - What-If Scenario Simulation Engine
* Description: Multi-scenario comparative simulation and financial variance analytics
* for enterprise decision intelligence.
*/

load "jsonlib.ring"
load "chronos.ring"

class OptScenarioEngine

    /*
    * Function: simulate
    * Description: Executes multi-scenario simulation across work order demands.
    * Inputs: aDemands (List of Numbers), cScenariosPath (String), cMethod (String)
    * Outputs: Structured Decision Matrix Map
    */
    func simulate(aDemands, cScenariosPath, cMethod) {
        if !fexists(cScenariosPath) {
            ? f"[MadarOpt Error] Scenarios file not found: {cScenariosPath}"
            return []
        }

        cContent = read(cScenariosPath)
        aJSON = JSON2List(cContent)

        cProjectName = ""
        cBaselineID  = ""
        aScenarios   = []

        # Extract top-level attributes from parsed JSON list
        for item in aJSON {
            if isList(item) and len(item) = 2 {
                cKey = lower(item[1])
                if cKey = "project" {
                    cProjectName = item[2]
                elseif cKey = "baseline_scenario_id"
                    cBaselineID = item[2]
                elseif cKey = "scenarios"
                    aScenarios = item[2]
                }
            }
        }

        nScenarioCount = len(aScenarios)
        if nScenarioCount = 0 {
            ? "[MadarOpt Error] No scenarios defined in manifest!"
            return []
        }

        aEvaluations = []
        nBaselineCost = 0.0
        nBaselineWaste = 0.0
        nTotalDemandMm = 0.0

        # Calculate demand sum once
        for d in aDemands {
            nTotalDemandMm += d
        }

        # Step 1: Execute simulation for every candidate scenario
        for s in aScenarios {
            cID     = ""
            cName   = ""
            nStock  = 6000.0
            nPrice  = 45.0
            nKerf   = 4.0
            cSupp   = "Default"
            nLead   = 0

            # Extract scenario properties
            for prop in s {
                if isList(prop) and len(prop) = 2 {
                    cK = lower(prop[1])
                    if cK = "id" {
                        cID = prop[2]
                    elseif cK = "name"
                        cName = prop[2]
                    elseif cK = "stock_length_mm"
                        nStock = 0.0 + prop[2]
                    elseif cK = "price_per_bar_usd"
                        nPrice = 0.0 + prop[2]
                    elseif cK = "blade_kerf_mm"
                        nKerf = 0.0 + prop[2]
                    elseif cK = "supplier"
                        cSupp = prop[2]
                    elseif cK = "lead_time_days"
                        nLead = 0 + prop[2]
                    }
                }
            }

            # Run solver with high-precision hardware timer
            nStartNs = nanotime()
            aSol = madaropt_solve_cutting_stock(nStock, aDemands, nKerf, cMethod)
            nElapsedUs = (nanotime() - nStartNs) / 1000.0
            nElapsedMs = nElapsedUs / 1000.0

            nBars = aSol[:bars_used]
            nTotalStockMm = nBars * nStock
            nWasteMm = nTotalStockMm - nTotalDemandMm
            nWastePct = 0.0
            if nTotalStockMm > 0 {
                nWastePct = (nWasteMm / nTotalStockMm) * 100.0
            }
            nTotalCost = nBars * nPrice

            nCostPerMeter = 0.0
            if nTotalDemandMm > 0 {
                nCostPerMeter = nTotalCost / (nTotalDemandMm / 1000.0)
            }

            aEval = [
                :id                 = cID,
                :name               = cName,
                :supplier           = cSupp,
                :lead_time_days     = nLead,
                :stock_length_mm    = nStock,
                :price_per_bar_usd  = nPrice,
                :blade_kerf_mm      = nKerf,
                :bars_used          = nBars,
                :theoretical_min    = aSol[:theoretical_min],
                :total_waste_mm     = nWasteMm,
                :waste_percentage   = nWastePct,
                :total_cost_usd     = nTotalCost,
                :cost_per_meter_usd = nCostPerMeter,
                :latency_us         = nElapsedUs,
                :latency_ms         = nElapsedMs,
                :solution           = aSol
            ]

            aEvaluations + aEval

            if cID = cBaselineID or len(aEvaluations) = 1 {
                if nBaselineCost = 0.0 {
                    nBaselineCost  = nTotalCost
                    nBaselineWaste = nWasteMm
                    cBaselineID    = cID
                }
            }
        }

        # Step 2: Compute Financial and Waste Variance vs Baseline
        nMinCost = 999999999.0
        nMinWaste = 999999999.0
        cWinnerID = ""
        cCheapestID = ""
        cGreenestID = ""

        nTotalEvals = len(aEvaluations)
        for nI = 1 to nTotalEvals {
            nCost = aEvaluations[nI][:total_cost_usd]
            nWaste = aEvaluations[nI][:waste_percentage]
            cID = aEvaluations[nI][:id]

            nCostDelta = nCost - nBaselineCost
            nCostDeltaPct = 0.0
            if nBaselineCost > 0 {
                nCostDeltaPct = (nCostDelta / nBaselineCost) * 100.0
            }
            nWasteDeltaMm = aEvaluations[nI][:total_waste_mm] - nBaselineWaste

            aEvaluations[nI][:cost_delta_usd]     = nCostDelta
            aEvaluations[nI][:cost_delta_percent] = nCostDeltaPct
            aEvaluations[nI][:waste_delta_mm]     = nWasteDeltaMm

            # Track optimization champions
            if nCost < nMinCost {
                nMinCost = nCost
                cCheapestID = cID
            }
            if nWaste < nMinWaste {
                nMinWaste = nWaste
                cGreenestID = cID
            }
        }

        # Overall Recommendation: default to Cheapest unless waste difference is extreme
        cWinnerID = cCheapestID

        return [
            :project              = cProjectName,
            :baseline_scenario_id = cBaselineID,
            :total_demand_mm      = nTotalDemandMm,
            :demanded_pieces      = len(aDemands),
            :scenarios_count      = nTotalEvals,
            :recommended_winner   = cWinnerID,
            :cheapest_scenario    = cCheapestID,
            :greenest_scenario    = cGreenestID,
            :evaluations          = aEvaluations
        ]
    }
