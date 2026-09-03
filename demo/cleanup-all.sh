#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/scenarios/01-replay-benchmark/cleanup.sh"
bash "${SCRIPT_DIR}/scenarios/02-prefix-cache-lab/cleanup.sh"
bash "$(cd "${SCRIPT_DIR}/.." && pwd)/setup/reset-demo.sh"
