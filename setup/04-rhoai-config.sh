#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${REPO_ROOT}/manifests"

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "Phase 4: RHOAI Configuration"
echo "========================================="

echo "1. Applying DataScienceCluster..."
oc apply -f "${MANIFESTS_DIR}/rhoai-config/datasciencecluster.yaml"

echo "2. Applying DSCInitialization..."
oc apply -f "${MANIFESTS_DIR}/rhoai-config/dscinitializaton.yaml"

echo "3. Waiting for OdhDashboardConfig to be created by the operator..."
TIMEOUT=120
INTERVAL=10
ELAPSED=0
while true; do
  if oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications &>/dev/null; then
    echo "   OdhDashboardConfig is available."
    break
  fi
  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "   WARNING: OdhDashboardConfig not found after ${TIMEOUT}s. Patch may fail."
    break
  fi
  echo "   Waiting for OdhDashboardConfig... (${ELAPSED}s / ${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "4. Enabling RHOAI 3.4 dashboard features..."
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  --type merge -p '{
    "spec": {
      "dashboardConfig": {
        "disableModelCatalog": false,
        "modelAsService": true,
        "genAiStudio": false,
        "maasAuthPolicies": true,
        "observabilityDashboard": true,
        "vLLMDeploymentOnMaaS": true,
        "llmGatewayField": true,
        "promptManagement": true,
        "mcpCatalog": false,
        "aiAssetCustomEndpoints": true
      },
      "genAiStudioConfig": {
        "aiAssetCustomEndpoints": {
          "externalProviders": false,
          "clusterDomains": []
        }
      }
    }
  }'
echo "   Dashboard features enabled: Observability, MaaS, Prompt Management (Gen AI Studio/MCP off for booth v1)."

echo "5. Creating HardwareProfile for L4 GPU (RHOAI 3.4 schema)..."
# Replace avoids stale last-applied fields from the pre-3.4 profile shape
# (displayName/enabled/nodeSelectors at spec root were dropped by the CRD).
oc delete hardwareprofile gpu-l4-nvidia -n redhat-ods-applications --ignore-not-found
oc apply -f "${MANIFESTS_DIR}/rhoai-config/hardware-profile.yaml"
HP_SCHED=$(oc get hardwareprofile gpu-l4-nvidia -n redhat-ods-applications \
  -o jsonpath='{.spec.scheduling.type}' 2>/dev/null || echo "")
HP_NAME=$(oc get hardwareprofile gpu-l4-nvidia -n redhat-ods-applications \
  -o jsonpath='{.metadata.annotations.opendatahub\.io/display-name}' 2>/dev/null || echo "")
if [[ "$HP_SCHED" == "Node" && -n "$HP_NAME" ]]; then
  echo "   HardwareProfile ready: display-name='${HP_NAME}', scheduling=${HP_SCHED}"
else
  echo "   WARNING: HardwareProfile may be incomplete (scheduling='${HP_SCHED}', display-name='${HP_NAME}')."
  echo "   OpenShift AI Deployments edit form can render empty without a valid profile."
fi

echo "6. Waiting for ModelsAsServiceReady condition..."
TIMEOUT=300
INTERVAL=15
ELAPSED=0
while true; do
  STATUS=$(oc get datasciencecluster default-dsc \
    -o jsonpath='{.status.conditions[?(@.type=="ModelsAsServiceReady")].status}' 2>/dev/null || echo "Unknown")
  if [[ "$STATUS" == "True" ]]; then
    echo "   MaaS is ready!"
    break
  fi
  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "   WARNING: MaaS not yet ready after ${TIMEOUT}s. Check DSC status."
    break
  fi
  echo "   ModelsAsServiceReady: ${STATUS} (${ELAPSED}s / ${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""
echo "Phase 4 complete: RHOAI configured with MaaS, Model Registry, and Model Catalog."
echo "========================================="
