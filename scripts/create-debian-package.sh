#!/bin/bash
# Autononext Debian x64 Package Builder
# Creates a .deb package for Autononext Linux desktop application
#
# Usage: ./scripts/create-debian-package.sh
# Requirements: Flutter SDK, dpkg-deb

set -e

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/linux/x64/release"
DIST_DIR="$PROJECT_DIR/dist/debian-x64"
BUILD_ROOT="/tmp/autononext-build-$$"  # Unique temp directory

# === Configuration ===
APP_NAME="autononext"
VERSION=$(grep '^version:' "$PROJECT_DIR/pubspec.yaml" | awk '{print $2}')

# `0.4.0-b1` means "beta build 1". Debian reads `-` as the upstream/revision
# separator, so a literal `0.4.0-b1` is upstream 0.4.0 + revision b1 and sorts
# ABOVE the 0.4.0 release — a beta that can never be upgraded to the release.
# `~` sorts below, which is what a prerelease should do, so map the build suffix
# onto it. Verified with: dpkg --compare-versions 0.4.0~b1 lt 0.4.0
DEB_VERSION="${VERSION/-b/~b}"
ARCH="amd64"
MAINTAINER="Autononext Team"
DESCRIPTION="A Linux package manager for GitHub releases"

# Flutter path (detect system flutter or use hardcoded local path as fallback)
if command -v flutter &> /dev/null; then
    FLUTTER_PATH=$(which flutter)
else
    FLUTTER_PATH="/home/mxadm/fvm/versions/stable/bin/flutter"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

