# ringenv - OS Helper Utilities
# Cross-platform support for Windows, Linux, and macOS

# Default global version (overridden by main.ring)
cVersion = "1.1.0"

func ismacos
    return ismacosx()

# Detect operating system platform name
func getPlatformName
    if iswindows()
        return "windows"
    but islinux()
        return "linux"
    but ismacosx()
        return "macos"
    else
        return "unknown"
    ok

# Get binary executable name based on OS
func getBinaryName
    if iswindows()
        return "ring.exe"
    else
        return "ring"
    ok

# Resolve user's home directory
func getHomeDir
    cHome = ""
    if iswindows()
        cHome = sysget("USERPROFILE")
        if cHome = ""
            cHome = sysget("HOMEDRIVE") + sysget("HOMEPATH")
        ok
    else
        cHome = sysget("HOME")
    ok

    if cHome = ""
        cHome = "."
    ok
    return normalizePath(cHome)

# Normalize file path separators to standard forward slash
func normalizePath cPath
    cOut = substr(cPath, char(92), "/")
    # Remove trailing slash if present (except root)
    nLen = len(cOut)
    if nLen > 1 and substr(cOut, nLen, 1) = "/"
        cOut = substr(cOut, 1, nLen - 1)
    ok
    return cOut

# Convert path to native system separators
func toNativePath cPath
    if iswindows()
        return substr(cPath, "/", char(92))
    else
        return substr(cPath, char(92), "/")
    ok

# Resolve target path relative to caller working directory if not absolute
func resolveCallerPath cPath
    cNorm = normalizePath(cPath)
    lIsAbs = false
    if len(cNorm) >= 2 and substr(cNorm, 2, 1) = ":"
        lIsAbs = true
    but len(cNorm) >= 1 and substr(cNorm, 1, 1) = "/"
        lIsAbs = true
    ok

    if lIsAbs
        return cNorm
    ok

    cCallerDir = getCallerDir()
    if cCallerDir != ""
        return normalizePath(cCallerDir + "/" + cNorm)
    ok

    return cNorm

# Get caller working directory
func getCallerDir
    cCallerDir = sysget("RINGENV_CALLER_DIR")
    if cCallerDir != ""
        return normalizePath(cCallerDir)
    ok
    return normalizePath(currentdir())

# Get root ringenv global directory (~/.ringenv)
func getRingenvDir
    return getHomeDir() + "/.ringenv"

# Get versions directory (~/.ringenv/versions)
func getVersionsDir
    return getRingenvDir() + "/versions"

# Get cache directory (~/.ringenv/cache)
func getCacheDir
    return getRingenvDir() + "/cache"

# Ensure a directory exists, creating all parent directories if necessary
func ensureDir cPath
    cNorm = normalizePath(cPath)
    if direxists(cNorm)
        return true
    ok

    aParts = split(cNorm, "/")
    cCur = ""
    for i = 1 to len(aParts)
        cPart = aParts[i]
        if cPart = ""
            if i = 1 and not iswindows()
                cCur = "/"
            ok
            loop
        ok

        if i = 1 and iswindows() and substr(cPart, ":") > 0
            cCur = cPart
        else
            if cCur = "" or cCur = "/"
                cCur = cCur + cPart
            else
                cCur = cCur + "/" + cPart
            ok

            if not direxists(cCur)
                makedir(cCur)
            ok
        ok
    next

    # Native command fallback if still not created
    if not direxists(cNorm)
        cNative = toNativePath(cNorm)
        if iswindows()
            system('cmd /c if not exist "' + cNative + '" mkdir "' + cNative + '" >nul 2>&1')
        else
            system('mkdir -p "' + cNorm + '" 2>/dev/null')
        ok
    ok

    return direxists(cNorm)

# Initialize global ringenv directories
func initRingenvDirs
    ensureDir(getRingenvDir())
    ensureDir(getVersionsDir())
    ensureDir(getCacheDir())

# Copy a single file from source to destination
func copyFile cSrc, cDest
    cContent = read(cSrc)
    if cContent = "" and not fexists(cSrc)
        return false
    ok
    try
        write(cDest, cContent)
    catch
        cNativeSrc = toNativePath(cSrc)
        cNativeDest = toNativePath(cDest)
        if iswindows()
            system('cmd /c copy /Y "' + cNativeSrc + '" "' + cNativeDest + '" >nul 2>&1')
        else
            system('cp -f "' + cSrc + '" "' + cDest + '" 2>/dev/null')
        ok
    done
    return fexists(cDest)

# Copy a directory recursively
func copyFolder cSrc, cDest
    ensureDir(cDest)
    if iswindows()
        cNativeSrc = toNativePath(cSrc)
        cNativeDest = toNativePath(cDest)
        system('cmd /c xcopy /E /I /Y /Q "' + cNativeSrc + '\*" "' + cNativeDest + '\" >nul 2>&1')
    else
        system('cp -R "' + cSrc + '/"* "' + cDest + '/" 2>/dev/null')
    ok

    aItems = dir(cSrc)
    for aItem in aItems
        cName = aItem[1]
        nType = aItem[2]
        if cName = "." or cName = ".."
            loop
        ok
        cSrcPath = cSrc + "/" + cName
        cDestPath = cDest + "/" + cName
        if nType = 1
            if not direxists(cDestPath)
                copyFolder(cSrcPath, cDestPath)
            ok
        else
            if not fexists(cDestPath)
                copyFile(cSrcPath, cDestPath)
            ok
            if not iswindows()
                if substr(cDestPath, "/bin/") > 0 or cName = "ring"
                    system('chmod +x "' + cDestPath + '" 2>/dev/null')
                ok
            ok
        ok
    next
    return true

# Delete a directory and its contents
func deleteFolder cFolder
    cNorm = normalizePath(cFolder)
    if not direxists(cNorm)
        return true
    ok

    aItems = dir(cNorm)
    for aItem in aItems
        cName = aItem[1]
        nType = aItem[2]
        if cName = "." or cName = ".."
            loop
        ok
        cPath = cNorm + "/" + cName
        if nType = 1
            deleteFolder(cPath)
        else
            remove(cPath)
        ok
    next

    # Fallback to system command for complete cleanup
    cNative = toNativePath(cNorm)
    if iswindows()
        system('rmdir /s /q "' + cNative + '" >nul 2>&1')
    else
        system('rm -rf "' + cNorm + '" 2>/dev/null')
    ok

    return not direxists(cNorm)

# Get ringenv version
func getRingenvVersion
    return "1.1.0"
