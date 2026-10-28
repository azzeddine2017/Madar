@echo off
cls
setlocal enableextensions enabledelayedexpansion
call ../../../language/build/locatevc.bat x64
cl /c /DEBUG ..\src\ringregex.c -I"..\..\..\language\include" -I"..\include"
link /DEBUG ringregex.obj  ..\..\..\lib\ring.lib "..\lib\pcre2-8.lib" /DLL /OUT:..\..\..\bin\ringregex.dll
del ringregex.obj
endlocal
