# ====================================================================
# Madar AI - LoRA Layer Implementation (Low-Rank Adaptation)
# High-performance trainable adapter using RingTensor C Kernels
# ====================================================================

load "ringtensor.ring"

class MadarLoRALinear
	cName    = "lora_linear"
	nInDim   = 0
	nOutDim  = 0
	nRank    = 8
	fAlpha   = 16.0
	fScale   = 2.0
	bEnabled = true

	# Tensors (C Pointers)
	pA  = NULL  # (Rank x InDim)
	pB  = NULL  # (OutDim x Rank)
	pdA = NULL  # Gradients for A
	pdB = NULL  # Gradients for B

	# Adam Optimizer States
	pMA = NULL
	pVA = NULL
	pMB = NULL
	pVB = NULL

	# Cached activation for backward pass
	pLastX = NULL
	pLastH = NULL

	func init(cLayerName, nIn, nOut, nR = 8, fAlp = 16.0)
		cName   = cLayerName
		nInDim  = nIn
		nOutDim = nOut
		nRank   = nR
		fAlpha  = fAlp
		fScale  = fAlpha / nRank

		# 1. Allocate LoRA A: (r x d_in)
		# Initialized with small Gaussian noise
		pA = tensor_init(nRank, nInDim)
		fBound = 1.0 / sqrt(nRank)
		tensor_random(pA, -fBound, fBound)

		# 2. Allocate LoRA B: (d_out x r)
		# Initialized strictly to ZERO so initial Delta Y == 0
		pB = tensor_init(nOutDim, nRank)
		tensor_fill(pB, 0.0)

		# 3. Gradients
		pdA = tensor_init(nRank, nInDim)
		tensor_fill(pdA, 0.0)
		pdB = tensor_init(nOutDim, nRank)
		tensor_fill(pdB, 0.0)

		# 4. Adam States
		pMA = tensor_init(nRank, nInDim)
		tensor_fill(pMA, 0.0)
		pVA = tensor_init(nRank, nInDim)
		tensor_fill(pVA, 0.0)

		pMB = tensor_init(nOutDim, nRank)
		tensor_fill(pMB, 0.0)
		pVB = tensor_init(nOutDim, nRank)
		tensor_fill(pVB, 0.0)

		return self

	/*
	* Function: forward
	* Computes: DeltaY = scale * ((X * A^T) * B^T)
	* Inputs: pX (Batch x InDim)
	* Output: pDeltaY (Batch x OutDim)
	*/
	func forward(pX)
		if !bEnabled return NULL ok

		nBatch = tensor_get_rows(pX)
		pLastX = pX

		# Step 1: Transpose A -> (InDim x Rank)
		pAT = tensor_init(nInDim, nRank)
		tensor_transpose(pA, pAT)

		# Step 2: H = X * A^T -> (Batch x Rank)
		pLastH = tensor_init(nBatch, nRank)
		tensor_matmul(pX, pAT, pLastH)

		# Step 3: Transpose B -> (Rank x OutDim)
		pBT = tensor_init(nRank, nOutDim)
		tensor_transpose(pB, pBT)

		# Step 4: DeltaY = H * B^T -> (Batch x OutDim)
		pDeltaY = tensor_init(nBatch, nOutDim)
		tensor_matmul(pLastH, pBT, pDeltaY)

		# Step 5: Scale by (alpha / r)
		tensor_scalar_mul(pDeltaY, fScale)

		return pDeltaY

	/*
	* Function: backward
	* Computes gradients with respect to B, A, and Input X
	* Inputs: pdY (Batch x OutDim)
	* Output: pdX (Batch x InDim) for backprop to preceding layer
	*/
	func backward(pdY)
		if !bEnabled or isnull(pLastX) or isnull(pLastH)
			return NULL
		ok

		nBatch = tensor_get_rows(pdY)

		# Scale upstream gradient: pdY_scaled = pdY * fScale
		pdYScaled = tensor_init(nBatch, nOutDim)
		tensor_copy_data(pdYScaled, pdY)
		tensor_scalar_mul(pdYScaled, fScale)

		# 1. Gradient for B: pdB = pdYScaled^T * H -> (OutDim x Batch) * (Batch x Rank) = (OutDim x Rank)
		pdYTrans = tensor_init(nOutDim, nBatch)
		tensor_transpose(pdYScaled, pdYTrans)

		pStepdB = tensor_init(nOutDim, nRank)
		tensor_matmul(pdYTrans, pLastH, pStepdB)
		tensor_add(pdB, pStepdB) # Accumulate gradient

		# 2. Gradient for H: pdH = pdYScaled * B -> (Batch x OutDim) * (OutDim x Rank) = (Batch x Rank)
		pdH = tensor_init(nBatch, nRank)
		tensor_matmul(pdYScaled, pB, pdH)

		# 3. Gradient for A: pdA = pdH^T * X -> (Rank x Batch) * (Batch x InDim) = (Rank x InDim)
		pdHTrans = tensor_init(nRank, nBatch)
		tensor_transpose(pdH, pdHTrans)

		pStepdA = tensor_init(nRank, nInDim)
		tensor_matmul(pdHTrans, pLastX, pStepdA)
		tensor_add(pdA, pStepdA) # Accumulate gradient

		# 4. Gradient for Input X: pdX = pdH * A -> (Batch x Rank) * (Rank x InDim) = (Batch x InDim)
		pdX = tensor_init(nBatch, nInDim)
		tensor_matmul(pdH, pA, pdX)

		return pdX

	/*
	* Function: updateAdam
	* Executes C kernel Adam update on matrices A and B
	*/
	func updateAdam(fLR, nStep, fBeta1 = 0.9, fBeta2 = 0.999, fEps = 0.00000001)
		tensor_update_adam(pA, pdA, pMA, pVA, fLR, fBeta1, fBeta2, fEps, nStep)
		tensor_update_adam(pB, pdB, pMB, pVB, fLR, fBeta1, fBeta2, fEps, nStep)
		zeroGrad()

	/*
	* Function: zeroGrad
	* Resets gradient accumulators to zero
	*/
	func zeroGrad()
		tensor_fill(pdA, 0.0)
		tensor_fill(pdB, 0.0)

	/*
	* Function: computeDeltaWeight
	* Computes the full dense delta matrix: Delta W = scale * (B * A)
	* Output: (OutDim x InDim) tensor ready for merging into base weight
	*/
	func computeDeltaWeight()
		pDeltaW = tensor_init(nOutDim, nInDim)
		tensor_matmul(pB, pA, pDeltaW)
		tensor_scalar_mul(pDeltaW, fScale)
		return pDeltaW

	/*
	* Function: saveAdapter
	* Saves LoRA matrices A and B in binary format
	*/
	func saveAdapter(cDirectory)
		cFileA = cDirectory + "/" + cName + "_lora_a.tensor"
		cFileB = cDirectory + "/" + cName + "_lora_b.tensor"
		tensor_save(pA, cFileA)
		tensor_save(pB, cFileB)

	/*
	* Function: loadAdapter
	* Loads LoRA matrices A and B from binary files
	*/
	func loadAdapter(cDirectory)
		cFileA = cDirectory + "/" + cName + "_lora_a.tensor"
		cFileB = cDirectory + "/" + cName + "_lora_b.tensor"
		pA = tensor_load(cFileA)
		pB = tensor_load(cFileB)

