# syntax=docker/dockerfile:1

############################################
# Base emsdk
############################################
FROM emscripten/emsdk:3.1.40 AS base
ENV INSTALL_DIR=/opt
ENV FFMPEG_VERSION=n5.1.4

RUN apt-get update && \
    apt-get install -y \
      autoconf automake libtool pkg-config ragel cmake && \
    rm -rf /var/lib/apt/lists/*

############################################
# Build zlib (WASM)
############################################
FROM base AS zlib-builder
WORKDIR /src

ADD https://zlib.net/zlib-1.3.1.tar.gz .
RUN tar xf zlib-1.3.1.tar.gz && \
    cd zlib-1.3.1 && \
    emconfigure ./configure \
      --static \
      --prefix=/opt && \
    emmake make -j$(nproc) && \
    emmake make install

############################################
# Build FFmpeg (EXTREMELY MINIMAL)
############################################
FROM base AS ffmpeg-builder
WORKDIR /src

ADD https://github.com/FFmpeg/FFmpeg.git#${FFMPEG_VERSION} ffmpeg
COPY --from=zlib-builder /opt /opt

ENV PKG_CONFIG_PATH=/opt/lib/pkgconfig
ENV CFLAGS="-I/opt/include -O3"
ENV LDFLAGS="-L/opt/lib"

WORKDIR /src/ffmpeg

RUN emconfigure ./configure \
  --target-os=none \
  --arch=x86_32 \
  --enable-cross-compile \
  --disable-asm \
  --disable-programs \
  --disable-doc \
  --disable-debug \
  --disable-autodetect \
  --disable-network \
  --disable-everything \
  \
  --enable-zlib \
  --enable-protocol=file,crypto \
  \
  --enable-demuxer=concat,mpegts,hls,mov \
  --enable-muxer=mp4 \
  \
  --enable-decoder=h264,aac \
  --enable-parser=h264,aac,mpegts \
  \
  --enable-bsf=aac_adtstoasc \
  \
  --enable-small \
  --enable-gpl

RUN emmake make -j$(nproc)

############################################
# Build ffmpeg.wasm core
############################################
FROM ffmpeg-builder AS wasm-builder
WORKDIR /src

# 只复制必要的绑定
COPY src/bind /src/src/bind
COPY src/fftools /src/src/fftools
COPY build/ffmpeg-wasm.sh /src/build.sh

ENV FFMPEG_LIBS="-lz"

RUN mkdir -p dist && \
    bash /src/build.sh \
      ${FFMPEG_LIBS} \
      -sALLOW_MEMORY_GROWTH=1 \
      -sINITIAL_MEMORY=64MB \
      -sMAXIMUM_MEMORY=512MB \
      -o dist/ffmpeg-core.js

############################################
# Export
############################################
FROM scratch
COPY --from=wasm-builder /src/dist /dist
