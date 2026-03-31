TERMUX_PKG_HOMEPAGE=https://github.com/comrade/termux-build
TERMUX_PKG_DESCRIPTION="Helper commands for this custom Termux build"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="comrade"
TERMUX_PKG_VERSION="0.1.0"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

termux_step_make_install() {
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR/termux-font-mode" "$TERMUX_PREFIX/bin/termux-font-mode"
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR/termux-custom-help" "$TERMUX_PREFIX/bin/termux-custom-help"
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/README.md" "$TERMUX_PREFIX/share/doc/$TERMUX_PKG_NAME/README.md"
}

termux_step_install_license() {
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/LICENSE" "$TERMUX_PREFIX/share/doc/$TERMUX_PKG_NAME/copyright"
}
