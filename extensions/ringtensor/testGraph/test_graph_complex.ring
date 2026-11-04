load "ringtensor.ring"
decimals(5)
func main
    see "Testing Complex Graph (2-Layer NN)..." + nl

    # Hyperparameters
    lr = 0.5
    epochs = 500

    # 1. Init Graph
    graph_init()

    # 2. Data
    # Input: [0.5, -0.5, 1.0, 0.0]
    pInput = tensor_init(1, 4)
    tensor_set_from_list(pInput, [0.5, -0.5, 1.0, 0.0])

    # Target: [0.8]
    pTarget = tensor_init(1, 1)
    tensor_set_from_list(pTarget, [0.8])

    # 3. Weights
    # W1: 4x4
    pW1 = tensor_init(4, 4)
    tensor_random(pW1, -0.5, 0.5)

    # W2: 4x1
    pW2 = tensor_init(4, 1)
    tensor_random(pW2, -0.5, 0.5)

    # 4. Build Graph
    
    # Layer 1
    id_Input = graph_node(OP_INPUT, -1, -1, pInput)
    id_W1    = graph_node(OP_WEIGHT, -1, -1, pW1)
    id_MM1   = graph_node(OP_MATMUL, id_Input, id_W1) # 1x4 * 4x4 = 1x4
    id_Relu  = graph_node(OP_RELU, id_MM1, -1)

    # Layer 2
    id_W2    = graph_node(OP_WEIGHT, -1, -1, pW2)
    id_MM2   = graph_node(OP_MATMUL, id_Relu, id_W2)  # 1x4 * 4x1 = 1x1
    id_Sig   = graph_node(OP_SIGMOID, id_MM2, -1)

    # Loss
    id_Target = graph_node(OP_INPUT, -1, -1, pTarget)
    id_Loss   = graph_node(OP_MSE, id_Sig, id_Target)

    # 5. Training Loop
    see "Initial Loss: "
    graph_forward()
    pOut = graph_get_output(id_Loss)
    loss_start = tensor_get(pOut, 1, 1)
    see loss_start + nl

    see "Training for " + epochs + " epochs..." + nl
    graph_run(epochs, lr)

    # 6. Check Result
    pOut = graph_get_output(id_Loss)
    loss_end = tensor_get(pOut, 1, 1)
    see "Final Loss: " + loss_end + nl

    if loss_end < loss_start
        see "TEST PASSED: Loss decreased." + nl
    else
        see "TEST FAILED: Loss did not decrease." + nl
    ok
    
    # Verify Output Value
    pPred = graph_get_output(id_Sig)
    pred_val = tensor_get(pPred, 1, 1)
    see "Prediction: " + pred_val + " (Target: 0.8)" + nl

    graph_free()
