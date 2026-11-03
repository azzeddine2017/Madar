# ====================================================================
# Madar AI - Context Budget Manager (MadarContextManager)
# Features:
#   1. Dynamic Token Budget Allocation (Context Window Awareness)
#   2. "Lost in the Middle" Mitigation (Strategic Placement of Top Context)
#   3. Graceful Truncation with Ellipsis (...)
#   4. Multi-Template Formatting (ChatML, Tags, System/User Blocks)
# ====================================================================

load "stdlibcore.ring"

class MadarContextManager

    nMaxContextTokens   = 4096  # Total context window of the model
    nMaxGenTokens       = 256   # Tokens reserved for LLM generation
    nSafetyMarginTokens = 40    # Breathing room for delimiters / special tokens
    oTokenizer          = NULL  # Optional native tokenizer
    cFormat             = "chatml" # "chatml", "tags", or "plain"

    func init(nMaxContext = 4096, nMaxGen = 256, oTok = NULL)
        nMaxContextTokens = nMaxContext
        nMaxGenTokens = nMaxGen
        oTokenizer = oTok
        return self

    # ----------------------------------------------------------------
    # Token count estimator (uses native tokenizer if present, else ~1.3 tokens/word)
    # ----------------------------------------------------------------
    func estimateTokens(cText)
        if !isNull(oTokenizer)
            try
                aTokens = oTokenizer.encode(cText)
                return len(aTokens)
            catch
                # Fallback to word heuristic
            done
        ok
        aWords = split(trim(cText), " ")
        return ceil(len(aWords) * 1.35)

    # ----------------------------------------------------------------
    # Assemble Augmented Prompt with Budgeting and Strategic Placement
    # ----------------------------------------------------------------
    func buildPrompt(aRetrievedDocs, cQuestion, cSystemPrompt = "")
        if cSystemPrompt = ""
            cSystemPrompt = "You are a precise, factual assistant. Answer the user's question based strictly on the provided Context. If the context does not contain the answer, state that clearly."
        ok

        # 1. Calculate Reserved Budget
        nSysTokens  = estimateTokens(cSystemPrompt)
        nUserTokens = estimateTokens(cQuestion)
        nReserved   = nSysTokens + nUserTokens + nMaxGenTokens + nSafetyMarginTokens
        nRemainingBudget = nMaxContextTokens - nReserved

        if nRemainingBudget < 50
            nRemainingBudget = 50 # Minimum budget floor
        ok

        # 2. Pack Documents into Remaining Budget
        aPackedDocs = []
        nAccumulatedBudget = 0

        for doc in aRetrievedDocs
            cDocText = extractDocText(doc)
            if trim(cDocText) = "" loop ok

            nDocCost = estimateTokens(cDocText)
            if (nAccumulatedBudget + nDocCost) <= nRemainingBudget
                aPackedDocs + cDocText
                nAccumulatedBudget += nDocCost
            else
                # Truncate this document to fit the remaining headroom
                nAllowed = nRemainingBudget - nAccumulatedBudget
                if nAllowed > 20
                    cTruncated = truncateText(cDocText, nAllowed)
                    aPackedDocs + (cTruncated + "...")
                    nAccumulatedBudget += nAllowed
                ok
                exit # Budget exhausted
            ok
        next

        # 3. Strategic Placement (Mitigate "Lost in the Middle")
        # Place the highest-ranked document (#1) closest to the question at the bottom,
        # and #2 at the top, sandwiching lower-ranked context in between.
        aArrangedDocs = arrangeContext(aPackedDocs)

        # 4. Assemble Final Context Body
        cContextBody = ""
        for i = 1 to len(aArrangedDocs)
            cContextBody += f"[Reference #{i}]:" + nl + aArrangedDocs[i] + nl + nl
        next

        # 5. Format Prompt according to Template
        if cFormat = "chatml"
            cFinalPrompt = f"<|im_start|>system" + nl +
                           f"{cSystemPrompt}" + nl + nl +
                           f"Relevant Context:" + nl +
                           f"{cContextBody}<|im_end|>" + nl +
                           f"<|im_start|>user" + nl +
                           f"{cQuestion}<|im_end|>" + nl +
                           f"<|im_start|>assistant" + nl
            return cFinalPrompt
        elseif cFormat = "tags"
            cFinalPrompt = f"<SYSTEM>{cSystemPrompt}</SYSTEM>" + nl +
                           f"<CONTEXT>" + nl + cContextBody + f"</CONTEXT>" + nl +
                           f"<QUESTION>{cQuestion}</QUESTION>" + nl +
                           f"<ANSWER>" + nl
            return cFinalPrompt
        else
            cFinalPrompt = f"System: {cSystemPrompt}" + nl + nl +
                           f"Context:" + nl + cContextBody + nl +
                           f"Question: {cQuestion}" + nl +
                           f"Answer: "
            return cFinalPrompt
        ok

    # ----------------------------------------------------------------
    # Strategic Arrangement: [Rank 2, Rank 3, ... Rank 1]
    # Ensures Rank 1 is right next to the user question to maximize attention.
    # ----------------------------------------------------------------
    func arrangeContext(aDocs)
        nLen = len(aDocs)
        if nLen <= 2
            return aDocs
        ok
        # Take Rank 1 and put it at the very bottom
        oTop1 = aDocs[1]
        aRemaining = aDocs[2:nLen]
        aRemaining + oTop1
        return aRemaining

    # ----------------------------------------------------------------
    # Graceful Text Truncation
    # ----------------------------------------------------------------
    func truncateText(cText, nAllowedTokens)
        nAllowedWords = max(10, floor(nAllowedTokens / 1.35))
        aWords = split(trim(cText), " ")
        if len(aWords) <= nAllowedWords
            return cText
        ok
        aSub = aWords[1:nAllowedWords]
        cResult = ""
        for i = 1 to len(aSub)
            if i > 1 cResult += " " ok
            cResult += aSub[i]
        next
        return cResult

    # ----------------------------------------------------------------
    # Robust Document Text Extractor
    # ----------------------------------------------------------------
    func extractDocText(doc)
        if isstring(doc) return doc ok
        if islist(doc)
            for item in doc
                if islist(item) and len(item) >= 2
                    if lower("" + item[1]) = "text"
                        return "" + item[2]
                    ok
                ok
            next
            if len(doc) >= 1 and isstring(doc[1])
                return doc[1]
            ok
        ok
        return ""
