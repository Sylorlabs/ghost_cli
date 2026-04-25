#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Building ghost_cli in ReleaseSafe mode..."
zig build -Doptimize=ReleaseSafe

INSTALL_PATH="/usr/local/bin/ghost"
BINARY_PATH="$(pwd)/zig-out/bin/ghost"

if [ -f "$INSTALL_PATH" ] || [ -L "$INSTALL_PATH" ]; then
    echo -e "${RED}Warning:${NC} $INSTALL_PATH already exists."
    read -p "Overwrite? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "Installation aborted."
        exit 1
    fi
fi

echo "Installing symlink to $INSTALL_PATH..."
sudo ln -sf "$BINARY_PATH" "$INSTALL_PATH"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Success!${NC} 'ghost' is now installed globally."
    echo "Verifying installation..."
    if $INSTALL_PATH --version 2>&1 | grep -q "ghost_cli v0.1.0-hardened"; then
        echo -e "${GREEN}Verified:${NC} Global 'ghost' is at the correct version."
    else
        echo -e "${RED}Warning:${NC} Global 'ghost' might be stale or incorrect."
        $INSTALL_PATH --version
    fi
    echo "Run 'ghost --help' to verify."
else
    echo -e "${RED}Error:${NC} Failed to create symlink."
    exit 1
fi
