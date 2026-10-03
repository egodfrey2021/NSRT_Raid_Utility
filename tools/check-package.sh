#!/bin/bash
set -euo pipefail

# Package verification script.
# The packager only copies files git tracks, so uncommitted new files won't be in the result.

PACKAGER_COMMIT="e50a250f8705041e40f2fa1ddcb280a686d65aa0"
PACKAGER_URL="https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_COMMIT/release.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$REPO_ROOT/.release"
OUTPUT_DIR="$RELEASE_DIR/out"
PACKAGE_DIR="$OUTPUT_DIR/NSRT_Raid_Utility"

# Clean previous build
rm -rf "$OUTPUT_DIR"
mkdir -p "$RELEASE_DIR"

# Download packager script
curl -fsSL "$PACKAGER_URL" -o "$RELEASE_DIR/release.sh"

# Run packager without upload or zip from repo root
cd "$REPO_ROOT"
bash "$RELEASE_DIR/release.sh" -d -z -r "$OUTPUT_DIR"

# Verify exclusions: these files must not be in the package
excluded_files=(
	tests
	types
	mise.toml
	stylua.toml
	tools
	README.md
	CLAUDE.md
	.luarc.json
	.luacheckrc
	.styluaignore
	.editorconfig
	.github
)

for file in "${excluded_files[@]}"; do
	if [ -e "$PACKAGE_DIR/$file" ]; then
		echo "FAIL: $file should not be in package but exists"
		exit 1
	fi
done

# Verify .toc: must not contain tests/ingame.lua and no #@do-not-package@ marker
toc_file="$PACKAGE_DIR/NSRT_Raid_Utility.toc"
if grep -q "tests/ingame.lua" "$toc_file"; then
	echo "FAIL: .toc contains tests/ingame.lua which should be excluded"
	exit 1
fi
if grep -q "#@do-not-package@" "$toc_file"; then
	echo "FAIL: .toc contains do-not-package marker which should be stripped"
	exit 1
fi

# Verify all .toc entries exist: extract non-empty, non-comment lines and check they exist
while IFS= read -r line; do
	line="${line%$'\r'}"  # strip carriage return (Windows line endings)
	line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
	if [ -z "$line" ] || [[ "$line" == "#"* ]]; then
		continue
	fi
	if [ ! -e "$PACKAGE_DIR/$line" ]; then
		echo "FAIL: .toc references $line but it doesn't exist in package"
		exit 1
	fi
done < "$toc_file"

# Verify media/roster-icon.png exists (IconTexture in .toc)
if [ ! -e "$PACKAGE_DIR/media/roster-icon.png" ]; then
	echo "FAIL: media/roster-icon.png does not exist in package"
	exit 1
fi

# Success: print file list and confirmation
echo "Package contents:"
find "$PACKAGE_DIR" -type f | sort | sed "s|^$PACKAGE_DIR/||" | sed 's/^/  /'
echo "Package OK"
