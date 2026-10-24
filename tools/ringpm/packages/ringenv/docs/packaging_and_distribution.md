# Packaging and Distribution Guide

This guide explains how to structure an application built inside a `ringenv` virtual environment and how to compile and package it for desktop (Windows, Linux, macOS) using `ring2exe-plus` and mobile (Android) using `ring2apk`.

Both packaging tools are maintained by [@ysdragon](https://github.com/ysdragon) and are directly supported and categorized under `ringenv hub` in the `build` domain.

---

## 1. Project Directory Structure

Always keep your project source code outside the `.rvenv` directory. The virtual environment is an isolated runtime container that can be recreated at any time.

```text
MyProject/
├── .rvenv/                     # Virtual environment (ignored by Git)
├── src/                        # Application source code
│   ├── main.ring               # Entry point
│   ├── app_logic.ring
│   └── database.ring
├── assets/                     # Images, fonts, configuration files
├── tests/                      # Automated unit tests
│   └── test_app.ring
├── ring2exe.conf               # Desktop packaging configuration (ring2exe-plus)
├── ring2apk.ring               # Android packaging configuration (ring2apk)
├── scripts/                    # Build and release automation scripts
│   ├── build_desktop.bat       # Desktop packaging script
│   └── build_apk.bat           # Android APK packaging script
├── .gitignore                  # Ignore .rvenv/ and temporary build outputs
├── package.ring                # Ring package definition (for ringpm)
└── README.md                   # Project documentation
```

### Recommended `.gitignore`:
```gitignore
.rvenv/
myenv/
build/
release/
target/
*.exe
*.ringo
*.rc
*.res
*.dll
*.so
*.dylib
*.apk
```

---

## 2. Managing Dependencies inside `ringenv`

Inside an activated virtual environment, install application dependencies and packaging toolchains:

```bash
# Install packaging toolchain
ringenv hub install -c build

# Or install individual packaging tools:
ringenv hub install ring2exe-plus
ringenv hub install ring2apk

# Install project runtime dependencies:
ringenv hub install webview
ringenv hub install ring-libsql
```

In your `src/main.ring`, import the libraries normally:

```ring
load "stdlibcore.ring"
load "webview.ring"
load "libsql.ring"

func main
    ? "Application running inside isolated environment!"
    # Your application logic here
```

Run and test your application in development:
```bash
ring src/main.ring
```

---

## 3. Desktop Executable Packaging (`ring2exe-plus`)

`ring2exe-plus` extends standard `ring2exe` with essential production features:
- Declarative build configuration via `ring2exe.conf`.
- Automatic dependency and runtime DLL discovery (`-auto-libs`).
- Console suppression for windowed applications (`-gui`).
- Windows executable icon embedding (`-icon=<file.ico>`).
- Release optimization flag (`-release` maps to `-O3`).

### 3.1. Declarative Configuration: `ring2exe.conf`

Place `ring2exe.conf` in your project root:

```ini
# ==============================================================================
# Ring2EXE Plus Build Configuration
# ==============================================================================

# Entry point Ring script
source = src/main.ring

# Output executable name (without .exe extension)
output = MyApp

# GUI mode: hides the black console terminal on Windows
gui = true

# Automatically detect and bundle required Ring libraries (webview, libsql, etc.)
auto-libs = true

# Embed application icon directly into the executable binary
icon = assets/logo.ico

# Build optimized release binary (-O3)
release = true

# Keep intermediate build artifacts (false cleans temporary C/resource files)
keep = false
```

### 3.2. Building Desktop Executables

You can build the desktop package directly using `ringenv`, which manages the compilation, staging, and runtime bundling automatically:

```bash
# Automated cross-platform build via ringenv (Recommended):
ringenv build desktop

# Or generate standalone scripts and ring2exe.conf:
ringenv scaffold desktop

# Or manual compilation with ring2exe-plus:
ring2exe src/main.ring -gui -auto-libs -icon=assets/logo.ico -output=MyApp -release
```

### 3.3. Automated Desktop Build Script (`scripts/build_desktop.bat`)

Here is the production build script pattern used in standalone projects:

```bat
@echo off
@chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================================================
echo        MYAPP - DESKTOP BUILDER (Powered by ring2exe-plus)
echo ========================================================================

set PROJECT_ROOT=%~dp0..
cd /d "%PROJECT_ROOT%"

set DIST_DIR=%PROJECT_ROOT%\release\MyApp-Windows-x64
if not exist "%PROJECT_ROOT%\release" mkdir "%PROJECT_ROOT%\release"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo [1/3] Locating Ring runtime and compiling executable...
set RING2EXE_CMD=ring2exe
where ring2exe >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    set RING2EXE_CMD=ring ring2exe.ring
)

call %RING2EXE_CMD% src\main.ring -gui -auto-libs -icon=assets\logo.ico -output=MyApp -release

if exist "MyApp.exe" move /y "MyApp.exe" "%DIST_DIR%\" >nul
if exist "ring.ringo" move /y "ring.ringo" "%DIST_DIR%\" >nul
if exist "main.ringo" move /y "main.ringo" "%DIST_DIR%\" >nul
if exist "main.rc" del /f /q "main.rc" >nul 2>nul
if exist "main.res" del /f /q "main.res" >nul 2>nul

echo [2/3] Bundling Ring runtime libraries and assets...
for /f "delims=" %%i in ('where ring.exe 2^>nul') do set RING_BIN=%%~dpi
if defined RING_BIN (
    copy /y "%RING_BIN%ring.dll" "%DIST_DIR%\" >nul 2>nul
    copy /y "%RING_BIN%*webview*.dll" "%DIST_DIR%\" >nul 2>nul
    copy /y "%RING_BIN%*libsql*.dll" "%DIST_DIR%\" >nul 2>nul
    copy /y "%RING_BIN%*sqlite*.dll" "%DIST_DIR%\" >nul 2>nul
    copy /y "%RING_BIN%*ssl*.dll" "%DIST_DIR%\" >nul 2>nul
    copy /y "%RING_BIN%*crypto*.dll" "%DIST_DIR%\" >nul 2>nul
)

xcopy /y /e /i /q "%PROJECT_ROOT%\assets" "%DIST_DIR%\assets" >nul 2>nul

echo [3/3] Creating Launcher...
(
echo @echo off
echo cd /d "%%~dp0"
echo start "" "MyApp.exe"
) > "%DIST_DIR%\Launch_MyApp.bat"

echo ========================================================================
echo [SUCCESS] Standalone desktop application packaged into:
echo   %DIST_DIR%
echo ========================================================================
```

---

## 4. Mobile Android Packaging (`ring2apk`)

`ring2apk` compiles Ring source code into bytecode, bundles native C/C++ runtime engines and shared libraries (`.so`), packages web or native assets, and builds standalone Android APK files ready for deployment.

### 4.1. Android Packaging Directory Structure

For an Android build, prepare the following layout:

```text
MyProject/
├── ring2apk.ring               # Build configuration
├── ring/                       # Ring source files packaged into the APK
│   ├── main.ring               # Entry point executed by Android loader
│   └── app_logic.ring
├── assets/                     # Packaged runtime assets (HTML/CSS/JS frontend, images)
├── res/                        # Android resources (drawable icons, styles, strings)
├── src/                        # Native engine wrapper (C/C++ and Java)
└── build/                      # Generated APK and intermediate Gradle outputs
```

### 4.2. Declarative Configuration: `ring2apk.ring`

Place `ring2apk.ring` in your project root or `android/` directory:

```ring
/*
    Android Build Configuration for ring2apk
*/

Ring2ApkConfig = [
    # App identity
    :name        = "MyApp",
    :label       = "My Application",
    :packageId   = "com.mycompany.myapp",
    :versionCode = 1,
    :versionName = "1.0.0",

    # Android SDK versions
    :minSdk      = 21,
    :targetSdk   = 34,
    :compileSdk  = 34,

    # Target CPU architectures
    :targets     = ["arm64-v8a", "armeabi-v7a", "x86_64"],

    # Directories
    :srcDir      = "src",
    :resDir      = "res",
    :assetsDir   = "assets",
    :outputDir   = "build",

    # Entry point Ring code
    :ringSrcDir  = "ring",
    :entryPoint  = "main.ring",

    # Display configuration
    :theme       = "@style/AppTheme",
    :orientation = "unspecified",

    # Required Android permissions
    :permissions = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.ACCESS_WIFI_STATE",
        "android.permission.WAKE_LOCK",
        "android.permission.READ_EXTERNAL_STORAGE"
    ]
]
```

### 4.3. Building the APK

You can build the Android APK directly using `ringenv`:

```bash
# Automated APK build via ringenv (stages ring/ and assets/ automatically):
ringenv build apk

# Generate standalone Android scripts and ring2apk.ring:
ringenv scaffold apk

# Launch interactive Android SDK/NDK/JDK toolchain setup:
ringenv build setup-android
# or:
ringenv setup android

# Or manual compilation with ring2apk:
ring2apk build --rebuild
```

The compiled APK will be output to `build/outputs/apk/debug/` or `build/outputs/apk/release/`.

### 4.4. Automated Android Build Script (`scripts/build_apk.bat`)

Here is an automated batch build script that discovers the Android SDK/NDK, prepares staged directories, and triggers `ring2apk`:

```bat
@echo off
@chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================================================
echo        MYAPP - ANDROID APK BUILDER (Powered by ring2apk)
echo ========================================================================

:: Detect Android SDK and NDK
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v ANDROID_HOME 2^>nul') do set "ANDROID_HOME=%%b"
if not defined ANDROID_HOME (
    if exist "%USERPROFILE%\Android" set "ANDROID_HOME=%USERPROFILE%\Android"
)
if defined ANDROID_HOME (
    set "PATH=%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\cmdline-tools\latest\bin;!PATH!"
)

set PROJECT_ROOT=%~dp0..
cd /d "%PROJECT_ROOT%"

echo [1/3] Staging Ring code and assets...
if not exist "%PROJECT_ROOT%\ring" mkdir "%PROJECT_ROOT%\ring"
copy /y "%PROJECT_ROOT%\src\main.ring" "%PROJECT_ROOT%\ring\main.ring" >nul
if exist "%PROJECT_ROOT%\src\app_logic.ring" copy /y "%PROJECT_ROOT%\src\app_logic.ring" "%PROJECT_ROOT%\ring\" >nul

if not exist "%PROJECT_ROOT%\assets" mkdir "%PROJECT_ROOT%\assets"
if exist "%PROJECT_ROOT%\public\logo.png" copy /y "%PROJECT_ROOT%\public\logo.png" "%PROJECT_ROOT%\assets\icon.png" >nul

echo [2/3] Compiling Android APK with ring2apk...
where ring2apk >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    call ring2apk build --rebuild
) else (
    ring ring2apk.ring build --rebuild
)

echo [3/3] Build finished! Check build/ outputs.
```

---

### 4.5. Dynamic Android Engine & Native C-Extension Auto-Linking

Unlike desktop operating systems, Android does not support runtime dynamic library loading (`LoadLib("...dll")` or `LoadLib("...so")`). Every C/C++ extension must be compiled and linked directly into `libmain.so` at build time.

`ringenv build apk` features an automated pre-flight dependency analyzer:

```bash
ringenv build apk
```

When triggered, `ringenv`:
1. **Scans Project Code:** Parses all `load "..."` statements in project source files.
2. **Auto-Harvests C Extensions:** Automatically identifies supported C/C++ extensions (`sqlite`, `cjson`, `threads`, `openssl`, `raylib`, `curl`, `libuv`, etc.) and imports their native sources into `src/cpp/ext/<lib>` with zero manual steps.
3. **Generates NDK Build System:** Automatically provides `src/cpp/CMakeLists.txt`, `src/cpp/cmake/RingExtensions.cmake`, and `src/cpp/main.c` (with stdout/stderr redirected to Android logcat `adb logcat -s RingOutput:D`).
4. **Detects Desktop-Only Libraries:** Warns immediately if desktop-exclusive APIs (`libui`, `winapi`) are referenced.
5. **Advises on GUI Frameworks:** Informs the developer if Qt (`guilib`) is detected, offering one-click export to `ringenv scaffold qtmobile`.

---

## 5. RingQt Mobile Development (`ringenv scaffold qtmobile`)

For applications that rely on **Qt5 Widgets** (`guilib`, `lightguilib`, or `AnalogClock`), Ring provides official Qt Mobile support through Qt Creator and Qt for Android.

`ringenv` can generate and export a complete Qt Creator mobile project ready to build:

```bash
# Export Qt Mobile project into android-qt/
ringenv scaffold qtmobile
# or:
ringenv build qtmobile
```

### What this command does:
1. Compiles your Ring entry point (`src/main.ring` or `AnalogClock.ring`) into bytecode: `android-qt/ringapp.ringo`.
2. Extracts the official RingQt Android project template (`main.cpp`, `project.pro`, `ring/`, `ringqt/`).
3. Automatically collects all project media (images, icons, textures) and packages them into `android-qt/project.qrc`.
4. Outputs a ready-to-build Qt project at `android-qt/project.pro`.

### How to Build & Run:
1. Open `android-qt/project.pro` in **Qt Creator**.
2. Select your installed **Android Kit** (e.g. Qt 5.15.2 for Android Clang arm64-v8a).
3. Click **Run (Ctrl+R)** to compile the APK with full Qt GUI and launch it on your device or emulator!

---

## 6. Host Library Harvester (`ringenv harvest`)

Virtual environments and Android native builds often require built-in libraries, GUI frameworks, or C/C++ extensions from the host Ring installation (e.g. `C:\ring`). `ringenv harvest` imports them cleanly and prepares all necessary native bindings without manual file copying:

### Basic & Desktop Environment Usage

```shell
# Import Qt GUI runtime, RingQt DLLs, and platform plugins
ringenv harvest guilib

# Import game engine, multi-threading, or async runtimes
ringenv harvest raylib
ringenv harvest threads
ringenv harvest libuv

# Auto-scan project sources and harvest missing host dependencies automatically
ringenv harvest scan

# Import dependencies declared in a manifest file (e.g. env_packages.txt)
ringenv harvest -f env_packages.txt

# List available harvestable libraries
ringenv harvest list
```

---

### Android Native Extension Harvester (`--android`)

Android statically links Ring extensions directly into `libmain.so` (since dynamic `LoadLib` is not supported on Android NDK). `ringenv harvest <lib> --android` automates the entire native pipeline:

```shell
# Pure C extensions (Zero-configuration)
ringenv harvest sqlite --android
ringenv harvest cjson --android
ringenv harvest zip --android
ringenv harvest stbimage --android
ringenv harvest sockets --android

# Complex third-party native libraries & engines (Auto-deployed CMake Recipes)
ringenv harvest raylib --android
ringenv harvest curl --android
ringenv harvest webview --android
ringenv harvest httplib --android
ringenv harvest libuv --android
ringenv harvest openssl --android
ringenv harvest glaze --android
```

#### How the Android Pipeline Works:

1. **Scaffolding & CMake Generation**: Ensures `src/cpp/`, `src/cpp/ext/`, `src/cpp/recipes/`, Ring VM source files, `main.c`, and a dynamic `src/cpp/CMakeLists.txt` are created.
2. **Zero-Config Pure C Extensions**: In-tree extensions (`sqlite`, `cjson`, `zip`, `threads`, `stbimage`, `sockets`, `pdfgen`, etc.) are placed in `src/cpp/ext/<name>/` and automatically detected, compiled, and registered into `libmain.so` via `ring_target_add_extensions(main)`.
3. **Dynamic CMake Recipes (`src/cpp/recipes/*.cmake`)**:
   Complex libraries that require cloning third-party sources or special compiler flags are managed via self-contained CMake recipes:
   - **`raylib.cmake`**: Auto-clones and compiles Raylib 5.0 + RayGUI 4.0, applies NDK 27+ fixes (`ALooper_pollOnce`), and links `EGL`, `GLESv2`, and `OpenSLES`.
   - **`curl.cmake`**: Auto-clones and builds `libcurl` + `wolfSSL` for secure HTTPS requests.
   - **`webview.cmake`**: Auto-clones and builds `ring_webview_android`.
   - **`httplib.cmake`**: Configures `cpp-httplib` with C++17 support and zlib.
   - **`libuv.cmake`**: Auto-clones and builds the `libuv` async event loop.
   - **`openssl.cmake`**: Sets up wolfSSL in full OpenSSL compatibility mode.
   - **`glaze.cmake`**: Header-only C++23 JSON library configuration.
4. **Automatic `isAndroid()` LoadLib Patching**: Ring wrapper scripts (`.ring`) are automatically inspected and patched so that dynamic `LoadLib("...so")` calls are bypassed on Android while remaining fully functional on desktop platforms.
5. **Custom Recipes**: You can add support for any custom C/C++ library by simply creating a `src/cpp/recipes/mylib.cmake` file that appends to `RING_EXT_SOURCES`, `RING_EXT_INCLUDES`, or `RING_EXT_LIBS`.

---

## 7. Publishing as a Ring Package (`package.ring`)

To publish your library or application so other Ring developers can install it via `ringpm` or discover it in `ringenv hub`:

Create `package.ring` in your project root:

```ring
aPackageInfo = [
    :name = "myproject",
    :description = "Description of my project",
    :developer = "Your Name",
    :email = "your.email@example.com",
    :license = "MIT License",
    :version = "1.0.0",
    :ringversion = "1.27",
    :files = [
        "src/main.ring",
        "src/app_logic.ring",
        "ring2exe.conf",
        "ring2apk.ring",
        "README.md"
    ],
    :libs = [
        [
            :name = "webview",
            :version = "1.0",
            :providerusername = "ringpackages"
        ]
    ]
]
```

Push your project to GitHub. Users can then install it with:
```bash
ringpm install myproject from YourGitHubUsername
```
All dependencies specified in `:libs` will be resolved and installed automatically.
