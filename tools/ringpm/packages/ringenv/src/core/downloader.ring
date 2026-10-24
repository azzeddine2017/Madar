# ringenv - Downloader Module
# LibCurl wrapper with progress callback, memory-safe write, and system fallback

# Constants fallback in case not defined in libcurl.ring
if not isglobal(:CURLOPT_URL)               CURLOPT_URL = 10002 ok
if not isglobal(:CURLOPT_WRITEDATA)         CURLOPT_WRITEDATA = 10001 ok
if not isglobal(:CURLOPT_USERAGENT)         CURLOPT_USERAGENT = 10018 ok
if not isglobal(:CURLOPT_FOLLOWLOCATION)    CURLOPT_FOLLOWLOCATION = 52 ok
if not isglobal(:CURLOPT_NOPROGRESS)        CURLOPT_NOPROGRESS = 43 ok
if not isglobal(:CURLOPT_XFERINFOFUNCTION)  CURLOPT_XFERINFOFUNCTION = 20219 ok
if not isglobal(:CURLOPT_SSL_VERIFYPEER)    CURLOPT_SSL_VERIFYPEER = 64 ok
if not isglobal(:CURLOPT_SSL_VERIFYHOST)    CURLOPT_SSL_VERIFYHOST = 81 ok

# Track last percentage to throttle console updates
nLastPercent = -1

# Callback for curl download progress
func ringenv_download_progress
    aInfo = curl_get_progress_info()
    if islist(aInfo)
        if len(aInfo) >= 2
            dltotal = aInfo[1]
            dlnow = aInfo[2]

            if dltotal > 0
                nPercent = floor((dlnow / dltotal) * 100)
                if nPercent != nLastPercent
                    nLastPercent = nPercent
                    nMbNow = floor((dlnow / 1048576) * 10) / 10
                    nMbTotal = floor((dltotal / 1048576) * 10) / 10

                    cPct = "" + nPercent
                    if len(cPct) = 1
                        cPct = "  " + cPct
                    but len(cPct) = 2
                        cPct = " " + cPct
                    ok

                    see char(13) + "Progress: [" + cPct + "%] " + nMbNow + " MB / " + nMbTotal + " MB"
                ok
            ok
        ok
    ok
    curl_set_progress_result(0)

# System-level download fallback (curl / powershell / wget)
func downloadViaSystem cDownloadUrl, cDestPath
    if cDownloadUrl = "" or cDestPath = ""
        return false
    ok
    cNativeDest = toNativePath(cDestPath)
    cQ = char(34)

    if iswindows()
        # Attempt via curl.exe (built-in on Windows 10/11) with fast timeout
        cCmd = "curl.exe --connect-timeout 2 --max-time 3 -s -f -L -k -A " + cQ + "ringenv/" + getRingenvVersion() + cQ + " -o " + cQ + cNativeDest + cQ + " " + cQ + cDownloadUrl + cQ
        system(cCmd)

        if fexists(cDestPath)
            if getfilesize(cDestPath) > 1000
                return true
            else
                remove(cDestPath)
            ok
        ok

        return false
    else
        cCmd = "curl -f -L -A " + cQ + "ringenv/" + getRingenvVersion() + cQ + " -o " + cQ + cDestPath + cQ + " " + cQ + cDownloadUrl + cQ + " 2>/dev/null || wget -q -O " + cQ + cDestPath + cQ + " " + cQ + cDownloadUrl + cQ
        system(cCmd)

        if fexists(cDestPath) and getfilesize(cDestPath) > 1000
            return true
        ok
    ok

    return false

# Download file from URL to destination path
func downloadFile cDownloadUrl, cDestPath
    nLastPercent = -1

    hCurl = curl_easy_init()
    if hCurl = NULL
        ? "LibCurl init returned NULL. Falling back to system downloader..."
        return downloadViaSystem(cDownloadUrl, cDestPath)
    ok

    # Configure curl options
    curl_easy_setopt(hCurl, CURLOPT_URL, cDownloadUrl)
    curl_easy_setopt(hCurl, CURLOPT_USERAGENT, "ringenv/" + getRingenvVersion())
    curl_easy_setopt(hCurl, CURLOPT_FOLLOWLOCATION, 1)
    curl_easy_setopt(hCurl, CURLOPT_NOPROGRESS, 0)
    curl_easy_setopt(hCurl, CURLOPT_XFERINFOFUNCTION, :ringenv_download_progress)
    curl_easy_setopt(hCurl, CURLOPT_SSL_VERIFYPEER, 0)
    curl_easy_setopt(hCurl, CURLOPT_SSL_VERIFYHOST, 2)

    # Perform download safely into memory string
    cOutput = curl_easy_perform_silent(hCurl)
    nResponseCode = curl_getResponseCode(hCurl)

    curl_easy_cleanup(hCurl)

    # Clean up newline after progress display
    ? ""

    if nResponseCode = 200 and len(cOutput) > 1000
        write(cDestPath, cOutput)
        if fexists(cDestPath) and getfilesize(cDestPath) > 1000
            return true
        ok
    ok

    # If libcurl did not succeed, try system fallback
    if fexists(cDestPath)
        remove(cDestPath)
    ok

    ? "LibCurl response code: " + nResponseCode + " (data length: " + len(cOutput) + ")."
    ? "Falling back to system network downloader..."

    lSysOk = downloadViaSystem(cDownloadUrl, cDestPath)
    if lSysOk
        ? "Download completed successfully via system downloader."
        return true
    ok

    ? "Download failed for: " + cDownloadUrl
    return false
