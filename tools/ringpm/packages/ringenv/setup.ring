# setup.ring - Pure Ring Cross-Platform Installer for ringenv
# Works on Windows, Linux, and macOS

load "stdlibcore.ring"

func main
    aArgs = sysargv
    cAction = "install"
    if len(aArgs) >= 3
        cAction = lower(trim(aArgs[3]))
    ok

    if cAction = "remove" or cAction = "uninstall" or cAction = "--uninstall" or cAction = "-u"
        uninstallRingenv()
    else
        installRingenv()
    ok

func installRingenv
    ? "================================================="
    ? "Installing ringenv CLI to active Ring environment"
    ? "================================================="

    cRingBin = normalizePath(exefolder())
    cRingRoot = normalizePath(cRingBin + "/..")
    cTargetPkg = normalizePath(cRingRoot + "/tools/ringpm/packages/ringenv")
    cSourceDir = normalizePath(currentdir())

    ? "Ring Binary Directory: " + cRingBin
    ? "Target Package Path:   " + cTargetPkg
    ? "Source Directory:      " + cSourceDir
    ? "-------------------------------------------------"

    # Ensure target package directories exist
    ensureDirectory(cTargetPkg)
    ensureDirectory(cTargetPkg + "/src")
    ensureDirectory(cTargetPkg + "/src/core")
    ensureDirectory(cTargetPkg + "/src/commands")
    ensureDirectory(cTargetPkg + "/docs")
    ensureDirectory(cTargetPkg + "/templates")

    # Copy core root files
    copyFileSafely(cSourceDir + "/main.ring", cTargetPkg + "/main.ring")
    copyFileSafely(cSourceDir + "/package.ring", cTargetPkg + "/package.ring")
    copyFileSafely(cSourceDir + "/setup.ring", cTargetPkg + "/setup.ring")
    copyFileSafely(cSourceDir + "/README.md", cTargetPkg + "/README.md")

    # Copy src/core files
    copyDirFiles(cSourceDir + "/src/core", cTargetPkg + "/src/core", ".ring")

    # Copy src/commands files
    copyDirFiles(cSourceDir + "/src/commands", cTargetPkg + "/src/commands", ".ring")

    # Copy docs files
    copyDirFiles(cSourceDir + "/docs", cTargetPkg + "/docs", ".md")

    # Copy templates if they exist
    if direxists(cSourceDir + "/templates")
        copyDirectoryRecursive(cSourceDir + "/templates", cTargetPkg + "/templates")
    ok

    # Install launcher in Ring bin directory
    installLauncher(cRingBin, cTargetPkg)

    ? "================================================="
    ? "ringenv successfully installed!"
    ? "You can now use 'ringenv' from any directory:"
    ? "  ringenv --version"
    ? "  ringenv list"
    ? "  ringenv install 1.27"
    ? "  ringenv venv create .rvenv --version 1.27"
    ? "================================================="

func uninstallRingenv
    ? "================================================="
    ? "Uninstalling ringenv from Ring environment"
    ? "================================================="

    cRingBin = normalizePath(exefolder())
    cRingRoot = normalizePath(cRingBin + "/..")
    cTargetPkg = normalizePath(cRingRoot + "/tools/ringpm/packages/ringenv")

    # Remove launchers
    if iswindows()
        cLauncher = cRingBin + "/ringenv.bat"
        if fexists(cLauncher)
            remove(cLauncher)
            ? "Removed: " + cLauncher
        ok
    else
        cLauncher = cRingBin + "/ringenv"
        if fexists(cLauncher)
            remove(cLauncher)
            ? "Removed: " + cLauncher
        ok
    ok

    # Remove package folder if exists
    if direxists(cTargetPkg)
        system(getRemoveDirCmd(cTargetPkg))
        ? "Removed package directory: " + cTargetPkg
    ok

    ? "================================================="
    ? "ringenv successfully uninstalled!"
    ? "================================================="

