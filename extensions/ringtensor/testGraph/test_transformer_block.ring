load "ringtensor.ring"

func main
    see "Testing Transformer Block Graph..." + nl

    # Hyperparameters
    vocab_size = 10
    embed_dim = 8
    seq_len = 5
    batch_size = 2
    lr = 0.01
    epochs = 1

    # 1. Init Graph
    graph_init()
    graph_set_optimizer(OPTIMIZER_ADAM)

    # 2. Data
    # Input Indices: Batch=2, Seq=5. Values 1..vocab_size
    pInput = tensor_init(batch_size, seq_len)
    tensor_set_from_list(pInput, [
        1, 2, 3, 4, 5, 
        6, 7, 8, 9, 1
    ])

    # Target (Dummy Regression Target for simplicity): Batch=2, Seq=5, Dim=1 (after projection)
    # Actually, let's just do a simple classification or regression on the output.
    # Let's aim for output 0.0 for all.
    pTarget = tensor_init(batch_size, 1) 
    tensor_fill(pTarget, 0.5)

    # 3. Weights
    # Embedding Matrix: Vocab x Dim
    pEmb = tensor_init(vocab_size, embed_dim)
    tensor_random(pEmb, -0.1, 0.1)

    # LayerNorm Gamma: 1 x Dim
    pGamma = tensor_init(1, embed_dim)
    tensor_fill(pGamma, 1.0)

    # Linear 1: Dim x 1 (To project to scalar for loss)
    pW1 = tensor_init(embed_dim, 1)
    tensor_random(pW1, -0.1, 0.1)

    # 4. Build Graph
    
    # Input Nodes
    id_Input = graph_node(OP_INPUT, -1, -1, pInput)
    id_EmbW  = graph_node(OP_WEIGHT, -1, -1, pEmb)
    
    # 1. Embedding Layer
    # Output: Batch x Seq x Dim
    id_Embed = graph_node(OP_EMBEDDING, id_EmbW, id_Input)
    
    # 2. Layer Normalization
    id_Gamma = graph_node(OP_WEIGHT, -1, -1, pGamma)
    id_LN    = graph_node(OP_LAYERNORM, id_Embed, id_Gamma)
    
    # 3. Dropout
    id_Drop  = graph_node(OP_DROPOUT, id_LN, -1)
    
    # 4. Global Average Pooling (Manual: Sum then Divide)
    # Since we don't have OP_MEAN yet in Graph (we have kernel), let's use a trick or just reshape?
    # Wait, we don't have Reshape node yet.
    # Let's just do MatMul with a [Dim x 1] weight.
    # Input to MatMul must be 2D. 
    # Embedding output is logically 3D (Batch, Seq, Dim) but physically 2D (Batch*Seq, Dim).
    # So MatMul( (Batch*Seq x Dim) , (Dim x 1) ) -> (Batch*Seq x 1).
    
    id_W1    = graph_node(OP_WEIGHT, -1, -1, pW1)
    id_MM    = graph_node(OP_MATMUL, id_Drop, id_W1) 
    
    # 5. Activation
    id_Relu  = graph_node(OP_RELU, id_MM, -1)
    
    # 6. Loss (MSE against Target)
    # Target needs to match shape. (Batch*Seq x 1)
    # Our pTarget is (Batch x 1). We need to repeat it or just make pTarget bigger.
    pTargetBig = tensor_init(batch_size * seq_len, 1)
    tensor_fill(pTargetBig, 0.5)
    
    id_Target = graph_node(OP_INPUT, -1, -1, pTargetBig)
    id_Loss   = graph_node(OP_MSE, id_Relu, id_Target)

    # 5. Training Loop
    see "Initial Loss: "
    graph_forward()
    pOut = graph_get_output(id_Loss)
    loss_start = tensor_get(pOut, 1, 1)
    see loss_start + nl

    see "Training for " + epochs + " epochs with Adam..." + nl
    graph_run(epochs, lr)

    # 6. Check Result
    pOut = graph_get_output(id_Loss)
    loss_end = tensor_get(pOut, 1, 1)
    see "Final Loss: " + loss_end + nl

    if loss_end < loss_start
        see "TEST PASSED: Loss decreased significantly." + nl
    else
        see "TEST FAILED: Loss did not decrease." + nl
    ok

    graph_free()
