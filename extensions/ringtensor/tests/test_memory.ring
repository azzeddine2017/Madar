# File: extensions/ringtensor/tests/test_memory.ring

load "ringtensor.ring"

see "=== Memory Leak Test ===" + nl
see "Creating 100,000 Tensors..." + nl

tStart = clock()

for i = 1 to 100000
    # Create tensor (Malloc in C)
    t = tensor_init(100, 100) 
    
    # Do some math
    tensor_fill(t, 1.0)
    
    # End of loop scope -> Ring GC should call ring_tensor_free() automatically
    # If not freeing, RAM usage will explode.
    
    if i % 10000 = 0 
        see "Iteration: " + i + nl
        callgc() # Help Ring GC
    ok
next

see "Done in " + ((clock()-tStart)/clockspersecond()) + "s" + nl
see "Check Task Manager. If RAM is low, GC is working!" + nl