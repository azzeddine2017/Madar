clang -c -fpic ../src/ringregex.c -I $PWD/../../../language/include
clang -dynamiclib -o libringregex.dylib ringregex.o -L $PWD/../../../language/lib -lring
rm ringregex.o
cp libringregex.dylib /usr/local/lib
cp libringregex.dylib ../bin/
