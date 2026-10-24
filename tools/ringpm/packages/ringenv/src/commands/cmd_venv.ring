# ringenv - Command: venv
# Creates project-level isolated virtual environment


# Helper to get base folder name for prompt display
func getBaseName cPath
    cNorm = normalizePath(cPath)
    aParts = split(cNorm, "/")
    for i = len(aParts) to 1 step -1
        if aParts[i] != "" and aParts[i] != "."
            return aParts[i]
        ok
    next
    return "rvenv"

# Copy runtime files from version to target environment
func copyRuntimeFiles cSrcDir, cTargetDir
    cBinFile = getBinaryName()

    # Automatically normalize if needed
    normalizeVersionFolder(cSrcDir)

    # Locate the actual runtime directory (direct or nested)
    cRuntimeDir = findVersionRuntimeDir(cSrcDir)

    # Determine source binary directory
    cSrcBin = cRuntimeDir + "/bin"
    if not direxists(cSrcBin)
        cSrcBin = cRuntimeDir
    ok

    # Target directories
    cDestBin = cTargetDir + "/bin"
    cDestScripts = cTargetDir + "/Scripts"

    # Copy binary and associated runtime libraries
    aItems = dir(cSrcBin)
    for aItem in aItems
        cName = aItem[1]
        nType = aItem[2]
        if cName = "." or cName = ".."
            loop
        ok

        if nType = 0
            cLower = lower(cName)
            # Copy executable and dynamic libraries
            if cLower = cBinFile or substr(cLower, ".dll") > 0 or substr(cLower, ".so") > 0 or substr(cLower, ".dylib") > 0 or substr(cLower, ".exe") > 0
                copyFile(cSrcBin + "/" + cName, cDestBin + "/" + cName)
                if iswindows()
                    copyFile(cSrcBin + "/" + cName, cDestScripts + "/" + cName)
                ok
            ok
        ok
    next

    # Copy loader scripts (bridges load "lib.ring" to libraries and extensions)
    if direxists(cSrcBin + "/load")
        copyFolder(cSrcBin + "/load", cDestBin + "/load")
        if iswindows()
            copyFolder(cSrcBin + "/load", cDestScripts + "/load")
        ok
    ok

    # Ensure executable permissions on Unix
    if not iswindows()
        if fexists(cDestBin + "/" + cBinFile)
            system('chmod +x "' + cDestBin + '/' + cBinFile + '" 2>/dev/null')
        ok
    ok

    # Copy standard library files if available
    if direxists(cRuntimeDir + "/lib")
        copyFolder(cRuntimeDir + "/lib", cTargetDir + "/lib")
    ok

    # Copy include directory if available
    if direxists(cRuntimeDir + "/include")
        copyFolder(cRuntimeDir + "/include", cTargetDir + "/include")
    ok

    # Copy tools directory (includes ringpm and ring2exe)
    if direxists(cRuntimeDir + "/tools")
        copyFolder(cRuntimeDir + "/tools", cTargetDir + "/tools")
    ok

    # Copy libraries directory if available
    if direxists(cRuntimeDir + "/libraries")
        copyFolder(cRuntimeDir + "/libraries", cTargetDir + "/libraries")
    ok

    # Copy extensions directory if available
    if direxists(cRuntimeDir + "/extensions")
        copyFolder(cRuntimeDir + "/extensions", cTargetDir + "/extensions")
    ok

    # Ensure required environment directories exist
    ensureDir(cTargetDir + "/tools/ringpm/registry")
    ensureDir(cTargetDir + "/extensions")
    ensureDir(cTargetDir + "/libraries")

    # Sync latest registry cache to virtual environment's ringpm
    cCachedReg = getCacheDir() + "/registry.ring"
    if fexists(cCachedReg)
        copyFile(cCachedReg, cTargetDir + "/tools/ringpm/registry/registry.ring")
    ok

    return true

