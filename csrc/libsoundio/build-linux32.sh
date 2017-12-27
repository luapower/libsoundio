P=linux32 C="-DSOUNDIO_HAVE_ALSA src/alsa.c" \
	L="-s -static-libgcc -pthread -lasound -fno-exceptions -fno-rtti -fvisibility=hidden" \
	D=libsoundio.so A=libsoundio.a ./build.sh
