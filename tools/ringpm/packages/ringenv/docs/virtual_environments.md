# Virtual Environments Guide

`ringenv` creates self-contained, project-level virtual environments for the Ring language. This guarantees that each project has its own isolated dependencies, version runtime, and tools without polluting the global Ring installation.

---

## 1. Creating a Virtual Environment

Navigate to your project folder and run:

```bash
# Create an environment named .rvenv using the latest installed Ring version
ringenv venv create .rvenv

# Specify a specific Ring version
ringenv venv create .rvenv --version 1.27

# Recreate a fresh environment from scratch (clears old files)
ringenv venv create .rvenv --version 1.27 --clear

# Create environment with custom name
ringenv venv create myenv --version 1.26
```

---

## 2. Environment Directory Layout

When an environment is created, `ringenv` constructs a standard runtime structure:

```text
myenv/
├── Scripts/               # Windows executables (ring.exe, ringpm.exe, ring2exe.exe) and activate.bat
├── bin/                   # Unix binaries (ring, ringpm, ring2exe) and activate script
├── lib/                   # Standard library Ring scripts
├── tools/
│   └── ringpm/            # Isolated package manager storage
│       ├── packages/      # Installed external libraries (xlsxlib, bolt, etc.)
│       └── registry/      # Synchronized package registry
├── ringenv.cfg            # Configuration metadata (version, platform, origin)
└── ...
```

---

## 3. Activating the Environment

### Windows Command Prompt (`cmd.exe`)
```cmd
.\myenv\Scripts\activate.bat
```
*(Your prompt will change to `(myenv) λ`)*

### Windows PowerShell
```powershell
.\myenv\Scripts\activate.ps1
```

### Linux / macOS / Git Bash
```bash
source myenv/bin/activate
```

---

## 4. What Happens During Activation?

When an environment is activated:
1. **`PATH` Prepending**: The environment's `Scripts/` (or `bin/`) folder is placed at the front of `PATH`. Any command such as `ring`, `ringpm`, or `ring2exe` executes the environment's isolated binary.
2. **`RINGPATH` Setting**: The `RINGPATH` environment variable is set to the environment's root directory. The Ring runtime searches this path first for loaded libraries.
3. **Prompt Customization**: The shell prompt indicates the active environment name (e.g. `(myenv)`).

---

## 5. Deactivating the Environment

To exit the virtual environment and restore your original shell session:

```bash
deactivate
```
This restores your previous `PATH`, `RINGPATH`, and prompt cleanly.
