# Autononext Makefile
# Centralized command aliases for Flutter build and Debian packaging

.PHONY: dev build build-deb build-rpm build-all bump-build bump-patch help

# Default target
all: help

## Development
dev:
	flutter run -d linux

## Build
build:
	flutter build linux --release

## Debian Packaging
build-deb:
	./scripts/create-debian-package.sh

## RPM Packaging
build-rpm:
	chmod +x scripts/create-rpm-package.sh
	./scripts/create-rpm-package.sh

## Both DEB and RPM
build-all: build-deb build-rpm

## Version Management
bump-build:
	@./scripts/bump-version.sh --build

bump-patch:
	@./scripts/bump-version.sh --patch

bump-minor:
	@./scripts/bump-version.sh --minor

## Help
help:
	@echo "Autononext Build System"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  dev          - Run the application in development mode (Linux)"
	@echo "  build        - Build the Flutter Linux release bundle"
	@echo "  build-deb    - Build the Debian package"
	@echo "  build-rpm    - Build the RPM package"
	@echo "  build-all    - Build both DEB and RPM packages"
	@echo "  bump-build   - Manually increment build number (0.3.X-bY -> 0.3.X-bY+1)"
	@echo "  bump-patch   - Manually increment patch version (0.3.X -> 0.3.X+1, reset bY=1)"
	@echo "  bump-minor   - Manually increment minor version (0.X.Y -> 0.X+1.0, reset bY=1)"
	@echo "  help         - Show this help message"