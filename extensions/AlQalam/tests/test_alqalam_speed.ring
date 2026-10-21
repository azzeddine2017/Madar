/*
    Project: Jabr
    File: test_alqalam_speed.ring
    Author: Code Gear-1
    Description: Performance Benchmark (Ring Native vs. AlQalam C++)
*/

load "alqalam.ring"


# --- Configuration ---
nVectorItems    = 1000000   # 1 Million Numbers
nStringLoops    = 20000     # 20k String Appends
nMapLookups     = 10000     # 10k Dictionary Searches

func main
    oTime = new QalamChronos()

    printHeader("BENCHMARK STARTED")
    ? "Qalam Time: " + oTime.elapsed()
    see "Vector Size : " + nVectorItems + nl
    see "String Ops  : " + nStringLoops + nl
    see "Map Lookups : " + nMapLookups + nl
    # =============================================================
    # TEST 1: VECTOR MATH (Scaling values)
    # =============================================================
    printHeader("1. VECTOR MATH (Multiply x 2)")

    # --- A. Ring Native List ---
    aList = list(nVectorItems)
    # Fill list first
    for i = 1 to nVectorItems 
        aList[i] = 1.0 
    next

    

    see "Running Ring List Loop..." + nl
    oTime.reset()

    
    # Ring Loop (Interpreter overhead per item)
    for i = 1 to nVectorItems
        aList[i] *= 2.0
    next
    
    nTimeRing = oTime.elapsed_ns() 
    printResult("Ring List", nTimeRing)

    # --- B. AlQalam Vector ---
    oVec = new QalamVector(nVectorItems)
    oVec.flood(1.0) # Fast fill

    see "Running AlQalam C++ Loop..." + nl
    oTime.reset()
    
    # C++ Loop (SIMD Optimized)
    oVec.amplify(2.0)
    
    nTimeQalam = oTime.elapsed_ns()
    printResult("QalamVector", nTimeQalam)

    calcSpeedup(nTimeRing, nTimeQalam )

    # =============================================================
    # TEST 2: STRING CONCATENATION (Building Text)
    # =============================================================
    printHeader("2. STRING BUILDING (Append)")

    cChunk = "Data_"

    # --- A. Ring Native String ---
    cStr = ""
    see "Running Ring String Append..." + nl
    oTime.reset()
    
    for i = 1 to nStringLoops
        # Creates a new string object in memory every iteration
        cStr += cChunk 
    next
    
    nTimeRing = oTime.elapsed_ns()
    printResult("Ring String", nTimeRing)

    # --- B. AlQalam Ink ---
    oInk = new QalamInk()
    see "Running QalamInk Append..." + nl
    oTime.reset()
    
    for i = 1 to nStringLoops
        # Appends to reserved memory buffer
        oInk.inscribe(cChunk)
    next
    
    nTimeQalam = oTime.elapsed_ns()
    printResult("QalamInk", nTimeQalam)

    calcSpeedup(nTimeRing, nTimeQalam)
