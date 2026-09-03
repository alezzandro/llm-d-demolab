#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
LLM_NAME="llama-3-1-8b-fp8"
RUN_SHORT_BENCH="${RUN_SHORT_BENCH:-false}"

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "Phase 11: Baseline assets + Observability"
echo "========================================="

echo "1. Ensuring benchmark PVC..."
oc apply -f "${MANIFESTS_DIR}/monitoring/benchmark-pvc.yaml"

echo "2. Confirming canned comparison leave-behind exists..."
if [[ -f "${REPO_ROOT}/docs/assets/baseline-comparison.md" ]]; then
  echo "   docs/assets/baseline-comparison.md ready for booth slides."
else
  echo "   WARNING: baseline-comparison.md missing."
fi

echo "3. Observability pointers..."
echo "   - Perses MaaS Usage dashboards (RHOAI monitoring namespace)"
echo "   - OpenShift Observe → Metrics: query vllm:kv_cache_usage_perc / TTFT-related series"
echo "   - Leave-behind numbers: docs/assets/baseline-comparison.md"
echo "   - Prep-day full GuideLLM: demo/scenarios/01-replay-benchmark/"

if [[ "$RUN_SHORT_BENCH" == "true" ]]; then
  echo ""
  echo "4. Running optional short GuideLLM burst (60s @ concurrency 32)..."
  CHATBOT_KEY=$(oc get secret chatbot-maas-apikey -n open-webui \
    -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || echo "")
  if [[ -z "$CHATBOT_KEY" ]]; then
    echo "   WARNING: No chatbot API key; skipping short bench."
  else
    oc delete job guidellm-llmd-short -n models-as-a-service --ignore-not-found
    MAAS_ENDPOINT="${MAAS_URL}/models-as-a-service/${LLM_NAME}/v1"
    sed -e "s|MAAS_ENDPOINT_PLACEHOLDER|${MAAS_ENDPOINT}|g" \
        -e "s|API_KEY_PLACEHOLDER|${CHATBOT_KEY}|g" \
      "${MANIFESTS_DIR}/monitoring/guidellm-short-job.yaml" | oc apply -f -
    echo "   Job guidellm-llmd-short created. Follow logs with:"
    echo "   oc logs -f job/guidellm-llmd-short -n models-as-a-service"
  fi
else
  echo ""
  echo "4. Skipping live short bench (set RUN_SHORT_BENCH=true to enable)."
fi

echo ""
echo "Phase 11 complete: booth observability assets ready."
echo "========================================="
