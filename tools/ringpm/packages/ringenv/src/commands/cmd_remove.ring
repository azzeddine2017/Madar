# ringenv - Command: remove / uninstall
# Uninstalls and removes a specified Ring version from storage

func cmdRemove cVersion
    if cVersion = ""
        ? uiError("Error: Please specify the version to remove.")
        ? "Usage:   " + uiStyle("ringenv remove <version>", C_BOLD + C_BCYAN)
        ? "Example: " + uiStyle("ringenv remove 1.27", C_BOLD + C_BYELLOW)
        return false
    ok

    initRingenvDirs()

    cVersionsDir = getVersionsDir()
    cTargetDir = cVersionsDir + "/" + cVersion

    if not direxists(cTargetDir)
        ? uiError("Error: Ring version " + cVersion + " is not installed.")
        ? "Run 'ringenv list' to view all installed versions."
        return false
    ok

    uiBanner("Removing Ring " + cVersion, toNativePath(cTargetDir))
    ? ""

    lSuccess = deleteFolder(cTargetDir)

    if lSuccess and not direxists(cTargetDir)
        ? "  " + uiSuccess("Successfully removed Ring " + cVersion + "!")
    else
        ? "  " + uiWarn("Warning: Could not completely delete directory: " + toNativePath(cTargetDir))
        ? "  " + uiStyle("Please ensure no processes are currently using files in this folder.", C_DIM)
        return false
    ok

    # Also clean matching archive in cache directory if exists
    cCacheDir = getCacheDir()
    if direxists(cCacheDir)
        aCacheItems = dir(cCacheDir)
        for aItem in aCacheItems
            cName = aItem[1]
            if aItem[2] = 0 and substr(cName, cVersion) > 0 and substr(cName, ".zip") > 0
                remove(cCacheDir + "/" + cName)
            ok
        next
    ok

    ? ""
    uiDivider()
    ? uiStyle("======================================================================", C_CYAN)
    return true
