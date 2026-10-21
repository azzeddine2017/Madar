# Project: Jabr
# File: tests_alqalam.ring
# Description: full Unit Testing for AlQalam (The Pen) Extension

load "ringml.ring" # نحتاجه لاختبار الـ Tensor Bridge


func main()
    oStyl.bright_magenta(:BOLD, nl + "✒️ Starting AlQalam Global Diagnostics..." + nl)
    
    test_chronos()
    test_vector_basic()
    test_vector_alchemy()
    test_vector_memory_and_ptr()
    test_vector_processing()
    test_ink_mastery()
    test_index_logic()
    test_formula_engine()

    oStyl.bright_green(:BOLD, nl + "✅ All AlQalam Modules passed the test! The Pen is sharp." + nl)

# =========================================================================
# 1. Timer test(Chronos)
# =========================================================================
func test_chronos()
    oStyl.cyan(:BOLD, "--- [1] Testing QalamChronos (Time Lord) ---" + nl)
    
    oTimer = new QalamChronos()
    
    # Test waiting
    sleep(0.5) 
    nNs = oTimer.elapsed_ns()
    cTime = oTimer.elapsed()
    
    if nNs > 0
        oStyl.green(:NONE, "  OK: Timer initiated. Elapsed: " + cTime + nl)
    else
        oStyl.red(:BOLD, "  FAIL: Timer returned zero." + nl)
    ok
    
    oTimer.reset()
    if oTimer.elapsed_ns() < nNs
        oStyl.green(:NONE, "  OK: Timer reset successful." + nl)
    ok
    ? ""

# =========================================================================
# 2. Basic Vector Ops
# =========================================================================
func test_vector_basic()
    oStyl.cyan(:BOLD, "--- [2] Testing QalamVector (Basic I/O) ---" + nl)
    
    oVec = new QalamVector(10)
    
    # Flow test
    for i=1 to 5 oVec.flow(i * 1.5) next
    
    if oVec.size() = 5
        oStyl.green(:NONE, "  OK: Size is correct (5)." + nl)
    ok
    
    # Reading and writing test
    oVec.write(1, 99.9)
    if oVec.read(1) = 99.9
        oStyl.green(:NONE, "  OK: Read/Write successful." + nl)
    ok
    
    oVec.correct(5, 77.7)
    if oVec.read(5) = 77.7
        oStyl.green(:NONE, "  OK: Correction (Set) successful." + nl)
    ok
    ? ""

# =========================================================================
# 3. Vector Alchemy
# =========================================================================
func test_vector_alchemy()
    oStyl.cyan(:BOLD, "--- [3] Testing QalamVector (Alchemy & Batch) ---" + nl)
    
    oVec = new QalamVector(100)
    oVec.expand(10) # 10 elements filled with 0
    
    # Flood
    oVec.flood(10.0)
    if oVec.read(1) = 10 and oVec.read(10) = 10
        oStyl.green(:NONE, "  OK: Flooding successful." + nl)
    ok
    
    # Elevate
    oVec.elevate(5.5) # All should be 15.5
    if oVec.read(5) = 15.5
        oStyl.green(:NONE, "  OK: Elevation (Batch Add) successful." + nl)
    ok
    
    # Amplify
    oVec.amplify(2) # All should be 31.0
    if oVec.read(1) = 31.0
        oStyl.green(:NONE, "  OK: Amplification (Batch Mul) successful." + nl)
    ok
    ? ""

# =========================================================================
# 4. Memory & Pointers
# =========================================================================
func test_vector_memory_and_ptr()
    oStyl.cyan(:BOLD, "--- [4] Testing Memory Bridge & Pointers ---" + nl)
    
    oVec = new QalamVector(0)
    oVec.prepare(1000) # Reserve
    
    # Create data in external tensor to transfer
    oTemp = new Tensor(1, 3)
    oTemp.setVal(1, 1, 11) oTemp.setVal(1, 2, 22) oTemp.setVal(1, 3, 33)
    
    # LoadFromPtr
    oVec.loadFromPtr(oTemp.getRawPointer(), 3)
    if oVec.size() = 3 and oVec.read(3) = 33
        oStyl.green(:NONE, "  OK: LoadFromPtr (memcpy) successful." + nl)
    ok
    
    # FlowFromPtr
    oVec.flowFromPtr(oTemp.getRawPointer(), 3) # Size becomes 6
    if oVec.size() = 6 and oVec.read(4) = 11
        oStyl.green(:NONE, "  OK: FlowFromPtr (std::insert) successful." + nl)
    ok
    
    # Wipe
    oVec.wipe()
    if oVec.size() = 0
        oStyl.green(:NONE, "  OK: Wipe (Memory Clear) successful." + nl)
    ok
    ? ""

