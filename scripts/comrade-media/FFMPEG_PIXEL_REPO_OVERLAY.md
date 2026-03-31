## Pixel FFmpeg Overlay Repo

Current known-good custom packages:

- `ffmpeg_8.0.1-7_aarch64.deb`
- `vapoursynth_73-2_aarch64.deb`

Why the overlay is minimal:

- `ffmpeg_8.0.1-7` already ships `ffmpeg`, `ffprobe`, and all `libav*` / `libsw*` shared libraries.
- `vapoursynth_73-2` must be shipped alongside it because the Termux package was locally patched to include the native C API, shared libraries, and pkg-config files that FFmpeg expects.
- Other dependencies can continue to resolve from the normal Termux repositories because their package contents and versions were not customized for runtime delivery.

Repo helper:

- `publish_ffmpeg_pixel_repo_overlay.sh`

Current host-side publish blockers:

- `apt-ftparchive` is not currently available on the host path.
- No OpenPGP secret key is currently available in `gpg --list-secret-keys` for APT repository signing.

So the current status is:

1. the exact overlay package set is identified
2. staging layout is scripted
3. full signed repo publication only needs the index tool and repo-signing key
