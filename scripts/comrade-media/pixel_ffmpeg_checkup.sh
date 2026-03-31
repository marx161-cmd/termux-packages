#!/data/data/com.termux/files/usr/bin/bash
set -u

PREFIX="/data/data/com.termux/files/usr"
export PATH="$PREFIX/bin:$PATH"
FFMPEG_BIN="$PREFIX/bin/ffmpeg"
PYTHON_BIN="$PREFIX/bin/python3"

OUT_DIR="${HOME}/ffmpeg-checkup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/report.txt"

exec > >(tee "$REPORT") 2>&1

pass_count=0
fail_count=0

section() {
  printf '\n== %s ==\n' "$1"
}

run_case() {
  local name="$1"
  shift
  local slug
  slug="$(printf '%s' "$name" | tr ' /:' '___' | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')"
  local log="$OUT_DIR/${slug}.log"

  printf '\n-- %s --\n' "$name"
  if "$@" >"$log" 2>&1; then
    printf 'PASS: %s\n' "$name"
    pass_count=$((pass_count + 1))
  else
    printf 'FAIL: %s\n' "$name"
    fail_count=$((fail_count + 1))
  fi

  sed -n '1,120p' "$log"
}

section "Environment"
command -v "$FFMPEG_BIN" || exit 1
command -v "$PYTHON_BIN" || exit 1
printf 'Output dir: %s\n' "$OUT_DIR"
printf 'PATH=%s\n' "$PATH"

section "Static checks"
run_case "ffmpeg version" "$FFMPEG_BIN" -hide_banner -version
run_case "ffmpeg buildconf" "$FFMPEG_BIN" -hide_banner -buildconf
run_case "ffmpeg hwaccels" "$FFMPEG_BIN" -hide_banner -hwaccels
run_case "ffmpeg demuxers vapoursynth" sh -c "\"$FFMPEG_BIN\" -hide_banner -demuxers | grep -i vapoursynth"
run_case "ffmpeg filters gpu related" sh -c "\"$FFMPEG_BIN\" -hide_banner -filters | grep -Ei 'opencl|vulkan|libplacebo'"
run_case "ffmpeg codecs mediacodec" sh -c "\"$FFMPEG_BIN\" -hide_banner -decoders | grep -i mediacodec"

section "Python and VapourSynth"
run_case "python import vapoursynth" "$PYTHON_BIN" -c "import sys; print(sys.version); print(sys.path); import vapoursynth as vs; print(vs.__file__)"

cat > "$OUT_DIR/test.vpy" <<'EOF'
import vapoursynth as vs
core = vs.core
clip = core.std.BlankClip(width=320, height=180, format=vs.RGB24, length=1)
clip.set_output()
EOF

run_case "ffmpeg vapoursynth vpy smoke" \
  "$FFMPEG_BIN" -hide_banner -f vapoursynth -i "$OUT_DIR/test.vpy" -frames:v 1 -y "$OUT_DIR/out.png"

section "GPU device init"
run_case "init vulkan device" \
  "$FFMPEG_BIN" -hide_banner -init_hw_device vulkan=vulkan:0 -f lavfi -i color=s=16x16:r=1 -frames:v 1 -f null -
run_case "init opencl device" \
  "$FFMPEG_BIN" -hide_banner -init_hw_device opencl=opencl:0.0 -f lavfi -i color=s=16x16:r=1 -frames:v 1 -f null -

section "GPU filter smoke tests"
run_case "vulkan scale filter" \
  "$FFMPEG_BIN" -hide_banner \
    -init_hw_device vulkan=vulkan:0 -filter_hw_device vulkan \
    -f lavfi -i testsrc2=size=128x72:rate=1 \
    -vf "format=yuv420p,hwupload,scale_vulkan=w=64:h=36,hwdownload,format=yuv420p" \
    -frames:v 1 -f null -

run_case "vulkan libplacebo filter presence" \
  sh -c "\"$FFMPEG_BIN\" -hide_banner -filters | grep -i libplacebo"

run_case "opencl blur filter" \
  "$FFMPEG_BIN" -hide_banner \
    -init_hw_device opencl=opencl:0.0 -filter_hw_device opencl \
    -f lavfi -i testsrc2=size=128x72:rate=1 \
    -vf "format=rgba,hwupload,avgblur_opencl=3,hwdownload,format=rgba" \
    -frames:v 1 -f null -

section "MediaCodec smoke"
run_case "generate sample h264" \
  "$FFMPEG_BIN" -hide_banner -f lavfi -i testsrc2=size=128x72:rate=30 -t 1 -c:v libx264 -pix_fmt yuv420p -y "$OUT_DIR/sample.mp4"

run_case "mediacodec decode sample" \
  "$FFMPEG_BIN" -hide_banner \
    -hwaccel mediacodec -hwaccel_output_format mediacodec \
    -i "$OUT_DIR/sample.mp4" \
    -frames:v 1 -f null -

section "Summary"
printf 'PASS=%d FAIL=%d\n' "$pass_count" "$fail_count"
printf 'Report: %s\n' "$REPORT"
printf 'Artifacts: %s\n' "$OUT_DIR"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
