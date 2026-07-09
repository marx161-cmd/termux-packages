TERMUX_PKG_HOMEPAGE=https://ffmpeg.org
TERMUX_PKG_DESCRIPTION="Tools and libraries to manipulate a wide range of multimedia formats and protocols"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
# Please align version with `ffplay` package.
TERMUX_PKG_VERSION="8.1.2"
TERMUX_PKG_SRCURL="https://www.ffmpeg.org/releases/ffmpeg-${TERMUX_PKG_VERSION}.tar.xz"
TERMUX_PKG_SHA256=464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c
TERMUX_PKG_DEPENDS="fontconfig, freetype, fribidi, game-music-emu, glslang, harfbuzz, libaom, libandroid-glob, libandroid-stub, libass, libbluray, libbs2b, libbz2, libdav1d, libiconv, libjxl, liblzma, libmysofa, libmp3lame, libopencore-amr, libopenmpt, libopus, libplacebo, librav1e, libsoxr, libsrt, libssh, libtheora, libv4l, libvidstab, libvmaf, libvo-amrwbenc, libvorbis, libvpx, libwebp, libx264, libx265, libxml2, libzimg, libzmq, littlecms, ocl-icd, openjpeg, openssl, rubberband, svt-av1, vapoursynth, vulkan-loader-android, xvidcore, zlib"
TERMUX_PKG_BUILD_DEPENDS="opencl-headers, vulkan-headers"
TERMUX_PKG_CONFLICTS="libav"
TERMUX_PKG_BREAKS="ffmpeg-dev"
TERMUX_PKG_REPLACES="ffmpeg-dev"

termux_step_pre_configure() {
	# Do not forget to bump revision of reverse dependencies and rebuild them
	# after SOVERSION is changed. (These variables are also used afterwards.)
	declare -gA _FFMPEG_SOVER=(
		[avutil]=60
		[avcodec]=62
		[avformat]=62
	)

	local lib so_version
	for lib in util codec format; do
		so_version=$(sh ffbuild/libversion.sh av${lib} \
				libav${lib}/version.h libav${lib}/version_major.h \
				| sed -En 's/^libav'"${lib}"'_VERSION_MAJOR=([0-9]+)$/\1/p')
		if [[ ! "${so_version}"  ||  "${_FFMPEG_SOVER[av${lib}]}" != "${so_version}" ]]; then
			termux_error_exit "SOVERSION guard check failed for libav${lib}.so. expected ${so_version}"
		fi
	done

	if [[ "$TERMUX_ARCH" == "aarch64" ]]; then
		CFLAGS+=" -O2 -march=armv8.4-a"
		CXXFLAGS+=" -O2 -march=armv8.4-a"
	fi

	# ffmpeg's configure looks for 'opencv.pc' but Termux ships 'opencv4.pc'.
	# Create a compatibility symlink so the pkg-config check succeeds.
	if [ -f "${TERMUX_PREFIX}/lib/pkgconfig/opencv4.pc" ] && \
	   [ ! -f "${TERMUX_PREFIX}/lib/pkgconfig/opencv.pc" ]; then
		ln -sf "${TERMUX_PREFIX}/lib/pkgconfig/opencv4.pc" \
		       "${TERMUX_PREFIX}/lib/pkgconfig/opencv.pc"
	fi
	# opencv4 headers live under include/opencv4/, not include/ directly.
	CFLAGS+=" -I${TERMUX_PREFIX}/include/opencv4"
	CXXFLAGS+=" -I${TERMUX_PREFIX}/include/opencv4"

	# libavdevice uses Termux shmem shims (libandroid_shmget etc.) which come
	# from libandroid-shmem.  Must be in LDFLAGS so the flag reaches shared-lib
	# link commands, not just the final executable link.
	LDFLAGS+=" -landroid-shmem"
}

