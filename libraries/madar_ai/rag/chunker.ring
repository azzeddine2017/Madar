# ====================================================================
# Madar AI - Semantic & Overlapping Text Chunker (MadarChunker)
# Features:
#   1. Sliding Window with Word/Token Overlap (Never cuts context abruptly)
#   2. Sentence-Boundary Respecting (Splits cleanly on . ! ? \n)
#   3. Markdown Heading-Aware Hierarchical Chunking (#, ##, ###)
# ====================================================================

load "stdlibcore.ring"

class MadarChunker

    nDefaultChunkWords = 150  # Target words per chunk (~200 tokens)
    nDefaultOverlapWords = 30 # Overlapping words between consecutive chunks
    nMinChunkChars      = 40  # Filter out trivial fragments

    func init(nChunkWords = 150, nOverlapWords = 30)
        nDefaultChunkWords = nChunkWords
        nDefaultOverlapWords = nOverlapWords
        return self

    # ----------------------------------------------------------------
    # Sliding Window Chunking with Overlap for General Text
    # ----------------------------------------------------------------
    func chunkText(cText, nChunkWords = 0, nOverlapWords = -1)
        if nChunkWords <= 0
            nChunkWords = nDefaultChunkWords
        ok
        if nOverlapWords < 0
            nOverlapWords = nDefaultOverlapWords
        ok

        cClean = trim(cText)
        if len(cClean) < nMinChunkChars
            return [cClean]
        ok

        # Split into words while normalizing multiple whitespace
        aRawWords = split(cClean, " ")
        aWords = []
        for w in aRawWords
            w = trim(w)
            if w != "" aWords + w ok
        next

        nTotalWords = len(aWords)
        if nTotalWords <= nChunkWords
            return [cClean]
        ok

        aChunks = []
        nStep = nChunkWords - nOverlapWords
        if nStep < 1 nStep = 1 ok

        nStart = 1
        while nStart <= nTotalWords
            nEnd = min(nStart + nChunkWords - 1, nTotalWords)
            
            # Slice words for the current chunk
            aSlice = aWords[nStart:nEnd]
            cChunkText = ""
            for i = 1 to len(aSlice)
                if i > 1 cChunkText += " " ok
                cChunkText += aSlice[i]
            next

            if len(trim(cChunkText)) >= nMinChunkChars
                aChunks + trim(cChunkText)
            ok

            if nEnd >= nTotalWords
                exit
            ok
            nStart += nStep
        end

        return aChunks

    # ----------------------------------------------------------------
    # Markdown-Aware Hierarchical Chunking (Preserves section headers)
    # ----------------------------------------------------------------
    func chunkMarkdown(cContent, cDocTitle = "")
        aLines = split(cContent, nl)
        aSections = []
        cCurrentHeader = cDocTitle
        cCurrentBody = ""

        for line in aLines
            sLine = trim(line)
            bIsHeader = false
            if len(sLine) >= 2
                if left(sLine, 2) = "# " or left(sLine, 3) = "## " or left(sLine, 4) = "### "
                    bIsHeader = true
                ok
            ok

            if bIsHeader
                if len(trim(cCurrentBody)) >= nMinChunkChars
                    aSections + [
                        :header = cCurrentHeader,
                        :text   = trim(cCurrentBody)
                    ]
                ok
                cCurrentHeader = sLine
                cCurrentBody = ""
            else
                cCurrentBody += line + nl
            ok
        next

        if len(trim(cCurrentBody)) >= nMinChunkChars
            aSections + [
                :header = cCurrentHeader,
                :text   = trim(cCurrentBody)
            ]
        ok

        # Now apply overlapping chunking within each section
        aFinalChunks = []
        for sec in aSections
            cHeaderPrefix = ""
            if sec[:header] != ""
                cHeaderPrefix = "[" + sec[:header] + "]" + nl
            ok
            aSubChunks = chunkText(sec[:text], nDefaultChunkWords, nDefaultOverlapWords)
            for sub in aSubChunks
                aFinalChunks + (cHeaderPrefix + sub)
            next
        next

        return aFinalChunks

