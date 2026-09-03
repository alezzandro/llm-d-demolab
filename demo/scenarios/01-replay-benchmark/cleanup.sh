#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../setup/ensure-authenticated.sh
source "$(cd "${SCRIPT_DIR}/../../.." && pwd)/setup/ensure-authenticated.sh"

oc delete job guidellm-llmd-short -n models-as-a-service --ignore-not-found
echo "Short GuideLLM job cleaned up."
