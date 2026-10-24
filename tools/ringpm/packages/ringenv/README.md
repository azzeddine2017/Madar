# ringenv

> **ringenv** is an isolated virtual environment and version manager for the [Ring Programming Language](https://ring-lang.github.io).

Built natively in Ring, `ringenv` enables developers to download and manage multiple Ring language versions, create lightweight project-specific virtual environments with isolated binaries, runtime libraries, and shell activation scripts across Windows, Linux, and macOS.

---

## Features

- **Version Management**: Download and install specific Ring versions directly from official GitHub releases.
- **Virtual Environments**: Create project-isolated virtual environments (`.rvenv`) with their own `bin/` or `Scripts/` folders, `lib/`, and `packages/`.
- **Cross-Platform Activation**:
  - Windows Command Prompt (`activate.bat` / `deactivate.bat`)
  - Windows PowerShell (`activate.ps1` with prompt customization)
  - Linux & macOS Bash/Zsh (`bin/activate` with `deactivate` function)
- **Native Ecosystem Integration**: Built with native Ring standard libraries (`libcurl.ring` and `stdlibcore.ring`) with zero external C dependencies.
- **Download Progress Meter**: Real-time download progress displaying downloaded megabytes, total size, and completion percentage.
- **Relocatable Environments**: Shell activation scripts compute the environment path dynamically, allowing environments to remain functional across workspace moves.

---

## Target Architecture

```
~/.ringenv/                     # Global storage directory
├── versions/                   # Installed Ring runtimes (~/.ringenv/versions/<version>/)
│   ├── 1.26/
│   └── 1.27/
└── cache/                      # Download cache for release archives

<project_dir>/.rvenv/           # Project-level isolated virtual environment
├── bin/                        # Binary directory (ring binary and Unix activation)
│   ├── ring
│   ├── activate
│   ├── activate.bat
│   └── activate.ps1
├── Scripts/                    # Windows-compatible Scripts directory
│   ├── ring.exe
│   ├── activate.bat
│   ├── deactivate.bat
│   └── activate.ps1
├── lib/                        # Runtime and standard libraries
├── packages/                   # Isolated packages directory
└── ringenv.cfg                 # Environment metadata configuration
```

---

## Directory Structure

```
ringenv/
├── main.ring                   # CLI router and argument parser
├── README.md                   # Project documentation
├── .gitignore                  # Git ignore rules
├── src/
│   ├── core/
│   │   ├── os_helper.ring      # OS detection, paths, directory creation, file operations
│   │   ├── ui_style.ring       # Rich ANSI terminal formatting, themes, badges, and colors
│   │   ├── downloader.ring     # LibCurl wrapper with progress callback and HTTP validation
│   │   ├── zipengine.ring      # ZipEngine class wrapper for archive handling
│   │   └── extractor.ring      # Archive unpacking and permission management
│   └── commands/
│       ├── cmd_install.ring    # Downloads and installs target Ring version
│       ├── cmd_list.ring       # Lists locally installed Ring versions
│       ├── cmd_list_remote.ring# Lists remote Ring versions available on GitHub
│       ├── cmd_hub.ring        # Community package discovery, live READMEs, and installation
│       └── cmd_venv.ring       # Creates project virtual environments
└── tests/
    └── test_ringenv.ring       # Automated test suite
```

---

## Requirements

- **Ring Programming Language** (v1.19+ recommended, including 1.26, 1.27, and LightRelease builds)
- Ring standard extensions:
  - `libcurl.ring`
  - `stdlibcore.ring`

---

## Installation

### Install via Ring Package Manager (`ringpm`)
```bash
ringpm install ringenv from Azzeddine2017
```

## Command Reference

### 1. Show Help & Version
```bash
ring main.ring help
ring main.ring version
```

### 2. Install a Ring Version
Downloads the matching release archive from GitHub releases, extracts it into `~/.ringenv/versions/<version>/`, and removes the temporary cache archive upon completion.

```bash
# Install Ring version 1.27 (light release by default on Windows)
ringenv install 1.27

# Reinstall even if already installed
ringenv install 1.27 --force

# Explicitly specify light release flag
ringenv install 1.27 --light
```

#### GitHub Releases Mapping:
- **Windows (64-bit Light)**: `Ring_<version>_LightRelease_Windows_Binary_64bit.zip`
- **Linux (Ubuntu/Debian)**: `Ring_<version>_Ubuntu.zip`
- **macOS (Apple Silicon)**: `Ring_<version>_macOS_Applesilicon.zip`
- **Fallback URL**: `https://github.com/ring-lang/ring/releases/download/v<version>/<asset_name>`

### 3. Remove a Ring Version
Uninstalls a previously downloaded Ring version from `~/.ringenv/versions/<version>/` and removes any associated cached files:

```bash
# Remove Ring version 1.27
ringenv remove 1.27

# Alternatively
ringenv uninstall 1.27
```

### 4. List Locally Installed Versions
Inspects `~/.ringenv/versions/` and displays all installed Ring runtimes:

```bash
ringenv list
```

Example output:
```
=================================================
Installed Ring Versions (~/.ringenv/versions):
=================================================
  * 1.27 [ready]
=================================================
Total: 1 version(s) installed.
```

### 5. List Available Remote Versions
Queries official GitHub releases to display available Ring versions for download:

```bash
ringenv list-remote
# Or alternatively:
ringenv list --remote
```

Example output:
```
=================================================
Available Ring Versions (GitHub Releases):
=================================================
  * 1.27  [installed]
  * 1.26  [installed]
    1.25
    1.24
    1.23
=================================================
To install a version, run:
  ringenv install <version>
=================================================
```

### 6. Create a Virtual Environment
Creates an isolated project virtual environment with runtime files, binary executables, and shell activation scripts.

```bash
# Create default .rvenv directory using specified version
ringenv venv create .rvenv --version 1.27

# Clear existing virtual environment and recreate fresh
ringenv venv create .rvenv --version 1.27 --clear

# Create virtual environment in custom folder
ringenv venv create myenv --version 1.27

# If only one version is installed, --version is automatically detected
ringenv venv create .rvenv
```

### 7. Community Libraries Hub (External Packages)
Discover and install external libraries developed by the Ring community (Excel, Word, PowerPoint, PDF, QR Code, Barcode, Web Frameworks, FFI, LibSQL, etc.):

```bash
# List community-developed external libraries (Default View - compact & clean)
ringenv hub
# Or:
ringenv libs

# List all 250+ packages in the registry (including core extensions, samples & games)
ringenv hub --all

# List official Ring packages and samples only (@ringpackages)
ringenv hub --official

# Search across all packages (community & official) by keyword:
ringenv hub search excel
ringenv hub search sql

# View library details and live overview extracted from the repository README.md:
# (Specify by package name or by table row number #)
ringenv hub info xlsxlib
ringenv hub info 1
ringenv hub info ring-libsql

# Install a community library into current environment via ringpm:
# (Specify by package name or by table row number #)
ringenv hub install xlsxlib
ringenv hub install 1

# Refresh and update the local package registry cache from GitHub:
ringenv hub refresh
# Or top-level shortcut:
ringenv refresh
```

#### Key Features of the Hub:
- **Smart Community Filtering:** Displays curated, community-developed libraries by default (ideal for finding productivity libraries without scrolling through 200+ demo games).
- **Fast Silent Caching:** Automatically caches registry data locally with zero delay and no progress bar clutter.
- **Numbered Library Table:** Every package is assigned an index number `#` so you can install or inspect packages without typing long names.
- **Repository README Extraction:** `ringenv hub info` automatically fetches and parses the live `README.md` directly from the library's GitHub repository, displaying a formatted summary of what the library does.
- **ANSI Terminal Styling:** Full ANSI color highlighting with automatic detection and `--no-color` / `NO_COLOR` support.

---

## Activating and Deactivating Environments

### Windows Command Prompt (`cmd.exe`)
```cmd
# Activate
.rvenv\Scripts\activate.bat

# Deactivate
deactivate
```

### Windows PowerShell
```powershell
# Activate
.rvenv\Scripts\activate.ps1

# Deactivate
deactivate
```

### Linux / macOS / Git Bash
```bash
# Activate
source .rvenv/bin/activate

# Deactivate
deactivate
```

When activated:
- The virtual environment's `bin/` (and `Scripts/` on Windows) is prepended to the system `PATH`.
- The `RINGPATH` environment variable is set to the virtual environment folder.
- The command prompt is prefixed with `(<env_name>)`.

---

### 8. Host Library Harvester (`harvest`)
Directly imports built-in libraries, GUI frameworks, runtime DLLs, and C/C++ extensions from the host Ring installation (e.g. `C:\ring`) into the active isolated virtual environment:

```bash
# Harvest GUI frameworks and runtime DLLs into virtual environment
ringenv harvest guilib
ringenv harvest raylib
ringenv harvest threads
ringenv harvest libuv

# Auto-scan project sources and harvest missing host dependencies automatically
ringenv harvest scan

# Harvest multiple packages from a manifest file (e.g. env_packages.txt)
ringenv harvest -f env_packages.txt

# Harvest C/C++ extension wrappers for Android NDK compilation (into src/cpp/ext/)
ringenv harvest sqlite --android
ringenv harvest cjson --android

# List all harvestable libraries from the host installation
ringenv harvest list
```

---

## Project Lifecycle & Packaging (`build` & `scaffold`)

`ringenv` manages the complete application lifecycle, from development to standalone packaging for desktop and mobile devices:

```bash
# Compile standalone desktop executable package (with zero-config DLL & Qt plugin bundling)
ringenv build desktop

# Build standalone Android APK package with Dynamic C-Extension Auto-Harvesting (into libmain.so)
ringenv build apk

# Export complete Qt Creator Mobile project for RingQt GUI applications (AnalogClock, etc.)
ringenv build qtmobile
# or:
ringenv scaffold qtmobile

# Configure and verify Android SDK, NDK, and JDK toolchains
ringenv build setup-android
# or:
ringenv setup android

# Generate starter configuration files and cross-platform build scripts (.bat & .sh)
ringenv scaffold all
ringenv scaffold desktop
ringenv scaffold apk
ringenv scaffold qtmobile
```

See the [Packaging and Distribution Guide](docs/packaging_and_distribution.md) for complete details.

---

## Documentation

Comprehensive guides and technical documentation are available in the [docs/](docs/README.md) directory:

- [Getting Started](docs/getting_started.md)
- [Version Management Guide](docs/version_management.md)
- [Virtual Environments Guide](docs/virtual_environments.md)
- [Community Libraries Hub](docs/community_hub.md)
- [Packaging and Distribution Guide](docs/packaging_and_distribution.md)

---

## Running Tests

Execute the automated test suite to verify platform detection, path resolution, directory creation, file copying, and activation script generation:

```bash
ring tests/test_ringenv.ring
```

---

## License

This project is licensed under the MIT License.
