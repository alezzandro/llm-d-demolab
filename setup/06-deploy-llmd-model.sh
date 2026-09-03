#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
LLM_NAME="llama-3-1-8b-fp8"
MAAS_REF_NAME="llama-3-1-8b"
EXPECTED_REPLICAS=4

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "Phase 6: Deploy llm-d Model (${EXPECTED_REPLICAS} replicas)"
echo "========================================="

echo "1. Ensuring models-as-a-service namespace (visible in OpenShift AI Projects)..."
oc apply -f "${MANIFESTS_DIR}/model/namespace.yaml"
oc label namespace models-as-a-service \
  maas.opendatahub.io/gateway-access=true \
  opendatahub.io/dashboard=true \
  opendatahub.io/generated-namespace=true \
  modelmesh-enabled=false \
  --overwrite
oc annotate namespace models-as-a-service \
  openshift.io/display-name="Models as a Service" \
  openshift.io/description="llm-d + MaaS governed model pool (booth demo)" \
  --overwrite

echo "2. Creating OCI ModelCar connection (required for OpenShift AI Deployments Edit)..."
oc apply -f "${MANIFESTS_DIR}/model/oci-connection.yaml"

echo "3. Creating llm-d LLMInferenceService (${EXPECTED_REPLICAS}x vLLM + prefix-caching)..."
oc apply -f "${MANIFESTS_DIR}/model/llm-inference-service.yaml"
# Ensure connection annotation sticks even if an older CR already exists
oc annotate llminferenceservice "${LLM_NAME}" -n models-as-a-service \
  opendatahub.io/connections=llama-3-1-8b-fp8-connection \
  --overwrite

echo "4. Waiting for LLMInferenceService to be Ready..."
echo "   First deploy can take 15-25 minutes (4x image pull + model load)..."
TIMEOUT=1500
INTERVAL=30
ELAPSED=0
while true; do
  IS_READY=$(oc get llminferenceservice "${LLM_NAME}" -n models-as-a-service \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
  READY_PODS=$(oc get pods -n models-as-a-service \
    -l app.kubernetes.io/name="${LLM_NAME}" --no-headers 2>/dev/null | grep -c " Running" || true)
  TOTAL_PODS=$(oc get pods -n models-as-a-service \
    -l app.kubernetes.io/name="${LLM_NAME}" --no-headers 2>/dev/null | wc -l || true)
  if [[ "$IS_READY" == "True" ]]; then
    echo "   LLMInferenceService is Ready! (pods Running: ${READY_PODS}/${TOTAL_PODS})"
    break
  fi
  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "ERROR: Timeout waiting for llm-d model deployment"
    oc get llminferenceservice "${LLM_NAME}" -n models-as-a-service -o yaml | tail -80
    exit 1
  fi
  echo "   Ready=${IS_READY} | pods=${READY_PODS}/${TOTAL_PODS} (${ELAPSED}s / ${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

REPLICAS=$(oc get llminferenceservice "${LLM_NAME}" -n models-as-a-service \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
echo "   Spec replicas: ${REPLICAS} (expected ${EXPECTED_REPLICAS})"

echo "5. Creating MaaSModelRef..."
oc apply -f "${MANIFESTS_DIR}/model/maas-model-ref.yaml"

echo "6. Waiting for MaaSModelRef to become Ready..."
TIMEOUT=180
INTERVAL=10
ELAPSED=0
while true; do
  PHASE=$(oc get maasmodelref "${MAAS_REF_NAME}" -n models-as-a-service \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  if [[ "$PHASE" == "Ready" ]]; then
    echo "   MaaSModelRef is Ready!"
    ENDPOINT=$(oc get maasmodelref "${MAAS_REF_NAME}" -n models-as-a-service \
      -o jsonpath='{.status.endpoint}' 2>/dev/null || echo "")
    echo "   MaaS Endpoint: ${ENDPOINT}"
    break
  fi
  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "   WARNING: MaaSModelRef not Ready yet (phase: ${PHASE}). May need more time."
    break
  fi
  echo "   MaaSModelRef phase: ${PHASE} (${ELAPSED}s / ${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "7. Verifying model serves through MaaS Gateway..."
sleep 5
TOKEN=$(oc whoami -t)
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
  "https://maas.${CLUSTER_DOMAIN}/models-as-a-service/${LLM_NAME}/v1/models" \
  -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "   MaaS Gateway returns 200 - Model accessible!"
elif [[ "$HTTP_CODE" == "403" ]]; then
  echo "   MaaS Gateway returns 403 (subscription required) - Auth working!"
elif [[ "$HTTP_CODE" == "401" ]]; then
  echo "   MaaS Gateway returns 401 (auth required) - Gateway routing works!"
else
  echo "   WARNING: Unexpected HTTP code: ${HTTP_CODE}. Check gateway routing."
fi

echo ""
echo "Phase 6 complete: llm-d model deployed and exposed via MaaS."
echo "   Model: Llama 3.1 8B Instruct FP8 (4x vLLM + prefix-cache-aware EPP)"
echo "   MaaS Endpoint: https://maas.${CLUSTER_DOMAIN}/models-as-a-service/${LLM_NAME}/v1"
echo "========================================="
