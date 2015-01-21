# install: libasound2-dev

fish_util_dir = ../fish-util
fish_util_o = $(fish_util_dir)/fish-util.o

#glib_inc_dir = $(shell pkg-config --cflags glib-2.0)

FLAGS_C = -std=c99 -fPIC -lm -lpthread -lasound -I$(fish_util_dir)
FLAGS_SHARED = -fPIC -shared
#FLAGS_SHARED = -shared

all: fasound.o libfasound.so

fasound.o: $(fish_util_o) fasound.c fasound.h
	gcc $(FLAGS_C) fasound.c -c -o fasound.o

# The shared library is not necessary for fish-vol, but it is useful for
# other applications. 
# Also make install is not necessary for fish-vol.
libfasound.so: $(fish_util_o) fasound.c fasound.h
	gcc $(FLAGS_C) $(FLAGS_SHARED) fasound.c fasound.h  -o libfasound.so

install: all
	cp fasound.h /usr/local/include
	cp libfasound.so /usr/local/lib
	ldconfig


clean: 
	rm -f *.o
	rm -f test
