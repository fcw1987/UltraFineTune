#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if ! bash "$PROJECT_DIR/build.sh" --run-local; then
    printf '\nBuild failed. Read the error above. Press Return to close.\n'
    read -r
    exit 1
fi
