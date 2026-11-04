# ====================================================================
# Madar AI - Native Documentation to Instruction Dataset Converter
# Converts official Ring Sphinx documentation (158 RST sources) into
# a high-density, unified JSONL instruction-tuning training dataset.
# Written 100% in pure Madar / Ring with Zero external dependencies.
# ====================================================================

load "stdlibcore.ring"

func main()
    ? "===================================================================="
    ? "  Madar AI: Official Ring Documentation Dataset Synthesizer"
    ? "  100% Native Ring/Madar Engine (Zero Shell, Zero Python Dependency)"
    ? "===================================================================="

    # 1. Locate Source Directory
    cSourceDir = "C:/ring/documents/build/html/_sources"
    if !direxists(cSourceDir)
        cSourceDir = "documents/build/html/_sources"
    ok
    if !direxists(cSourceDir)
        cSourceDir = "../documents/build/html/_sources"
    ok
    if !direxists(cSourceDir)
        cSourceDir = "/content/ring/documents/build/html/_sources"
    ok

    if !direxists(cSourceDir)
        ? f"  [ERROR] Documentation sources directory not found at: {cSourceDir}"
        ? "  Please ensure the Ring docs folder '_sources' is available."
        return
    ok

    # 2. Output Configuration
    cDataDir = "data"
    if !direxists(cDataDir)
        # Create data directory if missing
        if iswindows()
            system("mkdir data >nul 2>&1")
        else
            system("mkdir -p data >/dev/null 2>&1")
        ok
    ok

    cOutputFile = cDataDir + "/ring_instruct_dataset.jsonl"
    cSummaryFile = cDataDir + "/ring_dataset_summary.txt"

    ? f"  [Sources Path] {cSourceDir}"
    ? f"  [Target JSONL] {cOutputFile}"
    ? "--------------------------------------------------------------------"

    # 3. Read All Source Files
    aDirEntries = dir(cSourceDir)
    aFiles = []
    for entry in aDirEntries
        cName = entry[1]
        cExt = lower(right(cName, 4))
        if cExt = ".txt" and entry[2] = 0 # 0 means regular file in Ring dir()
            aFiles + cName
        ok
    next

    ? f"  Found {len(aFiles)} Sphinx documentation source files."
    ? "  Parsing sections, syntax rules, and code examples..."
    ? "--------------------------------------------------------------------"

    # 4. Open Output JSONL File
    fpOut = fopen(cOutputFile, "wb")
    if fpOut = NULL
        ? f"  [ERROR] Cannot open output file '{cOutputFile}' for writing."
        return
    ok

    nTotalPairs = 0
    nTotalFiles = 0
    t0 = clock()

    for cFileName in aFiles
        cFilePath = cSourceDir + "/" + cFileName
        cContent = read(cFilePath)
        if len(trim(cContent)) = 0 loop ok

        aPairs = parseRstDocument(cContent, cFileName)
        if len(aPairs) > 0
            for pair in aPairs
                cJsonRecord = formatJsonLine(pair[:instruction], pair[:output])
                fputs(fpOut, cJsonRecord + nl)
                nTotalPairs++
            next
            nTotalFiles++
            ? f"  + [{cFileName}] -> Generated {len(aPairs)} instruction pairs"
        ok
    next

    fclose(fpOut)
    t1 = clock()
    fSec = (t1 - t0) / clockspersecond()

    ? "===================================================================="
    ? f"  [SUCCESS] Dataset Synthesis Complete in {fSec} seconds!"
    ? f"  Total Processed Files : {nTotalFiles} / {len(aFiles)}"
    ? f"  Total Training Pairs  : {nTotalPairs} Instruction-Response Pairs"
    ? f"  Saved Output File     : {cOutputFile}"
    ? "===================================================================="

