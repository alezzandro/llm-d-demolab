#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${REPO_ROOT}/manifests"

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "Phase 5: Model Registry"
echo "========================================="

echo "1. Verifying Model Registry namespace exists..."
oc get namespace rhoai-model-registries &>/dev/null || \
  oc create namespace rhoai-model-registries

echo "2. Verifying Model Registry operator is running..."
oc wait deployment model-registry-operator-controller-manager \
  -n redhat-ods-applications \
  --for=condition=Available --timeout=120s

echo "3. Verifying component-level ModelRegistry is ready..."
oc wait modelregistry default-modelregistry -n rhoai-model-registries \
  --for=jsonpath='{.status.conditions[0].status}'=True --timeout=120s 2>/dev/null || \
  echo "   ModelRegistry component not ready yet, will reconcile automatically."

echo "4. Verifying Model Catalog is operational..."
oc wait deployment model-catalog -n rhoai-model-registries \
  --for=condition=Available --timeout=120s 2>/dev/null || \
  echo "   Model Catalog deployment not yet available."

echo "5. Deploying MySQL backend for Model Registry..."
if ! oc get secret model-registry-db-credentials -n rhoai-model-registries &>/dev/null; then
  MR_DB_PASS=$(openssl rand -hex 16)
  MR_ROOT_PASS=$(openssl rand -hex 16)
  oc create secret generic model-registry-db-credentials \
    -n rhoai-model-registries \
    --from-literal=password="${MR_DB_PASS}" \
    --from-literal=root-password="${MR_ROOT_PASS}"
fi
oc apply -f "${MANIFESTS_DIR}/model-registry/mysql/mysql.yaml"
echo "   Waiting for MySQL to be ready..."
oc wait statefulset model-registry-db -n rhoai-model-registries \
  --for=jsonpath='{.status.readyReplicas}'=1 --timeout=120s 2>/dev/null || \
  echo "   WARNING: MySQL not ready yet, continuing..."

echo "6. Creating Model Registry instance (REST API server)..."
oc apply -f "${MANIFESTS_DIR}/model-registry/model-registry-instance.yaml"

echo "   Waiting for Model Registry server to be available..."
TIMEOUT=120
INTERVAL=10
ELAPSED=0
while true; do
  READY=$(oc get deployment default-registry -n rhoai-model-registries \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
  if [[ "$READY" -ge 1 ]]; then
    echo "   Model Registry server is running!"
    break
  fi
  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "   WARNING: Model Registry server not ready after ${TIMEOUT}s."
    break
  fi
  echo "   Waiting... (${ELAPSED}s / ${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "7. Registering Llama 3.1 8B Instruct FP8 model..."
# Call the REST API via 127.0.0.1 inside the registry pod. Curling the
# ClusterIP Service from that same pod times out (CNI hairpin).
mr_curl() {
  oc exec deployment/default-registry -n rhoai-model-registries -c rest-container -- \
    curl -sS -m 20 "$@"
}

MR_LOCAL="http://127.0.0.1:8080/api/model_registry/v1alpha3"
MODEL_JSON=$(mr_curl "${MR_LOCAL}/registered_models")
MODEL_EXISTS=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('size',0))" "${MODEL_JSON}" 2>/dev/null || echo "0")
MODEL_ID=$(python3 -c "
import json,sys
d=json.loads(sys.argv[1])
items=d.get('items') or []
for m in items:
  if m.get('name')=='llama-3-1-8b-instruct-fp8-dynamic':
    print(m.get('id','')); break
" "${MODEL_JSON}" 2>/dev/null || echo "")

if [[ -z "$MODEL_ID" || "$MODEL_EXISTS" == "0" ]]; then
  echo "   Creating registered model..."
  CREATE_JSON=$(mr_curl -X POST "${MR_LOCAL}/registered_models" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "llama-3-1-8b-instruct-fp8-dynamic",
      "description": "Red Hat AI validated Llama 3.1 8B Instruct FP8 for llm-d multi-replica serving and MaaS consumers",
      "customProperties": {
        "source": {"metadataType": "MetadataStringValue", "string_value": "Red Hat AI Model Catalog"},
        "provider": {"metadataType": "MetadataStringValue", "string_value": "RedHatAI"},
        "task": {"metadataType": "MetadataStringValue", "string_value": "text-generation"},
        "quantization": {"metadataType": "MetadataStringValue", "string_value": "FP8-dynamic"},
        "parameters": {"metadataType": "MetadataStringValue", "string_value": "8B"}
      }
    }')
  MODEL_ID=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('id',''))" "${CREATE_JSON}")
  if [[ -z "$MODEL_ID" ]]; then
    echo "   ERROR: registered model create failed: ${CREATE_JSON}"
    exit 1
  fi
  echo "   Registered model id=${MODEL_ID}"