# Generate shell activation scripts
func generateActivationScripts cTargetDir, cEnvName
    cNorm = normalizePath(cTargetDir)
    cBinDir = cNorm + "/bin"
    cScriptsDir = cNorm + "/Scripts"

    ensureDir(cBinDir)
    ensureDir(cScriptsDir)

    # 1. Unix Bash/Zsh activation script (bin/activate)
    cUnixScript = '#!/usr/bin/env bash' + nl +
        '# Activation script for ringenv virtual environment' + nl + nl +
        'deactivate () {' + nl +
        '    if [ -n "${_OLD_RINGENV_PATH:-}" ] ; then' + nl +
        '        PATH="${_OLD_RINGENV_PATH:-}"' + nl +
        '        export PATH' + nl +
        '        unset _OLD_RINGENV_PATH' + nl +
        '    fi' + nl +
        '    if [ -n "${_OLD_RINGPATH:-}" ] ; then' + nl +
        '        RINGPATH="${_OLD_RINGPATH:-}"' + nl +
        '        export RINGPATH' + nl +
        '        unset _OLD_RINGPATH' + nl +
        '    else' + nl +
        '        unset RINGPATH' + nl +
        '    fi' + nl +
        '    if [ -n "${_OLD_RINGENV_PROMPT:-}" ] ; then' + nl +
        '        PS1="${_OLD_RINGENV_PROMPT:-}"' + nl +
        '        export PS1' + nl +
        '        unset _OLD_RINGENV_PROMPT' + nl +
        '    fi' + nl +
        '    unset RVENV_DIR' + nl +
        '    if [ ! "${1:-}" = "nondestructive" ] ; then' + nl +
        '        unset -f deactivate' + nl +
        '    fi' + nl +
        '}' + nl + nl +
        'deactivate nondestructive' + nl + nl +
        'RVENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' + nl +
        'export RVENV_DIR' + nl + nl +
        '_OLD_RINGENV_PATH="$PATH"' + nl +
        'PATH="$RVENV_DIR/bin:$PATH"' + nl +
        'export PATH' + nl + nl +
        '_OLD_RINGPATH="${RINGPATH:-}"' + nl +
        'RINGPATH="$RVENV_DIR"' + nl +
        'export RINGPATH' + nl + nl +
        '_OLD_RINGENV_PROMPT="${PS1:-}"' + nl +
        'PS1="(' + cEnvName + ') ${PS1:-}"' + nl +
        'export PS1' + nl

    write(cBinDir + "/activate", cUnixScript)
    if not iswindows()
        system('chmod +x "' + cBinDir + '/activate" 2>/dev/null')
    ok

    # 2. Windows Command Prompt (Scripts/activate.bat)
    cBatScript = '@echo off' + nl +
        'rem ringenv virtual environment activation script for Windows Command Prompt' + nl + nl +
        'for %%I in ("%~dp0..") do set "RVENV_DIR=%%~fI"' + nl + nl +
        'if defined _OLD_RINGENV_PATH (' + nl +
        '    set "PATH=%_OLD_RINGENV_PATH%"' + nl +
        ') else (' + nl +
        '    set "_OLD_RINGENV_PATH=%PATH%"' + nl +
        ')' + nl + nl +
        'set "PATH=%RVENV_DIR%\bin;%RVENV_DIR%\Scripts;%PATH%"' + nl + nl +
        'if defined RINGPATH (' + nl +
        '    set "_OLD_RINGPATH=%RINGPATH%"' + nl +
        ')' + nl +
        'set "RINGPATH=%RVENV_DIR%"' + nl + nl +
        'if defined PROMPT (' + nl +
        '    set "_OLD_RINGENV_PROMPT=%PROMPT%"' + nl +
        ')' + nl +
        'set "PROMPT=(' + cEnvName + ') %PROMPT%"' + nl + nl +
        'echo Virtual environment (' + cEnvName + ') activated.' + nl

    write(cScriptsDir + "/activate.bat", cBatScript)
    write(cBinDir + "/activate.bat", cBatScript)

    # Deactivate script for CMD
    cBatDeact = '@echo off' + nl +
        'rem ringenv virtual environment deactivation script' + nl + nl +
        'if defined _OLD_RINGENV_PATH (' + nl +
        '    set "PATH=%_OLD_RINGENV_PATH%"' + nl +
        '    set "_OLD_RINGENV_PATH="' + nl +
        ')' + nl +
        'if defined _OLD_RINGPATH (' + nl +
        '    set "RINGPATH=%_OLD_RINGPATH%"' + nl +
        '    set "_OLD_RINGPATH="' + nl +
        ') else (' + nl +
        '    set "RINGPATH="' + nl +
        ')' + nl +
        'if defined _OLD_RINGENV_PROMPT (' + nl +
        '    set "PROMPT=%_OLD_RINGENV_PROMPT%"' + nl +
        '    set "_OLD_RINGENV_PROMPT="' + nl +
        ')' + nl +
        'set "RVENV_DIR="' + nl +
        'echo Virtual environment deactivated.' + nl

    write(cScriptsDir + "/deactivate.bat", cBatDeact)
    write(cBinDir + "/deactivate.bat", cBatDeact)

    # 3. Windows PowerShell (Scripts/activate.ps1)
    cPs1Script = '<#' + nl +
        '.Synopsis' + nl +
        'ringenv virtual environment activation script for PowerShell' + nl +
        '#>' + nl + nl +
        'function global:deactivate ([switch]$NonDestructive) {' + nl +
        '    if (Test-Path variable:_OLD_RINGENV_PATH) {' + nl +
        '        $env:PATH = $global:_OLD_RINGENV_PATH' + nl +
        '        Remove-Variable "_OLD_RINGENV_PATH" -Scope global' + nl +
        '    }' + nl +
        '    if (Test-Path variable:_OLD_RINGPATH) {' + nl +
        '        $env:RINGPATH = $global:_OLD_RINGPATH' + nl +
        '        Remove-Variable "_OLD_RINGPATH" -Scope global' + nl +
        '    } else {' + nl +
        '        Remove-Item env:RINGPATH -ErrorAction SilentlyContinue' + nl +
        '    }' + nl +
        '    if (Test-Path function:_old_ringenv_prompt) {' + nl +
        '        Set-Item function:prompt -Value $function:_old_ringenv_prompt -Force' + nl +
        '        Remove-Item function:_old_ringenv_prompt -Force' + nl +
        '    }' + nl +
        '    Remove-Item env:RVENV_DIR -ErrorAction SilentlyContinue' + nl +
        '    if (-not $NonDestructive) {' + nl +
        '        Remove-Item function:deactivate -Force' + nl +
        '    }' + nl +
        '}' + nl + nl +
        'deactivate -NonDestructive' + nl + nl +
        '$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path' + nl +
        '$env:RVENV_DIR = (Resolve-Path (Join-Path $scriptDir "..")).Path' + nl +
        '$global:_OLD_RINGENV_PATH = $env:PATH' + nl +
        '$env:PATH = "$env:RVENV_DIR\bin;$env:RVENV_DIR\Scripts;$env:PATH"' + nl +
        'if (Test-Path env:RINGPATH) {' + nl +
        '    $global:_OLD_RINGPATH = $env:RINGPATH' + nl +
        '}' + nl +
        '$env:RINGPATH = $env:RVENV_DIR' + nl + nl +
        'if (-not (Test-Path function:_old_ringenv_prompt)) {' + nl +
        '    $function:_old_ringenv_prompt = $function:prompt' + nl +
        '}' + nl +
        'function global:prompt {' + nl +
        '    "(' + cEnvName + ') " + (& $function:_old_ringenv_prompt)' + nl +
        '}' + nl + nl +
        'Write-Host "Virtual environment (' + cEnvName + ') activated."' + nl

    write(cScriptsDir + "/activate.ps1", cPs1Script)
    write(cBinDir + "/activate.ps1", cPs1Script)

    return true

