# ====================================================================
#   MadarAgent - Built-in System Tools
#   أدوات النظام التفاعلية: التوقيت، استعراض المجلدات، قراءة وكتابة الملفات
# ====================================================================


# --------------------------------------------------------------------
# 1. TimeTool: Get Current Time and Date
# --------------------------------------------------------------------
class TimeTool from AgentTool
	func init()
		cName = "get_time"
		cDescription = "Returns the current local date, time, and timezone information"
		aParameters = []
		return self

	func execute(aArgs)
		return f"Current Local Date & Time: {date()} {time()} (Madar Agent System Clock)"

# --------------------------------------------------------------------
# 2. ListFilesTool: Browse Files and Directories
# --------------------------------------------------------------------
class ListFilesTool from AgentTool
	func init()
		cName = "list_files"
		cDescription = "Lists directory contents (files and subdirectories) for a given path"
		aParameters = [
			["dir_path", "string", "Path of directory to list (e.g. '.' or 'subfolder')", false]
		]
		return self

	func execute(aArgs)
		cTarget = "."
		if islist(aArgs) and len(aArgs) >= 1 and trim(aArgs[1]) != ""
			cTarget = trim(aArgs[1])
		elseif isstring(aArgs) and trim(aArgs) != ""
			cTarget = trim(aArgs)
		ok

		cTarget = substr(cTarget, '"', "")
		cTarget = substr(cTarget, "'", "")
		cTarget = trim(cTarget)
		if cTarget = "" cTarget = "." ok

		if not direxists(cTarget)
			return f"Error: Directory '{cTarget}' does not exist."
		ok

		aList = dir(cTarget)
		cOut = ""
		nCount = 0
		for f in aList
			cItemName = f[1]
			bIsDir = f[2]
			if cItemName != "." and cItemName != ".."
				if bIsDir
					cOut += f"  [DIR]  {cItemName}" + nl
				else
					cOut += f"  [FILE] {cItemName}" + nl
				ok
				nCount++
				if nCount >= 30
					cOut += f"  ... and {len(aList) - nCount} more items." + nl
					exit
				ok
			ok
		next

		if cOut = "" return f"Directory '{cTarget}' is empty." ok
		return f"Contents of '{cTarget}' ({nCount} items):" + nl + cOut

# --------------------------------------------------------------------
# 3. ReadFileTool: Safely Read Text Content
# --------------------------------------------------------------------
class ReadFileTool from AgentTool
	func init()
		cName = "read_file"
		cDescription = "Reads and returns the text content of a specified file path"
		aParameters = [
			["file_path", "string", "Path of the file to read", true]
		]
		return self

	func execute(aArgs)
		cPath = ""
		if islist(aArgs) and len(aArgs) >= 1
			cPath = trim(aArgs[1])
		elseif isstring(aArgs)
			cPath = trim(aArgs)
		ok
		cPath = substr(cPath, '"', "")
		cPath = substr(cPath, "'", "")
		cPath = trim(cPath)

		if cPath = ""
			return "Error: file_path argument cannot be empty."
		ok
		if not fexists(cPath)
			return f"Error: File '{cPath}' was not found."
		ok

		cContent = read(cPath)
		if len(cContent) > 4000
			return left(cContent, 4000) + nl + f"... [Truncated: File has {len(cContent)} characters total]"
		ok
		return cContent

# --------------------------------------------------------------------
# 4. WriteFileTool: Safely Write File
# --------------------------------------------------------------------
class WriteFileTool from AgentTool
	func init()
		cName = "write_file"
		cDescription = "Writes or overwrites text content to a specified file path"
		aParameters = [
			["file_path", "string", "Target file path to write", true],
			["content", "string", "Text content to save", true]
		]
		return self

	func execute(aArgs)
		cPath = ""
		cData = ""
		if islist(aArgs) and len(aArgs) >= 2
			cPath = trim(aArgs[1])
			cData = "" + aArgs[2]
		else
			return "Error: write_file requires two arguments: [file_path, content]"
		ok
		cPath = substr(cPath, '"', "")
		cPath = substr(cPath, "'", "")
		cPath = trim(cPath)

		write(cPath, cData)
		return f"Successfully saved {len(cData)} characters to '{cPath}'."

