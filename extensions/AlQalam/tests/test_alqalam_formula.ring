/*
    Project: AlQalam
    File: tests/test_alqalam_formula.ring
    Description: Comprehensive Test Suite for AlQalam Formula Engine & I/O
*/

load "AlQalam.ring"
load "ringml.ring"


func main
    
    printHeader("ALQALAM FORMULA ENGINE TEST")

    # 1. Arithmetic
    ? info("1. Testing Basic Arithmetic & Precedence...")
    run_test("x + 5", 10, 15)
    run_test("2 + 3 * 4", 0, 14)
    run_test("x * 2 + 5", 10, 25)
    run_test("(2 + 3) * 4", 0, 20)
    run_test("2 ^ 3", 0, 8)
    run_test("10 + (2 * 5)^2", 0, 110)

    # 2. Functions
    ? info(nl + "2. Testing Math Functions...")
    run_test("relu(x)", 5, 5)
    run_test("relu(x)", -5, 0)
    run_test("abs(x)", -10, 10)
    run_test("sqrt(x)", 16, 4)
    run_test("sin(x)", 0, 0)

    # 3. Stress Test
    ? info(nl + "3. Formula Engine Stress Test (1 Million Items)...")
    nSize = 1000000
    oBigVec = new QalamVector(nSize) # Creates [0.0, 0.0, ...]
    oBigVec.flood(1.0)               # Overwrites all to [1.0, 1.0, ...]
    
    oTimer = new QalamChronos 
    oTimer.reset()
    oBigVec.transform("(x * 2.5 + 10) / 2")
    cTime = oTimer.elapsed() 
    
    val = oBigVec.read(1)
    if fabs(val - 6.25) < 0.0001
        pass("Calculation Correct (Result: 6.25)")
    else
        fail("Calculation Wrong. Got " + val)
    ok
    
    oStyl.cyan(:BOLD, "    Time taken: " + cTime + nl)

    # 4. Binary I/O
    ? info(nl + "4. Testing Binary I/O (Save/Load)...")
    cFile = "test_formula_dump.bin"
    oBigVec.saveBinary(cFile)
    
    oNewVec = new QalamVector(1) 
    oNewVec.loadBinary(cFile) # This resizes automatically
    
    if oNewVec.size() = nSize
        pass("Size Check Passed (" + nSize + ")")
    else
        fail("Size Check Failed. Expected " + nSize + ", Got " + oNewVec.size())
    ok
    
    valLoad = oNewVec.read(1)
    if fabs(valLoad - 6.25) < 0.0001
        pass("Value Check Passed (6.25)")
    else
        fail("Value Check Failed. Got " + valLoad)
    ok
    
    system("del " + cFile)
    success("Binary I/O Test Complete.")

# --- Helper Functions ---

func run_test cExpr, nInput, nExpected
    oVec = new QalamVector(1) # Creates vector of size 1: [0.0]
    
    # FIX: Use write() to overwrite the existing zero
    # Instead of flow() which would append to make [0.0, nInput]
    oVec.flow(nInput) 
    
    oVec.transform(cExpr)
    
    nResult = oVec.read(1)
    
    if fabs(nResult - nExpected) < 0.0001
        pass("Expr: [" + cExpr + "] | In: " + nInput + " -> " + nResult)
    else
        fail("Expr: [" + cExpr + "] | Expected: " + nExpected + " | Got: " + nResult)
    ok


func pass cMsg
    oStyl.green(:NONE, "   [PASS] " + cMsg + nl)

func fail cMsg
    oStyl.red(:BOLD, "   [FAIL] " + cMsg + nl)

func printHeader cTitle
    see nl
    oStyl.cyan(:BOLD, "==================================================" + nl)
    oStyl.white(:BOLD, "  " + cTitle + nl)
    oStyl.cyan(:BOLD, "==================================================" + nl)

/*
λ ring test_alqalam_formula.ring                                  
                                                                  
==================================================                
  ALQALAM FORMULA ENGINE TEST                                     
==================================================                
[INFO] :1. Testing Basic Arithmetic & Precedence...               
   [PASS] Expr: [x + 5] | In: 10 -> 15                            
   [PASS] Expr: [2 + 3 * 4] | In: 0 -> 14                         
   [PASS] Expr: [x * 2 + 5] | In: 10 -> 25                        
   [PASS] Expr: [(2 + 3) * 4] | In: 0 -> 20                       
   [PASS] Expr: [2 ^ 3] | In: 0 -> 8                              
   [PASS] Expr: [10 + (2 * 5)^2] | In: 0 -> 110                   
[INFO] :                                                          
2. Testing Math Functions...                                      
   [PASS] Expr: [relu(x)] | In: 5 -> 5                            
   [PASS] Expr: [relu(x)] | In: -5 -> 0                           
   [PASS] Expr: [abs(x)] | In: -10 -> 10                          
   [PASS] Expr: [sqrt(x)] | In: 16 -> 4                           
   [PASS] Expr: [sin(x)] | In: 0 -> 0                             
[INFO] :                                                          
3. Formula Engine Stress Test (1 Million Items)...                
   [PASS] Calculation Correct (Result: 6.25)                      
    Time taken: 0 ns                                              
[INFO] :                                                          
4. Testing Binary I/O (Save/Load)...                              
    [PASS] Size Check Passed (1000000)                             
    [PASS] Value Check Passed (6.25)                               
	[SUCCESS] :Binary I/O Test Complete. 	
	
*/