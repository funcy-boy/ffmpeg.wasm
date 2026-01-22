# syntax=docker/dockerfile-upstream:master-labs

############################################
# Base emsdk
############################################
FROM emscripten/emsdk:3.1.40 AS emsdk-base
ENV INSTALL_DIR=/opt
ENV FFMPEG_VERSION=n5.1.4

RUN apt-get update && \
    apt-get install -y pkg-config autoconf automake libtool ragel

############################################
# Build zlib (required)
############################################
FROM emsdk-base AS zlib-builder
ENV ZLIB_BRANCH=v1.2.11
ADD https://github.com/ffmpegwasm/zlib.git#$ZLIB_BRANCH /src
COPY build/zlib.sh /src/build.sh
RUN bash -x /src/build.sh

############################################
# Base ffmpeg
############################################
FROM emsdk-base AS ffmpeg-base
ADD https://github.com/FFmpeg/FFmpeg.git#$FFMPEG_VERSION /src
COPY --from=zlib-builder $INSTALL_DIR $INSTALL_DIR

############################################
# Build ffmpeg (TS → MP4 ONLY)
############################################
FROM ffmpeg-base AS ffmpeg-builder
COPY build/ffmpeg.sh /src/build.sh

RUN bash -x /src/build.sh \
  --disable-everything \
  --disable-programs \
  --disable-doc \
  --disable-debug \
  --disable-autodetect \
  --disable-network \
  --enable-zlib \
  --enable-gpl \
  --enable-protocol=file,crypto \
  --enable-demuxer=concat,mpegts,hls,mov \
  --enable-muxer=mp4 \
  --enable-decoder=h264,aac \
  --enable-parser=h264,aac,mpegts \
  --enable-bsf=aac_adtstoasc \
  --enable-small

############################################
# Build ffmpeg.wasm
############################################
FROM ffmpeg-builder AS ffmpeg-wasm-builder
COPY src/bind /src/src/bind
COPY src/fftools /src/src/fftools
COPY build/ffmpeg-wasm.sh build.sh

ENV FFMPEG_LIBS="-lz"

RUN mkdir -p /src/dist && \
    bash -x /src/build.sh \
      ${FFMPEG_LIBS} \
      -sALLOW_MEMORY_GROWTH=1 \
      -sINITIAL_MEMORY=64MB \
      -sMAXIMUM_MEMORY=512MB \
      -o dist/ffmpeg-core.js

############################################
# Export
############################################
FROM scratch AS exportor
COPY --from=ffmpeg-wasm-builder /src/dist /dist
