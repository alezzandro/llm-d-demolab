#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  llm-d + MaaS Booth Hybrid Demo - Full Setup"
echo "============================================================"
echo ""
echo "OpenShift 4.22+ → RHOAI 3.5 → 4x L4 → llm-d → MaaS →"
echo "Dev Spaces + Open WebUI"
echo "Estimated time: 60-120 minutes (dominated by 4x GPU + model load)"
echo ""

START_PHASE=${1:-0}

run_phase() {
  local phase=$1
  local script=$2
  if [[ "$phase" -ge "$START_PHASE" ]]; then
    echo ""
    bash "${SCRIPT_DIR}/${script}"
    echo ""
  else
    echo "Skipping phase ${phase} (starting from phase ${START_PHASE})"
  fi
}

run_phase 0 "00-gpu-provisioner.sh"
run_phase 1 "01-install-operators.sh"
run_phase 2 "02-platform-config.sh"
run_phase 3 "03-maas-platform.sh"
run_phase 4 "04-rhoai-config.sh"
run_phase 5 "05-model-registry.sh"
run_phase 6 "06-deploy-llmd-model.sh"
run_phase 7 "07-verify-maas-llmd.sh"
run_phase 8 "08-setup-subscriptions.sh"
run_phase 9 "09-deploy-devspaces.sh"
run_phase 10 "10-deploy-chatbot.sh"
run_phase 11 "11-baseline-and-observability.sh"
run_phase 12 "12-prefix-cache-lab.sh"

echo ""
echo "============================================================"
echo "  Setup Complete!"
echo "============================================================"
echo ""
bash "${SCRIPT_DIR}/show-credentials.sh"
echo ""
echo "Pre-booth checklist:"
echo "  1. bash setup/health-check.sh"
echo "  2. Create Dev Spaces workspace (deep-link in credentials output)"
echo "  3. First-login to Open WebUI and confirm model chat works"
echo "  4. Open Prefix Cache Lab URL and click Run comparison once"