termux_step_configure() {
	cd $TERMUX_PKG_BUILDDIR

	local _EXTRA_CONFIGURE_FLAGS=""
	case "$TERMUX_ARCH" in
		"aarch64")
			_ARCH="$TERMUX_ARCH"
			# Android NDK ioctl uses unsigned long but v4l2.c casts to int,
			# causing a fatal -Wincompatible-function-pointer-types error.
			# V4L2 is also unusable on Android anyway.
			_EXTRA_CONFIGURE_FLAGS="--disable-indev=v4l2 --disable-outdev=v4l2 --disable-libv4l2"
		;;
		"arm")
			_ARCH="armeabi-v7a"
			_EXTRA_CONFIGURE_FLAGS="--enable-neon"
		;;
		"i686")
			_ARCH="x86"
			# Specify --disable-asm to prevent text relocations on i686,
			# see https://trac.ffmpeg.org/ticket/4928
			_EXTRA_CONFIGURE_FLAGS="--disable-asm"
		;;
		"x86_64")
			_ARCH="x86_64"
		;;
		*) termux_error_exit "Unsupported arch: $TERMUX_ARCH";;
	esac

	# Prefer OpenSSL when available, then GnuTLS, then mbedTLS.
	if "$PKG_CONFIG" --exists openssl; then
		_CONFIG_FLAGS+=(--enable-openssl)
	elif "$PKG_CONFIG" --exists gnutls; then
		_CONFIG_FLAGS+=(--enable-gnutls)
	elif "$PKG_CONFIG" --exists mbedtls; then
		_CONFIG_FLAGS+=(--enable-mbedtls)
	fi

	# Enable optional libraries opportunistically, keeping the profile maximal
	# while still buildable with the currently available cross sysroot.
	local _feature _flag _pc
	for _feature in \
		"--enable-libaom:aom" \
		"--enable-libass:libass" \
		"--enable-libbluray:libbluray" \
		"--enable-libbs2b:libbs2b" \
		"--enable-libcaca:caca" \
		"--enable-libdav1d:dav1d" \
		"--enable-libdvdnav:dvdnav" \
		"--enable-libdvdread:dvdread" \
		"--enable-libfdk-aac:fdk-aac" \
		"--enable-libfontconfig:fontconfig" \
		"--enable-libfreetype:freetype2" \
		"--enable-libfribidi:fribidi" \
		"--enable-gcrypt:libgcrypt" \
		"--enable-libgme:libgme" \
		"--enable-libharfbuzz:harfbuzz" \
		"--enable-libjxl:libjxl" \
		"--enable-libmodplug:libmodplug" \
		"--enable-libmp3lame:lame" \
		"--enable-libopencore-amrnb:opencore-amrnb" \
		"--enable-libopencore-amrwb:opencore-amrwb" \
		"--enable-libopenh264:openh264" \
		"--enable-libopenjpeg:libopenjp2" \
		"--enable-libopenmpt:libopenmpt" \
		"--enable-libopus:opus" \
		"--enable-libplacebo:libplacebo" \
		"--enable-librav1e:rav1e" \
		"--enable-librubberband:rubberband" \
		"--enable-libsoxr:soxr" \
		"--enable-libsrt:srt" \
		"--enable-libssh:libssh" \
		"--enable-libsnappy:snappy" \
		"--enable-libsvtav1:SvtAv1Enc" \
		"--enable-libtesseract:tesseract" \
		"--enable-libtheora:theora" \
		"--enable-libv4l2:libv4l2" \
		"--enable-libvidstab:vidstab" \
		"--enable-libvmaf:libvmaf" \
		"--enable-libvo-amrwbenc:vo-amrwbenc" \
		"--enable-libvorbis:vorbis" \
		"--enable-libvpx:vpx" \
		"--enable-libwebp:libwebp" \
		"--enable-libx264:x264" \
		"--enable-libx265:x265" \
		"--enable-libxml2:libxml-2.0" \
		"--enable-libxvid:xvidcore" \
		"--enable-libzimg:zimg" \
		"--enable-libzmq:libzmq" \
		"--enable-opencl:OpenCL" \
		"--enable-libpulse:libpulse" \
		"--enable-openal:openal" \
		"--enable-opengl:egl" \
		"--enable-vapoursynth:vapoursynth-script" \
		"--enable-frei0r:frei0r" \
		"--enable-lv2:lv2" \
		"--enable-libopencv:opencv4" \
		"--enable-libshaderc:shaderc" \
		"--enable-libglslang:glslang"; do
		_flag="${_feature%%:*}"
		_pc="${_feature#*:}"
		if "$PKG_CONFIG" --exists "${_pc}"; then
			_CONFIG_FLAGS+=("${_flag}")
		fi
	done

	if [[ " ${_CONFIG_FLAGS[*]} " == *" --enable-libfdk-aac "* ]]; then
		_CONFIG_FLAGS+=(--enable-nonfree)
	fi

	$TERMUX_PKG_SRCDIR/configure \
		--arch="${_ARCH}" \
		--as="$AS" \
		--cc="$CC" \
		--cxx="$CXX" \
		--nm="$NM" \
		--ar="$AR" \
		--ranlib="llvm-ranlib" \
		--pkg-config="$PKG_CONFIG" \
		--strip="$STRIP" \
		--cross-prefix="${TERMUX_HOST_PLATFORM}-" \
		--disable-static \
		--disable-symver \
		--enable-cross-compile \
		--enable-gpl \
		--enable-version3 \
		--disable-libsmbclient \
		--enable-jni \
		--enable-ladspa \
		--enable-lcms2 \
		--enable-libaom \
		--enable-libass \
		--enable-libbluray \
		--enable-libbs2b \
		--enable-libdav1d \
		--enable-libfontconfig \
		--enable-libfreetype \
		--enable-libfribidi \
		--enable-libglslang \
		--enable-libgme \
		--enable-libharfbuzz \
		--enable-libmysofa \
		--enable-libmp3lame \
		--enable-libopencore-amrnb \
		--enable-libopencore-amrwb \
		--enable-libopenmpt \
		--enable-libopus \
		--enable-libplacebo \
		--enable-librav1e \
		--enable-librubberband \
		--enable-libsoxr \
		--enable-libsrt \
		--enable-libssh \
		--enable-libsvtav1 \
		--enable-libtheora \
		--enable-libv4l2 \
		--enable-libvidstab \
		--enable-libvmaf \
		--enable-libvo-amrwbenc \
		--enable-libvorbis \
		--enable-libvpx \
		--enable-libwebp \
		--enable-libx264 \
		--enable-libx265 \
		--enable-libxml2 \
		--enable-libxvid \
		--enable-libzimg \
		--enable-libzmq \
		--enable-mediacodec \
		--enable-opencl \
		--enable-openssl \
		"${_CONFIG_FLAGS[@]}" \
		--enable-shared \
		--prefix="$TERMUX_PREFIX" \
		--target-os=android \
		--extra-libs="-landroid-glob" \
		--enable-vulkan \
		$_EXTRA_CONFIGURE_FLAGS \
		--disable-libfdk-aac
}

