# syntax=docker/dockerfile-upstream:master-labs

############################################
# Base emsdk
############################################
FROM emscripten/emsdk:3.1.40 AS emsdk-base

ENV INSTALL_DIR=/opt
ENV FFMPEG_VERSION=n5.1.4

RUN apt-get update && \
    apt-get install -y \
      pkg-config \
      autoconf \
      automake \
      libtool \
      ragel \
      && rm -rf /var/lib/apt/lists/*

ENV CFLAGS="-I$INSTALL_DIR/include -O3"
ENV CXXFLAGS="$CFLAGS"
ENV LDFLAGS="-L$INSTALL_DIR/lib"
ENV EM_PKG_CONFIG_PATH=$INSTALL_DIR/lib/pkgconfig
ENV PKG_CONFIG_PATH=$EM_PKG_CONFIG_PATH

############################################
# Build zlib (AES + MP4 必需)
############################################
FROM emsdk-base AS zlib-builder

ADD https://github.com/ffmpegwasm/zlib.git#v1.2.11 /src
COPY build/zlib.sh /src/build.sh

RUN bash /src/build.sh

############################################
# Build FFmpeg (TS + AES + concat only)
############################################
FROM emsdk-base AS ffmpeg-builder

ADD https://github.com/FFmpeg/FFmpeg.git#${FFMPEG_VERSION} /src
COPY --from=zlib-builder $INSTALL_DIR $INSTALL_DIR
COPY build/ffmpeg.sh /src/build.sh

RUN bash -x /src/build.sh \
  --disable-everything \
  --disable-doc \
  --disable-debug \
  --disable-network \
  --disable-autodetect \
  --disable-filters \
  --disable-programs \
  \
  --enable-zlib \
  \
  --enable-protocol=file,crypto \
  \
  --enable-demuxer=concat,mpegts \
  \
  --enable-parser=h264,aac \
  \
  --enable-bsf=aac_adtstoasc \
  \
  --enable-muxer=mp4

############################################
# Build ffmpeg.wasm
############################################
FROM ffmpeg-builder AS ffmpeg-wasm-builder

COPY src/bind /src/src/bind
COPY src/fftools /src/src/fftools
COPY build/ffmpeg-wasm.sh /src/build.sh

ENV FFMPEG_LIBS="-lz"

# UMD
RUN mkdir -p /src/dist/umd && \
    bash /src/build.sh \
      ${FFMPEG_LIBS} \
      -sINITIAL_MEMORY=268435456 \
      -sALLOW_MEMORY_GROWTH=1 \
      -sMAXIMUM_MEMORY=536870912 \
      -o dist/umd/ffmpeg-core.js

# ESM
RUN mkdir -p /src/dist/esm && \
    bash /src/build.sh \
      ${FFMPEG_LIBS} \
      -sEXPORT_ES6 \
      -sINITIAL_MEMORY=268435456 \
      -sALLOW_MEMORY_GROWTH=1 \
      -sMAXIMUM_MEMORY=536870912 \
      -o dist/esm/ffmpeg-core.js

############################################
# Export
############################################
FROM scratch AS export
COPY --from=ffmpeg-wasm-builder /src/dist /dist
