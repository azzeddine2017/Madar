# ====================================================================
#   MadarAgent - Entity & Pattern Extractor (مستخرج الكيانات والمعاملات)
#   مبني فوق مكتبة ringregex (PCRE2) فائقة السرعة بلغة C
# ====================================================================

class EntityExtractor

	# Extract arithmetic expressions from natural language
	# e.g. "احسب 45 * 2 + 10 من فضلك" -> "45 * 2 + 10"
	# e.g. "calc (100 - 20) / 4" -> "(100 - 20) / 4"
	func extractMathExpression(cText)
		cClean = trim(cText)

		# Pattern targeting math sequences containing numbers and operators
		cPattern = "([0-9\.]+\s*[\+\-\*\/\^\%]\s*[0-9\.\s\+\-\*\/\(\)\^\%]+)"
		oRegex = new RegEx(cPattern, 0)

		if oRegex.match(cClean)
			aMatches = oRegex.findAll(cClean)
			if len(aMatches) > 0
				cExpr = ""
				if islist(aMatches[1])
					cExpr = trim(aMatches[1][1])
				else
					cExpr = trim(aMatches[1])
				ok
				# Strip trailing punctuation if any
				while len(cExpr) > 0 and (right(cExpr, 1) = "?" or right(cExpr, 1) = "." or right(cExpr, 1) = "؟")
					cExpr = left(cExpr, len(cExpr) - 1)
				end
				return trim(cExpr)
			ok
		ok

		# Fallback: strip leading keywords if explicit
		cPrefixes = ["احسب:", "احسب", "كم ناتج", "ما حاصل", "calc:", "calc"]
		for p in cPrefixes
			if left(lower(cClean), len(p)) = p
				cCandidate = trim(substr(cClean, len(p) + 1))
				if len(cCandidate) > 0
					return cCandidate
				ok
			ok
		next

		return ""

	# Extract file paths from natural language
	# e.g. "اقرأ الملف config.ring واعرضه" -> "config.ring"
	func extractFilePath(cText)
		cPattern = "([a-zA-Z0-9_\-\.\/\\]+\.(?:ring|txt|md|json|csv|bin|c|h|py|log))"
		oRegex = new RegEx(cPattern, 1) # Case-insensitive

		if oRegex.match(cText)
			aMatches = oRegex.findAll(cText)
			if len(aMatches) > 0
				if islist(aMatches[1])
					return trim(aMatches[1][1])
				else
					return trim(aMatches[1])
				ok
			ok
		ok
		return ""

	# Extract XML Tool Calls: <tool_call><name>...</name>...</tool_call>
	func extractToolCalls(cText)
		aCalls = []
		# Pattern matching <tool_call><name>X</name>Y</tool_call>
		cPattern = "<tool_call>\\s*<name>([^<]+)</name>([\\s\\S]*?)</tool_call>"
		oRegex = new RegEx(cPattern, 0)

		if oRegex.match(cText)
			aMatches = oRegex.findAll(cText)
			for item in aMatches
				block = item
				if islist(item) block = item[1] ok

				# Extract name and body
				cName = ""
				cBody = ""
				oNameRegex = new RegEx("<name>([^<]+)</name>", 0)
				if oNameRegex.match(block)
					aNames = oNameRegex.findAll(block)
					if len(aNames) > 0
						cName = aNames[1]
						if islist(cName) cName = cName[1] ok
						# Remove XML tags from match
						cName = substr(cName, "<name>", "")
						cName = substr(cName, "</name>", "")
						cName = trim(cName)
					ok
				ok

				# Extract inner body between </name> and </tool_call>
				nPosName = substr(block, "</name>")
				nPosEnd  = substr(block, "</tool_call>")
				if nPosName > 0 and nPosEnd > nPosName
					cBody = substr(block, nPosName + 7, nPosEnd - (nPosName + 7))
				ok

				if cName != ""
					aCalls + [cName, trim(cBody)]
				ok
			next
		ok
		return aCalls
