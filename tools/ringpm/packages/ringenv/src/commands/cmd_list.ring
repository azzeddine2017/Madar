# ringenv - Command: list
# Scans and prints locally installed Ring versions

func cmdList
    initRingenvDirs()
    cVersionsDir = getVersionsDir()

    if not direxists(cVersionsDir)
        ? "No Ring versions installed."
        ? "Run 'ringenv install <version>' to install one."
        return true
    ok

    aItems = dir(cVersionsDir)
    aVersions = []
    for aItem in aItems
        cName = aItem[1]
        nType = aItem[2]
        if cName != "." and cName != ".." and nType = 1
            aVersions + cName
        ok
    next

    if len(aVersions) = 0
        ? "No Ring versions installed."
        ? "Run 'ringenv install <version>' to install one."
        return true
    ok

    uiBanner("Installed Ring Versions", toNativePath(cVersionsDir))
    ? ""

    cBinFile = getBinaryName()
    for cVer in aVersions
        cVerDir = cVersionsDir + "/" + cVer

        # Automatically normalize if needed
        normalizeVersionFolder(cVerDir)

        cRuntimeDir = findVersionRuntimeDir(cVerDir)
        cBinPath = cRuntimeDir + "/bin/" + cBinFile

        cStatusBadge = ""
        if fexists(cBinPath) or fexists(cRuntimeDir + "/" + cBinFile)
            cStatusBadge = uiBadge("ready", C_BOLD + C_BGREEN)
        else
            cStatusBadge = uiBadge("incomplete", C_BOLD + C_BYELLOW)
        ok
        ? "  " + uiStyle("*", C_BOLD + C_BCYAN) + " " + uiStyle(cVer, C_BOLD + C_WHITE) + "  " + cStatusBadge
    next

    ? ""
    uiDivider()
    ? "  " + uiInfo("Total: " + len(aVersions) + " version(s) installed.")
    ? uiStyle("======================================================================", C_CYAN)
    return true
