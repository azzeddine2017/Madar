load "ringtensor.ring"

func main
    see "Testing Graph Engine Backward Pass..." + nl
    
    # 1. Initialize Graph
    graph_init()
    
    # 2. Create Nodes: Loss = (A * B - Target)^2
    # A: 2x2, B: 2x2, Target: 2x2
    
    # Define Tensors
    pA = tensor_init(2, 2)
    tensor_fill(pA, 1.0)
    
    pB = tensor_init(2, 2)
    tensor_fill(pB, 2.0)
    
    pTarget = tensor_init(2, 2)
    tensor_fill(pTarget, 4.0) # Target = 4.0
    
    # Create Graph Nodes
    # Node 0: Weight A (Trainable)
    id_A = graph_node(OP_WEIGHT, -1, -1, pA)
    
    # Node 1: Input B (Fixed)
    id_B = graph_node(OP_INPUT, -1, -1, pB)
    
    # Node 2: MatMul (A * B) -> Should be [[4,4],[4,4]]
    id_Mul = graph_node(OP_MATMUL, id_A, id_B)
    
    # Node 3: Target
    id_Target = graph_node(OP_INPUT, -1, -1, pTarget)
    
    # Node 4: Loss (MSE)
    id_Loss = graph_node(OP_MSE, id_Mul, id_Target)
    
    # 3. Run Training Step (1 Epoch)
    # Forward: A*B = [[4,4],[4,4]]. Loss = (4-4)^2 = 0.
    # Let's make Target 5.0 to get gradients.
    tensor_fill(pTarget, 5.0)
    
    # Run Graph (1 epoch, lr=0.1)
    graph_run(1, 0.1)
    
    # 4. Verify Gradients
    # Forward: Pred = 4.0, Target = 5.0. Diff = -1.0.
    # MSE Grad (dLoss/dPred) = 2/N * (Pred - Target) = 2/2 * (-1) = -1.0
    # (Assuming internal_mse_backward uses 2/N or 1/N? internal_mse_backward uses 1/N scale * (p-t))
    # Wait, internal_mse_backward implementation:
    # Grad->data[i] = scale * (p - t); where scale = 1.0 / Pred->rows (which is 2)
    # So Grad = 0.5 * (4 - 5) = -0.5.
    
    # Backprop to A:
    # C = A * B. dC = -0.5.
    # dA = dC * B.T
    # B = [[2,2],[2,2]]. B.T = [[2,2],[2,2]].
    # dA = [[-0.5, -0.5], [-0.5, -0.5]] * [[2,2],[2,2]]
    # dA[0,0] = (-0.5*2) + (-0.5*2) = -1.0 - 1.0 = -2.0.
    
    # New A = Old A - lr * dA
    # New A = 1.0 - 0.1 * (-2.0) = 1.2
    
    val = tensor_get(pA, 1, 1)
    see "Value of A(1,1) after update: " + val + nl
    
    if fabs(val - 1.2) < 0.001
        see "TEST PASSED!" + nl
    else
        see "TEST FAILED! Expected 1.2" + nl
    ok

    graph_free()
