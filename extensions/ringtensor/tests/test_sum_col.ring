load "ringml.ring"
tensor_set_threads(1)

func main
    # مصفوفة 2x2
    # [ 1  2 ]
    # [ 3  4 ]
    oT = new Tensor(2, 2)
    oT.setVal(1,1, 1) oT.setVal(1,2, 2)
    oT.setVal(2,1, 3) oT.setVal(2,2, 4)
    
    # نريد جمع الأعمدة (Axis 0)
    # النتيجة يجب أن تكون: [4, 6]
    
    oRes = oT.sum(0)
    
    v1 = oRes.getVal(1, 1) # يجب أن يكون 4
    v2 = oRes.getVal(1, 2) # يجب أن يكون 6
    
    see "Sum Column 1: " + v1 + " (Expected 4)" + nl
    see "Sum Column 2: " + v2 + " (Expected 6)" + nl
    
    if v1 = 4 and v2 = 6
        see ">>> SUCCESS: Column Sum works correctly." + nl
    else
        see ">>> FAILURE: C Kernel sum(axis=0) is BROKEN." + nl
    ok