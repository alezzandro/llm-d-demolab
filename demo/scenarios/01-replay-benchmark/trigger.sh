#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

export RUN_SHORT_BENCH=true
bash "${REPO_ROOT}/setup/11-baseline-and-observability.sh"

echo ""
echo "Follow logs:"
echo "  oc logs -f job/guidellm-llmd-short -n models-as-a-service"
