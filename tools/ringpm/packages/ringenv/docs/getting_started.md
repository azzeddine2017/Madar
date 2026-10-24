# Getting Started with ringenv

`ringenv` provides a self-contained, native virtual environment and multi-version runtime manager for the Ring programming language.

---

## 1. System Requirements

- **Ring Programming Language**: Version 1.19 or later (including 1.26, 1.27, and LightRelease builds).
- **Standard Extensions**:
  - `libcurl.ring`
  - `stdlibcore.ring`
- **Operating Systems**:
  - Windows 7, 8, 10, 11 (Command Prompt and PowerShell)
  - Linux (Ubuntu, Debian, Fedora, Arch, etc.)
  - macOS (Apple Silicon and Intel)

---

## 2. Installation

### Install via Ring Package Manager (`ringpm`)
```bash
ringpm install ringenv from Azzeddine2017
```
Once installed, the `ringenv` command is immediately available in your terminal.

---

## 3. Verifying Installation

Verify that the CLI is working and detects your platform correctly:

```bash
ringenv version
```

Example output:
```text
======================================================================
  ringenv v1.0.2
  Isolated Virtual Environment & Version Manager for Ring
======================================================================

  Version:  1.0.2
  Platform: windows
  Storage:  C:\Users\<User>\.ringenv
  Author:   @Azzeddine2017
  Source:   https://github.com/Azzeddine2017/ringenv
======================================================================
```

---

## 4. Storage Architecture

`ringenv` manages all its data under a dedicated user directory:

- **Windows**: `%USERPROFILE%\.ringenv\` (e.g. `C:\Users\<User>\.ringenv\`)
- **Linux / macOS**: `~/.ringenv/`

Inside `~/.ringenv/`:
- `versions/`: Holds downloaded and extracted Ring runtimes (e.g. `1.27`, `1.26`).
- `cache/`: Stores downloaded release archives and the cached package registry.
