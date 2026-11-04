load "ringml.ring"

func main
    see "Loading Library..." + nl
    
    # Huge matrices (2000x2000)
    # That's about 4 million numbers; the multiplication requires 8 billion calculations!
    nSize = 2000 
    
    see "Allocating Huge Tensors ("+nSize+"x"+nSize+")..." + nl
    A = new Tensor(nSize, nSize)
    B = new Tensor(nSize, nSize)
    
    see "Filling Data..." + nl
    A.fill(1.0)
    B.fill(2.0)
    
    see "Running MatMul (Watch Task Manager NOW!)..." + nl
    t1 = clock()
    
    # This process will take time and force the GPU to work.
    C = A.matMul(B)
    
    see "Done in " + ((clock()-t1)/clockspersecond()) + " seconds." + nl
    see "Result Sample: " + C.getVal(1,1) + nl