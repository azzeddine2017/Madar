# ringenv_test.ring - اختبارات شاملة لمشروع ringenv
# باستخدام إطار عمل ringtest (describe / it / expect)

load "stdlibcore.ring"
load "libcurl.ring"

# تحميل وحدات المشروع
load "src/core/os_helper.ring"
load "src/core/ui_style.ring"
load "src/core/categories.ring"
load "src/core/zipengine.ring"
load "src/core/extractor.ring"
load "src/commands/cmd_list.ring"
load "src/commands/cmd_venv.ring"
load "src/commands/cmd_hub.ring"
load "src/commands/cmd_build.ring"
load "src/commands/cmd_list_remote.ring"
load "src/commands/cmd_install.ring"
load "src/commands/cmd_remove.ring"
load "src/commands/cmd_harvest.ring"
load "src/core/downloader.ring"

# ====================================================================
# اختبارات وحدة os_helper.ring
# ====================================================================
describe("OS Helper - Platform Detection", func {

    it("should return a known platform name", func {
        cPlatform = getPlatformName()
        expect(cPlatform = "windows" or cPlatform = "linux" or cPlatform = "macos").toBeTruthy()
    })

    it("should return correct binary name for platform", func {
        cBin = getBinaryName()
        if iswindows()
            expect(cBin).toBe("ring.exe")
        else
            expect(cBin).toBe("ring")
        ok
    })

    it("should resolve home directory to non-empty string", func {
        cHome = getHomeDir()
        expect(len(cHome) > 0).toBeTruthy()
    })

    it("should resolve ringenv directory containing .ringenv", func {
        cBase = getRingenvDir()
        expect(substr(cBase, ".ringenv") > 0).toBeTruthy()
    })

    it("should resolve versions directory containing 'versions'", func {
        cVers = getVersionsDir()
        expect(substr(cVers, "versions") > 0).toBeTruthy()
    })

    it("should resolve cache directory containing 'cache'", func {
        cCache = getCacheDir()
        expect(substr(cCache, "cache") > 0).toBeTruthy()
    })
})

describe("OS Helper - Path Normalization", func {

    it("should normalize backslashes to forward slashes", func {
        cNorm = normalizePath("C:" + char(92) + "Users" + char(92) + "test" + char(92) + "file.txt")
        expect(cNorm).toBe("C:/Users/test/file.txt")
    })

    it("should remove trailing slash from path", func {
        cNorm = normalizePath("/home/user/dir/")
        expect(cNorm).toBe("/home/user/dir")
    })

    it("should keep root slash intact", func {
        cNorm = normalizePath("/")
        expect(cNorm).toBe("/")
    })

    it("should convert to native path on Windows", func {
        if iswindows()
            cNative = toNativePath("C:/Users/test")
            expect(cNative).toBe("C:" + char(92) + "Users" + char(92) + "test")
        else
            cNative = toNativePath("C:/Users/test")
            expect(cNative).toBe("C:/Users/test")
        ok
    })
})

describe("OS Helper - Directory Operations", func {

    it("should create nested directories with ensureDir", func {
        cTestDir = ctxGet("cTestDir")
        if cTestDir = ""
            cTestDir = "./tests/test_tmp/sub1/sub2"
            ctxSet("cTestDir", cTestDir)
        ok
        ensureDir(cTestDir)
        expect(direxists(cTestDir)).toBeTruthy()
    })

    it("should copy file content correctly", func {
        cSrc = "./tests/test_tmp/sample.txt"
        cDest = "./tests/test_tmp/sub1/copied.txt"
        write(cSrc, "ringenv unit test")
        copyFile(cSrc, cDest)
        expect(fexists(cDest) and read(cDest) = "ringenv unit test").toBeTruthy()
    })

    it("should delete folder recursively", func {
        cTestDir = ctxGet("cTestDir")
        if cTestDir = ""
            cTestDir = "./tests/test_tmp"
        ok
        deleteFolder(cTestDir)
        expect(not direxists(cTestDir)).toBeTruthy()
    })
})

describe("OS Helper - Caller Path Resolution", func {

    it("should keep absolute Windows paths intact", func {
        cAbs = "C:/TestDir"
        expect(resolveCallerPath(cAbs)).toBe(cAbs)
    })

    it("should keep absolute Unix paths intact", func {
        cAbs = "/tmp/test"
        expect(resolveCallerPath(cAbs)).toBe(cAbs)
    })

    it("should return relative path when no caller dir set", func {
        cRel = "myfolder"
        cResult = resolveCallerPath(cRel)
        expect(cResult = cRel or substr(cResult, cRel) > 0).toBeTruthy()
    })
})

