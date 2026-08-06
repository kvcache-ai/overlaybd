ARG BUILDER_IMAGE=alpine:3.22
FROM ${BUILDER_IMAGE} AS builder

ARG ALPINE_MIRROR=https://mirror.math.princeton.edu/pub/alpinelinux
ARG RELEASE_VERSION=dev
ARG SOURCE_COMMIT=unknown
ARG TARGETARCH
ARG OCF_COMMIT=c2dd2259e47c2e5e72dc77f99d0150a5d05496d7
ARG OCF_SOURCE_SHA256=b67a4cda8e940ab68b3f67995c04d1d6da1e3a8299dfef7136cd1a4626c61cf8
ARG PHOTON_COMMIT=0178d14499d8639759a81e32ad58da5226df5e9b
ARG PHOTON_SOURCE_SHA256=b5d4a1fad757df6808e83108b2b311d310807e54c06ab9eef7896a2ece2647b0
ARG E2FSPROGS_COMMIT=404deb95e6b0ed0ceb0148d289977e65bee7f8d0
ARG E2FSPROGS_SOURCE_SHA256=2c3efbc3f98c6db52425fe4f5d04194c3f4abbb2676388617c57127c3d30a5a1
ARG EROFS_UTILS_COMMIT=eec6f7a2755dfccc8f655aa37cf6f26db9164e60
ARG EROFS_UTILS_SOURCE_SHA256=4cccdb0932dd3c2ca0595451463e0819be8e14d99961c896f91f6f6a90082158

RUN sed -i "s|https://dl-cdn.alpinelinux.org/alpine|${ALPINE_MIRROR}|g" /etc/apk/repositories && \
    apk add --no-cache \
        autoconf \
        automake \
        bash \
        binutils \
        brotli-static \
        build-base \
        cmake \
        curl \
        curl-dev \
        curl-static \
        e2fsprogs-dev \
        e2fsprogs-static \
        file \
        jq \
        libaio-dev \
        libidn2-static \
        libpsl-static \
        libtool \
        libunistring-static \
        linux-headers \
        ninja \
        nghttp2-static \
        openssl-dev \
        openssl-libs-static \
        pkgconf \
        rapidjson-dev \
        tar \
        util-linux-dev \
        util-linux-static \
        yaml-cpp-dev \
        zlib-dev \
        zlib-static \
        zstd-dev \
        zstd-static

WORKDIR /work

RUN set -eu; \
    fetch_source() { \
        name="$1"; repository="$2"; commit="$3"; expected_sha256="$4"; \
        archive="/tmp/${name}.tar.gz"; \
        curl --fail --location --show-error --silent \
            --connect-timeout 20 --max-time 300 \
            --retry 3 --retry-all-errors --retry-delay 2 \
            --output "$archive" \
            "https://codeload.github.com/${repository}/tar.gz/${commit}"; \
        echo "${expected_sha256}  ${archive}" | sha256sum -c -; \
        mkdir -p "/work/${name}"; \
        tar -xzf "$archive" -C "/work/${name}" --strip-components=1; \
        rm "$archive"; \
    }; \
    fetch_source ocf Open-CAS/ocf "$OCF_COMMIT" "$OCF_SOURCE_SHA256"; \
    fetch_source photon alibaba/PhotonLibOS "$PHOTON_COMMIT" "$PHOTON_SOURCE_SHA256"; \
    fetch_source e2fsprogs data-accelerator/e2fsprogs "$E2FSPROGS_COMMIT" "$E2FSPROGS_SOURCE_SHA256"; \
    fetch_source erofs-utils erofs/erofs-utils "$EROFS_UTILS_COMMIT" "$EROFS_UTILS_SOURCE_SHA256"; \
    mkdir -p source/src/overlaybd/cache/ocf_cache/ocf; \
    cp -a ocf/. source/src/overlaybd/cache/ocf_cache/ocf/

COPY CMakeLists.txt LICENSE /work/source/
COPY CMake /work/source/CMake
COPY baselayers /work/source/baselayers
COPY src /work/source/src

