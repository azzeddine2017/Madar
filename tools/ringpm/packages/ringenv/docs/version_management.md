# Version Management Guide

`ringenv` lets you download, manage, and switch between multiple official Ring language runtimes simultaneously.

---

## 1. Viewing Available Versions on GitHub

To see which Ring versions are available for download from the official GitHub releases repository:

```bash
ringenv list-remote
```

This queries the GitHub Releases API live and marks which versions are already installed locally:

```text
======================================================================
  Available Ring Versions
  Official binary releases hosted on GitHub
======================================================================

  * 1.27  [installed]
  * 1.26  [installed]
    1.25
    1.24
    1.23
    1.22
    ...
```

---

## 2. Installing a Ring Version

To download and install a specific version of Ring into `~/.ringenv/versions/<version>/`:

```bash
ringenv install 1.27
```

### Options:
- `--force`: Reinstall even if the version is already installed.
  ```bash
  ringenv install 1.27 --force
  ```
- `--light`: Download the lightweight distribution package.
  ```bash
  ringenv install 1.27 --light
  ```

### Release Binary Mapping:
`ringenv` automatically detects your operating system and CPU architecture to download the correct binary release:
- **Windows**: `Ring_<version>_LightRelease_Windows_Binary_64bit.zip`
- **Linux (x86_64)**: `Ring_<version>_Ubuntu.zip`
- **macOS (Apple Silicon)**: `Ring_<version>_macOS_Applesilicon.zip`

---

## 3. Listing Installed Versions

To view all versions currently downloaded and available in `~/.ringenv/versions/`:

```bash
ringenv list
```

Example output:
```text
======================================================================
  Installed Ring Versions
  C:\Users\<User>\.ringenv\versions
======================================================================

  * 1.27  [ready]
  * 1.26  [ready]

----------------------------------------------------------------------
  Total: 2 version(s) installed.
======================================================================
```

---

## 4. Removing an Installed Version

To delete a version from local storage and clean up associated caches:

```bash
ringenv remove 1.26
# Or:
ringenv uninstall 1.26
```
