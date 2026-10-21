cls
setlocal enableextensions enabledelayedexpansion
call ../../language/build/locatevc.bat x64

REM /TP forces C++ compilation
REM /O2 = Maximize Speed
REM /EHsc = Enable C++ Exceptions (required for std::vector/string)

cl /c /O2 /Ot /GL /MD /TP /EHsc /std:c++20 alqalam.cpp -I"..\..\language\include"
link /LTCG /DLL alqalam.obj ..\..\lib\ring.lib kernel32.lib /OUT:..\..\bin\alqalam.dll

del alqalam.obj
endlocal