# ringenv - Command: build / scaffold
# Production Project Lifecycle Management for Desktop (ring2exe-plus) & Mobile (ring2apk)

load "stdlibcore.ring"

# Main entry point for 'ringenv build' command
func cmdBuild aArgs
    # Switch to caller working directory so relative paths and builds run in caller project
    cCaller = getCallerDir()
    if cCaller != "" and direxists(cCaller)
        chdir(cCaller)
    ok

    if len(aArgs) < 2
        showBuildHelp()
        return
    ok

    cSub = lower(aArgs[2])

    switch cSub
        on "help"
            showBuildHelp()

        on "--help"
            showBuildHelp()

        on "-h"
            showBuildHelp()

        on "desktop"
            buildDesktop(aArgs)

        on "exe"
            buildDesktop(aArgs)

        on "apk"
            buildApk(aArgs)

        on "android"
            buildApk(aArgs)

        on "qtmobile"
            buildQtMobile(aArgs)

        on "mobileqt"
            buildQtMobile(aArgs)

        on "setup-android"
            buildSetupAndroid()

        on "setup"
            buildSetupAndroid()

        on "scaffold"
            cType = "all"
            if len(aArgs) >= 3
                cType = lower(aArgs[3])
            ok
            buildScaffold(cType)

        other
            ? uiError("Unknown build target: '" + cSub + "'")
            ? "Run " + uiStyle("ringenv build help", C_BOLD + C_BYELLOW) + " to view available build commands."
    off

