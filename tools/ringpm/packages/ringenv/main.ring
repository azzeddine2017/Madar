# ringenv - Isolated Virtual Environment & Version Manager for Ring Programming Language
# Main CLI Router and Argument Parser

load "stdlibcore.ring"
load "libcurl.ring"

load "src/core/ui_style.ring"
load "src/core/os_helper.ring"
load "src/core/categories.ring"
load "src/core/zipengine.ring"
load "src/core/downloader.ring"
load "src/core/extractor.ring"
load "src/commands/cmd_install.ring"
load "src/commands/cmd_remove.ring"
load "src/commands/cmd_list.ring"
load "src/commands/cmd_list_remote.ring"
load "src/commands/cmd_hub.ring"
load "src/commands/cmd_venv.ring"
load "src/commands/cmd_build.ring"
load "src/commands/cmd_harvest.ring"

cVersion = "1.1.0"

func main
    # Switch working directory to caller's directory
    cCaller = getCallerDir()
    if cCaller != "" and direxists(cCaller)
        chdir(cCaller)
    ok

    aArgs = parseCliArgs()

    # Check for --no-color flag across arguments
    for cArg in aArgs
        if lower(cArg) = "--no-color"
            setColorEnabled(false)
        ok
    next

    if len(aArgs) = 0
        showHelp()
        return
    ok

    cCommand = lower(aArgs[1])

    switch cCommand
        on "help"
            showHelp()

        on "--help"
            showHelp()

        on "-h"
            showHelp()

        on "version"
            showVersion()

        on "--version"
            showVersion()

        on "-v"
            showVersion()

        on "list"
            if len(aArgs) >= 2 and (lower(aArgs[2]) = "--remote" or lower(aArgs[2]) = "-r")
                cmdListRemote()
            else
                cmdList()
            ok

        on "list-remote"
            cmdListRemote()

        on "available"
            cmdListRemote()

        on "install"
            if len(aArgs) < 2
                ? "Error: Missing version argument."
                ? "Usage:   ringenv install <version> [--light] [--force]"
                ? "Example: ringenv install 1.27"
                return
            ok

            cVersion = aArgs[2]
            lLight = false
            lForce = false
            for i = 3 to len(aArgs)
                cArg = lower(aArgs[i])
                if cArg = "--light"
                    lLight = true
                but cArg = "--force" or cArg = "-f"
                    lForce = true
                ok
            next

            cmdInstall(cVersion, lLight, lForce)

        on "remove"
            if len(aArgs) < 2
                ? "Error: Missing version argument."
                ? "Usage:   ringenv remove <version>"
                ? "Example: ringenv remove 1.27"
                return
            ok
            cmdRemove(aArgs[2])

        on "uninstall"
            if len(aArgs) < 2
                ? "Error: Missing version argument."
                ? "Usage:   ringenv remove <version>"
                ? "Example: ringenv remove 1.27"
                return
            ok
            cmdRemove(aArgs[2])

        on "hub"
            cmdHub(aArgs)

        on "libs"
            cmdHub(aArgs)

        on "community"
            cmdHub(aArgs)

        on "refresh"
            cmdHub(["hub", "refresh"])

        on "update"
            cmdHub(["hub", "refresh"])

        on "venv"
            aVenvArgs = []
            for i = 2 to len(aArgs)
                aVenvArgs + aArgs[i]
            next
            cmdVenv(aVenvArgs)

        on "build"
            cmdBuild(aArgs)

        on "scaffold"
            aScaffoldArgs = ["build", "scaffold"]
            for i = 2 to len(aArgs)
                aScaffoldArgs + aArgs[i]
            next
            cmdBuild(aScaffoldArgs)

        on "setup"
            if len(aArgs) >= 2 and (lower(aArgs[2]) = "android" or lower(aArgs[2]) = "apk")
                buildSetupAndroid()
            else
                ? uiError("Missing setup target.")
                ? "Usage: ringenv setup android"
            ok

        on "harvest"
            cmdHarvest(aArgs)

        on "vendor"
            cmdHarvest(aArgs)

        other
            ? uiError("Unknown command: " + cCommand)
            ? "Run " + uiStyle("ringenv help", C_BOLD + C_BYELLOW) + " to view available commands."
    off

