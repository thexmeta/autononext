#!/bin/bash
# Autononext RPM x64 Package Builder
# Creates a .rpm package for Autononext Linux desktop application
#
# Usage: ./scripts/create-rpm-package.sh
# Requirements: Flutter SDK, rpm, rpmbuild

set -e

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/linux/x64/release"
DIST_DIR="$PROJECT_DIR/dist/rpm-x64"
BUILD_ROOT="/tmp/autononext-rpm-build-$$"

# === Configuration ===
APP_NAME="autononext"
VERSION=$(grep '^version:' "$PROJECT_DIR/pubspec.yaml" | awk '{print $2}')
ARCH="x86_64"
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
    
    if ! command -v rpmbuild &> /dev/null; then
        log_error "rpmbuild not found. Install: sudo apt-get install rpm"
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

create_rpm_structure() {
    log_step "Creating RPM build structure..."
    
    # Create RPM build directories
    mkdir -p "$BUILD_ROOT/BUILD"
    mkdir -p "$BUILD_ROOT/RPMS"
    mkdir -p "$BUILD_ROOT/SOURCES"
    mkdir -p "$BUILD_ROOT/SPECS"
    mkdir -p "$BUILD_ROOT/SRPMS"
    
    # Create SPEC file
    cat > "$BUILD_ROOT/SPECS/$APP_NAME.spec" << 'SPECEOF'
Name:           autononext
Version:        %{version}
Release:        %{release}%{?dist}
Summary:        Linux package manager for GitHub releases
License:        MIT

URL:            https://github.com/thexmeta/autononext
BuildArch:      x86_64

Requires:       libgtk-3-0, libblkid1, liblzma5, libcurl4, libfreetype6

%description
Autononext helps you track, install, update, and manage applications 
distributed via GitHub releases. It provides a clean, modern GUI for 
managing your GitHub-sourced applications with support for multiple 
package formats including DEB, RPM, AppImage, Flatpak, and Snap.

%prep
# No preparation needed - we're using pre-built binary

%build
# No build needed - we're using pre-built binary

%install
mkdir -p %{buildroot}/opt/autononext
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps

# Copy application files (from staged payload, never from %{buildroot})
cp -r %{payloaddir}/bundle %{buildroot}/opt/autononext/

# Create symlink for command-line access
ln -sf /opt/autononext/bundle/autononext %{buildroot}/usr/bin/autononext

# Install desktop file
cat > %{buildroot}/usr/share/applications/autononext.desktop << 'DESKTOPEOF'
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
DESKTOPEOF

chmod 0644 %{buildroot}/usr/share/applications/autononext.desktop

# Install icon if available
if [ -f "%{payloaddir}/autononext.png" ]; then
    cp %{payloaddir}/autononext.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/autononext.png
fi

%post
# Update desktop database
if [ -d "/usr/share/applications" ]; then
    update-desktop-database /usr/share/applications || true
fi
# Update icon cache
if [ -d "/usr/share/icons/hicolor" ]; then
    touch /usr/share/icons/hicolor
    if command -v update-icon-caches &> /dev/null; then
        update-icon-caches /usr/share/icons/hicolor || true
    fi
fi
echo "Autononext installed successfully!"
echo "You can now run 'autononext' from the command line or find it in your applications menu."

%postun
# Remove symlink on uninstall
rm -f /usr/bin/autononext
# Update desktop database
if [ -d "/usr/share/applications" ]; then
    update-desktop-database /usr/share/applications || true
fi
# Update icon cache
if [ -d "/usr/share/icons/hicolor" ]; then
    touch /usr/share/icons/hicolor
    if command -v update-icon-caches &> /dev/null; then
        update-icon-caches /usr/share/icons/hicolor || true
    fi
fi
echo "Autononext removed successfully!"

%files
/opt/autononext
/usr/bin/autononext
/usr/share/applications/autononext.desktop
%attr(644, root, root) /usr/share/icons/hicolor/256x256/apps/autononext.png

%changelog
* %(date +"%a %b %d %Y") Autononext Team <team@autononext.dev> - %{version}-1
- Release build
SPECEOF

    # Stage only the release bundle (exclude CMake/ninja build intermediates)
    cp -r "$BUILD_DIR/bundle" "$BUILD_ROOT/BUILD/"
    
    # Copy icon if available
    if [ -f "$PROJECT_DIR/autononext.png" ]; then
        cp "$PROJECT_DIR/autononext.png" "$BUILD_ROOT/BUILD/"
    fi
    
    log_info "RPM structure created ✓"
}

build_rpm_package() {
    log_step "Building RPM package..."
    
    mkdir -p "$DIST_DIR"
    
      # Extract version and release
      VERSION_CLEAN="${VERSION%-*}"  # Remove build suffix if present
      # RPM forbids `-` in Version, so the build suffix moves into Release.
      # `0.b1` sorts BELOW `1`, which is what a beta needs: hardcoding Release
      # to 1 for both the beta and the final release gave them the SAME NEVRA,
      # so rpm could not tell them apart and the upgrade was impossible.
      if [[ "$VERSION" == *"-b"* ]]; then
          RPM_RELEASE="0.${VERSION##*-}"
      else
          RPM_RELEASE="1"
      fi
      
      # Build the RPM
      rpmbuild \
          --define "_topdir $BUILD_ROOT" \
          --define "version $VERSION_CLEAN" \
          --define "release $RPM_RELEASE" \
          --define "_builddir $BUILD_ROOT/BUILD" \
          --define "payloaddir $BUILD_ROOT/BUILD" \
          -bb "$BUILD_ROOT/SPECS/$APP_NAME.spec"
    
    # Copy RPM to dist directory
    cp "$BUILD_ROOT/RPMS/$ARCH"/*.rpm "$DIST_DIR/"
    
    if [ ! -f "$DIST_DIR"/*.rpm ]; then
        log_error "Failed to create .rpm package"
        exit 1
    fi
    
    log_info "Package created ✓"
}

print_summary() {
    echo ""
    echo "=========================================="
    log_info "Build completed successfully!"
    echo "=========================================="
    echo ""
    echo "Package: $DIST_DIR/${APP_NAME}-*.${ARCH}.rpm"
    echo "Size: $(du -h "$DIST_DIR"/*.rpm 2>/dev/null | cut -f1 || echo 'N/A')"
    echo ""
    echo "To install:"
    echo "  sudo rpm -i $DIST_DIR/${APP_NAME}-*.${ARCH}.rpm"
    echo ""
    echo "To uninstall:"
    echo "  sudo rpm -e $APP_NAME"
    echo ""
}

# === Main ===
main() {
    echo "=========================================="
    echo "Autononext - RPM Package Builder"
    echo "Version: $VERSION"
    echo "=========================================="
    echo ""
    
    check_dependencies
    build_flutter
    create_rpm_structure
    build_rpm_package
    print_summary
}

main "$@"
