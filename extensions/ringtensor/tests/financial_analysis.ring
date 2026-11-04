load "ringml.ring"

# ============================================================
#  Financial Analysis: Massive Stock Market Simulation
#  Task: Calculate Correlation Matrix for Portfolio Optimization
# ============================================================
/*
We will simulate the following:
Data: 500 stocks × 2000 trading days (approximately 8 years of data). Total: 1 million data points.
Task: To calculate the "correlation matrix" to determine the relationship between each stock and the others.
Process: Requires multiplying a huge matrix by itself (R^T × R), 
a process that would kill regular scripting languages, but RingTensor will handle it.
*/

# Output:
/*
λ ring  financial_analysis.ring
============================================================
   High-Frequency Trading Simulation
   Matrix Size: 2000 Days x 500 Stocks
   Total Data Points: 1000000
============================================================
[1] Generating synthetic stock prices... Done in 55.9700 ms
[2] Calculating Daily Returns (Vectorized)... Done in 28.5700 ms
[3] Computing Correlation Matrix (500x500)... Done in 0.2611
    > Performance: 1.9151 MFLOPS (Approx)

--- Market Analysis Sample ---
Correlation of Stock #1 with others:
   Stock 1 vs Stock 1 : 0.0878 [Positive (+)]
   Stock 1 vs Stock 2 : 0.0033 [Neutral]
   Stock 1 vs Stock 3 : 0.0021 [Neutral]
   Stock 1 vs Stock 4 : 0.0044 [Neutral]
   Stock 1 vs Stock 5 : 0.0011 [Neutral]
*/

decimals(4)
func main
    
    # 1. Configuration
    nStocks = 500     # Number of Assets (e.g., S&P 500)
    nDays   = 2000    # Time Series Length (~8 Years)
    oTime = new QalamChronos()
    
    ? copy("=", 60)
    ? "   High-Frequency Trading Simulation"
    ? "   Matrix Size: " + nDays + " Days x " + nStocks + " Stocks"
    ? "   Total Data Points: " + (nDays * nStocks)
    ? copy("=", 60)

    # ---------------------------------------------------------
    # 2. Data Generation (Monte Carlo Simulation)
    # ---------------------------------------------------------
    see "[1] Generating synthetic stock prices..." 
    oTime.reset()
    
    # Random prices between 100.0 and 200.0
    oPrices = new Tensor(nDays, nStocks)
    oPrices.random()          # 0..1
    oPrices.scalarMul(100.0) # 0..100
    oPrices.addScalar(100.0) # 100..200
    
    ? " Done in " + oTime.elapsed()

    # ---------------------------------------------------------
    # 3. Calculate Daily Returns (Percentage Change)
    # Formula: R_t = (Price_t - Price_{t-1}) / Price_{t-1}
    # ---------------------------------------------------------
    see "[2] Calculating Daily Returns (Vectorized)..."
    oTime.reset()
    
    # Slice Days 2 to N (Today)
    oToday = oPrices.sliceRows(2, nDays - 1)
    
    # Slice Days 1 to N-1 (Yesterday)
    oYesterday = oPrices.sliceRows(1, nDays - 1)
    
    # Calculate Change: (Today - Yesterday)
    # Note: We copy Today first to preserve data if needed, or modify in place
    oDiff = oToday.copy()
    oDiff.sub(oYesterday)
    
    # Calculate Percentage: Diff / Yesterday
    oReturns = oDiff
    oReturns.div(oYesterday) 
    
    # Result is now (1999 x 500) matrix of returns
    ? " Done in " + oTime.elapsed()

    # ---------------------------------------------------------
    # 4. Compute Correlation Matrix (The Heavy Lifting)
    # Formula: Covariance ~ (R^T * R) 
    # Operation: (500 x 1999) * (1999 x 500) -> (500 x 500)
    # ---------------------------------------------------------
    see "[3] Computing Correlation Matrix (500x500)..."
    oTime.reset()
    
    # Transpose the Returns Matrix
    oReturnsT = oReturns.transpose()
    
    # Matrix Multiplication (This utilizes all CPU Cores via OpenMP)
    oCorrelation = oReturnsT.matmul(oReturns)
    
    # Normalize (Optional simplified step for demo)
    # Divide by number of days to get average covariance
    oCorrelation.scalarMul(1.0 / (nDays - 1))
    time_taken = oTime.elapsed_ns() / 1000000000
    ? " Done in " + time_taken
    ? "    > Performance: " + (nStocks*nStocks*nDays / time_taken / 1000000000) + " MFLOPS (Approx)"

    # ---------------------------------------------------------
    # 5. Analysis Results
    # ---------------------------------------------------------
    ? nl + "--- Market Analysis Sample ---"
    
    # Let's see correlation between Stock #1 and first 5 stocks
    # 1.0 means perfect correlation (itself), 0.0 means no correlation
    ? "Correlation of Stock #1 with others:"
    
    for i = 1 to 5
        val = oCorrelation.getVal(1, i)
        
        # Determine relationship
        cRel = "Neutral"
        if val > 0.05 cRel = "Positive (+)" ok
        if val < -0.01 cRel = "Negative (-)" ok
        
        ? "   Stock 1 vs Stock " + i + " : " + (floor(val*10000)/10000) + " [" + cRel + "]"
    next