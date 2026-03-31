# Pixel 10 Pro Android 16 FFmpeg Max Plan

Purpose: define a reproducible Android/Termux media stack for the rooted Pixel 10 Pro without mixing random host or app-state dependencies into the final build.

## Device profile
- Model: `Pixel 10 Pro`
- Android: `16`
- SDK: `36`
- ABI: `arm64-v8a`
- SoC: `Tensor G5`
- Board: `laguna`
- Graphics stack: `powervr`

## Runtime facts verified on-device
- Vulkan loader: `/system/lib64/libvulkan.so`
- Vulkan HAL: `/vendor/lib64/hw/vulkan.powervr.so`
- EGL vendor libs:
  - `/vendor/lib64/egl/libEGL_powervr.so`
  - `/vendor/lib64/egl/libGLESv2_powervr.so`
- OpenCL libs:
  - `/vendor/lib64/libOpenCL.so`
  - `/vendor/lib64/libOpenCL-pixel.so`
  - `/vendor/lib64/libPVROCL.so`
- Termux prefix: `/data/data/com.termux/files/usr`

## Build targets
- Daily-use profile: `max-practical-pixel`
- Keep from day one:
  - `vulkan`
  - `mediacodec`
  - `libplacebo`
  - `vapoursynth`
  - `opencl`
- Exclude as irrelevant on this device:
  - `amf`
  - `vaapi`
  - `vdpau`
  - `nvenc`
  - `cuda`

## Prefix layout
- Custom install root: `/data/data/com.termux/files/usr/local/max-media/pixel10pro-a16`
- FFmpeg install prefix: `/data/data/com.termux/files/usr/local/max-media/pixel10pro-a16/ffmpeg`
- Optional mirrored dependency root:
  - `/data/data/com.termux/files/usr/local/max-media/pixel10pro-a16/vendor-termux`

Rule: the final FFmpeg binary should install into the custom prefix, not over the normal Termux prefix.

## Dependency policy
- First choice: use current Termux packages as the build base.
- Second choice: mirror reused headers, pkg-config files, and shared libs into `vendor-termux` so the build has a frozen dependency snapshot.
- Do not link against arbitrary libraries outside:
  - the custom FFmpeg prefix
  - the mirrored dependency root when enabled
  - the normal Termux prefix only while bootstrapping

## Core dependency tiers
1. Base text/render/filter deps
- `freetype`
- `harfbuzz`
- `fribidi`
- `libass`
- `zimg`
- `libplacebo`
- `vapoursynth`

2. Codec deps
- `x264`
- `x265`
- `libvpx`
- `dav1d`
- `aom`
- `rav1e`
- `svt-av1` if Termux packaging/runtime stays sane
- `opus`
- `vorbis`
- `mp3lame`

3. Android-specific accel surface
- `vulkan`
- `mediacodec`
- `opencl`

## FFmpeg feature goals
- `--enable-vulkan`
- `--enable-opencl`
- `--enable-libplacebo`
- `--enable-vapoursynth`
- `--enable-mediacodec`
- `--enable-jni`
- `--enable-libx264`
- `--enable-libx265`
- `--enable-libaom`
- `--enable-libdav1d`
- `--enable-librav1e`
- `--enable-libvpx`
- `--enable-libopus`
- `--enable-libvorbis`
- `--enable-libass`
- `--enable-libzimg`

## Suggested workflow
1. Build or install Termux dependency packages.
2. Optionally mirror dependency artefacts into `vendor-termux`.
3. Build FFmpeg into the custom prefix.
4. Verify:
   - `ffmpeg -version`
   - `ffmpeg -buildconf`
   - `ffmpeg -hwaccels`
   - `ffmpeg -filters | grep -Ei 'opencl|vulkan|placebo|vapoursynth'`
   - `ffmpeg -codecs | grep -Ei 'mediacodec|av1|h264|hevc'`
5. Run smoke tests:
   - one Vulkan filter
   - one OpenCL filter
   - one MediaCodec decode or encode probe
   - one VapourSynth load probe

## OpenCL stance
- OpenCL is included in the first build on purpose.
- Reason: the device exposes vendor OpenCL userspace, and the goal is to surface regressions or newly enabled Android features early.
- Build success is not enough; runtime filter probes must be part of the verification path.

## Next layers
- `whisper.cpp` as a separate Android build after FFmpeg is stable
- `mpv` or `mpv-x` after FFmpeg + libplacebo + vapoursynth are clean
