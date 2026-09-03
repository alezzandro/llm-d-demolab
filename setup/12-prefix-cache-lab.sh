#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
APP_DIR="${REPO_ROOT}/apps/prefix-cache-lab"
LLM_NAME="llama-3-1-8b-fp8"
NS="prefix-cache-lab"

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "Phase 12: Prefix Cache Lab UI"
echo "========================================="

MAAS_ENDPOINT="${MAAS_URL}/models-as-a-service/${LLM_NAME}/v1"

echo "1. Applying namespace + build/deploy manifests..."
oc apply -f "${MANIFESTS_DIR}/bench-ui/namespace.yaml"
oc apply -f "${MANIFESTS_DIR}/bench-ui/imagestream.yaml"
oc apply -f "${MANIFESTS_DIR}/bench-ui/buildconfig.yaml"
oc apply -f "${MANIFESTS_DIR}/bench-ui/configmap.yaml"
oc apply -f "${MANIFESTS_DIR}/bench-ui/service.yaml"
oc apply -f "${MANIFESTS_DIR}/bench-ui/route.yaml"
oc apply -f "${MANIFESTS_DIR}/bench-ui/networkpolicy.yaml"

echo "2. Creating MaaS API key secret (reuse chatbot / ops key)..."
CHATBOT_KEY=$(oc get secret chatbot-maas-apikey -n open-webui \
  -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || echo "")
if [[ -z "$CHATBOT_KEY" ]]; then
  echo "   WARNING: chatbot-maas-apikey missing — generating a dedicated lab key..."
  TOKEN=$(oc whoami -t)
  CHATBOT_KEY=$(curl -sk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"name": "prefix-cache-lab-key", "subscription": "chatbot-subscription"}' | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")
fi
if [[ -z "$CHATBOT_KEY" ]]; then
  echo "ERROR: Could not obtain a MaaS API key for the Prefix Cache Lab."
  exit 1
fi
oc create secret generic prefix-cache-lab-maas-apikey \
  -n "${NS}" \
  --from-literal=api-key="${CHATBOT_KEY}" \
  --dry-run=client -o yaml | oc apply -f -

echo "3. Building image from apps/prefix-cache-lab (OpenShift binary build)..."
# Cancel any stuck previous build so re-runs stay idempotent.
oc cancel-build -n "${NS}" bc/prefix-cache-lab --state=new,pending,running 2>/dev/null || true
oc start-build prefix-cache-lab \
  -n "${NS}" \
  --from-dir="${APP_DIR}" \
  --follow \
  --wait

echo "4. Deploying UI..."
sed "s|MAAS_ENDPOINT_PLACEHOLDER|${MAAS_ENDPOINT}|g" \
  "${MANIFESTS_DIR}/bench-ui/deployment.yaml" | oc apply -f -

echo "5. Waiting for Deployment..."
# ImageStream may need a moment after build before the Deployment pulls latest.
sleep 3
oc rollout restart deployment/prefix-cache-lab -n "${NS}" 2>/dev/null || true
oc rollout status deployment/prefix-cache-lab -n "${NS}" --timeout=180s

echo "6. Applying Route timeout (long-running compare)..."
oc apply -f "${MANIFESTS_DIR}/bench-ui/route.yaml"

ROUTE_HOST=$(oc get route prefix-cache-lab -n "${NS}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

echo ""
echo "Phase 12 complete: Prefix Cache Lab UI ready."
echo "URL: https://${ROUTE_HOST}"
echo "Verify: bash demo/scenarios/02-prefix-cache-lab/test.sh"
echo "========================================="
