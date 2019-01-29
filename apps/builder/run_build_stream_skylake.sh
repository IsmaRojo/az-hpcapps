#!/bin/bash
# Prerequisites : GCC 7.x
set -e

BUILD_DIR=$(pwd)
WRITE_SAS_KEY=$1
AZCOPY=/opt/azcopy/azcopy

export PATH=/opt/rh/devtoolset-7/root/bin/:$PATH

get_source()
{
    wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c
    wget https://www.cs.virginia.edu/stream/FTP/Code/LICENSE.txt
}

build_stream() {

cat <<EOF >Makefile
# Makefile for STREAM version 5.10 using GCC 7.x, tuned for Intel Skylake

DOUBLE_FILENAME = stream_sky_double
SOURCE = stream.c

CC = gcc
CFLAGS = -O3 -fopenmp -DSTREAM_ARRAY_SIZE=800002560 -DOFFSET=64 -mcmodel=medium
CPUFLAGS = -march=skylake-avx512 -mtune=skylake-avx512
CFLAGS_DOUBLE = -DSTREAM_TYPE=double

CFLAGS += -Wall -Wno-unused-but-set-variable -Wno-unknown-pragmas

CFLAGS += -fprefetch-loop-arrays
CFLAGS += -funsafe-loop-optimizations -ffast-math

all: \$(DOUBLE_FILENAME)

\$(DOUBLE_FILENAME): \$(SOURCE)
	@echo "Building $@"
	\$(CC) \$(CPUFLAGS) \$(CFLAGS) \$(CFLAGS_DOUBLE) \$< \$(LDFLAGS) -o \$@

clean:
	@echo "Cleaning"
	rm -f \$(DOUBLE_FILENAME) *.o

EOF

    make

}

get_source
build_stream

echo "upload STREAM in blob"
stream_exe=stream_sky_double
if [ -e "$stream_exe" ]; then
    $AZCOPY cp $stream_exe "$HPC_APPS_STORAGE_ENDPOINT/bench/$stream_exe?$WRITE_SAS_KEY"
else
    echo "ERROR: $stream_exe not found"
    exit 1
fi



