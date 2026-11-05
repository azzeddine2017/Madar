if isWindows()
	LoadLib("ring_cjson.dll")
but ismacosx()
	LoadLib("libring_cjson.dylib")
else
	bLoaded = false
	aLibPaths = [
		"libring_cjson.so",
		"lib/libring_cjson.so",
		"bin/libring_cjson.so",
		"/content/Madar/lib/libring_cjson.so",
		"/content/Madar/bin/libring_cjson.so",
		"/content/Madar/extensions/ringcjson/libring_cjson.so"
	]
	for cLib in aLibPaths
		try
			LoadLib(cLib)
			bLoaded = true
			exit
		catch
		done
	next
	if !bLoaded
		LoadLib("libring_cjson.so")
	ok
ok

load "ring_cjson.rh"
