#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${REPO_ROOT}/setup/ensure-authenticated.sh"

HOST=$(oc get route prefix-cache-lab -n prefix-cache-lab -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -z "$HOST" ]]; then
  echo "Prefix Cache Lab Route not found. Run: bash setup/12-prefix-cache-lab.sh"
  exit 1
fi

echo "Prefix Cache Lab: https://${HOST}"
echo "Open in a browser and click Run comparison."
