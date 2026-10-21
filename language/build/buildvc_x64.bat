echo off
setlocal enableextensions enabledelayedexpansion
call locatevc.bat x64

cd ..\src

cl /c %ringcflags% /arch:AVX2 ring.c  ^
ring_tensor.c ring_gguf.c ring_tokenizer.c ring_inference.c ring_diagnostics.c ggml.c vmcgoto.c rstring.c rlist.c ritem.c ritems.c rhtable.c general.c state.c scanner.c parser.c hashlib.c vmgc.c ^
stmt.c expr.c codegen.c vm.c vmerror.c vmeval.c vmthread.c vmexpr.c vmvars.c ^
vmlists.c vmfuncs.c ringapi.c vmoop.c  ^
vmtry.c vmstr.c vmjump.c vmrange.c ^
vmperf.c vmexit.c vmstack.c vmstate.c genlib_e.c math_e.c file_e.c os_e.c list_e.c meta_e.c vminfo_e.c ^
ext.c dll_e.c objfile.c -I"..\include" 
if errorlevel 1 (
    echo [ERROR] cl compilation failed!
    exit /b 1
)

link  %ringldflags% /DLL /OUT:..\..\lib\ring.dll /SUBSYSTEM:CONSOLE,"%ringsubsystem%"  ring_tensor.obj ring_gguf.obj ring_tokenizer.obj ring_inference.obj ring_diagnostics.obj ggml.obj vmcgoto.obj rstring.obj ^
rlist.obj ritem.obj ritems.obj rhtable.obj general.obj state.obj scanner.obj parser.obj hashlib.obj vmgc.obj ^
stmt.obj expr.obj codegen.obj vm.obj vmerror.obj vmeval.obj vmthread.obj vmexpr.obj vmvars.obj ^
vmlists.obj vmfuncs.obj ringapi.obj vmoop.obj  ^
vmtry.obj vmstr.obj vmjump.obj vmrange.obj ^
vmperf.obj vmexit.obj vmstack.obj vmstate.obj genlib_e.obj math_e.obj file_e.obj os_e.obj list_e.obj meta_e.obj vminfo_e.obj ^
ext.obj dll_e.obj objfile.obj 
if errorlevel 1 (
    echo [ERROR] link failed!
    exit /b 1
) 

lib  /OUT:..\..\lib\ringstatic.lib ring_tensor.obj ring_gguf.obj ring_tokenizer.obj ring_inference.obj ring_diagnostics.obj ggml.obj vmcgoto.obj rstring.obj ^
rlist.obj ritem.obj ritems.obj rhtable.obj general.obj state.obj scanner.obj parser.obj hashlib.obj vmgc.obj ^
stmt.obj expr.obj codegen.obj vm.obj vmerror.obj vmeval.obj vmthread.obj vmexpr.obj vmvars.obj ^
vmlists.obj vmfuncs.obj ringapi.obj vmoop.obj  ^
vmtry.obj vmstr.obj vmjump.obj vmrange.obj ^
vmperf.obj vmexit.obj vmstack.obj vmstate.obj genlib_e.obj math_e.obj file_e.obj os_e.obj list_e.obj meta_e.obj vminfo_e.obj ^
ext.obj dll_e.obj objfile.obj 

copy ..\..\lib\ring.dll ..\..\bin\

cl %ringcflags% /arch:AVX2 ring.c ..\..\lib\ring.lib -I"..\include" /link /STACK:8388608 /OUT:..\..\bin\ring.exe 

del *.obj

endlocal