# Execute venv command
func cmdVenv aArgs
    initRingenvDirs()

    cAction = ""
    cTargetFolder = ""
    cVersion = ""
    lClear = false

    nLen = len(aArgs)
    i = 1
    while i <= nLen
        cArg = aArgs[i]
        if cArg = "create"
            cAction = "create"
        but cArg = "--version" or cArg = "-v"
            if i < nLen
                i = i + 1
                cVersion = aArgs[i]
            ok
        but substr(cArg, "--version=") > 0
            cVersion = substr(cArg, 11, len(cArg))
        but cArg = "--clear"
            lClear = true
        but substr(cArg, 1, 1) != "-"
            if cAction = "create" and cTargetFolder = ""
                cTargetFolder = cArg
            ok
        ok
        i = i + 1
    end

    if cAction != "create"
        ? "Usage:"
        ? "  ringenv venv create <target_folder> --version <version>"
        ? ""
        ? "Example:"
        ? "  ringenv venv create .rvenv --version 1.27"
        return false
    ok

    if cTargetFolder = ""
        cTargetFolder = ".rvenv"
    ok

    # If version not specified, check installed versions
    if cVersion = ""
        cVersionsDir = getVersionsDir()
        aInstalled = []
        if direxists(cVersionsDir)
            aItems = dir(cVersionsDir)
            for aItem in aItems
                cName = aItem[1]
                nType = aItem[2]
                if cName != "." and cName != ".." and nType = 1
                    aInstalled + cName
                ok
            next
        ok

        if len(aInstalled) = 0
            ? "Error: No Ring version specified, and no versions are currently installed."
            ? "Please install a version first: ringenv install <version>"
            return false
        but len(aInstalled) = 1
            cVersion = aInstalled[1]
            ? "Using installed Ring version: " + cVersion
        else
            ? "Error: Multiple versions installed. Please specify one with --version <version>."
            ? "Installed versions:"
            for v in aInstalled
                ? "  - " + v
            next
            return false
        ok
    ok

    # Validate that version exists
    cVersionDir = getVersionsDir() + "/" + cVersion
    cBinFile = getBinaryName()

    if not direxists(cVersionDir)
        ? uiError("Error: Ring version " + cVersion + " is not installed.")
        ? "Run '" + uiStyle("ringenv install " + cVersion, C_BOLD + C_BCYAN) + "' to download and install it."
        return false
    ok

    cTarget = resolveCallerPath(cTargetFolder)
    cEnvName = getBaseName(cTarget)

    # Prevent modifying/clearing currently active virtual environment
    cActiveVenv = sysget("RVENV_DIR")
    if cActiveVenv != ""
        cNormActive = lower(normalizePath(cActiveVenv))
        cNormTarget = lower(normalizePath(cTarget))
        if cNormActive = cNormTarget
            ? uiError("The virtual environment '" + cEnvName + "' is currently active in this terminal!")
            ? "  " + uiStyle("Please run 'deactivate' before clearing or recreating this environment.", C_BOLD + C_YELLOW)
            return false
        ok
    ok

    # Clear existing environment if requested
    if lClear and direxists(cTarget)
        ? uiWarn("Clearing existing virtual environment at: " + toNativePath(cTarget))
        deleteFolder(cTarget)
    ok

    uiBanner("Creating Virtual Environment (" + cEnvName + ")", "Ring Version: " + cVersion + " | Target: " + toNativePath(cTarget))
    ? ""

    # Create directory structure:
    # bin/ (or Scripts/ on Windows), lib/, packages/
    ensureDir(cTarget)
    ensureDir(cTarget + "/bin")
    if iswindows()
        ensureDir(cTarget + "/Scripts")
    ok
    ensureDir(cTarget + "/lib")
    ensureDir(cTarget + "/packages")

    # Copy binary and runtime files
    ? "  " + uiStyle("Copying runtime files:     ", C_BOLD + C_WHITE) + uiBadge("in progress", C_BYELLOW)
    copyRuntimeFiles(cVersionDir, cTarget)

    # Generate activation scripts
    ? "  " + uiStyle("Generating shell scripts:  ", C_BOLD + C_WHITE) + uiBadge("ready", C_BGREEN)
    generateActivationScripts(cTarget, cEnvName)

    # Write environment configuration file
    cCfg = "# ringenv environment configuration" + nl +
        "version = " + cVersion + nl +
        "platform = " + getPlatformName() + nl +
        "source = " + cVersionDir + nl
    write(cTarget + "/ringenv.cfg", cCfg)

    ? ""
    uiDivider()
    ? "  " + uiSuccess("Virtual environment created successfully!")
    ? "  " + uiStyle("Location: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cTarget), C_DIM)
    ? ""
    ? "  " + uiStyle("To activate:", C_BOLD + C_WHITE)
    if iswindows()
        ? "    " + uiStyle("CMD:        ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cTarget) + "\Scripts\activate.bat", C_BOLD + C_BYELLOW)
        ? "    " + uiStyle("PowerShell: ", C_BOLD + C_WHITE) + uiStyle(toNativePath(cTarget) + "\Scripts\activate.ps1", C_BOLD + C_BYELLOW)
        ? "    " + uiStyle("Git Bash:   ", C_BOLD + C_WHITE) + uiStyle("source " + cTarget + "/bin/activate", C_BOLD + C_BYELLOW)
    else
        ? "    " + uiStyle("Bash/Zsh:   ", C_BOLD + C_WHITE) + uiStyle("source " + cTarget + "/bin/activate", C_BOLD + C_BYELLOW)
    ok
    uiDivider()
    ? "  " + uiStyle("To deactivate: ", C_BOLD + C_WHITE) + uiStyle("deactivate", C_BOLD + C_BRED)
    ? uiStyle("======================================================================", C_CYAN)
    return true
