# File: src/core/tensor.ring
# Description: Core Tensor class - Updated for Auto-Graph Integration
# Author: Azzeddine Remmal

# Gradient Clipping  
func clipGlobalNorm aListOfTensors, nMaxNorm
    return tensor_clip_global_norm(aListOfTensors, nMaxNorm)
ok


class Tensor
    pData   = NULL  # C Pointer
    nRows   = 0     
    nCols   = 0     
    nBatch  = 1
    nHeads  = 1

    nGraphNodeID = -1   
    bGraphMode   = false 

    func init nR, nC
        self.nRows = nR
        self.nCols = nC
        if nR > 0 and nC > 0
            self.pData = tensor_init(nR, nC)
        ok
        return self
    
    func getVal r, c
        return tensor_get(pData, r, c)
        
    func setVal r, c, val
        tensor_set(pData, r, c, val)
    
    func size
        return nRows * nCols

    func getRawPointer
        return tensor_get_data_ptr(pData)
    
    func asGraphInput
        nNewID = graph_node(RT_OP_INPUT, -1, -1, -1, 0.0)
        graph_bind_memory(nNewID, pData)
        nGraphNodeID = nNewID
        bGraphMode   = true 
        return self
    
    func asGraphWeight oGrad
        nNewID = graph_node(RT_OP_WEIGHT, -1, -1, -1, 0.0)
        graph_bind_memory(nNewID, pData)
        # Bind gradient if provided
        if !isnull(oGrad)
            graph_bind_grad(nNewID, oGrad.pData)
        ok
        nGraphNodeID = nNewID
        bGraphMode   = true
        return self

    func asGraphConstant
        # نسجله كمدخل (INPUT) أو كثابت، بحيث لا يقترب منه المحسن
        nNewID = graph_node(RT_OP_INPUT, -1, -1, -1, 0.0)
        graph_bind_memory(nNewID, pData)
        
        nGraphNodeID = nNewID
        bGraphMode   = true 
        return self

    func setGraphMode bStatus
        bGraphMode = bStatus
        return self

    func bindGrad oGradTensor
        if nGraphNodeID != -1
            graph_bind_grad(nGraphNodeID, oGradTensor.pData)
        ok
        return self

    func fromMemory nAddress, nR, nC
        pNewPtr = tensor_from_memory(nAddress, nR, nC)
        oNew = new Tensor(1,1)
        oNew.pData = pNewPtr
        oNew.nRows = nR
        oNew.nCols = nC
        return oNew  

    func reshape nB, nH, nR, nC
        tensor_reshape(pData, nB, nH, nR, nC)
        nBatch = nB
        nHeads = nH
        nRows  = nR
        nCols  = nC
        return self
        
    func copyData oOtherTensor
        # Usage: oMyTensor.copyData(oSource)
        # C Function: copy_data(Dest, Src) -> (self, other)
        tensor_copy_data(pData, oOtherTensor.pData)
        return self

    func copy
        if bGraphMode
            return returnGraphNode(RT_OP_ADD, self, NULL, nRows, nCols)
        ok
        pNewPtr = tensor_copy(pData)
        oNew = new Tensor(1, 1)
        oNew.pData = pNewPtr
        oNew.nRows  = nRows
        oNew.nCols  = nCols
        oNew.nBatch = nBatch
        oNew.nHeads = nHeads
        return oNew

    func add oOther
        if bGraphMode
            # ? "DEBUG: OP_ADD = " + OP_ADD + " | OP_WEIGHT = " + OP_WEIGHT
            return returnGraphNode(RT_OP_ADD, self, oOther, nRows, nCols)
        else
            tensor_add(pData, oOther.pData)
            return self 
        ok

    func sub oOther
        if bGraphMode
            return returnGraphNode(RT_OP_SUB, self, oOther, nRows, nCols)
        else
            tensor_sub(pData, oOther.pData)
            return self
        ok

    func mul oOther 
        if bGraphMode
            return returnGraphNode(RT_OP_TENSOR_MUL, self, oOther, nRows, nCols)
        else
            tensor_mul_elem(pData, oOther.pData)
            return self
        ok

    func div oOther
        if bGraphMode
            return returnGraphNode(RT_OP_TENSOR_DIV, self, oOther, nRows, nCols)
        else
            tensor_div(pData, oOther.pData)
            return self
        ok
    func argmax
        if bGraphMode
            return returnGraphNode(RT_OP_ARGMAX, self, NULL, nRows, nCols)
        ok
        return tensor_argmax(pData)

    
    func scalarMul nVal
        if bGraphMode
            return returnGraphNodeParam(RT_OP_SCALAR_MUL, self, NULL, nRows, nCols, nVal)
        ok
        tensor_scalar_mul(pData, nVal)
        return self
        
    func addScalar nVal
        if bGraphMode
            return returnGraphNodeParam(RT_OP_ADD_SCALAR, self, NULL, nRows, nCols, nVal)
        ok
        tensor_add_scalar(pData, nVal)
        return self

    func subScalar nVal
        if bGraphMode
            return returnGraphNodeParam(RT_OP_SUB_SCALAR, self, NULL, nRows, nCols, nVal)
        ok
        tensor_sub_scalar(pData, nVal)
        return self    

    func addRowVec oTensorVec
        if bGraphMode
            return returnGraphNode(RT_OP_ADD_ROW_VEC, self, oTensorVec, nRows, nCols)
        ok
        tensor_add_row_vec(pData, oTensorVec.pData)
        return self

    func sliceRows nStartRow, nCount
        oNew = new Tensor(nCount, nCols)
        tensor_slice_rows(pData, oNew.pData, nStartRow, nCount)
        return oNew

    func insertRows oSrcTensor, nStartRow
        tensor_insert_rows(pData, oSrcTensor.pData, nStartRow)
        return self

    func dotRowVec oVector, oRes
        if bGraphMode
            return returnGraphNode(RT_OP_DOT_ROW_VEC, self, oVector, nRows, nCols)
        ok
        //oRes = new Tensor(nRows, nCols)
        tensor_dot_row_vec(pData, oVector.pData, oRes.pData)
        return oRes

    func repeatRows nTimes
        if bGraphMode
            return returnGraphNodeParam(RT_OP_REPEAT_ROWS, self, NULL, nRows * nTimes, nCols, nTimes)
        ok
        nNewRows = nRows * nTimes
        oRes = new Tensor(nNewRows, nCols)
        tensor_repeat_rows(pData, oRes.pData, nTimes)
        return oRes
    
    func matmul oOther
        if bGraphMode
            return returnGraphNode(RT_OP_MATMUL, self, oOther, nRows, oOther.nCols)
        else
            oRes = new Tensor(nRows, oOther.nCols)
            tensor_matmul(pData, oOther.pData, oRes.pData)
            return oRes
        ok 
        
    func transpose
        if bGraphMode
            return returnGraphNode(RT_OP_TRANSPOSE, self, NULL, nCols, nRows)
        else
            oRes = new Tensor(nCols, nRows)
            tensor_transpose(pData, oRes.pData)
            return oRes
        ok

    func sum nAxis
        if bGraphMode
            return returnGraphNodeParam(OP_SUM, self, NULL, 1, 1, nAxis)
        ok
        if nAxis = 1
            oRes = new Tensor(nRows, 1)
        else
            oRes = new Tensor(1, nCols)
        ok
        tensor_sum(pData, nAxis, oRes.pData)
        return oRes
        
    func mean
        if bGraphMode
            return returnGraphNode(OP_MEAN, self, NULL, 1, 1)
        ok
        return tensor_mean(pData)

    func selectColumns nStartCol, nCount
        oNew = new Tensor(nRows, nCount)
        tensor_select_columns(pData, oNew.pData, nStartCol, nCount)
        return oNew
    
    func sumSquares
        return tensor_sum_squares(pData)

    func insertColumns oSrcTensor, nStartCol
        tensor_insert_columns(pData, oSrcTensor.pData, nStartCol)   

    func clipTensor nMax
        tensor_clip_tensor(pData, nMax)
        return self

    func square
        if bGraphMode
            return returnGraphNode(OP_SQUARE, self, NULL, nRows, nCols)
        ok
        tensor_square(pData)
        return self
        
    func sqrt
        if bGraphMode
            return returnGraphNode(OP_SQRT, self, NULL, nRows, nCols)
        ok
        tensor_sqrt(pData)
        return self
        
    func expFunc
        if bGraphMode
            return returnGraphNode(OP_EXP, self, NULL, nRows, nCols)
        ok
        tensor_exp(pData)
        return self

    func random
        tensor_random(pData)
        return self
        
    func zeros
        tensor_fill(pData, 0.0)
        return self
        
    func fill nVal
        tensor_fill(pData, nVal)
        return self

    func sigmoid
        if bGraphMode
            return returnGraphNode(RT_OP_SIGMOID, self, NULL, nRows, nCols)
        else
            tensor_sigmoid(pData)
            return self
        ok

    func tanh
        if bGraphMode
            return returnGraphNode(RT_OP_TANH, self, NULL, nRows, nCols)
        else
            tensor_tanh(pData)
            return self
        ok
        
    func relu
        if bGraphMode
            return returnGraphNode(RT_OP_RELU, self, NULL, nRows, nCols)
        else
            tensor_relu(pData)
            return self
        ok
        
    func embedding oWeights
        if bGraphMode
            return returnGraphNode(OP_EMBEDDING, oWeights, self, size(), oWeights.nCols)
        ok
        oOut = new Tensor(size(), oWeights.nCols)
        tensor_embedding_forward(pData, oWeights.pData, oOut.pData)
        return oOut

    func softmax
        if bGraphMode
            return returnGraphNode(RT_OP_SOFTMAX, self, NULL, nRows, nCols)
        else
            tensor_softmax(pData)
            return self
        ok

    func gelu
        if bGraphMode
            return returnGraphNode(RT_OP_GELU, self, NULL, nRows, nCols)
        else
            tensor_gelu(pData)
            return self
        ok
    #-----------------------------
    func sigmoidPrime
        tensor_sigmoid_prime(pData)
        return self
        
    func tanhPrime
        tensor_tanh_prime(pData)
        return self
        
    func reluPrime
        tensor_relu_prime(pData)
        return self
    
    func geluPrime
        tensor_gelu_prime(pData)
        return self
    #-----------------------------

    func applyDropout nRate
        if bGraphMode
            return returnGraphNodeParam(OP_DROPOUT, self, NULL, nRows, nCols, nRate)
        ok
        tensor_dropout(pData, nRate)
        return self
    
    func layerNorm oGamma, oBeta, nEps
        if bGraphMode
            id1 = self.nGraphNodeID
            if oGamma.nGraphNodeID = -1 oGamma.asGraphConstant() ok
            id2 = oGamma.nGraphNodeID
            if oBeta.nGraphNodeID = -1 oBeta.asGraphConstant() ok
            id3 = oBeta.nGraphNodeID
            nNewID = graph_node(RT_OP_LAYERNORM, id1, id2, id3, nEps)
            oRes = new Tensor(nRows, nCols)
            oRes.bGraphMode = true
            oRes.nGraphNodeID = nNewID
            return oRes
        else
            oRes = new Tensor(nRows, nCols)
            tensor_layernorm(pData, oGamma.pData, oBeta.pData, oRes.pData, nEps)
            return oRes
        ok
        
    func matmulBatch oTensorB
        if nBatch != oTensorB.nBatch 
            raise("Batch Size Mismatch: " + nBatch + " vs " + oTensorB.nBatch)
        ok
        if nCols != oTensorB.nRows
            raise("Inner Dimension Mismatch: " + nCols + " vs " + oTensorB.nRows) 
        ok
        nNewBatch = nBatch
        nNewRows  = nRows
        nNewCols  = oTensorB.nCols
        nTotalBatch = nBatch * nHeads 
        oRes = new Tensor(nTotalBatch * nNewRows, nNewCols)
        oRes.reshape(nBatch, nHeads, nNewRows, nNewCols)
        tensor_matmul_batch(pData, oTensorB.pData, oRes.pData)
        return oRes
        
    func setFromList aList
        tensor_set_from_list(pData, aList)
        return self

    func setOneHot aIndices, nVal
        tensor_set_one_hot(pData, aIndices, nVal)
        return self

    func updateDimsFromC
        nRows = tensor_get_rows(pData)
        nCols = tensor_get_cols(pData)

    func setOneHotFromPtr nRawPtr, nCount, nVal
        tensor_set_one_hot_ptr(pData, nRawPtr, nCount, nVal)
        return self  
         
    func printShape
        see "(" + nRows + ", " + nCols + ")" + nl

    func checkDimensions oTensor
        if nRows != oTensor.nRows or nCols != oTensor.nCols
            raise("Dimension Mismatch")
        ok

    func print
        see "Tensor Shape: (" + nRows + ", " + nCols + ")" + nl
        if nRows <= 200 and nCols <= 200
            for r=1 to nRows
                see "| "
                for c=1 to nCols
                    val = getVal(r,c)
                    if val >= 0 see " " ok
                    see "" + floor(val*10000)/10000 
                    if c != nCols see ", " ok
                next
                see " |" + nl
            next
            see nl
        else
            see "Data is too large to display." + nl
        ok
        see nl
    
    func toList
        return tensor_to_list(pData)

    func fromList aList
        tensor_set_from_list(pData, aList)
        return self

    func saveFile cFileName
        tensor_save(pData, cFileName)
    
    func saveFileQuantized cFileName
        tensor_save_fp32(pData, cFileName)

    func loadFile cFile
        tensor_load_inplace(this.pData, cFile)
        return self
    
    func loadFileQuantized cFile
        tensor_load_fp32_inplace(this.pData, cFile)
        return self

    func loadFromQuantizedFile  cFileName
        pData = tensor_load_fp32(cFileName)
        updateDimsFromC()
    
    func returnGraphNode nOpCode, oIn1, oIn2, nR, nC
        id1 = -1 
        if !isnull(oIn1) 
            if oIn1.nGraphNodeID = -1 oIn1.asGraphConstant() ok
            id1 = oIn1.nGraphNodeID 
        ok
        id2 = -1 
        if !isnull(oIn2) 
            if oIn2.nGraphNodeID = -1 oIn2.asGraphConstant() ok
            id2 = oIn2.nGraphNodeID 
        ok
        nNewID = graph_node(nOpCode, id1, id2, -1, 0.0)
        oRes = new Tensor(0, 0)
        oRes.bGraphMode   = true
        oRes.nGraphNodeID = nNewID
        oRes.nRows        = nR
        oRes.nCols        = nC
        return oRes
    
    func returnGraphNodeParam nOpCode, oIn1, oIn2, nR, nC, nParam
        id1 = -1 
        if !isnull(oIn1) 
            if oIn1.nGraphNodeID = -1 oIn1.asGraphConstant() ok
            id1 = oIn1.nGraphNodeID 
        ok
        id2 = -1 
        if !isnull(oIn2) 
            if oIn2.nGraphNodeID = -1 oIn2.asGraphConstant() ok
            id2 = oIn2.nGraphNodeID 
        ok
        nNewID = graph_node(nOpCode, id1, id2, -1, nParam) 
        oRes = new Tensor(0, 0)
        oRes.bGraphMode   = true
        oRes.nGraphNodeID = nNewID
        oRes.nRows        = nR
        oRes.nCols        = nC
        return oRes

    func backward
        if nGraphNodeID != -1
            graph_backward(nGraphNodeID)
        ok

    /*func returnGraphNodeAttention oQ, oKey, oV, nScale, nBatch, nSeq, nHeads, nCausal, nAttnType
        id1 = oQ.nGraphNodeID
        id2 = oKey.nGraphNodeID
        id3 = oV.nGraphNodeID
        # graph_node(opcode, src1, src2, src3, param, heads, causal, batch, seq, attn_type)
        nNewID = graph_node(RT_OP_ATTENTION, id1, id2, id3, nScale, nHeads, nCausal, nBatch, nSeq, nAttnType)
        oRes = new Tensor(oQ.nRows, oQ.nCols)
        oRes.bGraphMode = true
        oRes.nGraphNodeID = nNewID
        return oRes*/
        
    # --- Attention (Smart Proxy) ---
    func returnGraphNodeAttention oQ, oKey, oV, nScale, nBatch, nSeq, nHeads, nCausal, nAttnType
        
        if bGraphMode
            # 1. Get Node IDs from Inputs
            idQ = oQ.nGraphNodeID
            idK = oKey.nGraphNodeID
            idV = oV.nGraphNodeID
            
            # 2. RECORD IN GRAPH (C-Side)
            # نمرر كل التفاصيل الدقيقة التي سيحتاجها الـ Backward في C
            # Params order mapped to C ring_graph_node:
            # 1:Op, 2:Src1, 3:Src2, 4:Src3, 5:Param(Scale), 6:Heads, 7:Causal, 8:Batch, 9:Seq, 10:Type
            
            nNewID = graph_node(
                33,       # RT_OP_ATTENTION
                idQ,      # Src1 (Q)
                idK,      # Src2 (K)
                idV,      # Src3 (V)
                nScale,   # Param
                nHeads,   # Param 6
                nCausal,  # Param 7
                nBatch,   # Param 8
                nSeq,     # Param 9
                nAttnType # Param 10
            )
            
            # 3. Virtual Result
            oRes = new Tensor(nBatch * nSeq, oQ.nCols)
            oRes.bGraphMode = true
            oRes.nGraphNodeID = nNewID
            
            return oRes

        else
            # --- EAGER EXECUTION (C-Speed) ---
            # إذا لم نكن نسجل، نفذ الحساب فوراً
            oRes = new Tensor(nBatch * nSeq, oQ.nCols)
            
            if nAttnType = 0 # Standard
                tensor_attention_fast(
                    pData, oKey.pData, oV.pData, oRes.pData, 
                    nScale
                    # ملاحظة: في النسخة السريعة C لا يحتاج لمعرفة الـ Heads لأنه يضرب مصفوفات مسطحة
                    # لكن إذا عدلنا C ليأخذها، نمررها.
                    # حالياً tensor_attention_fast تأخذ 5 بارامترات فقط (حسب آخر كود اعتمدناه)
                )
            elseif nAttnType = 1 # Linear Causal
                 tensor_attention_linear_causal(pData, oKey.pData, oV.pData, oRes.pData, nScale)
            else
                 # Batch Attention
                 tensor_attention_batch(
                    pData, oKey.pData, oV.pData, oRes.pData, 
                    nScale, nBatch, nSeq, oQ.nCols, nCausal
                 )
            ok
            
            return oRes
        ok


    func bindMemory
        if nGraphNodeID != -1
            if isnull(pData)
                pData = tensor_init(nRows, nCols)
            ok
            graph_bind_memory(nGraphNodeID, pData)
        ok
        return self

    func syncFromGraph
        if nGraphNodeID != -1
            pData = graph_get_output(nGraphNodeID)
            updateDimsFromC()
        ok
        return self

    func printStats
        tensor_print_stats(pData)
        return self

class Graph
    func init
        graph_init()
    
    func forward
        graph_forward()
    
    func backward nNodeID
        graph_backward(nNodeID)
    
    func setOptimizer nType
        graph_set_optimizer(nType)
    
    func run nEpochs, nLR
        graph_run(nEpochs, nLR)
    
    func update nLR
        graph_update(nLR)

    func bindGrad nNodeID, oGradTensor
        graph_bind_grad(nNodeID, oGradTensor.pData)

    func free
        graph_free()