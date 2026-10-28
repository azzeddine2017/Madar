# ====================================================================
#   MadarAgent - Intelligent Tool Calling Engine
#   محرك استخراج وتنفيذ استدعاءات الأدوات البرمجية وتغذية الملاحظات للنموذج
# ====================================================================

class ToolCallingEngine
	oRegistry = NULL

	func init(oToolRegistry)
		oRegistry = oToolRegistry
		return self

	# ----------------------------------------------------------------
	# Detect if the generated text contains tool calls
	# ----------------------------------------------------------------
	func hasToolCall(cText)
		if substr(cText, "<tool_call>") > 0 return true ok
		if substr(cText, "</tool_call>") > 0 return true ok
		if substr(cText, "[ACTION:") > 0 return true ok
		return false

	# ----------------------------------------------------------------
	# Parse and extract tool call data: returns [ [cToolName, aArgs, cOriginalBlock] ]
	# ----------------------------------------------------------------
	func extractToolCalls(cText)
		aCalls = []

		# 1. Parse XML-style tool calls: <tool_call>...</tool_call>
		nPos = substr(cText, "<tool_call>")
		while nPos > 0
			nEndPos = substr(cText, "</tool_call>")
			if nEndPos <= nPos exit ok

			nBlockLen = (nEndPos + 12) - nPos
			cBlock = substr(cText, nPos, nBlockLen)

			# Extract function name
			cToolName = ""
			nNameStart = substr(cBlock, 'name="')
			if nNameStart > 0
				nNameStart += 6
				cAfterName = substr(cBlock, nNameStart)
				nQuote = substr(cAfterName, '"')
				if nQuote > 0
					cToolName = substr(cAfterName, 1, nQuote - 1)
				ok
			ok

			# Extract arguments
			aArgs = []
			nArgStart = substr(cBlock, "<arguments>")
			nArgEnd = substr(cBlock, "</arguments>")
			if nArgStart > 0 and nArgEnd > nArgStart
				nArgStart += 11
				cArgsRaw = trim(substr(cBlock, nArgStart, nArgEnd - nArgStart))
				aArgs = parseArguments(cArgsRaw)
			ok

			if cToolName != ""
				aCalls + [cToolName, aArgs, cBlock]
			ok

			# Find next call
			cText = substr(cText, nEndPos + 12)
			nPos = substr(cText, "<tool_call>")
		end

		# 2. Parse Bracket-style tool calls: [ACTION: func(arg1, arg2)]
		if len(aCalls) = 0 and substr(cText, "[ACTION:") > 0
			nActStart = substr(cText, "[ACTION:")
			cAfterAct = substr(cText, nActStart)
			nActEndRel = substr(cAfterAct, "]")
			if nActEndRel > 0
				cActBlock = substr(cAfterAct, 1, nActEndRel)
				cInner = substr(cActBlock, 9, len(cActBlock) - 9) # remove '[ACTION:' and ']'
				cInner = trim(substr(cInner, 1, len(cInner) - 1))
				nParen = substr(cInner, "(")
				if nParen > 0
					cToolName = trim(substr(cInner, 1, nParen - 1))
					cArgsRaw = substr(cInner, nParen + 1)
					if substr(cArgsRaw, ")") > 0
						cArgsRaw = substr(cArgsRaw, 1, substr(cArgsRaw, ")") - 1)
					ok
					aArgs = parseArguments(cArgsRaw)
					aCalls + [cToolName, aArgs, cActBlock]
				ok
			ok
		ok

		return aCalls

	# ----------------------------------------------------------------
	# Helper: Parse raw argument string into array
	# Handles: [120, "path/file.txt", "content"] or comma-separated
	# ----------------------------------------------------------------
	func parseArguments(cArgsRaw)
		cArgsRaw = trim(cArgsRaw)
		if cArgsRaw = "" return [] ok

		# Strip outer brackets if present
		if left(cArgsRaw, 1) = "[" and right(cArgsRaw, 1) = "]"
			cArgsRaw = substr(cArgsRaw, 2, len(cArgsRaw) - 2)
		ok
		cArgsRaw = trim(cArgsRaw)
		if cArgsRaw = "" return [] ok

		# Simple token parsing handling quotes
		aArgs = []
		cCurrent = ""
		bInQuote = false
		cQuoteChar = ""

		for i = 1 to len(cArgsRaw)
			cChar = cArgsRaw[i]
			if (cChar = '"' or cChar = "'")
				if !bInQuote
					bInQuote = true
					cQuoteChar = cChar
				elseif cChar = cQuoteChar
					bInQuote = false
					cQuoteChar = ""
				else
					cCurrent += cChar
				ok
			elseif cChar = "," and !bInQuote
				aArgs + trim(cCurrent)
				cCurrent = ""
			else
				cCurrent += cChar
			ok
		next

		if trim(cCurrent) != ""
			aArgs + trim(cCurrent)
		ok

		return aArgs

	# ----------------------------------------------------------------
	# Execute extracted calls and produce observation block
	# ----------------------------------------------------------------
	func executeCalls(aCalls)
		if len(aCalls) = 0 return "" ok
		cResponses = ""
		for callItem in aCalls
			cName = callItem[1]
			aArgs = callItem[2]
			cRes = oRegistry.execute(cName, aArgs)
			cResponses += f"<tool_response name='{cName}'>" + nl
			cResponses += cRes + nl
			cResponses += "</tool_response>" + nl
		next
		return cResponses
