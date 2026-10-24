# zipengine.ring - ZipEngine wrapper class for archive extraction

class ZipEngine
    func extractZip cZipPath, cDestFolder
        cNormDest = normalizePath(cDestFolder)
        ensureDir(cNormDest)

        # 1. Try Ring's Zip class
        try
            new Zip {
                setFileName(cZipPath)
                extractAllFiles(cNormDest)
            }
        catch
        done

        # 2. Try procedural zip_extract_allfiles
        try
            zip_extract_allfiles(cZipPath, cNormDest)
        catch
        done

        # 3. If files not yet extracted, system fallback
        cBinFile = getBinaryName()
        if not fexists(cNormDest + "/bin/" + cBinFile) and not fexists(cNormDest + "/" + cBinFile)
            if iswindows()
                cNativeZip = toNativePath(cZipPath)
                cNativeDest = toNativePath(cNormDest)
                cCmd = "powershell -NoProfile -Command " + char(34) + "Expand-Archive -Path '" + cNativeZip + "' -DestinationPath '" + cNativeDest + "' -Force" + char(34)
                system(cCmd)
            else
                cCmd = 'unzip -q -o "' + cZipPath + '" -d "' + cNormDest + '" 2>/dev/null'
                system(cCmd)
            ok
        ok

        return true

    func extractAll cZipPath, cDestFolder
        return extractZip(cZipPath, cDestFolder)