# =============================================================
    # TEST 3: STRING BUILDING (Batch vs Loop)
    # =============================================================
    printHeader("3. STRING BUILDING (Batch Append)")

    # Prepare Data List
    aData = []
    for i=1 to nStringLoops aData + "Data_" next
    
    see "Data Size: " + len(aData) + " strings" + nl

    # --- A. Ring Native String Loop ---
    cStr = ""
    see "Running Ring Loop..." + nl
    oTime.reset()
    
    for x in aData
        cStr += x 
    next
    
    nTimeRing = oTime.elapsed_ns()
    printResult("Ring String", nTimeRing)

    # --- B. AlQalam Batch ---
    oInk = new QalamInk()
    see "Running Qalam Batch..." + nl
    oTime.reset()
    
    # One call does all the work!
    oInk.inscribeBatch(aData)
    
    nTimeQalam = oTime.elapsed_ns()
    printResult("QalamInk (Batch)", nTimeQalam)

    calcSpeedup(nTimeRing, nTimeQalam)

    # =============================================================
    # TEST 4: DICTIONARY LOOKUP (Search)
    # =============================================================
    printHeader("4. DICTIONARY SEARCH (O(N) vs O(1))")
    
    # We search for the LAST item to simulate worst-case for Linear Search
    cTargetKey = "key_" + nMapLookups

    # --- A. Ring List (Linear Search) ---
    aMapList = []
    # Prepare Data
    for i = 1 to nMapLookups
        aMapList + ("key_" + i)
    next
    
    see "Running Ring Find()..." + nl
    oTime.reset()
    
    # Linear Search O(N)
    for i = 1 to nMapLookups
        # Searching for the item (worst case)
        # Note: Ring's find() is C-optimized but linear
        nIdx = find(aMapList, cTargetKey)
    next
    
    nTimeRing =   oTime.elapsed_ns()
    printResult("Ring Find", nTimeRing)

    # --- B. AlQalam Index (Hash Map) ---
    oIndex = new QalamIndex()
    # Prepare Data
    for i = 1 to nMapLookups
        oIndex.define("key_" + i, i)
    next

    see "Running QalamIndex Get()..." + nl
    oTime.reset()
    
    # Hash Search O(1)
    for i = 1 to nMapLookups
        nVal = oIndex.recall(cTargetKey)
    next
    
    nTimeQalam = oTime.elapsed_ns()
    printResult("QalamIndex", nTimeQalam)

    calcSpeedup(nTimeRing, nTimeQalam)

    see nl + "==================================================" + nl
    see "TEST COMPLETE." + nl



# --- Helper Functions ---

func printHeader cTitle
    see nl
    see copy("=", 60) + nl
    see "  " + cTitle + nl
    see copy("=", 60) + nl

func printResult cName, nTime
    see "  > " + cName + " Time : " + nTime + " ns" + nl

func calcSpeedup nTimeRing, nTimeQalam
    if nTimeQalam = 0 nTimeQalam = 0.0001 ok # Avoid division by zero
    
    nSpeedup = floor(nTimeRing / nTimeQalam)
    
    see nl
    if nSpeedup > 1
        see "  >>> RESULT: AlQalam is " + nSpeedup + "x FASTER! 🚀" + nl
    else
        see "  >>> RESULT: Speeds are similar." + nl
    ok


	"
λ ring test_alqalam_speed.ring                                    
                                                                  
============================================================      
  BENCHMARK STARTED                                               
============================================================      
Vector Size : 1000000                                             
String Ops  : 20000                                               
Map Lookups : 10000                                               
                                                                  
============================================================      
  1. VECTOR MATH (Multiply x 2)                                   
============================================================      
Running Ring List Loop...                                         
  > Ring List Time : 0.27 seconds                                 
Running AlQalam C++ Loop...                                       
  > QalamVector Time : 0.00 seconds                               
                                                                  
  >>> RESULT: AlQalam is 271x FASTER! 🚀                          
                                                                  
============================================================      
  2. STRING BUILDING (Append)                                     
============================================================      
Running Ring String Append...                                     
  > Ring String Time : 0.01 seconds                               
Running QalamInk Append...                                        
  > QalamInk Time : 0.05 seconds                                  
                                                                  
  >>> RESULT: Speeds are similar.                                 
                                                                  
============================================================      
  3. STRING BUILDING (Batch Append)                               
============================================================      
Data Size: 20000 strings                                          
Running Ring Loop...                                              
  > Ring String Time : 0.02 seconds                               
Running Qalam Batch...                                            
  > QalamInk (Batch) Time : 0.00 seconds                          
                                                                  
  >>> RESULT: AlQalam is 17x FASTER! 🚀                           
                                                                  
============================================================      
  4. DICTIONARY SEARCH (O(N) vs O(1))                             
============================================================      
Running Ring Find()...                                            
  > Ring Find Time : 2.39 seconds                                 
Running QalamIndex Get()...                                       
  > QalamIndex Time : 0.03 seconds                                
                                                                  
  >>> RESULT: AlQalam is 79x FASTER! 🚀                           
                                                                  
==================================================                
TEST COMPLETE.                                                    
                                                                                                                     
" 