COPY contrib/static/photon-musl.patch /tmp/photon-musl.patch
RUN patch -d photon -p1 --dry-run < /tmp/photon-musl.patch && \
    patch -d photon -p1 < /tmp/photon-musl.patch

RUN cmake -S source -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_CURL_FROM_SOURCE=OFF \
        -DBUILD_STREAM_CONVERTOR=OFF \
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
        -DFETCHCONTENT_SOURCE_DIR_PHOTON=/work/photon \
        -DFETCHCONTENT_SOURCE_DIR_E2FSPROGS=/work/e2fsprogs \
        "-DFETCHCONTENT_SOURCE_DIR_EROFS-UTILS=/work/erofs-utils" \
        -DBUILD_STATIC_TOOLS=ON \
        -DBUILD_TCMU=OFF \
        -DBUILD_TESTING=OFF \
        -DENABLE_DSA=OFF \
        -DENABLE_ISAL=OFF \
        -DENABLE_QAT=OFF \
        -DOBD_VER="overlaybd/${RELEASE_VERSION}"

ARG BUILD_JOBS=4
RUN set -eu; \
    log=/tmp/overlaybd-build.log; \
    if cmake --build build --parallel "$BUILD_JOBS" --target \
            overlaybd-create \
            overlaybd-apply \
            overlaybd-commit \
            overlaybd-resize >"$log" 2>&1; then \
        tail -n 20 "$log"; \
    else \
        status=$?; \
        grep -n -E 'FAILED:|[Ee]rror:|Error [0-9]+|undefined reference|not found|Killed|terminated' "$log" || true; \
        tail -n 200 "$log"; \
        exit "$status"; \
    fi

COPY contrib/static/smoke-test.sh /usr/local/bin/overlaybd-static-smoke-test
RUN chmod 0755 /usr/local/bin/overlaybd-static-smoke-test && \
    overlaybd-static-smoke-test source/build/output source/src/example_config/overlaybd.json

RUN set -eu; \
    case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; esac; \
    artifact="overlaybd-tools-${RELEASE_VERSION}-linux-${arch}.tar.gz"; \
    mkdir -p package/bin package/etc/overlaybd package/licenses /out; \
    for tool in overlaybd-create overlaybd-apply overlaybd-commit overlaybd-resize; do \
        install -m 0755 "source/build/output/${tool}" "package/bin/${tool}"; \
        strip "package/bin/${tool}"; \
        if readelf -l "package/bin/${tool}" | grep -q 'Requesting program interpreter'; then \
            echo "error: ${tool} has a dynamic program interpreter" >&2; \
            exit 1; \
        fi; \
        if readelf -d "package/bin/${tool}" 2>/dev/null | grep -q '(NEEDED)'; then \
            echo "error: ${tool} has dynamic library dependencies" >&2; \
            exit 1; \
        fi; \
    done; \
    install -m 0644 source/src/example_config/overlaybd.json package/etc/overlaybd/overlaybd.json; \
    install -m 0644 source/LICENSE package/licenses/overlaybd-LICENSE; \
    printf '%s\n' \
        '{' \
        "  \"releaseVersion\": \"${RELEASE_VERSION}\"," \
        "  \"sourceCommit\": \"${SOURCE_COMMIT}\"," \
        "  \"architecture\": \"${arch}\"," \
        '  "libc": "musl",' \
        '  "sources": {' \
        "    \"ocf\": \"${OCF_COMMIT}\"," \
        "    \"photon\": \"${PHOTON_COMMIT}\"," \
        "    \"e2fsprogs\": \"${E2FSPROGS_COMMIT}\"," \
        "    \"erofsUtils\": \"${EROFS_UTILS_COMMIT}\"" \
        '  }' \
        '}' > package/build-manifest.json; \
    tar --sort=name --owner=0 --group=0 --numeric-owner \
        -czf "/out/${artifact}" -C package .; \
    cd /out; \
    sha256sum "${artifact}" > "${artifact}.sha256"

FROM scratch AS export
COPY --from=builder /out/ /
