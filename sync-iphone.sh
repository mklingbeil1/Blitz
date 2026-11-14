#!/bin/bash
# Copies the shared code (used by both the Mac and iPhone apps) into the iPhone project.
# Run this again after changing anything in Sources/Blitz/Shared.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf BlitzPhone.swiftpm/Shared
mkdir -p BlitzPhone.swiftpm/Shared
cp Sources/Blitz/Shared/*.swift BlitzPhone.swiftpm/Shared/
echo "Synced $(ls BlitzPhone.swiftpm/Shared | wc -l | tr -d ' ') shared files into BlitzPhone.swiftpm"
