# ringenv Documentation

Welcome to the official documentation for **ringenv**, the native isolated virtual environment and multi-version manager for the [Ring programming language](https://ring-lang.github.io/).

---

## Documentation Sections

1. [Getting Started](getting_started.md)
   - System requirements
   - Installing via `ringpm` or source installer (`setup.ring`)
   - Verifying your installation and platform detection

2. [Version Management](version_management.md)
   - Listing local versions (`ringenv list`)
   - Browsing remote GitHub releases (`ringenv list-remote`)
   - Installing versions (`ringenv install <ver> [--light] [--force]`)
   - Uninstalling versions (`ringenv remove <ver>`)

3. [Virtual Environments](virtual_environments.md)
   - Concept of project isolation in Ring
   - Creating environments (`ringenv venv create <path> [--version <ver>] [--clear]`)
   - Activating and deactivating in CMD, PowerShell, Bash, and Zsh
   - Environment structure and runtime isolation mechanics

4. [Community Libraries Hub](community_hub.md)
   - Bert's external packages exploration (`ringenv hub`)
   - Smart filtering: Community default, `--all`, and `--official`
   - Numeric index selection (`#`) vs package names
   - Real-time GitHub repository overview extraction (`ringenv hub info`)
   - Installing packages into active virtual environments (`ringenv hub install`)

5. [Packaging and Distribution](packaging_and_distribution.md)
   - Professional project layout and best practices
   - Host library harvester (`ringenv harvest`)
   - Desktop packaging with automatic Qt DLL bundling (`ringenv build desktop`)
   - Dynamic Android APK engine with native C-extension harvesting (`ringenv build apk`)
   - RingQt Mobile project scaffolding for Qt Creator (`ringenv scaffold qtmobile`)
   - Distributing as a Ring package (`package.ring`)

---

## Quick Command Cheat Sheet

| Command | Description |
| :--- | :--- |
| `ringenv list` | Display all locally installed Ring versions |
| `ringenv list-remote` | Browse available Ring versions on GitHub releases |
| `ringenv install <version>` | Download and install a specific Ring runtime |
| `ringenv remove <version>` | Uninstall and remove an installed Ring runtime |
| `ringenv venv create <dir>` | Create an isolated virtual environment in `<dir>` |
| `ringenv harvest <library>` | Harvest official host runtime libraries (`guilib`, `raylib`, etc.) |
| `ringenv harvest <lib> --android` | Harvest C/C++ extensions and deploy CMake recipes for Android NDK `libmain.so` |
| `ringenv harvest scan` | Scan current project for missing libraries and harvest them automatically |
| `ringenv build desktop` | Package standalone desktop release with all runtime DLLs and Qt plugins |
| `ringenv build apk` | Build Android APK package with dynamic native C extension auto-linking |
| `ringenv scaffold qtmobile` | Export turnkey RingQt Android/iOS project for Qt Creator |
| `ringenv hub` | Browse community-developed external libraries |
| `ringenv hub --all` | Show all 250+ packages in the Ring registry |
| `ringenv hub --official` | Show official core extensions, samples, and games |
| `ringenv hub search <query>` | Search across all registry packages by keyword |
| `ringenv hub info <# or name>` | View library details and live GitHub README overview |
| `ringenv hub install <# or name>` | Install a library into the current environment |
| `ringenv version` | Display ringenv version and platform information |
| `ringenv help` | Show the CLI command manual |
