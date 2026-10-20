cd /d G:\RingProject\Madar
echo Fetching self-contained pure C99 GGML Core...
curl -L -o language\include\ggml.h https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.2.0/ggml.h
curl -L -o language\src\ggml.c https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.2.0/ggml.c
echo GGML files fetched successfully.
