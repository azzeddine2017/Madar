# ====================================================================
# Madar AI - Optimizer & Learning Rate Scheduler
# AdamW Optimizer with Warmup, Cosine Annealing, and Gradient Clipping
# ====================================================================

load "ringtensor.ring"

class MadarAdamW
	fBaseLR       = 0.0002
	fMinLR        = 0.00001
	fCurrentLR    = 0.0002
	fBeta1        = 0.9
	fBeta2        = 0.999
	fEps          = 0.00000001
	fWeightDecay  = 0.01
	fMaxNorm      = 1.0

	nTotalSteps   = 1000
	nWarmupSteps  = 50
	nCurrentStep  = 0

	aLoRALayers   = []

	func init(aLayers, fLR = 0.0002, nSteps = 1000, nWarmup = 50, fWD = 0.01)
		aLoRALayers  = aLayers
		fBaseLR      = fLR
		fCurrentLR   = fLR
		nTotalSteps  = nSteps
		nWarmupSteps = nWarmup
		fWeightDecay = fWD
		nCurrentStep = 0
		return self

	/*
	* Function: computeScheduledLR
	* Computes learning rate based on Linear Warmup + Cosine Annealing
	*/
	func computeScheduledLR(nStep)
		if nStep < 1 return fMinLR ok

		# 1. Warmup Phase
		if nStep <= nWarmupSteps and nWarmupSteps > 0
			fRatio = nStep / nWarmupSteps
			return fMinLR + fRatio * (fBaseLR - fMinLR)
		ok

		# 2. Cosine Decay Phase
		if nStep >= nTotalSteps
			return fMinLR
		ok

		fProgress = (nStep - nWarmupSteps) / (nTotalSteps - nWarmupSteps)
		fCos = cos(fProgress * 3.141592653589793)
		fLR = fMinLR + 0.5 * (fBaseLR - fMinLR) * (1.0 + fCos)
		return fLR

	/*
	* Function: step
	* Performs gradient clipping, weight decay, and AdamW update across all LoRA layers
	*/
	func step()
		nCurrentStep++
		fCurrentLR = computeScheduledLR(nCurrentStep)

		# 1. Collect all gradient pointers for global norm clipping
		aGrads = []
		for oLayer in aLoRALayers
			aGrads + oLayer.pdA
			aGrads + oLayer.pdB
		next

		if len(aGrads) > 0 and fMaxNorm > 0.0
			tensor_clip_global_norm(aGrads, fMaxNorm)
		ok

		# 2. Execute Adam update per layer with decoupled weight decay
		for oLayer in aLoRALayers
			# Weight decay on Matrix A (Matrix B is zero-initialized and regularized)
			if fWeightDecay > 0.0
				tensor_scalar_mul(oLayer.pA, 1.0 - (fCurrentLR * fWeightDecay))
			ok

			oLayer.updateAdam(fCurrentLR, nCurrentStep, fBeta1, fBeta2, fEps)
		next

	/*
	* Function: zeroGrad
	* Clears gradients across all attached LoRA layers
	*/
	func zeroGrad()
		for oLayer in aLoRALayers
			oLayer.zeroGrad()
		next

