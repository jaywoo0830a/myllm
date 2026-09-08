#!/usr/bin/env bash
# start_all.sh – start all model servers defined in the registry
# Usage: ./start_all.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Load base environment first
load_base_env

# Define the list of model slugs to start (must match env filenames)
SLUGS=(
    parser
    worker1
    worker2
    worker3
    worker4
    coder1
    coder2
    coder3
    coder4
    reasoner
)

for SLUG in "${SLUGS[@]}"; do
    echo "🚀 Starting model $SLUG..."
    # Use the existing up.sh script to start each model in background
    "${SCRIPT_DIR}/up.sh" "$SLUG"
    # Give a short pause to avoid race conditions
    sleep 0.5
done

echo "✅ All models have been started."
