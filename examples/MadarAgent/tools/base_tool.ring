# ====================================================================
#   MadarAgent - Extensible Tool System
#   نظام الأدوات البرمجية الشامل والآمن للوكيل الذكي
# ====================================================================


# --------------------------------------------------------------------
# 1. Base Class: AgentTool (الفئة الأساسية المجردة للأداة)
# --------------------------------------------------------------------
class AgentTool
	cName        = ""
	cDescription = ""
	aParameters  = []  # Format: [ [cName, cType, cDesc, bRequired] ]

	func init(name = "", desc = "", params = [])
		cName = name
		cDescription = desc
		aParameters = params
		return self

	func execute(aArgs)
		# Subclasses MUST override this method
		return "Error: Tool execution not implemented for " + cName

	func toXmlSchema()
		cParamStr = ""
		for p in aParameters
			cParamStr += f'"{p[1]}"'
			if p != aParameters[len(aParameters)] cParamStr += ", " ok
		next
		return f'- {cName}({cParamStr}): {cDescription}. Call: <tool_call><function name="{cName}"><arguments>[{cParamStr}]</arguments></function></tool_call>'

	func toJsonSchema()
		cJson = f'{{"name": "{cName}", "description": "{cDescription}"'
		if len(aParameters) > 0
			cJson += ', "parameters": ['
			for i = 1 to len(aParameters)
				p = aParameters[i]
				cJson += f'{{"name": "{p[1]}", "type": "{p[2]}", "desc": "{p[3]}"}}'
				if i < len(aParameters) cJson += ", " ok
			next
			cJson += ']'
		ok
		cJson += '}'
		return cJson

# --------------------------------------------------------------------
# 2. ToolRegistry: Registry, Validator & Safe Execution Boundary
# --------------------------------------------------------------------
class ToolRegistry
	aTools = [] # List of AgentTool instances

	func register(oTool)
		if not isobject(oTool) return false ok
		# Replace if already exists, else append
		for i = 1 to len(aTools)
			if aTools[i].cName = oTool.cName
				aTools[i] = oTool
				return true
			ok
		next
		aTools + oTool
		return true

	func getTool(cName)
		cLower = lower(trim(cName))
		for t in aTools
			if lower(t.cName) = cLower return t ok
		next
		return NULL

	func has(cName)
		return (getTool(cName) != NULL)

	func count()
		return len(aTools)

	func list()
		return aTools

	func execute(cName, aArgs)
		oTool = getTool(cName)
		if oTool = NULL
			return f"Error: Tool '{cName}' is not registered in ToolRegistry."
		ok

		# Safe execution boundary
		try
			cResult = oTool.execute(aArgs)
			return "" + cResult
		catch
			return f"Error executing tool '{cName}': {cCatchError}"
		done

	func buildSchemaPrompt(cFormat = "xml", aFilterNames = [])
		if len(aTools) = 0 return "" ok
		cSchema = "# Available Tools (Call ONLY when needed):" + nl
		nCount = 0
		for t in aTools
			# If filter list provided, only include matching tools
			if len(aFilterNames) > 0
				bMatch = false
				for fName in aFilterNames
					if lower(trim(fName)) = lower(trim(t.cName))
						bMatch = true
						exit
					ok
				next
				if !bMatch loop ok
			ok

			nCount++
			if cFormat = "xml"
				cSchema += t.toXmlSchema() + nl
			else
				cSchema += t.toJsonSchema() + nl
			ok
		next
		if nCount = 0 return "" ok
		return cSchema

