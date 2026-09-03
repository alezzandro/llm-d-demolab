#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "  Reset Demo State (keep llm-d model)"
echo "========================================="
echo "Regenerates MaaS keys and clears consumers."
echo "Does NOT tear down the 4-replica LLMInferenceService."

echo "1. Deleting consumer API key secrets..."
oc delete secret chatbot-maas-apikey -n open-webui --ignore-not-found
oc delete secret devspaces-maas-apikey -n openshift-devspaces --ignore-not-found
oc delete secret continue-ai-config -n openshift-devspaces --ignore-not-found

echo "2. Revoking MaaS API keys..."
TOKEN=$(oc whoami -t)
curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys/bulk-revoke" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' 2>/dev/null || true

echo "3. Restarting Open WebUI..."
oc rollout restart deployment/open-webui -n open-webui 2>/dev/null || true

echo "4. Deleting Dev Spaces workspaces (re-create via deep-link)..."
oc delete devworkspace --all -A --ignore-not-found 2>/dev/null || true

echo "5. Cleaning short benchmark jobs..."
oc delete job guidellm-llmd-short -n models-as-a-service --ignore-not-found 2>/dev/null || true

echo "6. Re-generating API keys + Continue config..."
bash "${SCRIPT_DIR}/08-setup-subscriptions.sh"
bash "${SCRIPT_DIR}/09-deploy-devspaces.sh"

echo "7. Refreshing Prefix Cache Lab API key + rollout..."
if oc get ns prefix-cache-lab &>/dev/null; then
  CHATBOT_KEY=$(oc get secret chatbot-maas-apikey -n open-webui \
    -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || echo "")
  if [[ -n "$CHATBOT_KEY" ]]; then
    oc create secret generic prefix-cache-lab-maas-apikey \
      -n prefix-cache-lab \
      --from-literal=api-key="${CHATBOT_KEY}" \
      --dry-run=client -o yaml | oc apply -f -
    oc rollout restart deployment/prefix-cache-lab -n prefix-cache-lab 2>/dev/null || true
  fi
fi

echo ""
echo "Demo state reset. Run show-credentials.sh for new URLs/keys."
echo "Pre-create the Dev Spaces workspace before the next visitor."
echo "Open Prefix Cache Lab and use Reset results between visitors."
echo "========================================="