termux_step_post_massage() {
	cd "${TERMUX_PKG_MASSAGEDIR}/${TERMUX_PREFIX}/lib" || termux_error_exit "couldn't symlink shared libraries."
	local lib so_version
	for lib in util codec format; do
		so_version="${_FFMPEG_SOVER[av${lib}]}"
		if [[ ! "${so_version}" ]]; then
			termux_error_exit "Empty SOVERSION for libav${lib}."
		fi
		# SOVERSION suffix is expected by some programs, e.g. Firefox.
		if [[ ! -e "./libav${lib}.so.${so_version}" ]]; then
			ln -sf "libav${lib}.so" "libav${lib}.so.${so_version}"
		fi
	done

	# ── RPATH BUNDLE ─────────────────────────────────────────────────────────
	# Copy every third-party .so that the av*/sw* libs transitively depend on
	# into a private ffmpeg-bundle/ directory, then rewrite RPATHs so the
	# dynamic linker prefers those private copies.  This means future
	# "pkg install libx264" updates cannot silently break ffmpeg.
	#
	# NOTE: in the massagedir the av* libs appear as symlinks (libavcodec.so
	# → libavcodec.so.62).  patchelf and cp both follow symlinks, so we do
	# NOT exclude -L files from the queue or the patchelf loops.
	local _mdir="${TERMUX_PKG_MASSAGEDIR}${TERMUX_PREFIX}"
	local _bundle="${_mdir}/lib/ffmpeg-bundle"
	mkdir -p "${_bundle}"

	# Libs that must NOT be bundled — Android/Bionic system libs or GPU ICD
	# loaders that must resolve to the device's own driver stack at runtime.
	# Keep libc++_shared.so bundled: Android's linker does not reliably use a
	# bundled library's RUNPATH fallback to Termux's lib dir for transitive deps.
	# Patterns are unquoted in [[ ]] so glob wildcards match versioned sonames
	# (e.g. "libz.so*" catches libz.so.1).
	local -a _skip=(
		libc.so libm.so libdl.so
		"libz.so*"
		liblog.so libandroid.so "ld-android.so"
		libEGL.so "libGLES*.so"
		libOpenSLES.so libOpenMAXAL.so
		libmediandk.so libcamera2ndk.so libaaudio.so
		"libvulkan.so*"
		"libOpenCL.so*"
	)

	# BFS over the transitive dep graph starting from our av*/sw* libs.
	declare -A _seen
	local -a _queue=()
	for _lib in "${_mdir}/lib"/libav*.so "${_mdir}/lib"/libsw*.so; do
		if [[ -f "${_lib}" ]]; then
			_queue+=("${_lib}")
		fi
	done

	while [[ ${#_queue[@]} -gt 0 ]]; do
		local _cur="${_queue[0]}"
		_queue=("${_queue[@]:1}")

		while read -r _dep; do
			# Skip already-visited deps.
			if [[ -n "${_seen[${_dep}]+x}" ]]; then continue; fi

			# Skip system/ICD libs — unquoted _s so glob patterns match.
			local _skip_it=0
			for _s in "${_skip[@]}"; do
				# shellcheck disable=SC2053
				if [[ "${_dep}" == ${_s} ]]; then _skip_it=1; break; fi
			done
			if [[ "${_skip_it}" == 1 ]]; then continue; fi

			# Our own libs find each other via rpath — no need to bundle.
			# Match both unversioned (libavcodec.so) and versioned (libavcodec.so.62).
			case "${_dep}" in
				libav*.so|libav*.so.*|libsw*.so|libsw*.so.*) continue ;;
			esac

			_seen["${_dep}"]=1

			# Resolve DT_NEEDED name to a real file in the cross sysroot,
			# copy under the original name so the loader finds it.
			local _src="${TERMUX_PREFIX}/lib/${_dep}"
			if [[ -L "${_src}" ]]; then _src="$(readlink -f "${_src}")"; fi

			if [[ -f "${_src}" ]]; then
				cp --update=none "${_src}" "${_bundle}/${_dep}"
				_queue+=("${_bundle}/${_dep}")
			fi
		done < <(patchelf --print-needed "${_cur}" 2>/dev/null || true)
	done

	# Bundled deps: find each other within the bundle directory.
	# $ORIGIN/../lib provides fallback to the Termux lib dir (/usr/lib) for
	# skip-listed Termux system libs like libc++_shared.so that are not bundled.
	# Glob both *.so (unversioned) and *.so.* (versioned, e.g. libcrypto.so.3).
	for _lib in "${_bundle}"/*.so "${_bundle}"/*.so.*; do
		if [[ -f "${_lib}" ]]; then patchelf --set-rpath '$ORIGIN:$ORIGIN/../lib' "${_lib}"; fi
	done

	# av*/sw* shared libs: bundle dir first, then sibling lib/ for anything
	# deliberately left unbundled (libc++, libvulkan, libz, …).
	# patchelf follows the .so symlinks to the real versioned .so.N files.
	for _lib in "${_mdir}/lib"/libav*.so "${_mdir}/lib"/libsw*.so; do
		if [[ -f "${_lib}" ]]; then
			patchelf --set-rpath '$ORIGIN/ffmpeg-bundle:$ORIGIN' "${_lib}"
		fi
	done

	# Executables.
	for _bin in ffmpeg ffprobe ffplay; do
		local _bp="${_mdir}/bin/${_bin}"
		if [[ -f "${_bp}" ]]; then
			patchelf --set-rpath '$ORIGIN/../lib/ffmpeg-bundle:$ORIGIN/../lib' "${_bp}"
		fi
	done
}

termux_step_create_debscripts() {
	# See: https://github.com/termux/termux-packages/issues/23189#issuecomment-2663464359
	# See also: https://github.com/termux/termux-packages/wiki/Termux-execution-environment#dynamic-library-linking-errors
	sed -e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
		"$TERMUX_PKG_BUILDER_DIR/postinst.sh.in" > ./postinst
	chmod +x ./postinst
}