# Extract user arguments from sysargv
func parseCliArgs
    aArgs = []
    nStart = 2
    nArgCount = len(sysargv)

    if nArgCount >= 2
        cArg1 = lower(sysargv[1])
        cArg2 = lower(sysargv[2])

        # If executed via "ring main.ring <command> ..."
        if (substr(cArg1, "ring") > 0 or substr(cArg1, "ring.exe") > 0) and substr(cArg2, ".ring") > 0
            nStart = 3
        but substr(cArg1, ".ring") > 0
            nStart = 2
        else
            # Executable standalone or direct invocation
            nStart = 2
        ok
    ok

    for i = nStart to nArgCount
        aArgs + sysargv[i]
    next

    return aArgs

func showVersion
    cVer = getRingenvVersion()
    uiBanner("ringenv v" + cVer, "Isolated Virtual Environment & Version Manager for Ring")
    ? ""
    ? "  " + uiStyle("Version:  ", C_BOLD + C_WHITE) + uiStyle(cVer, C_BOLD + C_BGREEN)
    ? "  " + uiStyle("Platform: ", C_BOLD + C_WHITE) + uiStyle(getPlatformName(), C_BOLD + C_BYELLOW)
    ? "  " + uiStyle("Storage:  ", C_BOLD + C_WHITE) + uiStyle(toNativePath(getRingenvDir()), C_DIM)
    ? "  " + uiStyle("Author:   ", C_BOLD + C_WHITE) + uiAuthor("Azzeddine2017")
    ? "  " + uiStyle("Source:   ", C_BOLD + C_WHITE) + uiStyle("https://github.com/Azzeddine2017/ringenv", C_UNDERLINE + C_BCYAN)
    ? uiStyle("======================================================================", C_CYAN)

