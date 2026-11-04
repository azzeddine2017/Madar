# ====================================================================
# Madar AI - Loss Functions for Instruction Fine-Tuning
# Supports dense cross-entropy and masked instruction-loss
# ====================================================================

load "ringtensor.ring"

class MadarCrossEntropyLoss
	fLastLoss = 0.0

	/*
	* Function: forward
	* Computes Cross-Entropy loss between logits and target probabilities
	* Inputs: pPred (Batch x Vocab), pTarget (Batch x Vocab)
	* Output: Float (Loss scalar)
	*/
	func forward(pPred, pTarget)
		fLastLoss = tensor_crossentropy_loss(pPred, pTarget)
		return fLastLoss

	/*
	* Function: backward
	* Computes gradient with respect to logits: Grad = (Softmax(Pred) - Target) / Batch
	* Inputs: pPred, pTarget
	* Output: pGrad (Batch x Vocab)
	*/
	func backward(pPred, pTarget)
		nRows = tensor_get_rows(pPred)
		nCols = tensor_get_cols(pPred)
		pGrad = tensor_init(nRows, nCols)
		tensor_crossentropy_backward(pPred, pTarget, pGrad)
		return pGrad

	/*
	* Function: computeTokenLoss
	* Computes Cross-Entropy for a specific target token index without full one-hot allocation
	* Inputs: aLogits (List of numbers), nTargetTokenID (1-based index)
	* Output: Loss for this single token
	*/
	func computeTokenLoss(aLogits, nTargetTokenID)
		nSize = len(aLogits)
		if nTargetTokenID < 1 or nTargetTokenID > nSize
			return 0.0
		ok

		# 1. Numerical Stability: Find Max
		fMax = aLogits[1]
		for i = 2 to nSize
			if aLogits[i] > fMax fMax = aLogits[i] ok
		next

		# 2. Exponentiate and Sum
		fSumExp = 0.0
		for i = 1 to nSize
			fSumExp += exp(aLogits[i] - fMax)
		next

		# 3. Log-Softmax: log(P[target]) = (Logit[target] - Max) - log(SumExp)
		fLogProb = (aLogits[nTargetTokenID] - fMax) - log(fSumExp)
		fLoss = -fLogProb
		return fLoss