cleanup() {
    rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

check_dependencies() {
    log_step "Checking dependencies..."
    
    if [ ! -f "$FLUTTER_PATH" ]; then
        log_error "Flutter SDK not found at $FLUTTER_PATH"
        exit 1
    fi
    
    if ! command -v dpkg-deb &> /dev/null; then
        log_error "dpkg-deb not found. Install: sudo apt-get install dpkg-dev"
        exit 1
    fi
    
    log_info "All dependencies found ✓"
}

build_flutter() {
    log_step "Building Flutter Linux release..."
    
    log_info "Preparing Flutter build..."
    if [ "$GITHUB_ACTIONS" != "true" ]; then
        log_info "Cleaning Flutter cache..."
        "$FLUTTER_PATH" clean
        log_info "Getting dependencies..."
        "$FLUTTER_PATH" pub get
    fi
    
    "$FLUTTER_PATH" build linux --release
    
    if [ ! -d "$BUILD_DIR" ]; then
        log_error "Build failed - output directory not found: $BUILD_DIR"
        log_info "Current directory contents:"
        ls -la
        log_info "Build directory contents (if any):"
        ls -R build/ 2>/dev/null || echo "Build directory is empty"
        exit 1
    fi
    
    log_info "Flutter build completed ✓"
}

create_debian_structure() {
    log_step "Creating Debian package structure in /tmp..."
    
    # Create build structure in /tmp (avoids permission issues)
    rm -rf "$BUILD_ROOT"
    mkdir -p "$BUILD_ROOT/DEBIAN"
    mkdir -p "$BUILD_ROOT/opt/$APP_NAME"
    mkdir -p "$BUILD_ROOT/usr/share/applications"
    
    # Copy only the release bundle (exclude CMake/ninja build intermediates)
    cp -r "$BUILD_DIR/bundle" "$BUILD_ROOT/opt/$APP_NAME/"
    
    # Create control file
    cat > "$BUILD_ROOT/DEBIAN/control" << EOF
Package: $APP_NAME
Version: $DEB_VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Depends: libgtk-3-0, libblkid1, liblzma5, libcurl4, libfreetype6
Maintainer: $MAINTAINER
Description: $DESCRIPTION
  Autononext helps you manage and install applications from GitHub releases.
EOF

# Create postinst script
cat > "$BUILD_ROOT/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
# Create symlink to /usr/local/bin for command-line access
ln -sf /opt/autononext/bundle/autononext /usr/local/bin/autononext
# Update desktop database
if [ -d "/usr/share/applications" ]; then
    update-desktop-database /usr/share/applications || true
fi
# Update icon cache
if [ -d "/usr/share/icons/hicolor" ]; then
    touch /usr/share/icons/hicolor
    if command -v update-icon-caches &> /dev/null; then
        update-icon-caches /usr/share/icons/hicolor || true
    else
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
    fi
fi
echo "Autononext installed successfully!"
echo "You can now run 'autononext' from the command line or find it in your applications menu."
exit 0
EOF
chmod 0755 "$BUILD_ROOT/DEBIAN/postinst"

# Create prerm script
cat > "$BUILD_ROOT/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e
echo "Removing Autononext..."
exit 0
EOF
chmod 0755 "$BUILD_ROOT/DEBIAN/prerm"

# Create postrm script
cat > "$BUILD_ROOT/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e
# Remove symlink on uninstall
rm -f /usr/local/bin/autononext
# Update desktop database
if [ -d "/usr/share/applications" ]; then
    update-desktop-database /usr/share/applications || true
fi
# Update icon cache
if [ -d "/usr/share/icons/hicolor" ]; then
    touch /usr/share/icons/hicolor
    if command -v update-icon-caches &> /dev/null; then
        update-icon-caches /usr/share/icons/hicolor || true
    else
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
    fi
fi
echo "Autononext removed successfully!"
exit 0
EOF
chmod 0755 "$BUILD_ROOT/DEBIAN/postrm"

# Create desktop file
cat > "$BUILD_ROOT/usr/share/applications/autononext.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Autononext
Comment=Linux package manager for GitHub releases
Exec=/opt/autononext/bundle/autononext
Icon=autononext
Path=/opt/autononext/bundle
Terminal=false
Categories=System;Utility;PackageManager;
Keywords=package;github;release;manager;
StartupWMClass=com.autononext
EOF
chmod 0644 "$BUILD_ROOT/usr/share/applications/autononext.desktop"

# Copy icon (use autononext.png from project root)
if [ -f "$PROJECT_DIR/autononext.png" ]; then
  mkdir -p "$BUILD_ROOT/usr/share/icons/hicolor/256x256/apps"
  if command -v convert &> /dev/null; then
    convert -resize 256x256 "$PROJECT_DIR/autononext.png" "$BUILD_ROOT/usr/share/icons/hicolor/256x256/apps/autononext.png"
    log_info "Icon resized to 256x256 ✓"
  else
    cp "$PROJECT_DIR/autononext.png" "$BUILD_ROOT/usr/share/icons/hicolor/256x256/apps/autononext.png"
    log_info "Icon copied ✓"
  fi
fi

    # Set correct permissions
    chmod 0755 "$BUILD_ROOT/DEBIAN"
    chmod 0755 "$BUILD_ROOT/DEBIAN/control"
    chmod 0755 "$BUILD_ROOT/opt"
    chmod 0755 "$BUILD_ROOT/opt/$APP_NAME"
    
    log_info "Debian structure created ✓"
}

build_debian_package() {
    log_step "Building Debian package..."
    
    mkdir -p "$DIST_DIR"
    local output_deb="$DIST_DIR/${APP_NAME}_${DEB_VERSION}_${ARCH}.deb"
    
    # Build the package with root ownership
    dpkg-deb --root-owner-group --build "$BUILD_ROOT" "$output_deb"
    
    if [ ! -f "$output_deb" ]; then
        log_error "Failed to create .deb package"
        exit 1
    fi
    
    log_info "Package created: $output_deb"
}

print_summary() {
    echo ""
    echo "=========================================="
    log_info "Build completed successfully!"
    echo "=========================================="
    echo ""
    echo "Package: $DIST_DIR/${APP_NAME}_${DEB_VERSION}_${ARCH}.deb"
    echo "Size: $(du -h "$DIST_DIR/${APP_NAME}_${DEB_VERSION}_${ARCH}.deb" | cut -f1)"
    echo ""
    echo "To install:"
    echo "  sudo dpkg -i $DIST_DIR/${APP_NAME}_${DEB_VERSION}_${ARCH}.deb"
    echo ""
    echo "To uninstall:"
    echo "  sudo apt remove $APP_NAME"
    echo ""
}

# === Main ===
main() {
    echo "=========================================="
    echo "Autononext - Debian Package Builder"
    echo "Version: $DEB_VERSION"
    echo "=========================================="
    echo ""
    
    check_dependencies
    build_flutter
    create_debian_structure
    build_debian_package
    print_summary
}

main "$@"
