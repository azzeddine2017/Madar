clang -c -fpic -O2 ring_tensor.c -I $PWD/../../language/include
clang -dynamiclib -o $PWD/../../lib/libring_tensor.dylib ring_tensor.o  -L $PWD/../../lib  -lring -lOpenCL 