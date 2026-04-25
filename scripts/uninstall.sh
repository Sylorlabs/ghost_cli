#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

INSTALL_PATH="/usr/local/bin/ghost"

if [ ! -L "$INSTALL_PATH" ] && [ ! -f "$INSTALL_PATH" ]; then
    echo -e "${RED}Error:${NC} 'ghost' is not installed at $INSTALL_PATH."
    exit 1
fi

echo "Removing $INSTALL_PATH..."
sudo rm "$INSTALL_PATH"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Success!${NC} 'ghost' has been uninstalled."
else
    echo -e "${RED}Error:${NC} Failed to remove $INSTALL_PATH."
    exit 1
fi
