#!/usr/bin/env bash

set -euo pipefail

TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
STACK_ROOT="${STACK_ROOT:-$TERMUX_PREFIX/local/max-media/pixel10pro-a16}"
PREFIX="${PREFIX:-$STACK_ROOT/ffmpeg}"
VENDOR_PREFIX="${VENDOR_PREFIX:-$STACK_ROOT/vendor-termux}"
SRC_ROOT="${SRC_ROOT:-$HOME/src/android-media}"
FFMPEG_DIR="${FFMPEG_DIR:-$SRC_ROOT/FFmpeg-master}"
JOBS="${JOBS:-$(nproc)}"
UPDATE_SOURCES="${UPDATE_SOURCES:-1}"
INSTALL_BUILD_TOOLS="${INSTALL_BUILD_TOOLS:-0}"
MIRROR_REUSED_DEPS="${MIRROR_REUSED_DEPS:-0}"
ALLOW_TERMUX_FALLBACK="${ALLOW_TERMUX_FALLBACK:-1}"

readonly DEVICE_PROFILE="pixel10pro-a16"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

require_termux() {
    if [[ ! -d "$TERMUX_PREFIX" ]]; then
        echo "Termux prefix not found: $TERMUX_PREFIX" >&2
        exit 1
    fi
}

install_build_tools() {
    pkg update -y
    pkg install -y \
        binutils \
        clang \
        cmake \
        git \
        make \
        nasm \
        ninja \
        pkg-config \
        python \
        yasm
}

ensure_checkout() {
    local dir="$1"
    local remote="$2"
    local branch="$3"

    if [[ ! -d "$dir/.git" ]]; then
        rm -rf "$dir"
        git clone --depth 1 --branch "$branch" "$remote" "$dir"
        return
    fi

    git -C "$dir" fetch --all --tags --prune
    git -C "$dir" checkout "$branch"
    git -C "$dir" pull --ff-only
}

prepare_dirs() {
    mkdir -p "$STACK_ROOT" "$PREFIX" "$VENDOR_PREFIX" "$SRC_ROOT"
    mkdir -p "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/include" "$PREFIX/share"
    mkdir -p "$VENDOR_PREFIX/lib" "$VENDOR_PREFIX/include" "$VENDOR_PREFIX/share"
}

copy_if_exists() {
    local path="$1"
    local dest="$2"
    if [[ -e "$path" ]]; then
        mkdir -p "$dest"
        cp -a "$path" "$dest/"
    fi
}

mirror_pkgconfig_module() {
    local module="$1"
    local pc_dir include_dir lib_dir

    pc_dir="$(pkg-config --variable=pcfiledir "$module" 2>/dev/null || true)"
    include_dir="$(pkg-config --variable=includedir "$module" 2>/dev/null || true)"
    lib_dir="$(pkg-config --variable=libdir "$module" 2>/dev/null || true)"

    if [[ -n "$pc_dir" && -f "$pc_dir/$module.pc" ]]; then
        mkdir -p "$VENDOR_PREFIX/lib/pkgconfig"
        cp -a "$pc_dir/$module.pc" "$VENDOR_PREFIX/lib/pkgconfig/"
    fi

    if [[ -n "$include_dir" && -d "$include_dir" ]]; then
        rsync -a --delete "$include_dir/" "$VENDOR_PREFIX/include/"
    fi

    if [[ -n "$lib_dir" && -d "$lib_dir" ]]; then
        mkdir -p "$VENDOR_PREFIX/lib"
        find "$lib_dir" -maxdepth 1 -type f \
            \( -name '*.so' -o -name '*.so.*' -o -name '*.a' \) \
            -exec cp -a {} "$VENDOR_PREFIX/lib/" \;
    fi
}

mirror_reused_deps() {
    local -a modules=(
        aom
        dav1d
        fribidi
        freetype2
        harfbuzz
        libass
        libplacebo
        libpng
        libvorbis
        libvpx
        libwebp
        ogg
        openjpeg-2.5
        opus
        rav1e
        vapoursynth-script
        vulkan
        x264
        x265
        zimg
    )

    rm -rf "$VENDOR_PREFIX"
    mkdir -p "$VENDOR_PREFIX/lib" "$VENDOR_PREFIX/include" "$VENDOR_PREFIX/share"

    for module in "${modules[@]}"; do
        if pkg-config --exists "$module"; then
            mirror_pkgconfig_module "$module"
        fi
    done

    copy_if_exists "$TERMUX_PREFIX/lib/libOpenCL.so" "$VENDOR_PREFIX/lib"
    copy_if_exists "$TERMUX_PREFIX/include/CL" "$VENDOR_PREFIX/include"
    copy_if_exists "$TERMUX_PREFIX/include/vulkan" "$VENDOR_PREFIX/include"
}

