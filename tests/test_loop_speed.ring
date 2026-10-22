/*
    Madar Performance Benchmark: Loops & Comprehensions
    مقارنة أداء حلقات التكرار ومصفوفة الفهم في مدار
*/

load "alqalam.ring"

func main
    oTimer = new QalamChronos()
    
    # حجم البيانات للاختبار
    N = 20000
    tWarmFor = 0

    see nl
    see "====================================================================" + nl
    see "  Madar Loop & Comprehension Performance Benchmark" + nl
    see "  اختبار مقارنة أداء حلقات التكرار ومصفوفة الفهم في مدار" + nl
    see "====================================================================" + nl
    see "  Data Items (N): " + N + nl
    see "--------------------------------------------------------------------" + nl

    # -----------------------------------------------------------------
    # Test 1a: List Comprehension: [x*x for x in 1:N]
    # -----------------------------------------------------------------
    see "[1a] Testing List Comprehension: [x*x for x in 1:N] ... "
    oTimer.reset()
    aRes1 = [x*x for x in 1:N]
    tComp = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tComp + " ns)" + nl

    # -----------------------------------------------------------------
    # Test 1b: Madar DOUR Comprehension: [x*x dour x in 1:N]
    # -----------------------------------------------------------------
    see "[1b] Testing Madar DOUR Comprehension: [x*x dour x in 1:N] ... "
    oTimer.reset()
    aRes1b = [x*x dour x in 1:N]
    tDourComp = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tDourComp + " ns)" + nl

    # -----------------------------------------------------------------
    # Test 2: Pre-allocated List: list(N) + for x = 1 to N
    # -----------------------------------------------------------------
    see "[2] Testing Pre-allocated List + Numeric For Loop ... "
    oTimer.reset()
    aRes2 = list(N)
    for x = 1 to N
        aRes2[x] = x * x
    next
    tPreAlloc = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tPreAlloc + " ns)" + nl

    # -----------------------------------------------------------------
    # Test 3: Dynamic Append: [] + for x = 1 to N + aList + (x*x)
    # -----------------------------------------------------------------
    see "[3] Testing Dynamic Append + Numeric For Loop ... "
    oTimer.reset()
    aRes3 = []
    for x = 1 to N
        aRes3 + (x * x)
    next
    tAppend = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tAppend + " ns)" + nl

    # -----------------------------------------------------------------
    # Test 4: Numeric For Loop: for x = 1 to N
    # -----------------------------------------------------------------
    see "[4] Testing Numeric For Loop (for x = 1 to N) + Append ... "
    oTimer.reset()
    aRes4 = []
    for x = 1 to N
        aRes4 + (x * x)
    next
    tForIn = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tForIn + " ns)" + nl

    # -----------------------------------------------------------------
    # Test 5: While Loop: while x <= N
    # -----------------------------------------------------------------
    see "[5] Testing While Loop (while x <= N) ... "
    oTimer.reset()
    aRes5 = []
    x = 1
    while x <= N
        aRes5 + (x * x)
        x++
    end
    tWhile = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tWhile + " ns)" + nl

    # -----------------------------------------------------------------
    # Test 6: Pure Numeric Accumulation (No List Allocation)
    # -----------------------------------------------------------------
    see "--------------------------------------------------------------------" + nl
    see "[6] Pure Compute: Standard Ring 'for' loop (sum += x*x) ... "
    oTimer.reset()
    nSum1 = 0
    for x = 1 to N
        nSum1 += (x * x)
    next
    tPureFor = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tPureFor + " ns)" + nl

    if jit_available()
        see "[6b] Pure Compute: Madar 'dour' with Auto-JIT (dour x = 1 to N) ... "
        oTimer.reset()
        nSumDour = 0
        dour x = 1 to N
            nSumDour += (x * x)
        next
        tDour = oTimer.elapsed_ns()
        see "Done -> " + oTimer.elapsed() + " (" + tDour + " ns)" + nl
        see "    -> Auto-JIT Engine: executed " + jit_autoloops() + " loop(s) natively on CPU!" + nl
    ok

    see "[7] Pure Compute (No List): while x <= N (sum += x*x) ... "
    oTimer.reset()
    nSum2 = 0
    x = 1
    while x <= N
        nSum2 += (x * x)
        x++
    end
    tPureWhile = oTimer.elapsed_ns()
    see "Done -> " + oTimer.elapsed() + " (" + tPureWhile + " ns)" + nl

    # -----------------------------------------------------------------
    # Test 8: SLJIT Native Machine Code (Madar JIT Engine)
    # -----------------------------------------------------------------
    tJIT = 0
    if jit_available()
        see "[8] Native Machine Code (Madar JIT / SLJIT): jit_sumsq(N) ... "
        oTimer.reset()
        nSumJIT = jit_sumsq(N)
        tJIT = oTimer.elapsed_ns()
        see "Done -> " + oTimer.elapsed() + " (" + tJIT + " ns)" + nl
        see "    -> Verification: sum=" + nSumJIT + " (matches for=" + nSum1 + ")" + nl
    ok

    # -----------------------------------------------------------------
    # Summary & Analysis
    # -----------------------------------------------------------------
    see "====================================================================" + nl
    see "                       BENCHMARK SUMMARY & COMPARISON               " + nl
    see "====================================================================" + nl
    
    see "1a. List Comprehension [x*x for x in 1:N]  : " + formatNanoTime(tComp) + nl
    see "1b. Madar DOUR Comp [x*x dour x in 1:N]    : " + formatNanoTime(tDourComp) + nl
    see "2.  Pre-allocated List a[x] = x*x          : " + formatNanoTime(tPreAlloc) + nl
    see "3.  Dynamic Append (a + x*x)               : " + formatNanoTime(tAppend) + nl
    see "4.  Numeric For Loop (for x = 1 to N)      : " + formatNanoTime(tForIn) + nl
    see "5.  While Loop (while x <= N)              : " + formatNanoTime(tWhile) + nl
    see "6.  Pure Ring 'for' Loop (Sum)             : " + formatNanoTime(tPureFor) + nl
    if tDour > 0
        see "6b. Pure Madar 'dour' Auto-JIT (Sum)       : " + formatNanoTime(tDour) + nl
    ok
    see "7.  Pure Numeric While Loop (Sum)          : " + formatNanoTime(tPureWhile) + nl
    if tJIT > 0
        see "8.  Native Machine Code JIT (SLJIT)        : " + formatNanoTime(tJIT) + nl
    ok
    see "--------------------------------------------------------------------" + nl
    if tJIT > 0 and tJIT < tPureFor
        see "JIT Speedup Factor:" + nl
        see "  -> JIT vs Pure Numeric For Loop : " + (round((tPureFor / tJIT) * 100) / 100) + "x FASTER!" + nl
        see "  -> JIT vs While Loop            : " + (round((tPureWhile / tJIT) * 100) / 100) + "x FASTER!" + nl
        see "--------------------------------------------------------------------" + nl
    ok

    # التحليل المقارن مع مصفوفة الفهم
    see "Relative to List Comprehension:" + nl
    if tPreAlloc > 0
        ratioPre = (tComp / tPreAlloc)
        see "  -> Pre-allocated List vs Comprehension : " + (round(ratioPre * 100) / 100) + "x" + nl
    ok
    if tAppend > 0
        ratioApp = (tComp / tAppend)
        see "  -> Dynamic Append vs Comprehension     : " + (round(ratioApp * 100) / 100) + "x" + nl
    ok
    if tPureFor > 0
        see "  -> Pure CPU Compute vs Comprehension   : " + (round((tComp / tPureFor) * 100) / 100) + "x faster (no RAM allocations)" + nl
    ok
    see "====================================================================" + nl

