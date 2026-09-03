#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ensure-authenticated.sh"

LLM_NAME="llama-3-1-8b-fp8"

echo "========================================="
echo "  llm-d + MaaS Demo Credentials and URLs"
echo "========================================="

echo ""
echo "--- OpenShift ---"
echo "Console: https://console-openshift-console.${CLUSTER_DOMAIN}"
echo "User: $(oc whoami)"

echo ""
echo "--- RHOAI Dashboard ---"
RHOAI_URL=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
echo "URL: https://${RHOAI_URL}"

echo ""
echo "--- MaaS + llm-d ---"
echo "MaaS API: ${MAAS_URL}"
echo "Health: ${MAAS_URL}/maas-api/health"
echo "Model endpoint: ${MAAS_URL}/models-as-a-service/${LLM_NAME}/v1"
echo "LLMInferenceService: ${LLM_NAME} (4 replicas, prefix-caching; model id llama-3-1-8b-instruct-fp8)"

echo ""
echo "--- Dev Spaces (dev subscription) ---"
DEVSPACES_URL=$(oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.cheURL}' 2>/dev/null || echo "N/A")
echo "Dashboard: ${DEVSPACES_URL}"
echo "Workspace: ${DEVSPACES_URL}/#https://github.com/alezzandro/llm-d-demolab?devfilePath=devspaces-workspace/devfile.yaml"
echo "(Update git URL if using a different fork; ensure Continue config Secret is present.)"

echo ""
echo "--- Chatbot / Open WebUI (ops subscription) ---"
CHATBOT_URL=$(oc get route open-webui -n open-webui -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
echo "URL: https://${CHATBOT_URL}"
echo "First login creates admin account — do this before the booth opens."

echo ""
echo "--- Prefix Cache Lab (llm-d beat) ---"
LAB_URL=$(oc get route prefix-cache-lab -n prefix-cache-lab -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
echo "URL: https://${LAB_URL}"
echo "Buttons: unique vs shared prefix TTFT + canned EPP chart"
echo "Leave-behind markdown: docs/assets/baseline-comparison.md"

echo ""
echo "--- API Keys ---"
DEVSPACES_KEY=$(oc get secret devspaces-maas-apikey -n openshift-devspaces -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || echo "N/A")
CHATBOT_KEY=$(oc get secret chatbot-maas-apikey -n open-webui -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || echo "N/A")
echo "Dev Spaces key: ${DEVSPACES_KEY:0:20}..."
echo "Chatbot key:    ${CHATBOT_KEY:0:20}..."

echo ""
echo "========================================="