# --------------------------------------------------------------------
# Parse Sphinx RST Content into Structured Instruction-Response Pairs
# --------------------------------------------------------------------
func parseRstDocument(cContent, cFileName)
    aLines = split(cContent, nl)
    nLineCount = len(aLines)
    aPairs = []

    cDocTitle     = JustFileName(cFileName)
    cSectionTitle = ""
    cDescription  = ""
    cSyntaxCode   = ""
    cExampleCode  = ""
    cOutputCode   = ""

    nState = 0 # 0=normal, 1=in_syntax, 2=in_example, 3=in_output, 4=in_note

    for i = 1 to nLineCount
        sRaw = aLines[i]
        sTrim = trim(sRaw)

        # 1. Skip Sphinx indexing and meta directives
        if left(sTrim, 9) = ".. index:" or left(sTrim, 5) = "pair:" or left(sTrim, 7) = "single:"
            nState = 0
            loop
        ok
        if left(sTrim, 2) = ".." and left(sTrim, 15) != ".. code-block::"
            nState = 0
            loop
        ok

        # 2. Check for Underlined Headers (=== or --- or ~~~)
        bIsHeader = false
        if i < nLineCount
            sNext = trim(aLines[i + 1])
            if len(sNext) >= 3 and len(sTrim) >= 2
                cChar = sNext[1]
                if (cChar = "=" or cChar = "-" or cChar = "~")
                    bAllSame = true
                    for k = 1 to len(sNext)
                        if sNext[k] != cChar bAllSame = false exit ok
                    next
                    if bAllSame and len(sNext) >= len(sTrim)
                        bIsHeader = true
                    ok
                ok
            ok
        ok

        if bIsHeader
            # Flush previous section if it has meaningful code/syntax
            if (cExampleCode != "" or cSyntaxCode != "") and cSectionTitle != ""
                aPair = buildPair(cDocTitle, cSectionTitle, cDescription, cSyntaxCode, cExampleCode, cOutputCode)
                if aPair != NULL aPairs + aPair ok
            ok

            # Start new section
            cSectionTitle = sTrim
            cDescription  = ""
            cSyntaxCode   = ""
            cExampleCode  = ""
            cOutputCode   = ""
            nState = 0
            i++ # Skip the underline line
            loop
        ok

        # 3. Detect Code Block Transitions
        sLower = lower(sTrim)
        if sLower = "syntax:" or sLower = "* syntax:"
            nState = 1 # preparing syntax
            loop
        elseif sLower = "example:" or sLower = "* example:" or sLower = "examples:"
            nState = 2 # preparing example
            loop
        elseif sLower = "output:" or sLower = "* output:"
            nState = 3 # preparing output
            loop
        ok

        if left(sTrim, 15) = ".. code-block::"
            loop # Skip directive marker itself
        ok

        # 4. Ingest lines based on active state
        if nState = 1 # Syntax code
            if len(sTrim) > 0 and (left(sRaw, 1) = char(9) or left(sRaw, 2) = "  ")
                sCodeLine = unindentCode(sRaw)
                cSyntaxCode += sCodeLine + nl
            elseif sTrim = ""
                # allow blank lines inside code
            else
                nState = 0 # exited indented block
            ok
        elseif nState = 2 # Example code
            if len(sTrim) > 0 and (left(sRaw, 1) = char(9) or left(sRaw, 2) = "  ")
                sCodeLine = unindentCode(sRaw)
                cExampleCode += sCodeLine + nl
            elseif sTrim = ""
                if cExampleCode != "" cExampleCode += nl ok
            else
                nState = 0
            ok
        elseif nState = 3 # Output text
            if len(sTrim) > 0 and (left(sRaw, 1) = char(9) or left(sRaw, 2) = "  ")
                sCodeLine = unindentCode(sRaw)
                cOutputCode += sCodeLine + nl
            elseif sTrim = ""
                # blank line
            else
                nState = 0
            ok
        ok

        # 5. Ingest normal descriptive text
        if nState = 0
            if sTrim != "" and left(sTrim, 2) != ".." and left(sTrim, 1) != "*" and left(sTrim, 5) != "pair:" and left(sTrim, 7) != "single:"
                if cDescription != "" cDescription += " " ok
                cDescription += sTrim
            ok
        ok
    next

    # Flush final section
    if (cExampleCode != "" or cSyntaxCode != "") and cSectionTitle != ""
        aPair = buildPair(cDocTitle, cSectionTitle, cDescription, cSyntaxCode, cExampleCode, cOutputCode)
        if aPair != NULL aPairs + aPair ok
    ok

    return aPairs

# --------------------------------------------------------------------
# Build High-Quality Instruction-Response Item
# --------------------------------------------------------------------
func buildPair(cDoc, cTopic, cDesc, cSyntax, cExample, cOut)
    cTopic = cleanTopic(cTopic)
    if len(cTopic) < 2 return NULL ok
    if cExample = "" and cSyntax = "" return NULL ok

    # Formulate natural instruction
    cInstruction = ""
    nHash = len(cTopic) % 3
    if nHash = 0
        cInstruction = f"How do I use {cTopic} in the Ring programming language? Provide syntax and code examples."
    elseif nHash = 1
        cInstruction = f"Explain the concept and usage of {cTopic} in Ring with a working example."
    else
        cInstruction = f"Write a Ring code example demonstrating how to work with {cTopic}."
    ok

    # Assemble comprehensive grounded response
    cResponse = ""
    if cDesc != ""
        cResponse += cDesc + nl + nl
    else
        cResponse += f"In the Ring programming language, {cTopic} is used as follows:" + nl + nl
    ok

    if cSyntax != ""
        cResponse += "### Syntax:" + nl + "```ring" + nl + trim(cSyntax) + nl + "```" + nl + nl
    ok

    if cExample != ""
        cResponse += "### Code Example:" + nl + "```ring" + nl + trim(cExample) + nl + "```" + nl + nl
    ok

    if cOut != ""
        cResponse += "### Output:" + nl + "```" + nl + trim(cOut) + nl + "```" + nl
    ok

    return [
        :instruction = trim(cInstruction),
        :output      = trim(cResponse)
    ]

# Clean Sphinx header markers
func cleanTopic(cTopic)
    cTopic = substr(cTopic, "*", "")
    cTopic = substr(cTopic, ":", "")
    cTopic = trim(cTopic)
    return cTopic

# --------------------------------------------------------------------
# Pure RFC 8259 JSON Line Formatter
# --------------------------------------------------------------------
func formatJsonLine(cInstruction, cOutput)
    cEscInst = escapeJson(cInstruction)
    cEscOut  = escapeJson(cOutput)
    return '{"instruction": "' + cEscInst + '", "input": "", "output": "' + cEscOut + '"}'

# Robust String Escaper for JSON
func escapeJson(cText)
    cText = substr(cText, "\", "\\")
    cText = substr(cText, '"', '\"')
    cText = substr(cText, char(13), "")
    cText = substr(cText, char(10), "\n")
    cText = substr(cText, char(9), "\t")
    return cText

# Unindent outer 1-level code indent
func unindentCode(sLine)
    if left(sLine, 1) = char(9)
        return substr(sLine, 2)
    elseif left(sLine, 4) = "    "
        return substr(sLine, 5)
    elseif left(sLine, 2) = "  "
        return substr(sLine, 3)
    ok
    return sLine
