# ringenv - Command: install
# Downloads and sets up specified Ring version


# Determine release asset filename according to OS and flags
func getReleaseAsset cVersion, lLight
    cPlat = getPlatformName()

    if cPlat = "windows"
        return "Ring_" + cVersion + "_LightRelease_Windows_Binary_64bit.zip"
    but cPlat = "linux"
        return "Ring_" + cVersion + "_Ubuntu.zip"
    but cPlat = "macos"
        return "Ring_" + cVersion + "_macOS_Applesilicon.zip"
    else
        return "Ring_" + cVersion + "_LightRelease_Windows_Binary_64bit.zip"
    ok

# Execute install command
func cmdInstall cVersion, lLight, lForce
    if cVersion = ""
        ? uiError("Error: Please specify the version to install.")
        ? "Usage:   " + uiStyle("ringenv install <version>", C_BOLD + C_BCYAN)
        ? "Example: " + uiStyle("ringenv install 1.27", C_BOLD + C_BYELLOW)
        return false
    ok

    initRingenvDirs()

    cVersionDir = getVersionsDir() + "/" + cVersion
    cBinFile = getBinaryName()
    cAsset = getReleaseAsset(cVersion, lLight)
    cCacheZip = getCacheDir() + "/" + cAsset

    # Check if already installed
    if direxists(cVersionDir)
        if lForce
            ? uiWarn("Force reinstall requested. Removing previous installation of Ring " + cVersion + "...")
            deleteFolder(cVersionDir)
            if fexists(cCacheZip)
                remove(cCacheZip)
            ok
        but fexists(cVersionDir + "/bin/" + cBinFile) or fexists(cVersionDir + "/" + cBinFile)
            normalizeVersionFolder(cVersionDir)
            uiBanner("Ring " + cVersion + " Already Installed", toNativePath(cVersionDir))
            ? ""
            ? "  " + uiStyle("Status:  ", C_BOLD + C_WHITE) + uiBadge("ready", C_BOLD + C_BGREEN)
            ? "  " + uiStyle("Reinstall: ", C_BOLD + C_WHITE) + uiStyle("ringenv install " + cVersion + " --force", C_BOLD + C_BYELLOW)
            ? "  " + uiStyle("Create venv: ", C_BOLD + C_WHITE) + uiStyle("ringenv venv create <target> --version " + cVersion, C_BOLD + C_BCYAN)
            ? uiStyle("======================================================================", C_CYAN)
            return true
        ok
    ok

    uiBanner("Installing Ring " + cVersion, "Platform: " + getPlatformName() + " | Asset: " + cAsset)
    ? ""

    # Primary download URL
    cUrl = "https://github.com/ring-lang/ring/releases/download/v" + cVersion + "/" + cAsset
    ? "  " + uiStyle("Downloading: ", C_BOLD + C_WHITE) + uiStyle(cUrl, C_UNDERLINE + C_BCYAN)

    lSuccess = downloadFile(cUrl, cCacheZip)

    # Fallback without 'v' prefix in tag
    if not lSuccess
        cUrlFallback = "https://github.com/ring-lang/ring/releases/download/" + cVersion + "/" + cAsset
        ? "  " + uiStyle("Retrying:    ", C_BOLD + C_WHITE) + uiStyle(cUrlFallback, C_UNDERLINE + C_BCYAN)
        lSuccess = downloadFile(cUrlFallback, cCacheZip)
    ok

    if not lSuccess
        ? ""
        ? uiError("Error: Failed to download Ring version " + cVersion + ".")
        ? "Please check that the version exists on GitHub releases:"
        ? uiStyle("https://github.com/ring-lang/ring/releases", C_UNDERLINE + C_BCYAN)
        return false
    ok

    ? ""
    ? "  " + uiStyle("Extracting:  ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cVersionDir), C_DIM)
    ensureDir(cVersionDir)
    extractZip(cCacheZip, cVersionDir)

    # Remove cached archive file
    if fexists(cCacheZip)
        remove(cCacheZip)
    ok

    # Validate extracted binary
    cBinPath = cVersionDir + "/bin/" + cBinFile
    if not fexists(cBinPath)
        if fexists(cVersionDir + "/" + cBinFile)
            cBinPath = cVersionDir + "/" + cBinFile
        ok
    ok

    ? ""
    uiDivider()
    ? "  " + uiSuccess("Successfully installed Ring " + cVersion + "!")
    ? "  " + uiStyle("Binary: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cBinPath), C_BOLD + C_BGREEN)
    ? uiStyle("======================================================================", C_CYAN)
    return true