func round(nVal)
    return floor(nVal + 0.5)



/*
==== befor ====

G:\RingProject\Madar\tests (main -> origin)
λ ring test_loop_speed.ring

====================================================================
  Madar Loop & Comprehension Performance Benchmark
  اختبار مقارنة أداء حلقات التكرار ومصفوفة الفهم في مدار
====================================================================
  Data Items (N): 20000
--------------------------------------------------------------------
[1] Testing List Comprehension: [x*x for x in 1:N] ... Done -> 1m 04s (64830302122 ns)
[2] Testing Pre-allocated List + Numeric For Loop ... Done -> 52.620 ms (52607002 ns)
[3] Testing Dynamic Append + Numeric For Loop ... Done -> 9.021 ms (9008133 ns)
[4] Testing For-In with Range (for x in 1:N) ... Done -> 2m 06s (126342062767 ns)
[5] Testing While Loop (while x <= N) ... Done -> 12.388 ms (12371462 ns)
--------------------------------------------------------------------
[6] Pure Compute (No List): for x = 1 to N (sum += x*x) ... Done -> 5.994 ms (5986819 ns)
[7] Pure Compute (No List): while x <= N (sum += x*x) ... Done -> 9.044 ms (9034245 ns)
[8] Native Machine Code (Madar JIT / SLJIT): jit_sumsq(N) ... Done -> 116.224 µs (109568 ns)
    -> Verification: sum=2666866670000 (matches for=2666866670000)
====================================================================
                       BENCHMARK SUMMARY & COMPARISON
====================================================================
1. List Comprehension [x*x for x in 1:N] : 1m 04s
2. Pre-allocated List a[x] = x*x         : 52.607 ms
3. Dynamic Append (a + x*x)              : 9.008 ms
4. For-In Range (for x in 1:N)           : 2m 06s
5. While Loop (while x <= N)             : 12.371 ms
6. Pure Numeric For Loop (Sum)           : 5.987 ms
7. Pure Numeric While Loop (Sum)         : 9.034 ms
8. Native Machine Code JIT (SLJIT)       : 109.568 µs
--------------------------------------------------------------------
JIT Speedup Factor:
  -> JIT vs Pure Numeric For Loop : 54.64x FASTER!
  -> JIT vs While Loop            : 82.45x FASTER!
--------------------------------------------------------------------
Relative to List Comprehension:
  -> Pre-allocated List vs Comprehension : 1232.35x
  -> Dynamic Append vs Comprehension     : 7196.86x
  -> Pure CPU Compute vs Comprehension   : 10828.84x faster (no RAM allocations)
====================================================================

==   after ===

G:\RingProject\Madar\tests (main -> origin)                                                                     
λ ring test_loop_speed.ring                                                                                     
                                                                                                                
====================================================================                                            
  Madar Loop & Comprehension Performance Benchmark                                                              
  اختبار مقارنة أداء حلقات التكرار ومصفوفة الفهم في مدار                                                        
====================================================================                                            
  Data Items (N): 2000000                                                                                       
--------------------------------------------------------------------                                            
[1] Testing List Comprehension: [x*x for x in 1:N] ... Done -> 2.160 s (2159797329 ns)                          
[2] Testing Pre-allocated List + Numeric For Loop ... Done -> 1.084 s (1083948587 ns)                           
[3] Testing Dynamic Append + Numeric For Loop ... Done -> 1.077 s (1076611623 ns)                               
[4] Testing For-In with Range (for x in 1:N) ... Done -> 2.459 s (2458794730 ns)                                
[5] Testing While Loop (while x <= N) ... Done -> 1.177 s (1176984154 ns)                                       
--------------------------------------------------------------------                                            
[6] Pure Compute (No List): for x = 1 to N (sum += x*x) ... Done -> 808.682 ms (808670622 ns)                   
    -> Auto-JIT Engine: executed 0 loop(s) natively on CPU!                                                     
[7] Pure Compute (No List): while x <= N (sum += x*x) ... Done -> 964.013 ms (964002286 ns)                     
[8] Native Machine Code (Madar JIT / SLJIT): jit_sumsq(N) ... Done -> 1.617 ms (1610753 ns)                     
    -> Verification: sum=2666668666666999808.00 (matches for=2666668666670699520.00)                            
====================================================================                                            
                       BENCHMARK SUMMARY & COMPARISON                                                           
====================================================================                                            
1. List Comprehension [x*x for x in 1:N] : 2.160 s                                                              
2. Pre-allocated List a[x] = x*x         : 1.084 s                                                              
3. Dynamic Append (a + x*x)              : 1.077 s                                                              
4. For-In Range (for x in 1:N)           : 2.459 s                                                              
5. While Loop (while x <= N)             : 1.177 s                                                              
6. Pure Numeric For Loop (Sum)           : 808.671 ms                                                           
7. Pure Numeric While Loop (Sum)         : 964.002 ms                                                           
8. Native Machine Code JIT (SLJIT)       : 1.611 ms                                                             
--------------------------------------------------------------------                                            
JIT Speedup Factor:                                                                                             
  -> JIT vs Pure Numeric For Loop : 502.05x FASTER!                                                             
  -> JIT vs While Loop            : 598.48x FASTER!                                                             
--------------------------------------------------------------------                                            
Relative to List Comprehension:                                                                                 
  -> Pre-allocated List vs Comprehension : 1.99x                                                                
  -> Dynamic Append vs Comprehension     : 2.01x                                                                
  -> Pure CPU Compute vs Comprehension   : 2.67x faster (no RAM allocations)                                    
====================================================================                                            
                                                                                                        
*/