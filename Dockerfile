# syntax=docker/dockerfile-upstream:master-labs

# Base emsdk image
FROM emscripten/emsdk:3.1.40 AS emsdk-base
ARG EXTRA_CFLAGS
ARG EXTRA_LDFLAGS
ENV INSTALL_DIR=/opt

ENV FFMPEG_VERSION=n5.1.4
ENV CFLAGS="-I$INSTALL_DIR/include $CFLAGS $EXTRA_CFLAGS"
ENV CXXFLAGS="$CFLAGS"
ENV LDFLAGS="-L$INSTALL_DIR/lib $LDFLAGS $CFLAGS $EXTRA_LDFLAGS"
ENV EM_PKG_CONFIG_PATH=$EM_PKG_CONFIG_PATH:$INSTALL_DIR/lib/pkgconfig:/emsdk/upstream/emscripten/system/lib/pkgconfig
ENV EM_TOOLCHAIN_FILE=$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$EM_PKG_CONFIG_PATH
RUN apt-get update && \
      apt-get install -y pkg-config autoconf automake libtool ragel

# Build zlib 
FROM emsdk-base AS zlib-builder
ENV ZLIB_BRANCH=v1.2.11
ADD https://github.com/ffmpegwasm/zlib.git#$ZLIB_BRANCH /src
COPY build/zlib.sh /src/build.sh
RUN bash -x /src/build.sh

# Build x264 
FROM emsdk-base AS x264-builder
ENV X264_BRANCH=4-cores
ADD https://github.com/ffmpegwasm/x264.git#$X264_BRANCH /src
COPY build/x264.sh /src/build.sh
RUN bash -x /src/build.sh

# Base ffmpeg image
FROM emsdk-base AS ffmpeg-base
RUN embuilder build sdl2 sdl2-mt
ADD https://github.com/FFmpeg/FFmpeg.git#$FFMPEG_VERSION /src
COPY --from=zlib-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=x264-builder $INSTALL_DIR $INSTALL_DIR

# Build ffmpeg 
FROM ffmpeg-base AS ffmpeg-builder
COPY build/ffmpeg.sh /src/build.sh

RUN bash -x /src/build.sh \
      --disable-everything \
      --disable-doc \
      --disable-debug \
      --disable-network \
      --disable-autodetect \
      --enable-gpl \
      --enable-libx264 \
      --enable-zlib \
      --enable-protocol=file \
      --enable-swresample \
      --enable-swscale \
      --enable-decoder=h264,hevc,aac,mp3,pcm_s16le \
      --enable-encoder=aac,libx264,pcm_s16le \
      --enable-demuxer=aac,mov,mp4,m4v,mpegts,h264,hevc,mp3,wav \
      --enable-muxer=mp4,mov,wav,null \
      --enable-parser=aac,h264,hevc,mpegaudio \
      --enable-bsf=aac_adtstoasc,h264_mp4toannexb,hevc_mp4toannexb,extract_extradata \
      --enable-filter=concat,aresample,scale,crop,overlay,amix

# Build ffmpeg.wasm
FROM ffmpeg-builder AS ffmpeg-wasm-builder
COPY src/bind /src/src/bind
COPY src/fftools /src/src/fftools
COPY build/ffmpeg-wasm.sh build.sh

ENV FFMPEG_LIBS \
      -lx264 \
      -lz

RUN mkdir -p /src/dist/umd && bash -x /src/build.sh \
      ${FFMPEG_LIBS} \
      -o dist/umd/ffmpeg-core.js
RUN mkdir -p /src/dist/esm && bash -x /src/build.sh \
      ${FFMPEG_LIBS} \
      -sEXPORT_ES6 \
      -o dist/esm/ffmpeg-core.js

# Export
FROM scratch AS exportor
COPY --from=ffmpeg-wasm-builder /src/dist /dist
