# ringenv - Archive Extractor Module
# ZipEngine wrapper for archive unpacking and permission setup

# Locate runtime directory containing the ring binary within a version folder
func findVersionRuntimeDir cVerDir
    cBinFile = getBinaryName()

    if fexists(cVerDir + "/bin/" + cBinFile) or fexists(cVerDir + "/" + cBinFile)
        return cVerDir
    ok

    aItems = dir(cVerDir)
    for aItem in aItems
        cName = aItem[1]
        nType = aItem[2]
        if cName != "." and cName != ".." and nType = 1
            cSub = cVerDir + "/" + cName
            if fexists(cSub + "/bin/" + cBinFile) or fexists(cSub + "/" + cBinFile)
                return cSub
            ok
        ok
    next

    return cVerDir

# Normalize extracted directory structure so bin/ is directly under cDestFolder
func normalizeVersionFolder cDestFolder
    cBinFile = getBinaryName()

    if fexists(cDestFolder + "/bin/" + cBinFile) or fexists(cDestFolder + "/" + cBinFile)
        # Clean up legacy redundant nested folders if left behind from earlier installations
        aItems = dir(cDestFolder)
        for aItem in aItems
            cName = aItem[1]
            nType = aItem[2]
            if cName != "." and cName != ".." and nType = 1
                cSub = cDestFolder + "/" + cName
                if fexists(cSub + "/bin/" + cBinFile) or fexists(cSub + "/" + cBinFile)
                    deleteFolder(cSub)
                ok
            ok
        next
        return true
    ok

    aItems = dir(cDestFolder)
    for aItem in aItems
        cName = aItem[1]
        nType = aItem[2]
        if cName != "." and cName != ".." and nType = 1
            cSub = cDestFolder + "/" + cName
            if fexists(cSub + "/bin/" + cBinFile) or fexists(cSub + "/" + cBinFile)
                if iswindows()
                    system('cmd /c xcopy /E /Y /Q "' + toNativePath(cSub) + '\*" "' + toNativePath(cDestFolder) + '\" >nul 2>&1')
                else
                    system('cp -R "' + cSub + '/"* "' + cDestFolder + '/" 2>/dev/null')
                ok

                # Also standard Ring file copy fallback
                aSubItems = dir(cSub)
                for aSubItem in aSubItems
                    cSubName = aSubItem[1]
                    nSubType = aSubItem[2]
                    if cSubName = "." or cSubName = ".."
                        loop
                    ok
                    cFrom = cSub + "/" + cSubName
                    cTo = cDestFolder + "/" + cSubName
                    if not fexists(cTo) and not direxists(cTo)
                        if nSubType = 1
                            copyFolder(cFrom, cTo)
                        else
                            copyFile(cFrom, cTo)
                        ok
                    ok
                next

                # Clean up the original nested subfolder to prevent duplicate copies
                if fexists(cDestFolder + "/bin/" + cBinFile) or fexists(cDestFolder + "/" + cBinFile)
                    deleteFolder(cSub)
                ok

                return true
            ok
        ok
    next
    return false

# Extract zip archive to destination directory and ensure permissions
func extractZip cZipPath, cDestFolder
    cNormDest = normalizePath(cDestFolder)
    ensureDir(cNormDest)

    oEngine = new ZipEngine
    oEngine.extractZip(cZipPath, cNormDest)

    # Normalize folder hierarchy if extracted inside an enclosing folder
    normalizeVersionFolder(cNormDest)

    # Ensure executable permissions on Unix/macOS
    if not iswindows()
        cRuntimeDir = findVersionRuntimeDir(cNormDest)
        cBin = cRuntimeDir + "/bin/" + getBinaryName()
        if fexists(cBin)
            system('chmod +x "' + cBin + '" 2>/dev/null')
        ok
        cRootBin = cRuntimeDir + "/" + getBinaryName()
        if fexists(cRootBin)
            system('chmod +x "' + cRootBin + '" 2>/dev/null')
        ok
        cBinDir = cRuntimeDir + "/bin"
        if direxists(cBinDir)
            system('chmod +x "' + cBinDir + '"/* 2>/dev/null')
        ok
    ok

    return true
