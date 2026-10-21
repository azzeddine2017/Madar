# ====================================================================
#   Madar DataFrame - High-Performance Table & CSV Analytics Core
#   (محرك جداول البيانات فائق السرعة المبني على RingTensor وذاكرة C)
# ====================================================================



func read_csv(cFilePath)
	return new DataFrame(cFilePath)

class DataFrame
	aColumns     = []         # Column names [ "age", "salary", ... ]
	aColumnTypes = []         # Types: "numeric" | "string"
	aData        = []         # Raw row records [ [v1, v2], ... ]
	aTensors     = []         # Column Name -> Continuous RingTensor for numeric columns
	nRows        = 0
	nCols        = 0

	func init(cFilePath)
		if cFilePath != "" and fexists(cFilePath)
			loadCSV(cFilePath)
		ok
		return self

	func loadCSV(cFilePath)
		cContent = read(cFilePath)
		if len(cContent) = 0 return self ok

		# Clean carriage returns
		cContent = substr(cContent, char(13), "")
		aLines = split(cContent, nl)

		if len(aLines) = 0 return self ok

		# Parse Header
		cHeaderLine = trim(aLines[1])
		aColumns = parseCSVLine(cHeaderLine)
		nCols = len(aColumns)

		# Parse Data Rows
		aData = []
		for i = 2 to len(aLines)
			cLine = trim(aLines[i])
			if cLine != ""
				row = parseCSVLine(cLine)
				if len(row) = nCols
					aData + row
				ok
			ok
		next

		nRows = len(aData)
		buildTensors()
		return self

	func shape()
		return [nRows, nCols]

	func columns()
		return aColumns

	func buildTensors()
		aColumnTypes = []
		aTensors = []

		for c = 1 to nCols
			colName = aColumns[c]
			bIsNumeric = 1
			aColValues = []

			for r = 1 to nRows
				val = aData[r][c]
				if not isNumberStr(val)
					bIsNumeric = 0
					exit
				else
					aColValues + number(val)
				ok
			next

			if bIsNumeric and nRows > 0
				aColumnTypes + "numeric"
				# Build C-native continuous Float32 RingTensor
				tCol = tensor_from_list(aColValues, "Float32")
				aTensors + [colName, tCol]
			else
				aColumnTypes + "string"
			ok
		next

	func getTensor(cColName)
		cColName = lower(trim(cColName))
		for item in aTensors
			if lower(item[1]) = cColName
				return item[2]
			ok
		next
		return NULL

	# ==================================================================
	#   C-Accelerated Mathematical & Statistical Reductions
	# ==================================================================

	func mean(cColName)
		t = getTensor(cColName)
		if t != NULL
			return tensor_mean(t)
		ok
		return 0.0

	func sum(cColName)
		t = getTensor(cColName)
		if t != NULL
			return tensor_sum(t)
		ok
		return 0.0

	func min(cColName)
		t = getTensor(cColName)
		if t != NULL
			return tensor_min(t)
		ok
		return 0.0

	func max(cColName)
		t = getTensor(cColName)
		if t != NULL
			return tensor_max(t)
		ok
		return 0.0

	func std(cColName)
		t = getTensor(cColName)
		if t = NULL or nRows <= 1 return 0.0 ok
		m = tensor_mean(t)
		aVals = tensor_to_list(t)
		sumSq = 0.0
		for v in aVals
			diff = v - m
			sumSq += diff * diff
		next
		return sqrt(sumSq / (nRows - 1))

	# ==================================================================
	#   Filtering & Slicing Operations
	# ==================================================================

	func filter(cColName, cOp, val)
		colIdx = findColumn(cColName)
		if colIdx = 0 return self ok

		dfNew = new DataFrame("")
		dfNew.aColumns = aColumns
		dfNew.nCols = nCols
		dfNew.aData = []

		bValIsNum = isnumber(val) or isNumberStr("" + val)
		nTargetVal = 0
		if bValIsNum
			nTargetVal = number("" + val)
		ok

		for r = 1 to nRows
			cell = aData[r][colIdx]
			bMatch = 0

			if bValIsNum and isNumberStr(cell)
				nCellVal = number("" + cell)
				if cOp = ">"  and nCellVal > nTargetVal  bMatch = 1 ok
				if cOp = ">=" and nCellVal >= nTargetVal bMatch = 1 ok
				if cOp = "<"  and nCellVal < nTargetVal  bMatch = 1 ok
				if cOp = "<=" and nCellVal <= nTargetVal bMatch = 1 ok
				if (cOp = "=" or cOp = "==") and nCellVal = nTargetVal bMatch = 1 ok
				if (cOp = "!=" or cOp = "<>") and nCellVal != nTargetVal bMatch = 1 ok
			else
				sCellVal = lower(trim("" + cell))
				sTargetVal = lower(trim("" + val))
				if (cOp = "=" or cOp = "==") and sCellVal = sTargetVal bMatch = 1 ok
				if (cOp = "!=" or cOp = "<>") and sCellVal != sTargetVal bMatch = 1 ok
				if cOp = "contains" and substr(sCellVal, sTargetVal) > 0 bMatch = 1 ok
			ok

			if bMatch
				dfNew.aData + aData[r]
			ok
		next

		dfNew.nRows = len(dfNew.aData)
		dfNew.buildTensors()
		return dfNew

	func select(aColNames)
		dfNew = new DataFrame("")
		aNewCols = []
		aColIndices = []

		for name in aColNames
			idx = findColumn(name)
			if idx > 0
				aNewCols + aColumns[idx]
				aColIndices + idx
			ok
		next

		dfNew.aColumns = aNewCols
		dfNew.nCols = len(aNewCols)
		dfNew.aData = []

		for r = 1 to nRows
			newRow = []
			for idx in aColIndices
				newRow + aData[r][idx]
			next
			dfNew.aData + newRow
		next

		dfNew.nRows = len(dfNew.aData)
		dfNew.buildTensors()
		return dfNew

	# ==================================================================
	#   Display & Summaries
	# ==================================================================

	func head(n)
		if n <= 0 n = 5 ok
		if n > nRows n = nRows ok
		printTable(1, n)

	func tail(n)
		if n <= 0 n = 5 ok
		if n > nRows n = nRows ok
		printTable(nRows - n + 1, nRows)

	func printTable(nStart, nEnd)
		see nl
		# Print Header
		for c = 1 to nCols
			see padRight(aColumns[c], 16) + " | "
		next
		see nl
		for c = 1 to nCols
			see "-----------------+"
		next
		see nl

		# Print Rows
		for r = nStart to nEnd
			for c = 1 to nCols
				see padRight("" + aData[r][c], 16) + " | "
			next
			see nl
		next
		see "[" + (nEnd - nStart + 1) + " rows x " + nCols + " columns]" + nl

	func describe()
		see nl + "================================================================================" + nl
		see "  Madar DataFrame Summary Statistics (C-Tensor Accelerated)" + nl
		see "================================================================================" + nl
		see padRight("Metric", 12) + " | "
		for item in aTensors
			see padRight(item[1], 15) + " | "
		next
		see nl
		for c = 1 to (len(aTensors) + 1)
			see "----------------+"
		next
		see nl

		see padRight("Count", 12) + " | "
		for item in aTensors see padRight("" + nRows, 15) + " | " next
		see nl

		see padRight("Mean", 12) + " | "
		for item in aTensors see padRight("" + round(mean(item[1]), 3), 15) + " | " next
		see nl

		see padRight("Std", 12) + " | "
		for item in aTensors see padRight("" + round(std(item[1]), 3), 15) + " | " next
		see nl

		see padRight("Min", 12) + " | "
		for item in aTensors see padRight("" + round(min(item[1]), 3), 15) + " | " next
		see nl

		see padRight("Max", 12) + " | "
		for item in aTensors see padRight("" + round(max(item[1]), 3), 15) + " | " next
		see nl
		see "================================================================================" + nl

	private

	func findColumn(cName)
		cName = lower(trim(cName))
		for i = 1 to len(aColumns)
			if lower(aColumns[i]) = cName
				return i
			ok
		next
		return 0

	func parseCSVLine(cLine)
		aCells = []
		cCell = ""
		bInQuotes = 0
		for i = 1 to len(cLine)
			ch = cLine[i]
			if ch = '"'
				bInQuotes = not bInQuotes
			elseif ch = ',' and not bInQuotes
				aCells + trim(cCell)
				cCell = ""
			else
				cCell += ch
			ok
		next
		aCells + trim(cCell)
		return aCells

	func isNumberStr(s)
		s = trim("" + s)
		if len(s) = 0 return 0 ok
		nDots = 0
		for i = 1 to len(s)
			ch = s[i]
			nAsc = ascii(ch)
			if nAsc >= 48 and nAsc <= 57
				# Digit 0-9
			elseif ch = "."
				nDots++
				if nDots > 1 return 0 ok
			elseif ch = "-" and i = 1
				# Negative sign
			else
				return 0
			ok
		next
		return 1

	func padRight(s, nWidth)
		s = "" + s
		while len(s) < nWidth
			s += " "
		end
		return s

	func round(val, nDec)
		s = "" + val
		nDot = substr(s, ".")
		if nDot > 0 and len(s) > nDot + nDec
			return left(s, nDot + nDec)
		ok
		return s
