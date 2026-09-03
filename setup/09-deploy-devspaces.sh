#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
LLM_NAME="llama-3-1-8b-fp8"
MODEL_ID="llama-3-1-8b-instruct-fp8"
MAAS_MODEL_PATH="models-as-a-service/${LLM_NAME}/v1"

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "Phase 9: Deploy Dev Spaces"
echo "========================================="

echo "1. Creating CheCluster..."
oc apply -k "${MANIFESTS_DIR}/devspaces/"

echo "2. Waiting for Dev Spaces to be ready..."
TIMEOUT=600
INTERVAL=30
ELAPSED=0
while true; do
  PHASE=$(oc get checluster devspaces -n openshift-devspaces \
    -o jsonpath='{.status.chePhase}' 2>/dev/null || echo "Unknown")
  if [[ "$PHASE" == "Active" ]]; then
    echo "   Dev Spaces is Active!"
    break
  fi
  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "   WARNING: Dev Spaces not Active after ${TIMEOUT}s."
    break
  fi
  echo "   CheCluster phase: ${PHASE} (${ELAPSED}s / ${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "3. Creating Continue AI extension config (auto-mounted into workspaces)..."
DEVSPACES_KEY=$(oc get secret devspaces-maas-apikey -n openshift-devspaces \
  -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || echo "PLACEHOLDER_KEY")

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: continue-ai-config
  namespace: openshift-devspaces
  labels:
    app.kubernetes.io/part-of: che.eclipse.org
    app.kubernetes.io/component: workspaces-config
    controller.devfile.io/mount-to-devworkspace: "true"
    controller.devfile.io/watch-secret: "true"
  annotations:
    controller.devfile.io/mount-path: "/etc/continue-config"
    controller.devfile.io/mount-as: "subpath"
type: Opaque
stringData:
  config.json: |
    {
      "models": [
        {
          "title": "Llama 3.1 8B via MaaS (llm-d)",
          "model": "${MODEL_ID}",
          "apiBase": "https://maas.${CLUSTER_DOMAIN}/${MAAS_MODEL_PATH}",
          "provider": "openai",
          "apiKey": "${DEVSPACES_KEY}"
        }
      ],
      "tabAutocompleteModel": {
        "title": "Llama 3.1 8B via MaaS (llm-d)",
        "model": "${MODEL_ID}",
        "apiBase": "https://maas.${CLUSTER_DOMAIN}/${MAAS_MODEL_PATH}",
        "provider": "openai",
        "apiKey": "${DEVSPACES_KEY}"
      },
      "tabAutocompleteOptions": {
        "useCopyBuffer": false,
        "maxPromptTokens": 2048,
        "prefixPercentage": 0.5
      }
    }
EOF
echo "   Continue config Secret created (mounted to /etc/continue-config/config.json)."

DEVSPACES_URL=$(oc get checluster devspaces -n openshift-devspaces \
  -o jsonpath='{.status.cheURL}' 2>/dev/null || echo "")

# Prefer a public git URL if the repo is published; otherwise use local sample guidance.
WORKSPACE_HINT="${DEVSPACES_URL}/#https://github.com/alezzandro/llm-d-demolab?devfilePath=devspaces-workspace/devfile.yaml"

echo ""
echo "   MaaS endpoint: https://maas.${CLUSTER_DOMAIN}/${MAAS_MODEL_PATH}"
echo "   Dev Spaces URL: ${DEVSPACES_URL}"
echo ""
echo "   Pre-create the workspace before the booth opens (cold start 30-60s)."
echo "   Workspace deep-link (update git URL if your fork differs):"
echo "   ${WORKSPACE_HINT}"
echo ""
echo "Phase 9 complete: Dev Spaces ready."
echo "========================================="