else
  echo "   Model already registered (id=${MODEL_ID})."
fi

VER_JSON=$(mr_curl "${MR_LOCAL}/model_versions")
VERSION_ID=$(python3 -c "
import json,sys
d=json.loads(sys.argv[1])
mid=sys.argv[2]
for v in d.get('items') or []:
  if v.get('name')=='v1.5' and str(v.get('registeredModelId'))==str(mid):
    print(v.get('id','')); break
" "${VER_JSON}" "${MODEL_ID}" 2>/dev/null || echo "")

if [[ -z "$VERSION_ID" ]]; then
  echo "   Creating model version v1.5..."
  VCREATE=$(mr_curl -X POST "${MR_LOCAL}/model_versions" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"v1.5\",
      \"description\": \"OCI Modelcar from registry.redhat.io - FP8 dynamic quantization for 4x L4 llm-d\",
      \"registeredModelId\": \"${MODEL_ID}\",
      \"customProperties\": {
        \"runtime\": {\"metadataType\": \"MetadataStringValue\", \"string_value\": \"vLLM CUDA\"},
        \"gpu_required\": {\"metadataType\": \"MetadataStringValue\", \"string_value\": \"4x NVIDIA L4 (24GB VRAM)\"},
        \"serving_framework\": {\"metadataType\": \"MetadataStringValue\", \"string_value\": \"Red Hat AI Inference Server + llm-d\"}
      }
    }")
  VERSION_ID=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('id',''))" "${VCREATE}")
  if [[ -z "$VERSION_ID" ]]; then
    echo "   ERROR: model version create failed: ${VCREATE}"
    exit 1
  fi
  echo "   Version id=${VERSION_ID}"
else
  echo "   Model version v1.5 already present (id=${VERSION_ID})."
fi

ART_JSON=$(mr_curl "${MR_LOCAL}/model_versions/${VERSION_ID}/artifacts" 2>/dev/null || echo '{"size":0}')
ART_SIZE=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('size',0))" "${ART_JSON}" 2>/dev/null || echo "0")
if [[ "$ART_SIZE" == "0" ]]; then
  echo "   Creating model artifact (OCI image reference)..."
  mr_curl -X POST "${MR_LOCAL}/model_versions/${VERSION_ID}/artifacts" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "llama-3-1-8b-instruct-fp8-dynamic-oci",
      "description": "OCI Modelcar container image with Llama 3.1 8B Instruct FP8 dynamic model weights",
      "uri": "oci://registry.redhat.io/rhelai1/modelcar-llama-3-1-8b-instruct-fp8-dynamic:1.5",
      "artifactType": "model-artifact",
      "modelFormatName": "safetensors",
      "modelFormatVersion": "1.0",
      "customProperties": {
        "format": {"metadataType": "MetadataStringValue", "string_value": "OCI Modelcar"},
        "registry": {"metadataType": "MetadataStringValue", "string_value": "registry.redhat.io"}
      }
    }' >/dev/null
fi

echo "   Model registered successfully!"

echo ""
echo "   Flow: Catalog -> Register -> Deploy llm-d (4 replicas) -> MaaS subscriptions"
echo ""
echo "Phase 5 complete: Model Registry configured with Llama 3.1 8B Instruct FP8."
echo "========================================="
