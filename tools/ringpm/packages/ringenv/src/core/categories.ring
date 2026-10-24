# ringenv - Package Categories & Domain Mapping
# Categorizes Ring packages by technical domain for discovery and bundles

# Return metadata for all defined package categories
func getCategoriesInfo
    return [
        [
            :id = "data",
            :name = "Data & Documents",
            :desc = "Documents, Spreadsheets, Data Formats & Visuals",
            :aliases = ["data", "office", "docs", "format", "formats"],
            :packages = [
                "xlsxlib", "docxlib", "pptxlib", "pdflib", "svglib",
                "simplejson", "yaml", "toml", "markdown", "dbflib",
                "ringqr", "ringbc", "ringfm", "ascii2label", "dotenv", "csvlib"
            ]
        ],
        [
            :id = "web",
            :name = "Web & APIs",
            :desc = "Web Frameworks, APIs, Servers & Networking",
            :aliases = ["web", "net", "network", "api", "backend", "server"],
            :packages = [
                "bolt", "ringserv", "distromap", "ringscript",
                "ring-html", "ftp", "weblib", "socket", "httplib"
            ]
        ],
        [
            :id = "gui",
            :name = "GUI & Desktop",
            :desc = "Desktop GUIs, Forms, Mobile & UI Toolkits",
            :aliases = ["gui", "ui", "desktop", "mobile"],
            :packages = [
                "webview", "dialog", "ring-slint", "ringqt", "ringqml",
                "ringpmgui", "formdesigner", "im2ansi",
                "Adhkar_Ring_App", "praytimes"
            ]
        ],
        [
            :id = "database",
            :name = "Databases & Storage",
            :desc = "Databases, SQL Clients & File Storage",
            :aliases = ["database", "db", "sql", "storage"],
            :packages = [
                "ring-libsql", "dbflib", "ringsql", "sqlite",
                "mysql", "postgresql", "odbc"
            ]
        ],
        [
            :id = "gamedev",
            :name = "Game Dev & Media",
            :desc = "Game Engines, Audio, Multimedia & Games",
            :aliases = ["game", "games", "gamedev", "media", "audio"],
            :packages = [
                "RingVaders", "piano", "steamlib", "ringraylib",
                "gameengine", "allegro", "openal", "opengl"
            ]
        ],
        [
            :id = "ai-science",
            :name = "AI, Math & Science",
            :desc = "Machine Learning, Deep Learning, Quantum & Math",
            :aliases = ["ai", "ml", "math", "science", "quantum"],
            :packages = [
                "ringquantum", "ringml", "ringml-using-ringtensor",
                "ringtensor", "matrixlib", "bigint", "math"
            ]
        ],
        [
            :id = "security",
            :name = "Security & Crypto",
            :desc = "Cryptography, Hashing & Authentication",
            :aliases = ["security", "crypto", "auth", "hash"],
            :packages = [
                "ring-jwt", "argon2", "bcrypt", "ringopenssl", "crypto"
            ]
        ],
        [
            :id = "build",
            :name = "Build & Packaging",
            :desc = "Compilers, APK/EXE Builders, Bundlers & Dist Tools",
            :aliases = ["build", "packaging", "package", "dist", "apk", "exe"],
            :packages = [
                "ring2exe-plus", "ring2apk", "ring2exe"
            ]
        ],
        [
            :id = "system",
            :name = "System & Utilities",
            :desc = "System Utilities, Concurrency, FFI & Tooling",
            :aliases = ["system", "sys", "tools", "utils", "dev"],
            :packages = [
                "stzlib", "SysInfo", "ringregex", "RingThreadPro",
                "ringsubprocess", "proc", "archive", "ring-cffi",
                "ring-python", "uuid", "emoji",
                "ringenv", "typehints", "tokenslib", "zerolib",
                "Advanced-Trace", "Rosetta-Ring-Sample", "AlQalam"
            ]
        ]
    ]

# Resolve category alias to standard category ID
func resolveCategoryAlias cInput
    cLow = lower(trim(cInput))
    # Strip leading dashes if provided like --category or -c
    while len(cLow) > 0 and substr(cLow, 1, 1) = "-"
        cLow = substr(cLow, 2, len(cLow))
    end

    aCats = getCategoriesInfo()
    for aCat in aCats
        if lower(aCat[:id]) = cLow
            return aCat[:id]
        ok
        for cAlias in aCat[:aliases]
            if lower(cAlias) = cLow
                return aCat[:id]
            ok
        next
    next
    return ""

# Get single category info by ID or alias
func getCategoryById cCatId
    cCanonical = resolveCategoryAlias(cCatId)
    if cCanonical = ""
        cCanonical = lower(trim(cCatId))
    ok
    aCats = getCategoriesInfo()
    for aCat in aCats
        if lower(aCat[:id]) = cCanonical
            return aCat
        ok
    next
    return []

# Check if a package belongs to a category
func isPackageInCategory cPkgName, cCatId
    aCat = getCategoryById(cCatId)
    if len(aCat) = 0
        return false
    ok
    cTarget = lower(trim(cPkgName))
    for cPkg in aCat[:packages]
        if lower(cPkg) = cTarget
            return true
        ok
    next
    return false

# Find category of a package (returns category ID or 'other')
func getPackageCategory cPkgName
    cTarget = lower(trim(cPkgName))
    aCats = getCategoriesInfo()
    for aCat in aCats
        for cPkg in aCat[:packages]
            if lower(cPkg) = cTarget
                return aCat[:id]
            ok
        next
    next
    return "other"
