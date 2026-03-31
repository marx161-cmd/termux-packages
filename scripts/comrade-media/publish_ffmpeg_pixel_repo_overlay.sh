#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-/home/comrade/termux_build/repo-overlay/termux-main}"
DIST="stable"
COMPONENT="main"
ARCH="aarch64"
OUTPUT_DIR="/home/comrade/termux_build/termux-packages/output"

# Keep the overlay minimal: publish only the packages we actually customized.
CUSTOM_PACKAGES=(
  "ffmpeg_8.0.1-7_aarch64.deb"
  "vapoursynth_73-2_aarch64.deb"
)

usage() {
  cat <<'EOF'
Usage:
  publish_ffmpeg_pixel_repo_overlay.sh [repo_root]

What it does:
  1. stages the custom Pixel media overlay packages into a Termux-style repo tree
  2. writes a manifest of what was staged
  3. if apt-ftparchive and a GPG secret key are available, generates Packages,
     Release, InRelease, and Release.gpg

Notes:
  - This overlay is intentionally minimal. ffmpeg already ships libav*/libsw*
    itself, so the only extra custom package we need is vapoursynth.
  - Unchanged dependencies continue to come from the normal Termux repos.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

repo_dir="${REPO_ROOT%/}/dists/${DIST}/${COMPONENT}/binary-${ARCH}"
pool_dir="${REPO_ROOT%/}/pool/${COMPONENT}"
manifest="${REPO_ROOT%/}/CUSTOM_MEDIA_OVERLAY_MANIFEST.txt"

mkdir -p "$repo_dir" "$pool_dir"

printf 'Staging custom packages into %s\n' "$REPO_ROOT"

for pkg in "${CUSTOM_PACKAGES[@]}"; do
  src="${OUTPUT_DIR}/${pkg}"
  if [[ ! -f "$src" ]]; then
    printf 'Missing expected package: %s\n' "$src" >&2
    exit 1
  fi
  cp -f "$src" "$pool_dir/"
done

cat > "$manifest" <<EOF
Custom Termux media overlay
Generated: $(date -Iseconds)

Repo root:
${REPO_ROOT}

Staged packages:
$(printf '%s\n' "${CUSTOM_PACKAGES[@]}")

Why only these:
- ffmpeg_8.0.1-7 carries the ffmpeg/ffprobe binaries and all libav*/libsw* shared libraries
- vapoursynth_73-2 is locally patched and must be published alongside ffmpeg for --enable-vapoursynth to work

Unchanged dependencies:
- continue to resolve from the regular Termux repositories
EOF

if ! command -v apt-ftparchive >/dev/null 2>&1; then
  cat <<EOF

Overlay staged, but repo metadata was not generated.
Missing host tool: apt-ftparchive

Staged files:
  ${pool_dir}

Manifest:
  ${manifest}
EOF
  exit 0
fi

if ! gpg --list-secret-keys >/dev/null 2>&1 || [[ -z "$(gpg --list-secret-keys --with-colons 2>/dev/null)" ]]; then
  cat <<EOF

Overlay staged, but repo metadata signing was not completed.
Missing GPG secret key for APT repo signing.

Staged files:
  ${pool_dir}

Manifest:
  ${manifest}
EOF
  exit 0
fi

pushd "$REPO_ROOT" >/dev/null

apt-ftparchive packages "pool/${COMPONENT}" > "${repo_dir}/Packages"
gzip -fk "${repo_dir}/Packages"
xz -fk "${repo_dir}/Packages"
zstd -fq --rm -o "${repo_dir}/Packages.zst" "${repo_dir}/Packages"

cat > apt-release.conf <<EOF
APT::FTPArchive::Release {
  Origin "comrade";
  Label "comrade termux media";
  Suite "${DIST}";
  Codename "${DIST}";
  Architectures "${ARCH}";
  Components "${COMPONENT}";
  Description "Custom Termux media overlay for Pixel 10 Pro";
};
EOF

apt-ftparchive -c apt-release.conf release "dists/${DIST}" > "dists/${DIST}/Release"
gpg --batch --yes --clearsign -o "dists/${DIST}/InRelease" "dists/${DIST}/Release"
gpg --batch --yes --detach-sign -o "dists/${DIST}/Release.gpg" "dists/${DIST}/Release"

rm -f apt-release.conf
popd >/dev/null

cat <<EOF

Overlay repo generated successfully.

Repo root:
  ${REPO_ROOT}

APT index path:
  ${repo_dir}

Manifest:
  ${manifest}
EOF
