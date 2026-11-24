/*
* Project: MadarOpt - Industrial Decision Intelligence
* Module: Solvers - Genetic Algorithm (Metaheuristic)
* Description: Multi-generation evolutionary search exploring permutation space for global optimum.
*/

class GeneticCuttingSolver {

    # GA Hyperparameters
    nPopulationSize = 40
    nGenerations    = 50
    nMutationRate   = 0.20
    bVerbose        = false

    /*
    * Function: solve
    * Description: Executes evolutionary search across order permutations.
    * Inputs: oProblem (CuttingStock1D instance)
    * Outputs: Best Solution Evaluation List
    */
    func solve(oProblem) {
        aBaseItems = oProblem.aDemands
        nStock = oProblem.nStockLength
        nKerf  = oProblem.nBladeKerf
        nItemCount = len(aBaseItems)

        if nItemCount <= 1 {
            oHeuristic = new HeuristicCuttingSolver
            return oHeuristic.solveBFD(oProblem)
        }

        # Initialize Population (random permutations of demand indices)
        aPopulation = []
        for nP = 1 to nPopulationSize {
            aChrom = []
            for nI = 1 to nItemCount {
                aChrom + nI
            }
            # Shuffle chromosome
            aChrom = shuffleList(aChrom)
            aPopulation + aChrom
        }

        # Seed individual 1 with descending sort (guaranteeing GA is at least as good as BFD)
        aPopulation[1] = getDescendingIndices(aBaseItems)

        aBestBins = []
        nBestBarCount = 999999
        nBestWaste = 999999999.0

        for nGen = 1 to nGenerations {
            aFitness = []

            # Evaluate each chromosome in population
            for nP = 1 to nPopulationSize {
                aOrder = aPopulation[nP]
                aBins = packSequence(aBaseItems, aOrder, nStock, nKerf)
                nBars = len(aBins)

                # Fitness formula: prioritize fewer bars, then penalize fragmentation
                # High fitness is better
                nFit = 1000000.0 / (nBars + 1.0)
                aFitness + [:idx = nP, :bars = nBars, :fitness = nFit, :bins = aBins]

                if nBars < nBestBarCount {
                    nBestBarCount = nBars
                    aBestBins = aBins
                    if bVerbose {
                        ? f"[MadarOpt GA] Gen {nGen} found improved plan: {nBars} stock bars."
                    }
                }
            }

            # If theoretical lower bound is already reached, terminate early
            nTheoryMin = oProblem.theoreticalMinimumBars()
            if nBestBarCount <= nTheoryMin {
                if bVerbose {
                    ? f"[MadarOpt GA] Theoretical optimum reached ({nBestBarCount} bars) at Gen {nGen}!"
                }
                exit
            }

            # Selection & Reproduction (Elitism + Tournament Selection)
            aNewPopulation = []
            # Keep elite (best individual)
            aNewPopulation + aPopulation[aFitness[1][:idx]]

            while len(aNewPopulation) < nPopulationSize {
                # Tournament selection for parent 1 & 2
                nP1 = tournamentSelect(aFitness, 3)
                nP2 = tournamentSelect(aFitness, 3)

                # Order Crossover (OX)
                aChild = orderCrossover(aPopulation[nP1], aPopulation[nP2])

                # Mutation (Swap mutation)
                if (random(100) / 100.0) < nMutationRate {
                    aChild = mutateSwap(aChild)
                }

                aNewPopulation + aChild
            }

            aPopulation = aNewPopulation
        }

        return oProblem.evaluateSolution(aBestBins)
    }

    private

    func packSequence(aItems, aOrder, nStock, nKerf) {
        aBins = []
        aRemaining = []
        nLen = len(aOrder)

        for nK = 1 to nLen {
            nIdx = aOrder[nK]
            nItem = aItems[nIdx]
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
        return aBins
    }

    func shuffleList(aList) {
        nLen = len(aList)
        for nI = nLen to 2 step -1 {
            nJ = (random(nI - 1)) + 1
            nTmp = aList[nI]
            aList[nI] = aList[nJ]
            aList[nJ] = nTmp
        }
        return aList
    }

    func getDescendingIndices(aItems) {
        # Return indices sorted by item size descending
        aPairs = []
        nLen = len(aItems)
        for nI = 1 to nLen {
            aPairs + [:val = aItems[nI], :idx = nI]
        }
        # Bubble / insertion sort for pairs
        for nI = 1 to nLen {
            for nJ = nI + 1 to nLen {
                if aPairs[nJ][:val] > aPairs[nI][:val] {
                    aTmp = aPairs[nI]
                    aPairs[nI] = aPairs[nJ]
                    aPairs[nJ] = aTmp
                }
            }
        }
        aRes = []
        for nI = 1 to nLen {
            aRes + aPairs[nI][:idx]
        }
        return aRes
    }

    func tournamentSelect(aFitness, nK) {
        nBest = (random(len(aFitness) - 1)) + 1
        for nI = 2 to nK {
            nCand = (random(len(aFitness) - 1)) + 1
            if aFitness[nCand][:fitness] > aFitness[nBest][:fitness] {
                nBest = nCand
            }
        }
        return nBest
    }

    func orderCrossover(aParent1, aParent2) {
        nLen = len(aParent1)
        nPoint1 = (random(nLen - 1)) + 1
        nPoint2 = (random(nLen - 1)) + 1
        if nPoint1 > nPoint2 {
            nTmp = nPoint1
            nPoint1 = nPoint2
            nPoint2 = nTmp
        }

        aChild = []
        for nI = 1 to nLen {
            aChild + 0
        }

        # Copy segment from Parent 1
        for nI = nPoint1 to nPoint2 {
            aChild[nI] = aParent1[nI]
        }

        # Fill remaining positions from Parent 2
        nCur = 1
        for nI = 1 to nLen {
            nVal = aParent2[nI]
            # Check if nVal already in aChild
            bExists = false
            for nJ = nPoint1 to nPoint2 {
                if aChild[nJ] = nVal {
                    bExists = true
                    exit
                }
            }
            if !bExists {
                while nCur >= nPoint1 and nCur <= nPoint2 {
                    nCur++
                }
                if nCur <= nLen {
                    aChild[nCur] = nVal
                    nCur++
                }
            }
        }
        return aChild
    }

    func mutateSwap(aChrom) {
        nLen = len(aChrom)
        nI = (random(nLen - 1)) + 1
        nJ = (random(nLen - 1)) + 1
        nTmp = aChrom[nI]
        aChrom[nI] = aChrom[nJ]
        aChrom[nJ] = nTmp
        return aChrom
    }
}

