#!/bin/bash
# Build and run Arcmark as a proper macOS app bundle

set -e  # Exit on error

echo "🚀 Building and running Arcmark..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Build and run using swift-bundler via mint
mint run swift-bundler run