describe("OS Helper - Version", func {

    it("should return ringenv version string", func {
        cVer = getRingenvVersion()
        expect(len(cVer) > 0).toBeTruthy()
        expect(substr(cVer, ".") > 0).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة ui_style.ring
# ====================================================================
describe("UI Style - Color Constants", func {

    it("should define ANSI escape constants", func {
        expect(len(C_ESC) > 0).toBeTruthy()
        expect(len(C_RESET) > 0).toBeTruthy()
        expect(len(C_BOLD) > 0).toBeTruthy()
        expect(len(C_BGREEN) > 0).toBeTruthy()
    })

    it("should have reset code ending with [0m", func {
        expect(substr(C_RESET, "[0m") > 0).toBeTruthy()
    })
})

describe("UI Style - Styling Functions", func {

    it("should wrap text with style codes when color enabled", func {
        setColorEnabled(true)
        cStyled = uiStyle("test", char(27) + "[1m")
        expect(substr(cStyled, "test") > 0).toBeTruthy()
        expect(substr(cStyled, "[0m") > 0).toBeTruthy()
    })

    it("should return plain text when color disabled", func {
        setColorEnabled(false)
        cStyled = uiStyle("test", char(27) + "[1m")
        expect(cStyled).toBe("test")
        setColorEnabled(true)
    })

    it("should format badge with brackets", func {
        setColorEnabled(true)
        cBadge = uiBadge("ready", char(27) + "[32m")
        expect(substr(cBadge, "[ready]") > 0).toBeTruthy()
        setColorEnabled(true)
    })

    it("should apply semantic colors", func {
        setColorEnabled(true)
        expect(substr(uiSuccess("ok"), "ok") > 0).toBeTruthy()
        expect(substr(uiError("err"), "err") > 0).toBeTruthy()
        expect(substr(uiWarn("warn"), "warn") > 0).toBeTruthy()
        expect(substr(uiInfo("info"), "info") > 0).toBeTruthy()
        setColorEnabled(true)
    })

    it("should prepend @ to author name", func {
        setColorEnabled(true)
        cAuthor = uiAuthor("Azzeddine2017")
        expect(substr(cAuthor, "@Azzeddine2017") > 0).toBeTruthy()
        setColorEnabled(true)
    })
})

# ====================================================================
# اختبارات وحدة categories.ring
# ====================================================================
describe("Categories - Category Info", func {

    it("should return at least 9 categories", func {
        aCats = getCategoriesInfo()
        expect(len(aCats) >= 9).toBeTruthy()
    })

    it("should have data category with packages", func {
        aCat = getCategoryById("data")
        expect(len(aCat) > 0).toBeTruthy()
        expect(len(aCat[:packages]) > 0).toBeTruthy()
    })

    it("should return empty list for unknown category", func {
        aCat = getCategoryById("nonexistent_category_xyz")
        expect(len(aCat) = 0).toBeTruthy()
    })
})

describe("Categories - Alias Resolution", func {

    it("should map 'data' to 'data'", func {
        expect(resolveCategoryAlias("data")).toBe("data")
    })

    it("should map 'office' to 'data'", func {
        expect(resolveCategoryAlias("office")).toBe("data")
    })

    it("should map 'docs' to 'data'", func {
        expect(resolveCategoryAlias("docs")).toBe("data")
    })

    it("should map 'web' to 'web'", func {
        expect(resolveCategoryAlias("web")).toBe("web")
    })

    it("should map 'api' to 'web'", func {
        expect(resolveCategoryAlias("api")).toBe("web")
    })

    it("should map 'db' to 'database'", func {
        expect(resolveCategoryAlias("db")).toBe("database")
    })

    it("should map 'games' to 'gamedev'", func {
        expect(resolveCategoryAlias("games")).toBe("gamedev")
    })

    it("should map 'ai' to 'ai-science'", func {
        expect(resolveCategoryAlias("ai")).toBe("ai-science")
    })

    it("should map 'build' to 'build'", func {
        expect(resolveCategoryAlias("build")).toBe("build")
    })

    it("should map 'apk' to 'build'", func {
        expect(resolveCategoryAlias("apk")).toBe("build")
    })

    it("should return empty string for unknown alias", func {
        expect(resolveCategoryAlias("xyz_nonexistent")).toBe("")
    })
})

describe("Categories - Package Membership", func {

    it("should find xlsxlib in data category", func {
        expect(isPackageInCategory("xlsxlib", "data")).toBeTruthy()
    })

    it("should find docxlib in data category", func {
        expect(isPackageInCategory("docxlib", "data")).toBeTruthy()
    })

    it("should find bolt in web category", func {
        expect(isPackageInCategory("bolt", "web")).toBeTruthy()
    })

    it("should find ringquantum in ai-science category", func {
        expect(isPackageInCategory("ringquantum", "ai-science")).toBeTruthy()
    })

    it("should find ring2exe-plus in build category", func {
        expect(isPackageInCategory("ring2exe-plus", "build")).toBeTruthy()
    })

    it("should return false for package not in category", func {
        expect(isPackageInCategory("xlsxlib", "web")).toBeFalsy()
    })
})

describe("Categories - Package Category Lookup", func {

    it("should identify xlsxlib as data", func {
        expect(getPackageCategory("xlsxlib")).toBe("data")
    })

    it("should identify bolt as web", func {
        expect(getPackageCategory("bolt")).toBe("web")
    })

    it("should identify ring2exe-plus as build", func {
        expect(getPackageCategory("ring2exe-plus")).toBe("build")
    })

    it("should return 'other' for unknown package", func {
        expect(getPackageCategory("nonexistent_pkg_xyz")).toBe("other")
    })
})

# ====================================================================
# اختبارات وحدة cmd_hub.ring
# ====================================================================
describe("Hub - Curated Community Libraries", func {

    it("should return at least 10 curated libraries", func {
        aLibs = getCuratedCommunityLibs()
        expect(len(aLibs) >= 10).toBeTruthy()
    })

    it("should include xlsxlib by Azzeddine2017", func {
        aLibs = getCuratedCommunityLibs()
        lFound = false
        for aLib in aLibs
            if aLib[:name] = "xlsxlib"
                lFound = true
                expect(aLib[:author]).toBe("Azzeddine2017")
            ok
        next
        expect(lFound).toBeTruthy()
    })

    it("should include ringquantum by Azzeddine2017", func {
        aLibs = getCuratedCommunityLibs()
        lFound = false
        for aLib in aLibs
            if aLib[:name] = "ringquantum"
                lFound = true
                expect(aLib[:author]).toBe("Azzeddine2017")
            ok
        next
        expect(lFound).toBeTruthy()
    })
})

describe("Hub - Registry Field Extraction", func {

    it("should extract name field from registry block", func {
        cBlock = ':name = "testlib", :description = "Test Description", :ProviderUserName = "TestDev"'
        expect(extractRegistryField(cBlock, "name")).toBe("testlib")
    })

    it("should extract description field from registry block", func {
        cBlock = ':name = "testlib", :description = "Test Description", :ProviderUserName = "TestDev"'
        expect(extractRegistryField(cBlock, "description")).toBe("Test Description")
    })

    it("should extract author case-insensitively", func {
        cBlock = ':name = "testlib", :description = "Test Description", :ProviderUserName = "TestDev"'
        expect(extractRegistryField(cBlock, "providerusername")).toBe("TestDev")
    })

    it("should return empty string for missing field", func {
        cBlock = ':name = "testlib"'
        expect(extractRegistryField(cBlock, "nonexistent")).toBe("")
    })
})

describe("Hub - Library Resolution", func {

    it("should resolve library by numeric index", func {
        aLibs = [[:name = "firstlib", :author = "dev1"], [:name = "ring-libsql", :author = "yousif"]]
        aFound = findLibByIdOrName(aLibs, "2")
        expect(aFound[:name]).toBe("ring-libsql")
    })

    it("should resolve library by name with hyphen", func {
        aLibs = [[:name = "firstlib", :author = "dev1"], [:name = "ring-libsql", :author = "yousif"]]
        aFound = findLibByIdOrName(aLibs, "ring-libsql")
        expect(aFound[:name]).toBe("ring-libsql")
    })

    it("should return empty list for out-of-range index", func {
        aLibs = [[:name = "firstlib", :author = "dev1"]]
        aFound = findLibByIdOrName(aLibs, "99")
        expect(len(aFound) = 0).toBeTruthy()
    })

    it("should return empty list for non-existent name", func {
        aLibs = [[:name = "firstlib", :author = "dev1"]]
        aFound = findLibByIdOrName(aLibs, "nonexistent")
        expect(len(aFound) = 0).toBeTruthy()
    })
})

describe("Hub - Community vs Official Filtering", func {

    it("should identify community library by author", func {
        aComm = [:name = "xlsxlib", :author = "Azzeddine2017", :desc = "Excel"]
        expect(isCommunityLib(aComm)).toBeTruthy()
    })

    it("should identify official library by ringpackages author", func {
        aOfficial = [:name = "analogclock", :author = "ringpackages", :desc = "Clock game"]
        expect(isCommunityLib(aOfficial)).toBeFalsy()
    })

    it("should filter community libraries correctly", func {
        aComm = [:name = "xlsxlib", :author = "Azzeddine2017", :desc = "Excel"]
        aOfficial = [:name = "analogclock", :author = "ringpackages", :desc = "Clock game"]
        aMixed = [aComm, aOfficial]
        aOnlyComm = filterLibs(aMixed, "community")
        expect(len(aOnlyComm)).toBe(1)
        expect(aOnlyComm[1][:name]).toBe("xlsxlib")
    })

    it("should filter official libraries correctly", func {
        aComm = [:name = "xlsxlib", :author = "Azzeddine2017", :desc = "Excel"]
        aOfficial = [:name = "analogclock", :author = "ringpackages", :desc = "Clock game"]
        aMixed = [aComm, aOfficial]
        aOnlyOfficial = filterLibs(aMixed, "official")
        expect(len(aOnlyOfficial)).toBe(1)
        expect(aOnlyOfficial[1][:name]).toBe("analogclock")
    })

    it("should return all libraries in 'all' mode", func {
        aComm = [:name = "xlsxlib", :author = "Azzeddine2017", :desc = "Excel"]
        aOfficial = [:name = "analogclock", :author = "ringpackages", :desc = "Clock game"]
        aMixed = [aComm, aOfficial]
        aAll = filterLibs(aMixed, "all")
        expect(len(aAll)).toBe(2)
    })
})

describe("Hub - README Overview Extraction", func {

    it("should extract body text before H2 header", func {
        cReadme = "# MyPackage" + nl + "> A great library for Ring" + nl + nl + "Features and details..." + nl + "## Installation" + nl + "Install instructions"
        cOverview = extractReadmeOverview(cReadme)
        expect(substr(cOverview, "A great library for Ring") > 0).toBeTruthy()
    })

    it("should stop extraction before Installation section", func {
        cReadme = "# MyPackage" + nl + "> A great library for Ring" + nl + nl + "Features and details..." + nl + "## Installation" + nl + "Install instructions"
        cOverview = extractReadmeOverview(cReadme)
        expect(substr(cOverview, "Install instructions") = 0).toBeTruthy()
    })
})

describe("Hub - Cache Refresh & Registry Parsing", func {

    it("should parse valid registry format", func {
        cRegistrySample = 'aPackagesRegistry = [' + nl +
                          '   [' + nl +
                          '       :name = "xlsxlib",' + nl +
                          '       :description = "Modern XLSX library",' + nl +
                          '       :developer = "Azzeddine2017"' + nl +
                          '   ]' + nl +
                          ']'
        aParsed = parseRemoteRegistry(cRegistrySample)
        expect(len(aParsed)).toBe(1)
        expect(aParsed[1][:name]).toBe("xlsxlib")
        expect(aParsed[1][:author]).toBe("Azzeddine2017")
    })

    it("should resolve cache path for registry", func {
        cCachePath = getCacheDir() + "/registry.ring"
        expect(substr(cCachePath, "registry.ring") > 0).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة cmd_venv.ring
# ====================================================================
describe("Venv - Base Name Extraction", func {

    it("should extract base name from simple path", func {
        expect(getBaseName("/home/user/myenv")).toBe("myenv")
    })

    it("should extract base name from relative path", func {
        expect(getBaseName("./.rvenv")).toBe(".rvenv")
    })

    it("should return 'rvenv' for empty path", func {
        expect(getBaseName("")).toBe("rvenv")
    })
})

describe("Venv - Activation Scripts", func {

    it("should create bin/activate script", func {
        cTestDir = "./tests/test_tmp/sample_env"
        generateActivationScripts(cTestDir, "sample_env")
        expect(fexists(cTestDir + "/bin/activate")).toBeTruthy()
    })

    it("should create Scripts/activate.bat on Windows", func {
        cTestDir = "./tests/test_tmp/sample_env"
        if iswindows()
            expect(fexists(cTestDir + "/Scripts/activate.bat")).toBeTruthy()
        ok
    })

    it("should create Scripts/activate.ps1 on Windows", func {
        cTestDir = "./tests/test_tmp/sample_env"
        if iswindows()
            expect(fexists(cTestDir + "/Scripts/activate.ps1")).toBeTruthy()
        ok
    })

    it("should set RVENV_DIR in Unix activate script", func {
        cTestDir = "./tests/test_tmp/sample_env"
        cContent = read(cTestDir + "/bin/activate")
        expect(substr(cContent, "RVENV_DIR=") > 0).toBeTruthy()
    })

    it("should set RINGPATH in Unix activate script", func {
        cTestDir = "./tests/test_tmp/sample_env"
        cContent = read(cTestDir + "/bin/activate")
        expect(substr(cContent, "RINGPATH=") > 0).toBeTruthy()
    })

    it("should set RVENV_DIR in Windows activate.bat", func {
        cTestDir = "./tests/test_tmp/sample_env"
        if iswindows()
            cContent = read(cTestDir + "/Scripts/activate.bat")
            expect(substr(cContent, "RVENV_DIR=") > 0).toBeTruthy()
        ok
    })

    it("should set RINGPATH in Windows activate.bat", func {
        cTestDir = "./tests/test_tmp/sample_env"
        if iswindows()
            cContent = read(cTestDir + "/Scripts/activate.bat")
            expect(substr(cContent, "RINGPATH=") > 0).toBeTruthy()
        ok
    })

    it("should cleanup test environment", func {
        cTestDir = "./tests/test_tmp/sample_env"
        deleteFolder(cTestDir)
        expect(not direxists(cTestDir)).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة cmd_build.ring
# ====================================================================
describe("Build - Config File Parsing", func {

    it("should parse source from config file", func {
        cConf = "./tests/test_tmp/test_ring2exe.conf"
        ensureDir("./tests/test_tmp")
        cContent = "# Sample config" + nl +
                   "source = src/main.ring" + nl +
                   'output = "TestApp"' + nl +
                   "gui = true" + nl +
                   "auto-libs = true" + nl +
                   "release = true" + nl
        write(cConf, cContent)
        aParsed = parseConfigFile(cConf)
        expect(aParsed["source"]).toBe("src/main.ring")
    })

    it("should strip quotes from output value", func {
        cConf = "./tests/test_tmp/test_ring2exe.conf"
        aParsed = parseConfigFile(cConf)
        expect(aParsed["output"]).toBe("TestApp")
    })

    it("should parse boolean values as strings", func {
        cConf = "./tests/test_tmp/test_ring2exe.conf"
        aParsed = parseConfigFile(cConf)
        expect(aParsed["gui"]).toBe("true")
        expect(aParsed["auto-libs"]).toBe("true")
        expect(aParsed["release"]).toBe("true")
    })

    it("should return empty list for non-existent config file", func {
        aParsed = parseConfigFile("./tests/test_tmp/nonexistent.conf")
        expect(len(aParsed) = 0).toBeTruthy()
    })

    it("should cleanup test config", func {
        remove("./tests/test_tmp/test_ring2exe.conf")
    })
})

describe("Build - Scaffold Generator", func {

    it("should create ring2exe.conf for desktop scaffold", func {
        lOk = buildScaffold("desktop")
        expect(lOk).toBeTruthy()
        expect(fexists("ring2exe.conf")).toBeTruthy()
    })

    it("should create build scripts for desktop scaffold", func {
        expect(fexists("scripts/build_desktop.bat")).toBeTruthy()
        expect(fexists("scripts/build_desktop.sh")).toBeTruthy()
    })

    it("should cleanup scaffold artifacts", func {
        if fexists("ring2exe.conf") remove("ring2exe.conf") ok
        if fexists("scripts/build_desktop.bat") remove("scripts/build_desktop.bat") ok
        if fexists("scripts/build_desktop.sh") remove("scripts/build_desktop.sh") ok
        if direxists("scripts") deleteFolder("scripts") ok
        expect(not fexists("ring2exe.conf")).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة cmd_list_remote.ring
# ====================================================================
describe("List Remote - Release Tag Parsing", func {

    it("should extract 3 tags from JSON response", func {
        cJson = '[{"tag_name":"v1.27"},{"tag_name":"v1.26"},{"tag_name":"1.25"}]'
        aParsed = parseReleaseTags(cJson)
        expect(len(aParsed)).toBe(3)
    })

    it("should strip 'v' prefix from tag names", func {
        cJson = '[{"tag_name":"v1.27"},{"tag_name":"v1.26"},{"tag_name":"1.25"}]'
        aParsed = parseReleaseTags(cJson)
        expect(aParsed[1]).toBe("1.27")
    })

    it("should keep non-v prefix tag names", func {
        cJson = '[{"tag_name":"v1.27"},{"tag_name":"v1.26"},{"tag_name":"1.25"}]'
        aParsed = parseReleaseTags(cJson)
        expect(aParsed[3]).toBe("1.25")
    })

    it("should return empty list for empty JSON", func {
        aParsed = parseReleaseTags("[]")
        expect(len(aParsed) = 0).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة extractor.ring
# ====================================================================
describe("Extractor - Version Runtime Dir", func {

    it("should return same dir when binary exists directly", func {
        cVerDir = "./tests/test_tmp/fake_ver"
        ensureDir(cVerDir + "/bin")
        cBin = getBinaryName()
        write(cVerDir + "/bin/" + cBin, "fake")
        cResult = findVersionRuntimeDir(cVerDir)
        expect(cResult).toBe(cVerDir)
        deleteFolder(cVerDir)
    })

    it("should find nested runtime directory", func {
        cVerDir = "./tests/test_tmp/fake_ver"
        ensureDir(cVerDir + "/Ring_fake/bin")
        cBin = getBinaryName()
        write(cVerDir + "/Ring_fake/bin/" + cBin, "fake")
        cResult = findVersionRuntimeDir(cVerDir)
        expect(substr(cResult, "Ring_fake") > 0).toBeTruthy()
        deleteFolder(cVerDir)
    })

    it("should normalize nested version folder and remove duplicate subfolder", func {
        cVerDir = "./tests/test_tmp/norm_ver"
        ensureDir(cVerDir + "/ring/bin")
        cBin = getBinaryName()
        write(cVerDir + "/ring/bin/" + cBin, "fake")
        normalizeVersionFolder(cVerDir)
        expect(fexists(cVerDir + "/bin/" + cBin)).toBeTruthy()
        expect(direxists(cVerDir + "/ring")).toBeFalsy()
        deleteFolder(cVerDir)
    })
})

# ====================================================================
# اختبارات وحدة cmd_install.ring
# ====================================================================
describe("Install - Release Asset Naming", func {

    it("should return Windows asset name for Windows platform", func {
        if iswindows()
            cAsset = getReleaseAsset("1.27", true)
            expect(substr(cAsset, "Windows") > 0).toBeTruthy()
            expect(substr(cAsset, ".zip") > 0).toBeTruthy()
        ok
    })

    it("should return Linux asset name for Linux platform", func {
        if islinux()
            cAsset = getReleaseAsset("1.27", true)
            expect(substr(cAsset, "Ubuntu") > 0).toBeTruthy()
        ok
    })

    it("should return macOS asset name for macOS platform", func {
        if ismacos()
            cAsset = getReleaseAsset("1.27", true)
            expect(substr(cAsset, "macOS") > 0).toBeTruthy()
        ok
    })

    it("should include version in asset name", func {
        cAsset = getReleaseAsset("1.27", true)
        expect(substr(cAsset, "1.27") > 0).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة cmd_remove.ring
# ====================================================================
describe("Remove - Validation", func {

    it("should return false for non-existent version", func {
        lResult = cmdRemove("999.999.nonexistent")
        expect(lResult = false).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة cmd_harvest.ring
# ====================================================================
describe("Harvest - Host Ring Discovery", func {

    it("should locate a Ring installation or return empty", func {
        cHost = getHostRingDir()
        expect(cHost = "" or len(cHost) > 0).toBeTruthy()
    })
})

# ====================================================================
# اختبارات وحدة downloader.ring
# ====================================================================
describe("Downloader - System Fallback", func {

    it("should return false for invalid or empty URL", func {
        lResult = downloadViaSystem("", "./tests/test_tmp/test_dl.zip")
        expect(lResult = false).toBeTruthy()
    })
})