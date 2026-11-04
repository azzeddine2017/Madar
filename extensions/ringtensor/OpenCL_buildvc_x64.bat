cls
setlocal enableextensions enabledelayedexpansion
call ../../language/build/locatevc.bat x64
cl /c /O2 /Ot /GL /MD /openmp /arch:AVX2 /DUSE_OPENCL ring_tensor.c -I"..\..\language\include" -I"./include"
link /LTCG /DLL ring_tensor.obj lib\OpenCL.lib ..\..\lib\ring.lib kernel32.lib /OUT:..\..\bin\ring_tensor.dll
del ring_tensor.obj
endlocal