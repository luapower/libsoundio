P=mingw64 C="-DSOUNDIO_HAVE_WASAPI src/wasapi.cpp" \
	L="-s -static-libgcc -static-libstdc++ -lole32" \
	D=soundio.dll A=soundio.a ./build.sh
