# Community Libraries Hub

The Community Libraries Hub in `ringenv` provides discovery, inspection, and installation of external packages developed by the Ring community (Excel, Word, PowerPoint, PDF, QR Code, Barcode, FFI, LibSQL, Web Frameworks, etc.).

---

## 1. Exploring Libraries

### Default View: Community Libraries
By default, `ringenv hub` displays external packages authored by community members:

```bash
ringenv hub
# Or:
ringenv libs
```

This output is compact, clean, and displays essential tools without scrolling through 200+ demo games and samples.

### All Registry Packages
To inspect all 250+ packages present in the official Ring registry (including games and demos):

```bash
ringenv hub --all
```

### Official Packages Only
To list only standard core extensions, games, and samples authored by `@ringpackages`:

```bash
ringenv hub --official
```

---

## 2. Searching for Packages

Search across all registry packages by keyword:

```bash
ringenv hub search excel
ringenv hub search pdf
ringenv hub search sql
```

---

## 3. Viewing Library Details & Repository README

`ringenv hub info` connects directly to GitHub and extracts the live overview paragraph from the library's repository `README.md`.

You can query a library by its **name** or by its **table row number (#)**:

```bash
# By name
ringenv hub info xlsxlib
ringenv hub info ring-libsql

# By row number
ringenv hub info 1
```

Example output:
```text
======================================================================
  Library Details: xlsxlib
  Developed by @Azzeddine2017
======================================================================

  Name:        xlsxlib
  Author:      @Azzeddine2017
  Repository:  https://github.com/Azzeddine2017/xlsxlib
  Registry:    Modern XLSX (Excel) workbook creation and manipulation library

  Repository Overview (from README.md):
----------------------------------------------------------------------
    Modern XLSX (Excel) workbook creation and manipulation library for
    the Ring programming language with rich formatting and formulas.
----------------------------------------------------------------------

  Installation Command:
    ringpm install xlsxlib from Azzeddine2017
    ringenv hub install xlsxlib
======================================================================
```

---

## 4. Installing Libraries into Virtual Environments

When your virtual environment is active, run `ringenv hub install` to install packages directly into your isolated project environment:

```bash
# Install by name
ringenv hub install xlsxlib
ringenv hub install ringqr
ringenv hub install ringquantum

# Install by row number
ringenv hub install 1
```

This automatically routes the installation to the active environment's `ringpm`, ensuring that your global Ring installation remains completely untouched.

---

## 5. Categories & Domain Browsing

`ringenv` categorizes packages into specialized technical domains (Data & Documents, Web, GUI, Database, Game Dev, AI & Science, Security, Build & Packaging, System Utilities).

### Listing All Categories
```bash
ringenv hub categories
```

### Filtering Packages by Category
```bash
# Data & Documents (xlsxlib, docxlib, pdflib, simplejson, yaml, etc.)
ringenv hub --category data
# Or shorthand:
ringenv hub -c web
ringenv hub -c gui
ringenv hub -c database
ringenv hub -c gamedev
ringenv hub -c ai
ringenv hub -c build   # ring2exe-plus, ring2apk, ring2exe
```

---

## 6. Package Bundles & Batch Installation

### Exporting Category Packages to a Bundle File
Save all packages of a category to a requirements-style text file:

```bash
# Exports to default 'ringenv-data.txt'
ringenv hub export data

# Or export to custom filename
ringenv hub export data my_stack.txt
```

Example file output (`my_stack.txt`):
```text
# ringenv package bundle: Data & Documents (data)
# Description: Documents, Spreadsheets, Data Formats & Visuals
xlsxlib
docxlib
pptxlib
pdflib
svglib
simplejson
yaml
toml
markdown
dbflib
ringqr
ringbc
ringfm
ascii2label
dotenv
```

### Installing Packages from a File
Install all packages listed in a file directly into the active virtual environment:

```bash
ringenv hub install -f my_stack.txt
# Or:
ringenv hub install --file ringenv-data.txt
```

### Installing an Entire Category Directly
Install all packages of a domain in a single command:

```bash
ringenv hub install -c data
# Or:
ringenv hub install --category web
ringenv hub install --bundle gamedev
```
