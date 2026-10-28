# ====================================================================
#   MadarAgent - Autonomous Skill System (نظام المهارات المعرفية)
#   تغليف المهارات: قراءة وحفظ من وإلى ملفات Markdown في agentSkills/
# ====================================================================


# --------------------------------------------------------------------
# 1. Base Class: AgentSkill (فئة المهارة المعرفية)
# --------------------------------------------------------------------
class AgentSkill
	cName                = ""
	cDescription         = ""
	aTriggerKeywords     = []
	aSkillToolNames      = []
	cSystemPromptOverlay = ""
	cFilePath            = ""

	func init(name = "", desc = "")
		cName = name
		cDescription = desc
		return self

	func matches(cQuery)
		cLower = lower(cQuery)
		for kw in aTriggerKeywords
			if substr(cLower, lower(trim(kw))) > 0
				return true
			ok
		next
		return false

	func getPromptOverlay()
		return cSystemPromptOverlay

	func getTools()
		return aSkillToolNames

	# ----------------------------------------------------------------
	# Parse Skill from Standard Markdown file with YAML Frontmatter
	# ----------------------------------------------------------------
	func fromMarkdown(cContent, cSourcePath = "")
		cFilePath = cSourcePath
		cContent = trim(cContent)

		# Check for YAML frontmatter delimited by '---'
		if left(cContent, 3) = "---"
			cAfter = substr(cContent, 4)
			nRel = substr(cAfter, "---")
			if nRel > 0
				cFrontmatter = substr(cAfter, 1, nRel - 1)
				cBody = trim(substr(cAfter, nRel + 3))
				parseFrontmatter(cFrontmatter)
				cSystemPromptOverlay = cBody
				return self
			ok
		ok

		# Fallback: Parse Markdown without frontmatter (extract headers)
		cSystemPromptOverlay = cContent
		if cSourcePath != ""
			cName = JustFileName(cSourcePath)
			if substr(lower(cName), ".md") > 0
				cName = substr(cName, 1, len(cName) - 3)
			ok
		ok
		return self

	func parseFrontmatter(cFM)
		aLines = split(cFM, nl)
		for line in aLines
			line = trim(line)
			if line = "" or left(line, 1) = "#" loop ok
			nColon = substr(line, ":")
			if nColon > 0
				cKey = lower(trim(substr(line, 1, nColon - 1)))
				cVal = trim(substr(line, nColon + 1))
				switch cKey
					case "name"
						cName = cVal
					case "description"
						cDescription = cVal
					case "triggers"
						aTriggerKeywords = parseCsvList(cVal)
					case "tools"
						aSkillToolNames = parseCsvList(cVal)
				end
			ok
		next

	func parseCsvList(cStr)
		aParts = split(cStr, ",")
		aRes = []
		for p in aParts
			p = trim(p)
			if p != "" aRes + p ok
		next
		return aRes

	# ----------------------------------------------------------------
	# Serialize Skill to Standard Markdown with YAML Frontmatter
	# ----------------------------------------------------------------
	func toMarkdown()
		cTriggers = ""
		for i = 1 to len(aTriggerKeywords)
			cTriggers += aTriggerKeywords[i]
			if i < len(aTriggerKeywords) cTriggers += ", " ok
		next

		cTools = ""
		for i = 1 to len(aSkillToolNames)
			cTools += aSkillToolNames[i]
			if i < len(aSkillToolNames) cTools += ", " ok
		next

		cMd = "---" + nl +
			f"name: {cName}" + nl +
			f"description: {cDescription}" + nl +
			f"triggers: {cTriggers}" + nl +
			f"tools: {cTools}" + nl +
			"---" + nl + nl +
			cSystemPromptOverlay + nl
		return cMd

	func saveToFile(cPath)
		write(cPath, toMarkdown())
		cFilePath = cPath
		return true

# --------------------------------------------------------------------
# 2. SkillManager: Dynamic Discovery & File Orchestration
# --------------------------------------------------------------------
class SkillManager
	aSkills   = []
	cSkillsDir = "agentSkills"

	func init(cDir = "agentSkills")
		cSkillsDir = cDir
		return self

	func registerSkill(oSkill)
		if not isobject(oSkill) return false ok
		for i = 1 to len(aSkills)
			if aSkills[i].cName = oSkill.cName
				aSkills[i] = oSkill
				return true
			ok
		next
		aSkills + oSkill
		return true

	func count()
		return len(aSkills)

	func list()
		return aSkills

	func getSkill(cName)
		cLower = lower(trim(cName))
		for s in aSkills
			if lower(s.cName) = cLower return s ok
		next
		return NULL

	# ----------------------------------------------------------------
	# Load all .md skill files from agentSkills/ directory
	# ----------------------------------------------------------------
	func loadSkillsFromFolder(cDir = "")
		if cDir != "" cSkillsDir = cDir ok
		if not direxists(cSkillsDir)
			system(f"mkdir {cSkillsDir} >nul 2>&1")
			return 0
		ok

		aEntries = dir(cSkillsDir)
		nCount = 0
		for item in aEntries
			cItemName = item[1]
			bIsDir    = item[2]
			if cItemName = "." or cItemName = ".." loop ok

			cFullPath = cSkillsDir + "/" + cItemName
			if !bIsDir
				# Check for direct .md file
				if substr(lower(cItemName), ".md") > 0
					if loadSkillFile(cFullPath) nCount++ ok
				ok
			else
				# Check for subdirectory with SKILL.md or <name>.md
				cSubSkill = cFullPath + "/SKILL.md"
				if fexists(cSubSkill)
					if loadSkillFile(cSubSkill) nCount++ ok
				ok
			ok
		next
		return nCount

	func loadSkillFile(cFilePath)
		if not fexists(cFilePath) return false ok
		cContent = read(cFilePath)
		oSkill = new AgentSkill()
		oSkill.fromMarkdown(cContent, cFilePath)
		if oSkill.cName = ""
			oSkill.cName = JustFileName(cFilePath)
		ok
		registerSkill(oSkill)
		return true

	func saveSkill(oSkill)
		if not direxists(cSkillsDir)
			system(f"mkdir {cSkillsDir} >nul 2>&1")
		ok
		cTarget = cSkillsDir + "/" + oSkill.cName + ".md"
		return oSkill.saveToFile(cTarget)

	func detectActiveSkills(cQuery)
		aActive = []
		for s in aSkills
			if s.matches(cQuery)
				aActive + s
			ok
		next
		return aActive

	func buildCombinedOverlay(cQuery)
		aActive = detectActiveSkills(cQuery)
		if len(aActive) = 0 return "" ok

		cOverlay = nl + "# Active Specialized Cognitive Skills:" + nl
		for s in aActive
			cOverlay += f"## [Skill Activated: {s.cName}]" + nl
			cOverlay += s.getPromptOverlay() + nl + nl
		next
		return cOverlay
