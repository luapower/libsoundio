${X}gcc -c -O2 \
	-std=c11 -fvisibility=hidden -Wall -Werror=strict-prototypes \
	-Werror=old-style-definition -Werror=missing-prototypes \
	-D_REENTRANT -D_POSIX_C_SOURCE=200809L -Wno-missing-braces \
	$C \
	src/soundio.c src/util.c src/os.c src/dummy.c src/channel_layout.c src/ring_buffer.c \
	-Isrc -I.
${X}gcc *.o -shared -o ../../bin/$P/$D $L
${X}ar rcs ../../bin/$P/$A *.o
rm *.o