# --------------------------------------------------------------------
# 5. RememberTool: Autonomous Working Memory Storage
# --------------------------------------------------------------------
class RememberTool from AgentTool
	oMemory

	func init(oMem = NULL)
		cName = "remember_fact"
		cDescription = "Stores an important user fact, project rule, or preference into persistent working memory"
		aParameters = [
			["fact", "string", "The factual statement or rule to remember", true],
			["category", "string", "Category (e.g. 'preference', 'project_rule', 'user_info')", false]
		]
		oMemory = oMem
		return self

	func setMemory(oMem)
		oMemory = oMem

	func execute(aArgs)
		if oMemory = NULL
			return "Error: Memory system is not connected to remember_fact tool."
		ok

		cFact = ""
		cCat  = "general"
		if islist(aArgs) and len(aArgs) >= 1
			cFact = trim(aArgs[1])
			if len(aArgs) >= 2 and trim(aArgs[2]) != ""
				cCat = trim(aArgs[2])
			ok
		elseif isstring(aArgs)
			cFact = trim(aArgs)
		ok

		cFact = substr(cFact, '"', "")
		cFact = substr(cFact, "'", "")
		cFact = trim(cFact)

		if cFact = ""
			return "Error: Fact cannot be empty."
		ok

		if oMemory.rememberFact(cFact, cCat)
			return f"Success: Fact remembered in working memory under category '{cCat}'."
		else
			return "Error: Failed to store fact in memory."
		ok

# --------------------------------------------------------------------
# 6. CreateSkillTool: Autonomous Cognitive Skill Generation
# --------------------------------------------------------------------
class CreateSkillTool from AgentTool
	oSkillManager

	func init(oMgr = NULL)
		cName = "create_skill"
		cDescription = "Creates and activates a new specialized cognitive skill saved as a Markdown file in agentSkills/"
		aParameters = [
			["skill_name", "string", "Identifier for skill in snake_case (e.g. 'csv_expert')", true],
			["description", "string", "Summary of what the skill does", true],
			["triggers", "string", "Comma-separated keywords that activate this skill", true],
			["tools", "string", "Comma-separated tool names used by this skill", false],
			["instructions", "string", "Detailed markdown instructions/guidelines for the skill", true]
		]
		oSkillManager = oMgr
		return self

	func setSkillManager(oMgr)
		oSkillManager = oMgr

	func execute(aArgs)
		if oSkillManager = NULL
			return "Error: SkillManager is not connected to create_skill tool."
		ok

		if !islist(aArgs) or len(aArgs) < 4
			return "Error: create_skill requires at least 4 arguments: [skill_name, description, triggers, instructions]"
		ok

		cSkillName = lower(trim(aArgs[1]))
		cDesc      = trim(aArgs[2])
		cTriggers  = trim(aArgs[3])
		cTools     = ""
		cInstruct  = ""

		if len(aArgs) >= 5
			cTools    = trim(aArgs[4])
			cInstruct = trim(aArgs[5])
		else
			cInstruct = trim(aArgs[4])
		ok

		cCleanName = ""
		for i = 1 to len(cSkillName)
			cChar = cSkillName[i]
			if (cChar >= "a" and cChar <= "z") or (cChar >= "0" and cChar <= "9") or cChar = "_"
				cCleanName += cChar
			elseif cChar = " " or cChar = "-"
				cCleanName += "_"
			ok
		next
		if cCleanName = "" cCleanName = "custom_skill_" + len(oSkillManager.list()) ok

		oSkill = new AgentSkill(cCleanName, cDesc)
		oSkill.aTriggerKeywords = oSkill.parseCsvList(cTriggers)
		if cTools != ""
			oSkill.aSkillToolNames = oSkill.parseCsvList(cTools)
		ok
		oSkill.cSystemPromptOverlay = cInstruct

		oSkillManager.saveSkill(oSkill)
		oSkillManager.registerSkill(oSkill)

		return f"Success: Skill '{cCleanName}' successfully created, saved to agentSkills/{cCleanName}.md, and activated."