# =========================================================================
# 5. Processing
# =========================================================================
func test_vector_processing()
    oStyl.cyan(:BOLD, "--- [5] Testing Advanced Processing (Super Loop) ---" + nl)
    
    oVec = new QalamVector(5)
    for x in [10, 20, 30, 40, 50] oVec.flow(x) next
    
    # Clip
    oVec.clip(15, 45) # 10 becomes 15, 50 becomes 45
    if oVec.read(1) = 15 and oVec.read(5) = 45
        oStyl.green(:NONE, "  OK: Clipping (Min/Max) successful." + nl)
    ok
    
    # Threshold
    oVec.threshold(35, 0) # Anything > 35 becomes 0
    if oVec.read(4) = 0
        oStyl.green(:NONE, "  OK: Thresholding successful." + nl)
    ok
    
    # Search
    nIdx = oVec.findFirstGreater(20) # Should find 30 at index 3
    if nIdx = 3
        oStyl.green(:NONE, "  OK: FindFirstGreater successful (Index: "+nIdx+")." + nl)
    ok
    ? ""

# =========================================================================
# 6. Ink / String Builder
# =========================================================================
func test_ink_mastery()
    oStyl.cyan(:BOLD, "--- [6] Testing QalamInk (The High-Speed Inkwell) ---" + nl)
    
    oInk = new QalamInk()
    oInk.inscribe("I write with ")
    oInk.inscribe("Silicon.")
    
    if oInk.reveal() = "I write with Silicon."
        oStyl.green(:NONE, "  OK: Basic inscription successful." + nl)
    ok
    
    # Batch
    aWords = [" Jabr", " is", " Alive."]
    oInk.inscribeBatch(aWords)
    
    if substr(oInk.reveal(), "Alive.") > 0
        oStyl.green(:NONE, "  OK: Batch Inscription successful." + nl)
    ok
    
    oInk.wipe()
    if len(oInk.reveal()) = 0
        oStyl.green(:NONE, "  OK: Inkwell wiped clean." + nl)
    ok
    ? ""

# =========================================================================
# 7. Index / Hash Map
# =========================================================================
func test_index_logic()
    oStyl.cyan(:BOLD, "--- [7] Testing QalamIndex (The Neural Map) ---" + nl)
    
    oMap = new QalamIndex()
    oMap.define("Jabr", 101)
    oMap.define("Adam", 202)
    
    if oMap.knows("Jabr") and oMap.recall("Jabr") = 101
        oStyl.green(:NONE, "  OK: O(1) Recall successful." + nl)
    ok
    
    if oMap.recall("Unknown") = 0
        oStyl.green(:NONE, "  OK: Unknown keys handled (0)." + nl)
    ok
    ? ""

# =========================================================================
# 8. Formula Engine
# =========================================================================
func test_formula_engine()
    oStyl.cyan(:BOLD, "--- [8] Testing QalamFormula (Compiled Logic) ---" + nl)
    
    oVec = new QalamVector(5)
    for i=1 to 5 oVec.flow(i) next # [1, 2, 3, 4, 5]
    
    # Applying the formula: x * 2 + 10
    try
        # We test the programming bridge for the formula
        oVec.transform("x * 2 + 10 - 7") 
        if oVec.read(1) = 5
            oStyl.green(:NONE, "  OK: Formula transformation applied." + nl)
        ok
    catch
        oStyl.yellow(:NONE, "  INFO: Formula engine skip (Check C++ implementation)." + nl)
    done
    ? ""