func showHelp
    uiBanner("ringenv v" + getRingenvVersion(), "Isolated Virtual Environment & Version Manager for Ring")
    ? ""
    ? "  " + uiStyle("Usage:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("ringenv <command> [arguments] [options]", C_BOLD + C_BYELLOW)
    ? "    " + uiStyle("ring main.ring <command> [arguments] [options]", C_DIM)
    ? ""
    ? "  " + uiStyle("Core Commands:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("install <ver> [opts]", C_BOLD + C_BCYAN) + "     Download and install a Ring version"
    ? "    " + uiStyle("remove  <ver>", C_BOLD + C_BCYAN) + "            Uninstall and remove an installed version"
    ? "    " + uiStyle("list", C_BOLD + C_BCYAN) + "                    Display all locally installed Ring versions"
    ? "    " + uiStyle("list-remote", C_BOLD + C_BCYAN) + "             Display available Ring versions on GitHub"
    ? "    " + uiStyle("venv create <path>", C_BOLD + C_BCYAN) + "      Create an isolated virtual environment"
    ? ""
    ? "  " + uiStyle("Community Hub & External Libraries:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("hub / libs", C_BOLD + C_BMAGENTA) + "               Explore community libraries (default view)"
    ? "    " + uiStyle("hub refresh", C_BOLD + C_BMAGENTA) + "              Update and refresh package registry cache"
    ? "    " + uiStyle("hub categories", C_BOLD + C_BMAGENTA) + "           List all package categories and domains"
    ? "    " + uiStyle("hub --category <cat>", C_BOLD + C_BMAGENTA) + "     Filter packages by domain (e.g. data, web)"
    ? "    " + uiStyle("hub export <cat> [file]", C_BOLD + C_BMAGENTA) + "  Export category packages to bundle file"
    ? "    " + uiStyle("hub install -f <file>", C_BOLD + C_BMAGENTA) + "    Install all packages from a bundle file"
    ? "    " + uiStyle("hub --all", C_BOLD + C_BMAGENTA) + "                Show all 250+ packages (including games & samples)"
    ? "    " + uiStyle("hub --official", C_BOLD + C_BMAGENTA) + "           Show official Ring packages and samples only"
    ? "    " + uiStyle("hub search <query>", C_BOLD + C_BMAGENTA) + "       Search across all packages by keyword"
    ? "    " + uiStyle("hub info <# or name>", C_BOLD + C_BMAGENTA) + "     Show library details and repository README"
    ? "    " + uiStyle("hub install <# or name>", C_BOLD + C_BMAGENTA) + "  Install library by row number or name"
    ? ""
    ? "  " + uiStyle("Project Lifecycle & Packaging:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("build desktop / exe", C_BOLD + C_BGREEN) + "        Build desktop standalone executable (-gui, -auto-libs)"
    ? "    " + uiStyle("build apk / android", C_BOLD + C_BGREEN) + "        Build Android APK package with ring2apk"
    ? "    " + uiStyle("build setup-android", C_BOLD + C_BGREEN) + "        Configure Android SDK, NDK, and JDK toolchains"
    ? "    " + uiStyle("scaffold [desktop|apk]", C_BOLD + C_BGREEN) + "     Generate build configs & scripts (.bat & .sh)"
    ? ""
    ? "  " + uiStyle("Global Library Harvester (Full Install):", C_BOLD + C_WHITE)
    ? "    " + uiStyle("harvest <lib_name>", C_BOLD + C_BYELLOW) + "           Import full-install library/GUI into active venv"
    ? "    " + uiStyle("harvest -f <file>", C_BOLD + C_BYELLOW) + "            Import all libraries listed in a manifest file"
    ? "    " + uiStyle("harvest list", C_BOLD + C_BYELLOW) + "                 List all harvestable libraries from host Ring"
    ? ""
    ? "  " + uiStyle("General Commands:", C_BOLD + C_WHITE)
    ? "    " + uiStyle("version", C_BOLD + C_BCYAN) + "                 Display ringenv version and platform info"
    ? "    " + uiStyle("help", C_BOLD + C_BCYAN) + "                    Display this help manual"
    ? ""
    uiDivider()
    ? "  " + uiStyle("Practical Examples:", C_BOLD + C_WHITE)
    ? ""
    ? "  " + uiStyle("1. Manage Ring language versions:", C_BOLD + C_BYELLOW)
    ? "     ringenv install 1.27"
    ? "     ringenv install 1.27 --force          # Reinstall even if already installed"
    ? "     ringenv install 1.26 --light"
    ? "     ringenv remove 1.26"
    ? ""
    ? "  " + uiStyle("2. List versions:", C_BOLD + C_BYELLOW)
    ? "     ringenv list                          # Locally installed versions"
    ? "     ringenv list-remote                   # Remote releases on GitHub"
    ? ""
    ? "  " + uiStyle("3. Explore external community libraries:", C_BOLD + C_BYELLOW)
    ? "     ringenv hub                           # List community libraries only (fast & clean)"
    ? "     ringenv hub refresh                   # Refresh libraries list"
    ? "     ringenv hub categories                # List all technical domains"
    ? "     ringenv hub --category data           # List Data & Office libraries"
    ? "     ringenv hub export data               # Export data bundle to ringenv-data.txt"
    ? "     ringenv hub install -f my_stack.txt   # Install all packages from file"
    ? "     ringenv hub install -c data           # Install all data packages directly"
    ? "     ringenv hub --all                     # List all 250+ packages (games, demos, etc.)"
    ? "     ringenv hub --official                # List official packages & samples only"
    ? "     ringenv hub search excel              # Search for Excel libraries"
    ? "     ringenv hub info 1                    # View details & README by row number"
    ? "     ringenv hub info xlsxlib              # View details & README by package name"
    ? "     ringenv hub install 1                 # Install library by row number"
    ? "     ringenv hub install xlsxlib           # Install library by package name"
    ? ""
    ? "  " + uiStyle("4. Project virtual environments:", C_BOLD + C_BYELLOW)
    ? "     ringenv venv create .rvenv --version 1.27"
    ? "     ringenv venv create .rvenv --clear    # Clear and recreate fresh"
    ? "     ringenv venv create myproject_env -v 1.26"
    ? ""
    ? "  " + uiStyle("5. Activating virtual environment:", C_BOLD + C_BYELLOW)
    ? "     Windows CMD:         <path>\\Scripts\\activate.bat"
    ? "     Windows PowerShell:  <path>\\Scripts\\activate.ps1"
    ? "     Linux / macOS:       source <path>/bin/activate"
    ? ""
    ? "  " + uiStyle("6. Deactivating virtual environment:", C_BOLD + C_BYELLOW)
    ? "     deactivate"
    ? ""
    uiDivider()
    ? "  " + uiStyle("GitHub Repository: ", C_BOLD + C_WHITE) + uiStyle("https://github.com/Azzeddine2017/ringenv", C_UNDERLINE + C_BCYAN)
    ? uiStyle("======================================================================", C_CYAN)