# Display help and usage instructions for build command
func showBuildHelp
    uiBanner("ringenv build - Project Lifecycle & Packaging", "Desktop Executables & Android APKs")
    ? ""
    ? "  " + uiStyle("Usage:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("ringenv build <target> [options]", C_BOLD + C_BYELLOW)
    ? "    " + uiStyle("ringenv scaffold [desktop|apk|qtmobile|all]", C_BOLD + C_BYELLOW)
    ? ""
    ? "  " + uiStyle("Build Targets:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("desktop / exe", C_BOLD + C_BCYAN) + "        Build standalone desktop executable (powered by ring2exe-plus)"
    ? "    " + uiStyle("apk / android", C_BOLD + C_BCYAN) + "        Build standalone Android APK package (powered by ring2apk)"
    ? "    " + uiStyle("qtmobile / mobileqt", C_BOLD + C_BCYAN) + "    Export Qt Creator Android/iOS project (RingQt & full GUI)"
    ? "    " + uiStyle("setup-android", C_BOLD + C_BCYAN) + "        Verify and launch Android SDK/NDK/JDK toolchain installer"
    ? "    " + uiStyle("scaffold [type]", C_BOLD + C_BCYAN) + "      Generate configuration files and build automation scripts"
    ? ""
    ? "  " + uiStyle("Scaffold Types:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("scaffold desktop", C_BOLD + C_BMAGENTA) + "   Create ring2exe.conf and desktop build scripts (.bat & .sh)"
    ? "    " + uiStyle("scaffold apk", C_BOLD + C_BMAGENTA) + "       Create ring2apk.ring and Android build scripts (.bat & .sh)"
    ? "    " + uiStyle("scaffold qtmobile", C_BOLD + C_BMAGENTA) + "  Generate Qt Creator mobile project for RingQt GUI apps"
    ? "    " + uiStyle("scaffold all", C_BOLD + C_BMAGENTA) + "       Create full desktop and mobile build configuration suite"
    ? ""
    ? "  " + uiStyle("Examples:", C_BOLD + C_WHITE)
    ? "    ringenv build desktop"
    ? "    ringenv build apk"
    ? "    ringenv build qtmobile"
    ? "    ringenv build setup-android"
    ? "    ringenv scaffold all"
    ? uiStyle("======================================================================", C_CYAN)

# Parse simple key = value configuration file (like ring2exe.conf)
func parseConfigFile cFilePath
    aConfig = []
    if not fexists(cFilePath)
        return aConfig
    ok

    cContent = read(cFilePath)
    aLines = split(cContent, nl)
    for cLine in aLines
        cTrimmed = trim(cLine)
        # Skip empty lines and comments
        if cTrimmed = "" or substr(cTrimmed, 1, 1) = "#" or substr(cTrimmed, 1, 2) = "//"
            loop
        ok
        nEq = substr(cTrimmed, "=")
        if nEq > 0
            cKey = lower(trim(substr(cTrimmed, 1, nEq - 1)))
            cVal = trim(substr(cTrimmed, nEq + 1, len(cTrimmed)))
            # Strip quotes if present
            if (substr(cVal, 1, 1) = '"' and substr(cVal, len(cVal), 1) = '"') or
               (substr(cVal, 1, 1) = "'" and substr(cVal, len(cVal), 1) = "'")
                cVal = substr(cVal, 2, len(cVal) - 2)
            ok
            aConfig[cKey] = cVal
        ok
    next
    return aConfig

# Build Standalone Desktop Executable
func buildDesktop aArgs
    uiBanner("Building Desktop Application", "Using ring2exe-plus compiler")
    ? ""

    cConfPath = "ring2exe.conf"
    aConf = parseConfigFile(cConfPath)

    # Determine source file
    cSource = "src/main.ring"
    if aConf["source"] != NULL and aConf["source"] != ""
        cSource = aConf["source"]
    but fexists("main.ring")
        cSource = "main.ring"
    but fexists("app.ring")
        cSource = "app.ring"
    ok

    if not fexists(cSource)
        ? uiError("Source file not found: " + cSource)
        ? "Please make sure your entry point file exists or configure 'source' in ring2exe.conf."
        return false
    ok

    # Determine output name
    cOutput = "MyApp"
    if aConf["output"] != NULL and aConf["output"] != ""
        cOutput = aConf["output"]
    ok

    # Determine options
    lGui = true
    if aConf["gui"] != NULL and lower(aConf["gui"]) = "false"
        lGui = false
    ok

    lAutoLibs = true
    if aConf["auto-libs"] != NULL and lower(aConf["auto-libs"]) = "false"
        lAutoLibs = false
    ok

    lRelease = true
    if aConf["release"] != NULL and lower(aConf["release"]) = "false"
        lRelease = false
    ok

    cIcon = ""
    if aConf["icon"] != NULL and aConf["icon"] != ""
        cIcon = aConf["icon"]
    but fexists("assets/logo.ico")
        cIcon = "assets/logo.ico"
    but fexists("public/logo.ico")
        cIcon = "public/logo.ico"
    ok

    # Prepare command
    cCmd = "ring2exe " + toNativePath(cSource)
    if lGui
        cCmd = cCmd + " -gui"
    ok
    if lAutoLibs
        cCmd = cCmd + " -auto-libs"
    ok
    if cIcon != "" and fexists(cIcon)
        cCmd = cCmd + " -icon=" + toNativePath(cIcon)
    ok
    cCmd = cCmd + " -output=" + cOutput
    if lRelease
        cCmd = cCmd + " -release"
    ok

    # Display build plan
    ? "  " + uiStyle("Source File:  ", C_BOLD + C_WHITE) + uiStyle(cSource, C_BCYAN)
    ? "  " + uiStyle("Output Name:  ", C_BOLD + C_WHITE) + uiStyle(cOutput, C_BYELLOW)
    ? "  " + uiStyle("GUI Mode:     ", C_BOLD + C_WHITE) + uiStyle("" + lGui, C_BGREEN)
    ? "  " + uiStyle("Auto-Libs:    ", C_BOLD + C_WHITE) + uiStyle("" + lAutoLibs, C_BGREEN)
    if cIcon != ""
        ? "  " + uiStyle("App Icon:     ", C_BOLD + C_WHITE) + uiStyle(cIcon, C_DIM)
    ok
    ? "  " + uiStyle("Optimization: ", C_BOLD + C_WHITE) + uiStyle("Release (-O3)", C_BGREEN)
    ? ""
    # Pre-flight check: Test compile source file to catch missing libraries or syntax errors early
    cCheckFile = "ringenv_build_check.tmp"
    systemSilent('ring "' + toNativePath(cSource) + '" -go -norun > ' + cCheckFile + ' 2>&1')
    if fexists(cCheckFile)
        cCheckLog = read(cCheckFile)
        remove(cCheckFile)
        if substr(cCheckLog, "Error (") > 0 or substr(cCheckLog, "Error(") > 0
            ? uiError("Source code compilation error in '" + cSource + "':")
            ? ""
            ? cCheckLog
            ? uiWarn("Build aborted. Please resolve the compilation error above.")
            return false
        ok
    ok

    system(cCmd)

    # Destination directory
    cPlatform = getPlatformName()
    cDistDir = "release/" + cOutput + "-" + cPlatform + "-x64"
    ensureDir("release")
    ensureDir(cDistDir)

    # Resolve executable extension and source paths
    cSrcDir = getFileDir(cSource)
    cBase = getFileBaseName(cSource)
    cExt = ""
    if iswindows()
        cExt = ".exe"
    ok
    cExeName = cOutput + cExt

    # Search for compiled executable across all possible locations
    aExeCandidates = [
        cOutput + cExt,
        cSrcDir + "/" + cOutput + cExt,
        cBase + cExt,
        cSrcDir + "/" + cBase + cExt,
        "target/windows/" + cOutput + cExt,
        "target/windows/" + cBase + cExt,
        "target/linux/" + cOutput,
        "target/linux/" + cBase
    ]

    cFoundExe = ""
    for cCandidate in aExeCandidates
        if fexists(cCandidate)
            cFoundExe = cCandidate
            exit
        ok
    next

    if cFoundExe != ""
        cDestExe = cDistDir + "/" + cExeName
        if fexists(cDestExe)
            remove(cDestExe)
        ok
        copyFile(cFoundExe, cDestExe)

        # Clean intermediate executable from source/root directory
        if cFoundExe != cDestExe
            remove(cFoundExe)
        ok
    ok

    # Search for compiled ringo bytecode across all possible locations
    aRingoCandidates = [
        "ring.ringo",
        cSrcDir + "/ring.ringo",
        cOutput + ".ringo",
        cSrcDir + "/" + cOutput + ".ringo",
        cBase + ".ringo",
        cSrcDir + "/" + cBase + ".ringo"
    ]

    for cRingo in aRingoCandidates
        if fexists(cRingo)
            copyFile(cRingo, cDistDir + "/ring.ringo")
            if cRingo != (cDistDir + "/ring.ringo")
                remove(cRingo)
            ok
        ok
    next

    # Clean intermediate resource scripts
    aClean = ["main.rc", "main.res", "app.rc", "app.res", cOutput + ".rc", cOutput + ".res",
              cSrcDir + "/main.rc", cSrcDir + "/main.res", cSrcDir + "/app.rc", cSrcDir + "/app.res"]
    for cF in aClean
        if fexists(cF) remove(cF) ok
        if fexists(cDistDir + "/" + cF) remove(cDistDir + "/" + cF) ok
    next

    # Bundle active Ring runtime libraries (DLLs on Windows, SO on Linux) exclusively into cDistDir
    uiDivider()
    ? "  " + uiStyle("Bundling Runtime Dependencies & Assets...", C_BOLD + C_WHITE)
    
    # Locate runtime binary directory (prefer active virtual environment, then fallback to exefolder)
    cBinDir = exefolder()
    cVenvDir = sysget("RVENV_DIR")
    if cVenvDir != "" and direxists(cVenvDir + "/bin")
        cBinDir = normalizePath(cVenvDir + "/bin")
    but direxists(".rvenv/bin")
        cBinDir = normalizePath(".rvenv/bin")
    but direxists("rvenv/bin")
        cBinDir = normalizePath("rvenv/bin")
    ok

    if iswindows()
        # Copy core ring DLL to release package
        if fexists(cBinDir + "/ring.dll")
            copyFile(cBinDir + "/ring.dll", cDistDir + "/ring.dll")
        ok

        # Copy ALL DLLs present in active environment bin directory
        aDllNames = dir(cBinDir)
        for aItem in aDllNames
            cItemName = aItem[1]
            cLower = lower(cItemName)
            if substr(cLower, ".dll") > 0
                copyFile(cBinDir + "/" + cItemName, cDistDir + "/" + cItemName)
            ok
        next

        # Copy Qt / GUI plugins (platforms, imageformats, styles)
        if direxists(cBinDir + "/platforms")
            copyFolder(cBinDir + "/platforms", cDistDir + "/platforms")
        ok
        if direxists(cBinDir + "/imageformats")
            copyFolder(cBinDir + "/imageformats", cDistDir + "/imageformats")
        ok
        if direxists(cBinDir + "/styles")
            copyFolder(cBinDir + "/styles", cDistDir + "/styles")
        ok

        # Copy ring.exe CLI binary for diagnostics/debugging
        if fexists(cBinDir + "/ring.exe")
            copyFile(cBinDir + "/ring.exe", cDistDir + "/ring.exe")
        ok

        # Generate qt.conf if Qt is bundled to guarantee local plugin loading
        if fexists(cDistDir + "/ringqt.dll") or fexists(cDistDir + "/ringqt_light.dll")
            write(cDistDir + "/qt.conf", "[Paths]" + nl + "Prefix = ." + nl + "Plugins = ." + nl)
        ok
    ok

    # Copy assets, public, and res folders if present
    if direxists("assets")
        copyFolder("assets", cDistDir + "/assets")
    ok
    if direxists("public")
        copyFolder("public", cDistDir + "/public")
    ok
    if direxists("res")
        copyFolder("res", cDistDir + "/res")
    ok

    # Copy project media files (images, icons, sounds) from root and src/
    aMediaExts = [".jpg", ".jpeg", ".png", ".bmp", ".ico", ".gif", ".wav", ".mp3", ".ogg", ".ttf", ".otf"]
    aRootFiles = dir(".")
    for aItem in aRootFiles
        cName = aItem[1]
        cLowerName = lower(cName)
        for cExt in aMediaExts
            if substr(cLowerName, cExt) > 0
                copyFile(cName, cDistDir + "/" + cName)
                exit
            ok
        next
    next

    if direxists("src")
        aSrcMedia = dir("src")
        for aItem in aSrcMedia
            cName = aItem[1]
            cLowerName = lower(cName)
            for cExt in aMediaExts
                if substr(cLowerName, cExt) > 0
                    copyFile("src/" + cName, cDistDir + "/" + cName)
                    exit
                ok
            next
        next
    ok

    # Create convenient launcher script
    if iswindows()
        cLauncher = cDistDir + "/Launch_" + cOutput + ".bat"
        cBatchContent = "@echo off" + nl + 'cd /d "%~dp0"' + nl + 'start "" "' + cExeName + '"' + nl
        write(cLauncher, cBatchContent)

        # Root GUI launcher
        cRootLauncher = "Launch_" + cOutput + ".bat"
        cRootBatch = "@echo off" + nl + 'cd /d "%~dp0' + toNativePath(cDistDir) + '"' + nl + 'start "" "' + cExeName + '"' + nl
        write(cRootLauncher, cRootBatch)

        # Root CLI launcher (allows typing MyApp in project root without DLL pollution)
        cTermLauncher = cOutput + ".bat"
        cTermBatch = "@echo off" + nl + 'pushd "%~dp0' + toNativePath(cDistDir) + '"' + nl + '"%~dp0' + toNativePath(cDistDir) + '\' + cExeName + '" %*' + nl + 'popd' + nl
        write(cTermLauncher, cTermBatch)
    else
        cLauncher = cDistDir + "/launch_" + lower(cOutput) + ".sh"
        cShContent = "#!/bin/sh" + nl + 'cd "$(dirname "$0")"' + nl + './' + cExeName + ' "$@"' + nl
        write(cLauncher, cShContent)
        system('chmod +x "' + cLauncher + '" 2>/dev/null')
        if fexists(cDistDir + "/" + cExeName)
            system('chmod +x "' + cDistDir + '/' + cExeName + '" 2>/dev/null')
        ok

        # Root launcher script
        cRootSh = lower(cOutput) + ".sh"
        cRootShContent = "#!/bin/sh" + nl + 'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"' + nl + '"$SCRIPT_DIR/' + cDistDir + '/' + cExeName + '" "$@"' + nl
        write(cRootSh, cRootShContent)
        system('chmod +x "' + cRootSh + '" 2>/dev/null')
    ok

    ? ""
    uiBanner("Desktop Build Completed", "Distribution package ready")
    ? ""
    ? "  " + uiStyle("Package Location: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cDistDir), C_BOLD + C_BGREEN)
    ? "  " + uiStyle("Executable:       ", C_BOLD + C_WHITE) + uiStyle(cExeName, C_BOLD + C_BYELLOW)
    if iswindows()
        ? "  " + uiStyle("One-Click Launch: ", C_BOLD + C_WHITE) + uiStyle("Launch_" + cOutput + ".bat", C_BCYAN)
    else
        ? "  " + uiStyle("Launcher Script:  ", C_BOLD + C_WHITE) + uiStyle("launch_" + lower(cOutput) + ".sh", C_BCYAN)
    ok
    uiDivider()
    return true

# Build Android APK using ring2apk
func buildApk aArgs
    uiBanner("Building Android APK Package", "Using ring2apk toolchain")
    ? ""

    # Check for ring2apk.ring configuration
    if not fexists("ring2apk.ring") and not fexists("android/ring2apk.ring")
        ? uiError("Configuration file 'ring2apk.ring' was not found.")
        ? "Run " + uiStyle("ringenv scaffold apk", C_BOLD + C_BYELLOW) + " to generate a starter configuration."
        return false
    ok

    cConfFile = "ring2apk.ring"
    if not fexists("ring2apk.ring") and fexists("android/ring2apk.ring")
        cConfFile = "android/ring2apk.ring"
    ok

    # Validate Android SDK / JDK environment variables
    cAndroidHome = sysget("ANDROID_HOME")
    if cAndroidHome = ""
        cAndroidHome = sysget("ANDROID_SDK_ROOT")
    ok

    # Fallback registry lookup on Windows
    if cAndroidHome = "" and iswindows()
        cUser = sysget("USERPROFILE")
        if fexists(cUser + "/Android") or direxists(cUser + "/Android")
            cAndroidHome = cUser + "/Android"
        ok
    ok

    cJavaHome = sysget("JAVA_HOME")

    cAndroidStatus = ""
    if cAndroidHome != ""
        cAndroidStatus = uiStyle(cAndroidHome, C_BGREEN)
    else
        cAndroidStatus = uiStyle("Not detected in PATH", C_BYELLOW)
    ok

    cJavaStatus = ""
    if cJavaHome != ""
        cJavaStatus = uiStyle(cJavaHome, C_BGREEN)
    else
        cJavaStatus = uiStyle("Not detected in PATH", C_BYELLOW)
    ok

    ? "  " + uiStyle("Android SDK:   ", C_BOLD + C_WHITE) + cAndroidStatus
    ? "  " + uiStyle("Java JDK:      ", C_BOLD + C_WHITE) + cJavaStatus
    ? "  " + uiStyle("Config File:   ", C_BOLD + C_WHITE) + uiStyle(cConfFile, C_BCYAN)
    ? ""

    # Dynamic Android Compatibility Analysis and Extension Auto-Harvester
    analyzeAndHarvestAndroidDeps()

    # Stage ring/ directory temporarily only if needed
    lTemporaryRingDir = false
    if not direxists("ring") and fexists("src/main.ring")
        ensureDir("ring")
        copyFolder("src", "ring")
        if direxists("src")
            ensureDir("ring/src")
            copyFolder("src", "ring/src")
        ok
        lTemporaryRingDir = true
    ok

    # Ensure Android resource files exist (styles.xml, strings.xml)
    ensureDir("res/values")
    if not fexists("res/values/styles.xml")
        cStyles = '<?xml version="1.0" encoding="utf-8"?>' + nl +
                  '<resources>' + nl +
                  '    <style name="AppTheme" parent="@android:style/Theme.DeviceDefault.NoActionBar">' + nl +
                  '    </style>' + nl +
                  '</resources>' + nl
        write("res/values/styles.xml", cStyles)
    ok
    if not fexists("res/values/strings.xml")
        cStrings = '<?xml version="1.0" encoding="utf-8"?>' + nl +
                   '<resources>' + nl +
                   '    <string name="app_name">MyApp</string>' + nl +
                   '</resources>' + nl
        write("res/values/strings.xml", cStrings)
    ok

    # Stage assets/ directory if present
    if direxists("assets")
        ensureDir("android/assets")
        copyFolder("assets", "android/assets")
    ok

    # Pre-flight check: Test compile source file before Android packaging
    cSourceCheck = "ring/main.ring"
    cCheckFile = "ringenv_apk_check.tmp"
    systemSilent('ring "' + toNativePath(cSourceCheck) + '" -go -norun > ' + cCheckFile + ' 2>&1')
    if fexists(cCheckFile)
        cCheckLog = read(cCheckFile)
        remove(cCheckFile)
        if substr(cCheckLog, "Error (") > 0 or substr(cCheckLog, "Error(") > 0
            ? uiError("Source code compilation error in '" + cSourceCheck + "':")
            ? ""
            ? cCheckLog
            ? uiWarn("APK Build aborted. Please install required libraries or fix code errors above.")
            return false
        ok
    ok

    uiDivider()
    ? "  " + uiStyle("Executing ring2apk Android compilation...", C_BOLD + C_WHITE)
    ? ""

    cCmd = "ring2apk build --rebuild"
    system(cCmd)

    # Locate generated APK file
    cApkFile = ""
    if direxists("build")
        aBuildItems = dir("build")
        for aItem in aBuildItems
            if substr(lower(aItem[1]), ".apk") > 0
                cApkFile = "build/" + aItem[1]
                exit
            ok
        next
    ok

    # Cleanup temporary staged ring directory
    if lTemporaryRingDir and direxists("ring")
        deleteFolder("ring")
    ok

    ? ""
    uiBanner("Android Build Process Finished", "Check build/ directory for generated APK")
    ? ""
    if cApkFile != ""
        ? "  " + uiStyle("Generated APK: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cApkFile), C_BOLD + C_BGREEN)
    else
        ? "  " + uiStyle("Output Folder: ", C_BOLD + C_WHITE) + uiStyle(toNativePath("build"), C_BOLD + C_BGREEN)
    ok
    uiDivider()
    return true

# Launch Android Environment Setup Tool
func buildSetupAndroid
    uiBanner("Android Toolchain Setup", "ring2apk Environment Configuration")
    ? ""

    # Look for setup-env.ring in local or active ringpm packages
    aSearchPaths = [
        "tools/ringpm/packages/ring2apk/tools/setup-env.ring",
        exefolder() + "/../tools/ringpm/packages/ring2apk/tools/setup-env.ring",
        "C:/ring/tools/ringpm/packages/ring2apk/tools/setup-env.ring"
    ]

    cSetupFile = ""
    for cPath in aSearchPaths
        if fexists(cPath)
            cSetupFile = cPath
            exit
        ok
    next

    if cSetupFile = ""
        ? uiError("ring2apk setup tool was not found.")
        ? "Please install ring2apk first by running:"
        ? "  " + uiStyle("ringenv hub install ring2apk", C_BOLD + C_BCYAN)
        return false
    ok

    ? "  " + uiStyle("Found setup tool: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cSetupFile), C_BGREEN)
    ? "  " + uiStyle("Launching interactive setup...", C_BOLD + C_BYELLOW)
    ? ""

    cSetupDir = getFileDir(cSetupFile)
    cPrevDir = currentdir()
    if cSetupDir != "" and direxists(cSetupDir)
        chdir(cSetupDir)
    ok

    system('ring setup-env.ring')

    if cPrevDir != "" and direxists(cPrevDir)
        chdir(cPrevDir)
    ok
    return true

# Generate build configuration and shell scripts
func buildScaffold cType
    cTarget = lower(trim(cType))
    if cTarget = "qtmobile" or cTarget = "mobileqt"
        return buildQtMobile([])
    ok
    if cTarget = "" or cTarget = "all"
        lDesktop = true
        lApk = true
    but cTarget = "desktop" or cTarget = "exe"
        lDesktop = true
        lApk = false
    but cTarget = "apk" or cTarget = "android"
        lDesktop = false
        lApk = true
    else
        ? uiError("Invalid scaffold target: '" + cType + "'. Supported: desktop, apk, qtmobile, all")
        return false
    ok

    uiBanner("Scaffolding Build Automation", "Generating configs and scripts")
    ? ""

    ensureDir("scripts")

    if lDesktop
        # 1. ring2exe.conf
        if not fexists("ring2exe.conf")
            cConf = "# ==============================================================================" + nl +
                    "# Ring2EXE Plus Build Configuration" + nl +
                    "# ==============================================================================" + nl + nl +
                    "# Entry point Ring script" + nl +
                    "source = src/main.ring" + nl + nl +
                    "# Output executable name" + nl +
                    "output = MyApp" + nl + nl +
                    "# GUI mode: hides the black console window on Windows" + nl +
                    "gui = true" + nl + nl +
                    "# Automatically detect and bundle required Ring libraries" + nl +
                    "auto-libs = true" + nl + nl +
                    "# Application brand icon" + nl +
                    "icon = assets/logo.ico" + nl + nl +
                    "# Build optimized release binary (-O3)" + nl +
                    "release = true" + nl + nl +
                    "# Keep intermediate artifacts" + nl +
                    "keep = false" + nl

            write("ring2exe.conf", cConf)
            ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("ring2exe.conf", C_BOLD + C_WHITE)
        else
            ? "  " + uiStyle("[*] Exists:  ", C_BYELLOW) + uiStyle("ring2exe.conf", C_DIM)
        ok

        # 2. scripts/build_desktop.bat
        cBat = '@echo off' + nl +
               '@chcp 65001 >nul' + nl +
               'setlocal enabledelayedexpansion' + nl + nl +
               'echo ========================================================================' + nl +
               'echo        DESKTOP BUILDER (Powered by ringenv / ring2exe-plus)' + nl +
               'echo ========================================================================' + nl + nl +
               'set PROJECT_ROOT=%~dp0..' + nl +
               'cd /d "%PROJECT_ROOT%"' + nl + nl +
               'ringenv build desktop' + nl
        write("scripts/build_desktop.bat", cBat)
        ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("scripts/build_desktop.bat", C_BOLD + C_WHITE)

        # 3. scripts/build_desktop.sh
        cSh = '#!/usr/bin/env bash' + nl +
              'set -e' + nl +
              'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' + nl +
              'PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"' + nl +
              'cd "$PROJECT_ROOT"' + nl + nl +
              'echo "========================================================================"' + nl +
              'echo "       DESKTOP BUILDER (Powered by ringenv / ring2exe-plus)"' + nl +
              'echo "========================================================================"' + nl + nl +
              'ringenv build desktop' + nl
        write("scripts/build_desktop.sh", cSh)
        if not iswindows()
            system('chmod +x "scripts/build_desktop.sh" 2>/dev/null')
        ok
        ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("scripts/build_desktop.sh", C_BOLD + C_WHITE)
    ok

    if lApk
        # 1. ring2apk.ring
        if not fexists("ring2apk.ring")
            cApkConf = '/* ' + nl +
                       '    Android Build Configuration for ring2apk' + nl +
                       '*/' + nl + nl +
                       'Ring2ApkConfig = [' + nl +
                       '    # App identity' + nl +
                       '    :name        = "MyApp",' + nl +
                       '    :label       = "My Application",' + nl +
                       '    :packageId   = "com.company.myapp",' + nl +
                       '    :versionCode = 1,' + nl +
                       '    :versionName = "1.0.0",' + nl + nl +
                       '    # Android SDK versions' + nl +
                       '    :minSdk      = 21,' + nl +
                       '    :targetSdk   = 34,' + nl +
                       '    :compileSdk  = 34,' + nl + nl +
                       '    # Target CPU architectures' + nl +
                       '    :targets     = ["arm64-v8a", "armeabi-v7a", "x86_64"],' + nl + nl +
                       '    # Directories' + nl +
                       '    :srcDir      = "src",' + nl +
                       '    :resDir      = "res",' + nl +
                       '    :assetsDir   = "assets",' + nl +
                       '    :outputDir   = "build",' + nl + nl +
                       '    # Entry point Ring code' + nl +
                       '    :ringSrcDir  = "src",' + nl +
                       '    :entryPoint  = "main.ring",' + nl + nl +
                       '    # Display configuration' + nl +
                       '    :theme       = "@style/AppTheme",' + nl +
                       '    :orientation = "unspecified",' + nl + nl +
                       '    # Required Android permissions' + nl +
                       '    :permissions = [' + nl +
                       '        "android.permission.INTERNET",' + nl +
                       '        "android.permission.ACCESS_NETWORK_STATE"' + nl +
                       '    ]' + nl +
                       ']' + nl
            write("ring2apk.ring", cApkConf)
            ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("ring2apk.ring", C_BOLD + C_WHITE)
        else
            ? "  " + uiStyle("[*] Exists:  ", C_BYELLOW) + uiStyle("ring2apk.ring", C_DIM)
        ok

        # 2. scripts/build_apk.bat
        cApkBat = '@echo off' + nl +
                  '@chcp 65001 >nul' + nl +
                  'setlocal enabledelayedexpansion' + nl + nl +
                  'echo ========================================================================' + nl +
                  'echo        ANDROID APK BUILDER (Powered by ringenv / ring2apk)' + nl +
                  'echo ========================================================================' + nl + nl +
                  'set PROJECT_ROOT=%~dp0..' + nl +
                  'cd /d "%PROJECT_ROOT%"' + nl + nl +
                  'ringenv build apk' + nl
        write("scripts/build_apk.bat", cApkBat)
        ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("scripts/build_apk.bat", C_BOLD + C_WHITE)

        # 3. scripts/build_apk.sh
        cApkSh = '#!/usr/bin/env bash' + nl +
                 'set -e' + nl +
                 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' + nl +
                 'PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"' + nl +
                 'cd "$PROJECT_ROOT"' + nl + nl +
                 'echo "========================================================================"' + nl +
                 'echo "       ANDROID APK BUILDER (Powered by ringenv / ring2apk)"' + nl +
                 'echo "========================================================================"' + nl + nl +
                 'ringenv build apk' + nl
        write("scripts/build_apk.sh", cApkSh)
        if not iswindows()
            system('chmod +x "scripts/build_apk.sh" 2>/dev/null')
        ok
        ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("scripts/build_apk.sh", C_BOLD + C_WHITE)

        # 4. scripts/setup_android_env.bat
        cSetupBat = '@echo off' + nl +
                    'echo ========================================================================' + nl +
                    'echo        ANDROID ENVIRONMENT SETUP (Powered by ringenv)' + nl +
                    'echo ========================================================================' + nl + nl +
                    'ringenv build setup-android' + nl +
                    'pause' + nl
        write("scripts/setup_android_env.bat", cSetupBat)
        ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("scripts/setup_android_env.bat", C_BOLD + C_WHITE)

        # 5. res/values/styles.xml & strings.xml
        ensureDir("res/values")
        if not fexists("res/values/styles.xml")
            cStyles = '<?xml version="1.0" encoding="utf-8"?>' + nl +
                      '<resources>' + nl +
                      '    <style name="AppTheme" parent="@android:style/Theme.DeviceDefault.NoActionBar">' + nl +
                      '    </style>' + nl +
                      '</resources>' + nl
            write("res/values/styles.xml", cStyles)
            ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("res/values/styles.xml", C_BOLD + C_WHITE)
        ok
        if not fexists("res/values/strings.xml")
            cStrings = '<?xml version="1.0" encoding="utf-8"?>' + nl +
                       '<resources>' + nl +
                       '    <string name="app_name">MyApp</string>' + nl +
                       '</resources>' + nl
            write("res/values/strings.xml", cStrings)
            ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("res/values/strings.xml", C_BOLD + C_WHITE)
        ok

        # 6. src/cpp Native NDK Toolchain & Extensions Support (libmain.so)
        ensureDir("src/cpp")
        ensureDir("src/cpp/ext")
        ensureDir("src/cpp/cmake")
        ensureDir("src/cpp/ring")

        cRingHost = ""
        cHostEnv = sysget("HOST_RING_DIR")
        if cHostEnv != "" and direxists(cHostEnv)
            cRingHost = normalizePath(cHostEnv)
        but direxists("C:/ring")
            cRingHost = "C:/ring"
        but direxists(exefolder() + "/..")
            cRingHost = normalizePath(exefolder() + "/..")
        ok

        if cRingHost != ""
            cRing2ApkPkg = cRingHost + "/tools/ringpm/packages/ring2apk"
            if fexists(cRing2ApkPkg + "/examples/webview/src/cpp/cmake/RingExtensions.cmake") and not fexists("src/cpp/cmake/RingExtensions.cmake")
                copyFile(cRing2ApkPkg + "/examples/webview/src/cpp/cmake/RingExtensions.cmake", "src/cpp/cmake/RingExtensions.cmake")
            ok
            if fexists(cRing2ApkPkg + "/examples/webview/src/cpp/cmake/ext.c.in") and not fexists("src/cpp/cmake/ext.c.in")
                copyFile(cRing2ApkPkg + "/examples/webview/src/cpp/cmake/ext.c.in", "src/cpp/cmake/ext.c.in")
            ok

            if not direxists("src/cpp/ring/src") or not direxists("src/cpp/ring/include")
                cLangSrc = cRingHost + "/language/src"
                cLangInc = cRingHost + "/language/include"
                if direxists(cLangSrc) and direxists(cLangInc)
                    ensureDir("src/cpp/ring/src")
                    ensureDir("src/cpp/ring/include")
                    aFiles = dir(cLangSrc)
                    for aItem in aFiles
                        cFile = aItem[1]
                        if aItem[2] = 0 and cFile != "ring.c" and cFile != "ringw.c"
                            copyFile(cLangSrc + "/" + cFile, "src/cpp/ring/src/" + cFile)
                        ok
                    next
                    copyFolder(cLangInc, "src/cpp/ring/include")
                ok
            ok
        ok

        if not fexists("src/cpp/main.c")
            cMain = '/* Ring Android Native Application Entry Point */' + nl +
                    '#include <android_native_app_glue.h>' + nl +
                    '#include <android/log.h>' + nl +
                    '#include <stdio.h>' + nl +
                    '#include <stdlib.h>' + nl +
                    '#include <string.h>' + nl +
                    '#include <unistd.h>' + nl +
                    '#include <pthread.h>' + nl + nl +
                    '#include "ring.h"' + nl +
                    '#include "ringappcode.h"' + nl + nl +
                    '#define LOG_TAG "RingApp"' + nl +
                    '#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)' + nl +
                    '#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)' + nl + nl +
                    'static int pfd[2];' + nl +
                    'static pthread_t thr;' + nl + nl +
                    'static void *thread_func(void *arg) {' + nl +
                    '    (void)arg;' + nl +
                    '    ssize_t rdsz;' + nl +
                    '    char buf[256];' + nl +
                    '    while ((rdsz = read(pfd[0], buf, sizeof(buf) - 1)) > 0) {' + nl +
                    '        buf[rdsz] = 0;' + nl +
                    '        __android_log_write(ANDROID_LOG_DEBUG, "RingOutput", buf);' + nl +
                    '    }' + nl +
                    '    return 0;' + nl +
                    '}' + nl + nl +
                    'static void start_logger(void) {' + nl +
                    '    setvbuf(stdout, 0, _IOLBF, 0);' + nl +
                    '    setvbuf(stderr, 0, _IONBF, 0);' + nl +
                    '    pipe(pfd);' + nl +
                    '    dup2(pfd[1], 1);' + nl +
                    '    dup2(pfd[1], 2);' + nl +
                    '    pthread_create(&thr, 0, thread_func, 0);' + nl +
                    '}' + nl + nl +
                    'void android_main(struct android_app *app) {' + nl +
                    '    (void)app;' + nl +
                    '    start_logger();' + nl +
                    '    LOGI("=== Ring App Starting ===");' + nl + nl +
                    '    RingState *pState = ring_state_new();' + nl +
                    '    if (!pState) {' + nl +
                    '        LOGE("Failed to create Ring state");' + nl +
                    '        return;' + nl +
                    '    }' + nl +
                    '    pState->lRun = 1;' + nl +
                    '    ringappcode_run(pState);' + nl +
                    '    ring_state_delete(pState);' + nl +
                    '    LOGI("=== Ring App Finished ===");' + nl +
                    '}' + nl
            write("src/cpp/main.c", cMain)
            ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("src/cpp/main.c", C_BOLD + C_WHITE)
        ok

        if not fexists("src/cpp/CMakeLists.txt")
            cCMake = 'cmake_minimum_required(VERSION 3.22)' + nl +
                     'project(ringapp C CXX)' + nl + nl +
                     'set(CMAKE_C_STANDARD 99)' + nl +
                     'set(CMAKE_C_STANDARD_REQUIRED ON)' + nl + nl +
                     'list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")' + nl +
                     'include(RingExtensions)' + nl + nl +
                     'if((ANDROID_ABI STREQUAL "armeabi-v7a" OR ANDROID_ABI STREQUAL "x86") AND ANDROID_PLATFORM_LEVEL LESS 24)' + nl +
                     '    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -U_FILE_OFFSET_BITS")' + nl +
                     'endif()' + nl + nl +
                     'set(RING_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ring")' + nl +
                     'if(NOT EXISTS "${RING_DIR}/src")' + nl +
                     '    message(FATAL_ERROR "Ring sources not found! Expected at ${RING_DIR}/src")' + nl +
                     'endif()' + nl + nl +
                     'file(GLOB RING_SOURCES ${RING_DIR}/src/*.c)' + nl +
                     'list(FILTER RING_SOURCES EXCLUDE REGEX ".*/ext\\\\.c$")' + nl + nl +
                     'add_library(ring STATIC ${RING_SOURCES})' + nl +
                     'target_include_directories(ring PUBLIC "${RING_DIR}/include")' + nl +
                     'target_link_libraries(ring PUBLIC android log)' + nl + nl +
                     'set(NATIVE_APP_GLUE_DIR "${ANDROID_NDK}/sources/android/native_app_glue")' + nl +
                     'add_library(native_app_glue STATIC' + nl +
                     '    ${NATIVE_APP_GLUE_DIR}/android_native_app_glue.c' + nl +
                     ')' + nl +
                     'target_include_directories(native_app_glue PUBLIC ${NATIVE_APP_GLUE_DIR})' + nl + nl +
                     'add_library(main SHARED' + nl +
                     '    main.c' + nl +
                     '    ${CMAKE_SOURCE_DIR}/../../build/gen/ringappcode.c' + nl +
                     ')' + nl + nl +
                     'target_include_directories(main PRIVATE' + nl +
                     '    ${CMAKE_CURRENT_SOURCE_DIR}' + nl +
                     '    ${CMAKE_SOURCE_DIR}/../../build/gen' + nl +
                     '    ${RING_DIR}/include' + nl +
                     '    ${NATIVE_APP_GLUE_DIR}' + nl +
                     ')' + nl + nl +
                     'target_link_libraries(main PRIVATE' + nl +
                     '    ring' + nl +
                     '    -Wl,--whole-archive' + nl +
                     '    native_app_glue' + nl +
                     '    -Wl,--no-whole-archive' + nl +
                     '    android' + nl +
                     '    log' + nl +
                     ')' + nl + nl +
                     'set(RING_EXT_EXCLUDE tinycthread.c)' + nl +
                     'ring_target_add_extensions(main)' + nl
            write("src/cpp/CMakeLists.txt", cCMake)
            ? "  " + uiStyle("[+] Created: ", C_BGREEN) + uiStyle("src/cpp/CMakeLists.txt", C_BOLD + C_WHITE)
        ok
    ok

    ? ""
    uiSuccess("Scaffold files generated successfully!")
    uiDivider()
    return true

# Extract directory part from file path
func getFileDir cPath
    cNorm = normalizePath(cPath)
    nPos = 0
    for k = len(cNorm) to 1 step -1
        if substr(cNorm, k, 1) = "/"
            nPos = k
            exit
        ok
    next
    if nPos > 0
        return substr(cNorm, 1, nPos - 1)
    ok
    return "."

# Extract basename without extension from file path
func getFileBaseName cPath
    cNorm = normalizePath(cPath)
    nSlash = 0
    for k = len(cNorm) to 1 step -1
        if substr(cNorm, k, 1) = "/"
            nSlash = k
            exit
        ok
    next
    cFile = cNorm
    if nSlash > 0
        cFile = substr(cNorm, nSlash + 1, len(cNorm))
    ok
    nDot = 0
    for k = len(cFile) to 1 step -1
        if substr(cFile, k, 1) = "."
            nDot = k
            exit
        ok
    next
    if nDot > 0
        return substr(cFile, 1, nDot - 1)
    ok
    return cFile

# Dynamic Android Compatibility Analysis and Extension Auto-Harvester
func analyzeAndHarvestAndroidDeps
    cRingHost = ""
    cHostEnv = sysget("HOST_RING_DIR")
    if cHostEnv != "" and direxists(cHostEnv)
        cRingHost = normalizePath(cHostEnv)
    but direxists("C:/ring")
        cRingHost = "C:/ring"
    but direxists(exefolder() + "/..")
        cRingHost = normalizePath(exefolder() + "/..")
    ok

    if cRingHost = ""
        return
    ok

    # Ensure native scaffold structure exists
    ensureAndroidNativeScaffold(cRingHost)

    # 1. Collect all .ring files from project root, src/, and ring/
    aFilesToScan = []
    aRootFiles = dir(".")
    for aItem in aRootFiles
        cName = aItem[1]
        if right(lower(cName), 5) = ".ring"
            aFilesToScan + cName
        ok
    next
    if direxists("src")
        aSrcFiles = dir("src")
        for aItem in aSrcFiles
            cName = aItem[1]
            if right(lower(cName), 5) = ".ring"
                aFilesToScan + ("src/" + cName)
            ok
        next
    ok
    if direxists("ring")
        aRingFiles = dir("ring")
        for aItem in aRingFiles
            cName = aItem[1]
            if right(lower(cName), 5) = ".ring"
                aFilesToScan + ("ring/" + cName)
            ok
        next
    ok

    aLoads = []
    for cFilePath in aFilesToScan
        if not fexists(cFilePath) loop ok
        cContent = read(cFilePath)
        aLines = split(cContent, nl)
        for cLine in aLines
            cTrim = trim(cLine)
            cLowerLine = lower(cTrim)
            if substr(cLowerLine, "load ") = 1
                nQ1 = substr(cTrim, '"')
                if nQ1 > 0
                    cAfterQ1 = substr(cTrim, nQ1 + 1, len(cTrim))
                    nQ2 = substr(cAfterQ1, '"')
                    if nQ2 > 0
                        cLoaded = substr(cTrim, nQ1 + 1, nQ2 - 1)
                        cLoaded = lower(trim(cLoaded))
                        if right(cLoaded, 5) = ".ring"
                            cLoaded = left(cLoaded, len(cLoaded) - 5)
                        ok
                        if find(aLoads, cLoaded) = 0
                            aLoads + cLoaded
                        ok
                    ok
                ok
            ok
        next
    next

    # Classify dependencies
    aAutoHarvestTargets = [
        "cjson", "sqlite", "sqlitelib", "threads", "ringthreads",
        "ringthreadpro", "openssl", "raylib", "ringraylib5",
        "curl", "libcurl", "libuv", "stbimage", "ringstbimage",
        "fastpro", "ringfastpro", "murmurhash", "ringmurmurhash",
        "zip", "ringzip"
    ]

    aQtTargets = ["guilib", "lightguilib", "qt", "ringqt", "qtcore"]

    aDesktopOnly = ["libui", "ringlibui", "winapi", "winlib", "wincreg", "nappgui", "freeglut"]

    lHasQt = false
    aFoundDesktopOnly = []
    aHarvestedNow = []

    for cLoad in aLoads
        if find(aDesktopOnly, cLoad) > 0
            if find(aFoundDesktopOnly, cLoad) = 0
                aFoundDesktopOnly + cLoad
            ok
        ok

        if find(aQtTargets, cLoad) > 0
            lHasQt = true
        ok

        cCleanName = cLoad
        if left(cCleanName, 4) = "ring"
            cCleanName = substr(cCleanName, 5, len(cCleanName))
        ok
        if cCleanName = "raylib" or cCleanName = "raylib5"
            cCleanName = "raylib"
        but cCleanName = "libui"
            cCleanName = "libui"
        but cCleanName = "libuv" or cCleanName = "uv"
            cCleanName = "libuv"
        but right(cCleanName, 3) = "lib" and len(cCleanName) > 3
            cCleanName = left(cCleanName, len(cCleanName) - 3)
        ok
        if cCleanName = "sql" or cCleanName = "sqlite"
            cCleanName = "sqlite"
        but cCleanName = "cjson"
            cCleanName = "cjson"
        but cCleanName = "zip"
            cCleanName = "zip"
        but cCleanName = "openssl" or cCleanName = "ssl"
            cCleanName = "openssl"
        but cCleanName = "raylib" or cCleanName = "raylib5" or cCleanName = "ray"
            cCleanName = "raylib"
        but cCleanName = "curl"
            cCleanName = "curl"
        but cCleanName = "uv" or cCleanName = "libuv"
            cCleanName = "libuv"
        ok

        if find(aAutoHarvestTargets, cCleanName) > 0 or find(aAutoHarvestTargets, cLoad) > 0
            if harvestAndroidNative(cRingHost, cCleanName)
                if find(aHarvestedNow, cCleanName) = 0
                    aHarvestedNow + cCleanName
                ok
            ok
        ok
    next

    if len(aHarvestedNow) > 0 or len(aFoundDesktopOnly) > 0 or lHasQt
        uiDivider()
        ? "  " + uiStyle("Dynamic Android Compatibility Analysis:", C_BOLD + C_WHITE)
        
        for cExt in aHarvestedNow
            ? "  " + uiStyle("[✔] Auto-harvested native NDK extension: ", C_BGREEN) + uiStyle(cExt, C_BOLD + C_WHITE) + " (linked to libmain.so)"
        next

        if lHasQt
            ? "  " + uiStyle("[!] Advisory: ", C_BYELLOW) + "Project uses Qt GUI framework ('guilib')."
            ? "      " + uiStyle("Standalone NDK APK uses WebView or Raylib for GUI.", C_DIM)
            ? "      " + uiStyle("To export full Qt GUI for Android via Qt Creator, run:", C_DIM) + " " + uiStyle("ringenv scaffold qtmobile", C_BCYAN)
        ok

        for cDesk in aFoundDesktopOnly
            ? "  " + uiStyle("[!] Warning:  ", C_BRED) + "Detected desktop-only library '" + cDesk + "' (not supported on Android NDK)."
        next
        uiDivider()
    ok

# Prepare and export Qt Creator Mobile project (for RingQt / guilib / AnalogClock)
func buildQtMobile aArgs
    uiBanner("Preparing Qt Mobile Project (Android / iOS)", "For RingQt & GUI Applications")
    ? ""

    # Locate Host Ring directory
    cRingHost = ""
    cHostEnv = sysget("HOST_RING_DIR")
    if cHostEnv != "" and direxists(cHostEnv)
        cRingHost = normalizePath(cHostEnv)
    but direxists("C:/ring")
        cRingHost = "C:/ring"
    but direxists(exefolder() + "/..")
        cRingHost = normalizePath(exefolder() + "/..")
    ok

    if cRingHost = ""
        ? uiError("Could not locate a full Ring installation on this system.")
        return false
    ok

    cQtTemplate = cRingHost + "/extensions/android/ringqt/project"
    if not direxists(cQtTemplate)
        ? uiError("RingQt Android template not found at: " + cQtTemplate)
        return false
    ok

    # Determine entry source file
    cConfPath = "ring2exe.conf"
    aConf = parseConfigFile(cConfPath)
    cSource = "src/main.ring"
    if aConf["source"] != NULL and aConf["source"] != ""
        cSource = aConf["source"]
    but fexists("src/AnalogClock.ring")
        cSource = "src/AnalogClock.ring"
    but fexists("AnalogClock.ring")
        cSource = "AnalogClock.ring"
    but fexists("main.ring")
        cSource = "main.ring"
    ok

    if not fexists(cSource)
        ? uiError("Source file not found: " + cSource)
        return false
    ok

    cAppName = "MyApp"
    if aConf["output"] != NULL and aConf["output"] != ""
        cAppName = aConf["output"]
    ok

    cDest = "android-qt"
    ensureDir(cDest)

    ? "  " + uiStyle("Source File:      ", C_BOLD + C_WHITE) + uiStyle(cSource, C_BCYAN)
    ? "  " + uiStyle("Target Directory: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cDest), C_BYELLOW)
    ? ""

    # 1. Copy Ring and RingQt NDK sources from template
    ensureDir(cDest + "/ring")
    ensureDir(cDest + "/ringqt")
    copyFolder(cQtTemplate + "/ring", cDest + "/ring")
    copyFolder(cQtTemplate + "/ringqt", cDest + "/ringqt")

    # 2. Copy main.cpp and project.pro
    copyFile(cQtTemplate + "/main.cpp", cDest + "/main.cpp")
    copyFile(cQtTemplate + "/project.pro", cDest + "/project.pro")

    # 3. Compile Ring source into bytecode (.ringo)
    ? "  " + uiStyle("Compiling Ring bytecode for Mobile...", C_BOLD + C_WHITE)
    systemSilent('ring "' + toNativePath(cSource) + '" -go -norun')

    # Find generated ringo
    cBase = getFileBaseName(cSource)
    cGeneratedRingo = cBase + ".ringo"
    cSrcDir = getFileDir(cSource)
    if not fexists(cGeneratedRingo) and fexists(cSrcDir + "/" + cGeneratedRingo)
        cGeneratedRingo = cSrcDir + "/" + cGeneratedRingo
    ok

    if fexists(cGeneratedRingo)
        copyFile(cGeneratedRingo, cDest + "/ringapp.ringo")
        if cGeneratedRingo != (cDest + "/ringapp.ringo")
            remove(cGeneratedRingo)
        ok
        ? "  " + uiStyle("[✔] Embedded bytecode: ", C_BGREEN) + uiStyle("android-qt/ringapp.ringo", C_BOLD + C_WHITE)
    else
        ? uiError("Failed to compile Ring bytecode: " + cGeneratedRingo)
        return false
    ok

    # 4. Copy project media and assets
    aMediaExts = [".jpg", ".jpeg", ".png", ".bmp", ".ico", ".gif", ".wav", ".mp3", ".ogg", ".ttf", ".otf"]
    aFoundMedia = []
    aFilesToCheck = dir(".")
    for aItem in aFilesToCheck
        cName = aItem[1]
        cLowerName = lower(cName)
        for cExt in aMediaExts
            if substr(cLowerName, cExt) > 0
                copyFile(cName, cDest + "/" + cName)
                aFoundMedia + cName
                exit
            ok
        next
    next

    if direxists("src")
        aSrcFiles = dir("src")
        for aItem in aSrcFiles
            cName = aItem[1]
            cLowerName = lower(cName)
            for cExt in aMediaExts
                if substr(cLowerName, cExt) > 0
                    copyFile("src/" + cName, cDest + "/" + cName)
                    if find(aFoundMedia, cName) = 0
                        aFoundMedia + cName
                    ok
                    exit
                ok
            next
        next
    ok

    # 5. Generate project.qrc
    cQrc = '<RCC>' + nl +
           '    <qresource prefix="/">' + nl +
           '        <file>ringapp.ringo</file>' + nl
    for cMedia in aFoundMedia
        cQrc = cQrc + '        <file>' + cMedia + '</file>' + nl
    next
    cQrc = cQrc + '    </qresource>' + nl + '</RCC>' + nl
    write(cDest + "/project.qrc", cQrc)
    ? "  " + uiStyle("[✔] Generated resource manifest: ", C_BGREEN) + uiStyle("android-qt/project.qrc", C_BOLD + C_WHITE)

    uiDivider()
    uiBanner("Qt Mobile Project Ready!", "Open in Qt Creator to Build & Run on Android")
    ? ""
    ? "  " + uiStyle("Project Location: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cDest), C_BOLD + C_BGREEN)
    ? "  " + uiStyle("Qt Project File:  ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cDest + "/project.pro"), C_BOLD + C_BYELLOW)
    ? ""
    ? "  " + uiStyle("How to Build & Run on Android:", C_BOLD + C_WHITE)
    ? "    1. Open " + uiStyle(toNativePath(cDest + "/project.pro"), C_BOLD + C_BCYAN) + " in " + uiStyle("Qt Creator", C_BOLD + C_WHITE)
    ? "    2. Select an " + uiStyle("Android Kit", C_BOLD + C_BYELLOW) + " (e.g. Qt 5.15.2 for Android Clang arm64-v8a)"
    ? "    3. Click " + uiStyle("Run (Ctrl+R)", C_BOLD + C_BGREEN) + " to compile and launch your full Qt GUI on device!"
    uiDivider()
    return true
