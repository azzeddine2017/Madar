gcc -c -fpic ../src/ringregex.c -I $PWD/../../../language/include
gcc -shared -o libringregex.so ringregex.o -L $PWD/../../../language/lib -lring
rm ringregex.o
sudo cp libringregex.so /usr/lib
sudo cp libringregex.so /usr/lib64
cp libringregex.so ../bin/
