# ====================================================================
#   MadarAgent - Modern Terminal UI Styling & Aesthetics
#   تنسيقات الطرفية الحديثة للوكيل الذكي: ألوان، شارات، وبطاقات بصرية
# ====================================================================

C_ESC = char(27)

# Text Styles
C_RESET      = C_ESC + "[0m"
C_BOLD       = C_ESC + "[1m"
C_DIM        = C_ESC + "[2m"
C_ITALIC     = C_ESC + "[3m"
C_UNDERLINE  = C_ESC + "[4m"

# Standard Foreground Colors
C_BLACK      = C_ESC + "[30m"
C_RED        = C_ESC + "[31m"
C_GREEN      = C_ESC + "[32m"
C_YELLOW     = C_ESC + "[33m"
C_BLUE       = C_ESC + "[34m"
C_MAGENTA    = C_ESC + "[35m"
C_CYAN       = C_ESC + "[36m"
C_WHITE      = C_ESC + "[37m"

# High-Intensity Bright Colors
C_BBLACK     = C_ESC + "[90m"
C_BRED       = C_ESC + "[91m"
C_BGREEN     = C_ESC + "[92m"
C_BYELLOW    = C_ESC + "[93m"
C_BBLUE      = C_ESC + "[94m"
C_BMAGENTA   = C_ESC + "[95m"
C_BCYAN      = C_ESC + "[96m"
C_BWHITE     = C_ESC + "[97m"

# Background Colors
C_BG_BLACK   = C_ESC + "[40m"
C_BG_RED     = C_ESC + "[41m"
C_BG_GREEN   = C_ESC + "[42m"
C_BG_YELLOW  = C_ESC + "[43m"
C_BG_BLUE    = C_ESC + "[44m"
C_BG_MAGENTA = C_ESC + "[45m"
C_BG_CYAN    = C_ESC + "[46m"
C_BG_WHITE   = C_ESC + "[47m"

# Global color toggle state
if not isglobal(:lGlobalColorEnabled)
	lGlobalColorEnabled = true
ok

func isColorEnabled
	if sysget("NO_COLOR") != "" or sysget("TERM") = "dumb"
		return false
	ok
	if isglobal(:lGlobalColorEnabled)
		return lGlobalColorEnabled
	ok
	return true

func setColorEnabled lEnabled
	lGlobalColorEnabled = lEnabled

# Apply ANSI style
func uiStyle cText, cCode
	if not isColorEnabled()
		return cText
	ok
	return cCode + cText + C_RESET

# --------------------------------------------------------------------
# Semantic Color Helpers
# --------------------------------------------------------------------
func uiSuccess cText
	return uiStyle(cText, C_BOLD + C_BGREEN)

func uiError cText
	return uiStyle(cText, C_BOLD + C_BRED)

func uiWarn cText
	return uiStyle(cText, C_BOLD + C_BYELLOW)

func uiInfo cText
	return uiStyle(cText, C_BCYAN)

func uiAccent cText
	return uiStyle(cText, C_BOLD + C_BMAGENTA)

func uiMuted cText
	return uiStyle(cText, C_BBLACK)

func uiHighlight cText
	return uiStyle(cText, C_BOLD + C_BWHITE)

func uiBadge cText, cCode
	return uiStyle("[" + cText + "]", cCode)

# --------------------------------------------------------------------
# AI Agent Specific UI Badges & Interactive Prompts
# --------------------------------------------------------------------

# User Input Prompt: ● User ›
func uiUserPrompt
	if not isColorEnabled() return "User > " ok
	return nl + C_BBLUE + C_BOLD + "● User" + C_RESET + " " + C_BBLACK + "› " + C_RESET

# Agent Response Header: ◆ MadarAgent ›
func uiAgentPrompt cName
	if cName = NULL or cName = "" cName = "MadarAgent" ok
	if not isColorEnabled() return nl + "[" + cName + "]: " ok
	return nl + C_BGREEN + C_BOLD + "◆ " + cName + C_RESET + " " + C_BBLACK + "› " + C_RESET

# Active Cognitive Skill Activation Notification
func uiSkillBadge cSkillName
	if not isColorEnabled() return "  [Skill Active: " + cSkillName + "]" ok
	return "  " + C_BMAGENTA + C_BOLD + "⚡ [Skill Activated: " + cSkillName + "]" + C_RESET

# Ground Truth Knowledge Retrieval Badge
func uiRagBadge nCount
	if not isColorEnabled() return "  [Knowledge Base: " + nCount + " chunks retrieved]" ok
	return "  " + C_BCYAN + C_BOLD + "🧠 [Knowledge Base: " + nCount + " chunks retrieved]" + C_RESET

# Tool Execution Notification Badge
func uiToolCallBadge cToolName, cArgs
	if not isColorEnabled() return "  [Tool Call: " + cToolName + "(" + cArgs + ")]" ok
	cStr = "  " + C_BYELLOW + C_BOLD + "⚙ [Tool: " + cToolName + "]" + C_RESET
	if cArgs != ""
		cStr += " " + C_BBLACK + "(" + cArgs + ")" + C_RESET
	ok
	return cStr

# Tool Observation Output Block
func uiToolResultBlock cToolName, cResult
	cLinePrefix = C_BBLACK + "  │ " + C_RESET
	cLines = split(cResult, nl)
	cFormatted = "  " + C_BYELLOW + "╭─ [Output: " + cToolName + "]" + C_RESET + nl
	for line in cLines
		cFormatted += cLinePrefix + C_BCYAN + line + C_RESET + nl
	next
	cFormatted += "  " + C_BYELLOW + "╰──────────────────────────────────────" + C_RESET
	return cFormatted

# --------------------------------------------------------------------
# Decorative Banners & Cards
# --------------------------------------------------------------------
func uiBanner cTitle, cSubtitle
	cBorder = "────────────────────────────────────────────────────────────────────"
	? C_BCYAN + "╭" + cBorder + "╮" + C_RESET
	? C_BCYAN + "│" + C_RESET + "  " + C_BOLD + C_BWHITE + cTitle + C_RESET
	if cSubtitle != ""
		? C_BCYAN + "│" + C_RESET + "  " + C_BBLACK + cSubtitle + C_RESET
	ok
	? C_BCYAN + "╰" + cBorder + "╯" + C_RESET

func uiDivider
	? C_BBLACK + "────────────────────────────────────────────────────────────────────" + C_RESET

func uiSectionHeader cTitle
	? nl + C_BMAGENTA + C_BOLD + "## " + cTitle + C_RESET + nl