configure_paths() {
    local -a pkg_paths
    pkg_paths=()

    if [[ "$MIRROR_REUSED_DEPS" == "1" ]]; then
        pkg_paths+=("$VENDOR_PREFIX/lib/pkgconfig" "$VENDOR_PREFIX/share/pkgconfig")
    fi

    if [[ "$ALLOW_TERMUX_FALLBACK" == "1" ]]; then
        pkg_paths+=("$TERMUX_PREFIX/lib/pkgconfig" "$TERMUX_PREFIX/share/pkgconfig")
    fi

    export PKG_CONFIG_PATH
    PKG_CONFIG_PATH="$(IFS=:; echo "${pkg_paths[*]}")"

    export CPPFLAGS
    export CFLAGS
    export CXXFLAGS
    export LDFLAGS
    export LD_LIBRARY_PATH

    CPPFLAGS="-I$PREFIX/include"
    CFLAGS="-O3 -fPIC -march=armv8-a -mtune=generic"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
    LD_LIBRARY_PATH="$PREFIX/lib"

    if [[ "$MIRROR_REUSED_DEPS" == "1" ]]; then
        CPPFLAGS="$CPPFLAGS -I$VENDOR_PREFIX/include"
        LDFLAGS="$LDFLAGS -L$VENDOR_PREFIX/lib -Wl,-rpath,$VENDOR_PREFIX/lib"
        LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$VENDOR_PREFIX/lib"
    fi

    if [[ "$ALLOW_TERMUX_FALLBACK" == "1" ]]; then
        CPPFLAGS="$CPPFLAGS -I$TERMUX_PREFIX/include"
        LDFLAGS="$LDFLAGS -L$TERMUX_PREFIX/lib -Wl,-rpath,$TERMUX_PREFIX/lib"
        LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$TERMUX_PREFIX/lib"
    fi
}

configure_ffmpeg() {
    local -a flags=(
        --prefix="$PREFIX"
        --pkg-config=pkg-config
        --target-os=android
        --arch=aarch64
        --cpu=armv8-a
        --enable-cross-compile
        --cc=clang
        --cxx=clang++
        --nm=llvm-nm
        --ar=llvm-ar
        --ranlib=llvm-ranlib
        --strip=llvm-strip
        --extra-cflags="$CPPFLAGS $CFLAGS"
        --extra-cxxflags="$CPPFLAGS $CXXFLAGS"
        --extra-ldflags="$LDFLAGS"
        --enable-gpl
        --enable-version3
        --enable-shared
        --disable-static
        --disable-stripping
        --enable-jni
        --enable-mediacodec
        --enable-vulkan
        --enable-opencl
        --enable-libplacebo
        --enable-libass
        --enable-libfreetype
        --enable-libfribidi
        --enable-libharfbuzz
        --enable-libzimg
        --enable-vapoursynth
        --enable-libx264
        --enable-libx265
        --enable-libaom
        --enable-libdav1d
        --enable-librav1e
        --enable-libvpx
        --enable-libopus
        --enable-libvorbis
        --enable-libwebp
        --enable-libopenjpeg
    )

    cd "$FFMPEG_DIR"
    make distclean >/dev/null 2>&1 || true
    ./configure "${flags[@]}"
}

build_ffmpeg() {
    cd "$FFMPEG_DIR"
    make -j"$JOBS"
    make install
}

verify_ffmpeg() {
    export PATH="$PREFIX/bin:$PATH"
    export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"

    "$PREFIX/bin/ffmpeg" -hide_banner -version
    "$PREFIX/bin/ffmpeg" -hide_banner -buildconf
    "$PREFIX/bin/ffmpeg" -hide_banner -hwaccels | grep -Ei 'mediacodec|opencl|vulkan'
    "$PREFIX/bin/ffmpeg" -hide_banner -filters | grep -Ei 'opencl|vulkan|placebo|vapoursynth'
}

main() {
    require_termux
    require_cmd git
    require_cmd pkg-config
    require_cmd make
    require_cmd clang

    if [[ "$INSTALL_BUILD_TOOLS" == "1" ]]; then
        install_build_tools
    fi

    prepare_dirs

    if [[ "$UPDATE_SOURCES" == "1" ]]; then
        ensure_checkout "$FFMPEG_DIR" https://github.com/FFmpeg/FFmpeg.git master
    fi

    if [[ "$MIRROR_REUSED_DEPS" == "1" ]]; then
        mirror_reused_deps
    fi

    configure_paths
    configure_ffmpeg
    build_ffmpeg
    verify_ffmpeg

    cat <<EOF
Built FFmpeg for $DEVICE_PROFILE
Install prefix: $PREFIX
Dependency mirror: $VENDOR_PREFIX
MIRROR_REUSED_DEPS=$MIRROR_REUSED_DEPS
ALLOW_TERMUX_FALLBACK=$ALLOW_TERMUX_FALLBACK
EOF
}

main "$@"