func installLauncher cRingBin, cTargetPkg
    if iswindows()
        cLauncherPath = cRingBin + "/ringenv.bat"
        cContent = '@echo off' + windowsNl() +
                   'rem ringenv CLI launcher' + windowsNl() +
                   'set "RINGENV_CALLER_DIR=%CD%"' + windowsNl() +
                   'pushd "%~dp0..\tools\ringpm\packages\ringenv"' + windowsNl() +
                   'ring main.ring %*' + windowsNl() +
                   'set "EXIT_CODE=%ERRORLEVEL%"' + windowsNl() +
                   'popd' + windowsNl() +
                   'exit /b %EXIT_CODE%' + windowsNl()
        write(cLauncherPath, cContent)
        ? "Installed Windows launcher: " + cLauncherPath
    else
        cLauncherPath = cRingBin + "/ringenv"
        cContent = '#!/usr/bin/env bash' + char(10) +
                   '# ringenv CLI launcher' + char(10) +
                   'export RINGENV_CALLER_DIR="$(pwd)"' + char(10) +
                   'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' + char(10) +
                   'cd "$SCRIPT_DIR/../tools/ringpm/packages/ringenv"' + char(10) +
                   'ring main.ring "$@"' + char(10) +
                   'EXIT_CODE=$?' + char(10) +
                   'cd "$RINGENV_CALLER_DIR"' + char(10) +
                   'exit $EXIT_CODE' + char(10)
        write(cLauncherPath, cContent)
        system('chmod +x "' + cLauncherPath + '"')
        ? "Installed Unix launcher: " + cLauncherPath
    ok

func copyFileSafely cSrc, cDest
    if fexists(cSrc)
        cData = read(cSrc)
        write(cDest, cData)
        ? "  [+] " + getFilenameOnly(cDest)
        return true
    ok
    return false

func copyDirFiles cSrcDir, cDestDir, cExt
    if not direxists(cSrcDir)
        return false
    ok
    ensureDirectory(cDestDir)
    aDirList = dir(cSrcDir)
    for aItem in aDirList
        cName = aItem[1]
        lIsDir = aItem[2]
        if not lIsDir
            if cExt = "" or endsWith(lower(cName), lower(cExt))
                cSrcPath = cSrcDir + "/" + cName
                cDestPath = cDestDir + "/" + cName
                cData = read(cSrcPath)
                write(cDestPath, cData)
                ? "  [+] " + cName
            ok
        ok
    next
    return true

func copyDirectoryRecursive cSrcDir, cDestDir
    ensureDirectory(cDestDir)
    aDirList = dir(cSrcDir)
    for aItem in aDirList
        cName = aItem[1]
        lIsDir = aItem[2]
        if cName = "." or cName = ".."
            loop
        ok
        cSrcSub = cSrcDir + "/" + cName
        cDestSub = cDestDir + "/" + cName
        if lIsDir
            copyDirectoryRecursive(cSrcSub, cDestSub)
        else
            cData = read(cSrcSub)
            write(cDestSub, cData)
        ok
    next

func ensureDirectory cPath
    cNorm = normalizePath(cPath)
    if direxists(cNorm)
        return true
    ok
    # Build recursive path creation
    aParts = split(cNorm, "/")
    cCurrent = ""
    for i = 1 to len(aParts)
        cPart = aParts[i]
        if cPart = ""
            cCurrent = "/"
            loop
        ok
        if cCurrent = ""
            cCurrent = cPart
        else
            if cCurrent = "/"
                cCurrent = "/" + cPart
            else
                cCurrent = cCurrent + "/" + cPart
            ok
        ok
        if not direxists(cCurrent)
            if not (len(cCurrent) = 2 and substr(cCurrent, 2, 1) = ":")
                system(getMakeDirCmd(cCurrent))
            ok
        ok
    next
    return direxists(cNorm)

func getMakeDirCmd cDir
    if iswindows()
        return 'mkdir "' + substr(cDir, "/", char(92)) + '" >nul 2>nul'
    else
        return 'mkdir -p "' + cDir + '" >/dev/null 2>&1'
    ok

func getRemoveDirCmd cDir
    if iswindows()
        return 'rmdir /s /q "' + substr(cDir, "/", char(92)) + '" >nul 2>nul'
    else
        return 'rm -rf "' + cDir + '" >/dev/null 2>&1'
    ok

func normalizePath cPath
    cStr = substr(cPath, char(92), "/")
    while substr(cStr, "//") > 0
        cStr = substr(cStr, "//", "/")
    end
    if len(cStr) > 1 and substr(cStr, len(cStr), 1) = "/"
        if not (len(cStr) = 3 and substr(cStr, 2, 2) = ":/")
            cStr = left(cStr, len(cStr) - 1)
        ok
    ok
    return cStr

func getFilenameOnly cPath
    cNorm = normalizePath(cPath)
    nPos = 0
    for i = len(cNorm) to 1 step -1
        if substr(cNorm, i, 1) = "/"
            nPos = i
            exit
        ok
    next
    if nPos > 0
        return substr(cNorm, nPos + 1)
    ok
    return cNorm