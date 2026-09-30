#!/bin/bash
# Autononext Version Bumper
# Increments version in pubspec.yaml
# Format: major.minor.patch-bbuild (e.g., 0.3.8-b5)

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "Error: pubspec.yaml not found at $PUBSPEC"
    exit 1
fi

# Get current version string
CURRENT_VERSION=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | tr -d '[:space:]' | tr -d "'\"")

# Parse version
if [[ "$CURRENT_VERSION" != *"-b"* ]]; then
    # Fallback for versions without -b suffix
    SEMANTIC="$CURRENT_VERSION"
    BUILD_NUM=0
else
    SEMANTIC=$(echo "$CURRENT_VERSION" | cut -d'-' -f1)
    BUILD_PART=$(echo "$CURRENT_VERSION" | cut -d'-' -f2)
    BUILD_NUM=$(echo "$BUILD_PART" | sed 's/b//')
fi

# Extract semantic parts
IFS='.' read -r MAJOR MINOR PATCH <<< "$SEMANTIC"

  if [[ "$1" == "--minor" ]]; then
      # Increment minor, resetting patch and build number
      NEW_MINOR=$((MINOR + 1))
      NEW_VERSION="$MAJOR.$NEW_MINOR.0-b1"
  elif [[ "$1" == "--patch" ]]; then
      # Increment patch and reset build number
      NEW_PATCH=$((PATCH + 1))
      NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH-b1"
  elif [[ "$1" == "--build" ]]; then
      # Increment build number only
      NEW_BUILD=$((BUILD_NUM + 1))
      NEW_VERSION="$SEMANTIC-b$NEW_BUILD"
  else
      echo "Usage: $0 --build | --minor | --patch"
      exit 1
  fi

# Update pubspec.yaml
# Using a temp file to be safe with sed
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"

echo "Version bumped: $CURRENT_VERSION -> $NEW_VERSION"
