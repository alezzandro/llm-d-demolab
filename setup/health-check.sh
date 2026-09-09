#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "llm-d + MaaS Health Check & Post-Reboot Recovery"
echo "========================================="
echo ""

ERRORS=0

check_pass() { echo "  ✓ $1"; }
check_fail() { echo "  ✗ $1"; ERRORS=$((ERRORS + 1)); }
check_warn() { echo "  ! $1"; }

# ─── 1. Nodes ───────────────────────────────────────────────────────────────────
echo "1. Cluster Nodes"
NOT_READY=$(oc get nodes --no-headers 2>/dev/null | { grep -cv " Ready " || true; })
GPU_NODES=$(oc get nodes -l node-role.kubernetes.io/worker-gpu --no-headers 2>/dev/null | wc -l)
if [[ "$NOT_READY" -gt 0 ]]; then
  check_fail "$NOT_READY node(s) not Ready"
else
  check_pass "All nodes Ready"
fi
if [[ "$GPU_NODES" -ge 4 ]]; then
  check_pass "GPU nodes present: $GPU_NODES (need 4 for llm-d)"
elif [[ "$GPU_NODES" -gt 0 ]]; then
  check_fail "GPU nodes present: $GPU_NODES (need 4 for llm-d)"
else
  check_fail "No GPU nodes found"
fi
echo ""

# ─── 2. GPU Operator ────────────────────────────────────────────────────────────
echo "2. NVIDIA GPU Operator"
GPU_STATE=$(oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}' 2>/dev/null || echo "missing")
if [[ "$GPU_STATE" == "ready" ]]; then
  check_pass "ClusterPolicy: ready"
else
  check_warn "ClusterPolicy: $GPU_STATE (may need recovery — see below)"
fi

GPU_ALLOC=$(oc get nodes -l node-role.kubernetes.io/worker-gpu -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
if [[ "$GPU_ALLOC" -ge 1 ]]; then
  check_pass "GPU allocatable: $GPU_ALLOC"
else
  check_fail "No GPU allocatable on GPU node"
fi
echo ""

# ─── 3. LLM Inference Service ───────────────────────────────────────────────────
echo "3. LLM Inference Service"
DASH_LABEL=$(oc get ns models-as-a-service -o jsonpath='{.metadata.labels.opendatahub\.io/dashboard}' 2>/dev/null || echo "")
if [[ "$DASH_LABEL" == "true" ]]; then
  check_pass "Namespace models-as-a-service labeled for OpenShift AI Projects"
else
  check_fail "Namespace models-as-a-service missing opendatahub.io/dashboard=true (hidden in RHOAI Projects)"
fi

HP_SCHED=$(oc get hardwareprofile gpu-l4-nvidia -n redhat-ods-applications \
  -o jsonpath='{.spec.scheduling.type}' 2>/dev/null || echo "")
HP_NAME=$(oc get hardwareprofile gpu-l4-nvidia -n redhat-ods-applications \
  -o jsonpath='{.metadata.annotations.opendatahub\.io/display-name}' 2>/dev/null || echo "")
if [[ "$HP_SCHED" == "Node" && -n "$HP_NAME" ]]; then
  check_pass "HardwareProfile gpu-l4-nvidia (scheduling=Node, display-name set)"
else
  check_fail "HardwareProfile gpu-l4-nvidia incomplete (edit form may be empty)"
fi

CONN=$(oc get secret llama-3-1-8b-fp8-connection -n models-as-a-service \
  -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
LLMIS_CONN=$(oc get llminferenceservice llama-3-1-8b-fp8 -n models-as-a-service \
  -o jsonpath='{.metadata.annotations.opendatahub\.io/connections}' 2>/dev/null || echo "")
if [[ -n "$CONN" && "$LLMIS_CONN" == "llama-3-1-8b-fp8-connection" ]]; then
  check_pass "OCI connection linked on LLMInferenceService (Deployments Edit)"
else
  check_fail "Missing OCI connection / opendatahub.io/connections (Deployments Edit empty)"
fi

LLM_READY=$(oc get llminferenceservice llama-3-1-8b-fp8 -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [[ "$LLM_READY" == "True" ]]; then
  check_pass "LLMInferenceService llama-3-1-8b-fp8: Ready"
else
  check_fail "LLMInferenceService llama-3-1-8b-fp8: Not Ready ($LLM_READY)"
fi

LLM_REPLICAS_SPEC=$(oc get llminferenceservice llama-3-1-8b-fp8 -n models-as-a-service -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [[ "$LLM_REPLICAS_SPEC" == "4" ]]; then
  check_pass "llm-d replicas: 4"
else
  check_fail "llm-d replicas: $LLM_REPLICAS_SPEC (expected 4)"
fi

MAAS_REF=$(oc get maasmodelref llama-3-1-8b -n models-as-a-service -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [[ "$MAAS_REF" == "Ready" ]]; then
  check_pass "MaaSModelRef: Ready"
else
  check_fail "MaaSModelRef: $MAAS_REF"
fi
echo ""

# ─── 4. MaaS Gateway ────────────────────────────────────────────────────────────
echo "4. MaaS Gateway"
GW_STATUS=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "Unknown")
if [[ "$GW_STATUS" == "True" ]]; then
  check_pass "Gateway: Programmed"
else
  check_fail "Gateway not Programmed: $GW_STATUS"
fi
echo ""

# ─── 5. Observability ───────────────────────────────────────────────────────────
echo "5. Observability Stack"
MON_READY=$(oc get monitoring default-monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [[ "$MON_READY" == "True" ]]; then
  check_pass "Monitoring component: Ready"
else
  check_warn "Monitoring component: $MON_READY"
fi

PERSES_PODS=$(oc get pods -n redhat-ods-monitoring -l app.kubernetes.io/managed-by=perses-operator --no-headers 2>/dev/null | grep "Running" | wc -l)
if [[ "$PERSES_PODS" -ge 1 ]]; then
  check_pass "Perses: Running"
else
  check_warn "Perses: not running"
fi

TP_EXISTS=$(oc get telemetrypolicy maas-telemetry -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Enforced")].status}' 2>/dev/null || echo "Unknown")
if [[ "$TP_EXISTS" == "True" ]]; then
  check_pass "TelemetryPolicy: Enforced (Usage Dashboard labels)"
else
  check_warn "TelemetryPolicy: $TP_EXISTS (Usage Dashboard may not show subscription data)"
fi
echo ""

# ─── 6. Open WebUI ──────────────────────────────────────────────────────────────
echo "6. Open WebUI (Chatbot)"
WEBUI_READY=$(oc get deploy open-webui -n open-webui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$WEBUI_READY" -ge 1 ]]; then
  check_pass "Open WebUI: Running"
else
  check_fail "Open WebUI: not ready"
fi
echo ""

# ─── 7. Dev Spaces ──────────────────────────────────────────────────────────────
echo "7. OpenShift Dev Spaces"
CHE_PHASE=$(oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.chePhase}' 2>/dev/null || echo "Unknown")
if [[ "$CHE_PHASE" == "Active" ]]; then
  check_pass "CheCluster: Active"
else
  check_warn "CheCluster phase: $CHE_PHASE"
fi
echo ""

# ─── 8. Model Registry ──────────────────────────────────────────────────────────
echo "8. Model Registry"
MR_PODS=$(oc get pods -n rhoai-model-registries --no-headers 2>/dev/null | grep -c "Running" || true)
if [[ "$MR_PODS" -ge 1 ]]; then
  check_pass "Model Registry API: Running"
else
  check_warn "Model Registry API: not running"
fi
echo ""

# ─── 9. MaaS endpoint test ──────────────────────────────────────────────────────
echo "9. MaaS Endpoint Test"
TOKEN=$(oc whoami -t)
HTTP_CODE=$(timeout 10 curl -sk -o /dev/null -w "%{http_code}" \
  "${MAAS_URL}/models-as-a-service/llama-3-1-8b-fp8/v1/models" \
  -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "403" ]]; then
  check_pass "MaaS endpoint reachable (HTTP $HTTP_CODE)"
else
  check_fail "MaaS endpoint returned HTTP $HTTP_CODE"
fi
echo ""

# ─── 10. Prefix Cache Lab UI ────────────────────────────────────────────────────
echo "10. Prefix Cache Lab UI"
LAB_READY=$(oc get deploy prefix-cache-lab -n prefix-cache-lab -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${LAB_READY:-0}" -ge 1 ]]; then
  check_pass "Prefix Cache Lab: Running"
else
  check_fail "Prefix Cache Lab: not ready"
fi
LAB_HOST=$(oc get route prefix-cache-lab -n prefix-cache-lab -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "$LAB_HOST" ]]; then
  LAB_HTTP=$(timeout 10 curl -sk -o /dev/null -w "%{http_code}" \
    "https://${LAB_HOST}/api/health" 2>/dev/null || echo "000")
  if [[ "$LAB_HTTP" == "200" ]]; then
    check_pass "Prefix Cache Lab /api/health (HTTP 200)"
  else
    check_fail "Prefix Cache Lab /api/health HTTP $LAB_HTTP"
  fi
else
  check_fail "Prefix Cache Lab Route missing"
fi
echo ""

# ─── 11. In-cluster demo bootstrapper (optional) ────────────────────────────────
echo "11. Demo bootstrapper (optional)"
if oc get ns rh-demo-bootstrapper &>/dev/null; then
  BS_READY=$(oc get deploy demo-bootstrapper -n rh-demo-bootstrapper -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [[ "${BS_READY:-0}" -ge 1 ]]; then
    check_pass "demo-bootstrapper Deployment: Ready"
  else
    check_fail "demo-bootstrapper Deployment: not ready"
  fi
  WTO=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | awk '/web-terminal/ {print $NF; exit}')
  if [[ "${WTO}" == "Succeeded" ]]; then
    check_pass "Web Terminal Operator: Succeeded"
  else
    check_warn "Web Terminal Operator: ${WTO:-missing} (refresh console for masthead terminal)"
  fi
  BS_STATUS=$(oc exec -n rh-demo-bootstrapper deploy/demo-bootstrapper -- cat /work/status 2>/dev/null || echo "unknown")
  if [[ "${BS_STATUS}" == "succeeded" ]]; then
    check_pass "Bootstrapper setup status: succeeded"
  elif [[ "${BS_STATUS}" == "running" ]]; then
    check_warn "Bootstrapper setup status: running (see oc logs -n rh-demo-bootstrapper deploy/demo-bootstrapper)"
  elif [[ "${BS_STATUS}" == "failed" ]]; then
    check_fail "Bootstrapper setup status: failed (pod stays Running; attach with oc rsh)"
  else
    check_warn "Bootstrapper setup status: ${BS_STATUS}"
  fi
else
  check_warn "Namespace rh-demo-bootstrapper not present (laptop setup, or not kicked off yet)"
fi
echo ""

# ─── Summary ────────────────────────────────────────────────────────────────────
echo "========================================="
if [[ "$ERRORS" -eq 0 ]]; then
  echo "All checks PASSED. Demo is ready."
else
  echo "$ERRORS check(s) FAILED."
  echo "Run 'setup/health-check.sh --fix' to attempt automatic recovery."
fi
echo "========================================="

# ─── Auto-fix mode ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--fix" ]]; then
  echo ""
  echo "========================================="
  echo "Attempting automatic recovery..."
  echo "========================================="

  # Fix 1: GPU driver stuck after reboot
  if [[ "$GPU_STATE" != "ready" || "$GPU_ALLOC" -lt 1 ]]; then
    echo ""
    echo ">>> Fixing GPU driver (post-reboot recovery)..."

    echo "    Scaling down inference service..."
    oc patch llminferenceservice llama-3-1-8b-fp8 -n models-as-a-service --type merge -p '{"spec":{"replicas":0}}' 2>/dev/null || true
    sleep 5
    oc delete pods -n models-as-a-service --all --force --grace-period=0 2>/dev/null || true
    sleep 5

    echo "    Force-deleting stuck NVIDIA pods..."
    oc get pods -n nvidia-gpu-operator --no-headers | grep -v "Running\|Completed" | awk '{print $1}' | \
      xargs -r -I{} oc delete pod {} -n nvidia-gpu-operator --force --grace-period=0 2>/dev/null

    echo "    Uncordoning GPU node..."
    GPU_NODE=$(oc get nodes -l node-role.kubernetes.io/worker-gpu -o name | head -1)
    oc adm uncordon ${GPU_NODE} 2>/dev/null || true

    echo "    Waiting for GPU driver to install (up to 300s)..."
    TIMEOUT=300
    INTERVAL=30
    ELAPSED=0
    while true; do
      STATE=$(oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
      if [[ "$STATE" == "ready" ]]; then
        echo "    GPU ClusterPolicy is ready!"
        break
      fi
      if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
        echo "    WARNING: GPU not ready after ${TIMEOUT}s. May need manual intervention."
        echo "    Try: oc delete pod -n nvidia-gpu-operator -l app=nvidia-driver-daemonset --force --grace-period=0"
        break
      fi
      # Check if driver pod is stuck due to inference pods
      DRIVER_LOG=$(oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset -c k8s-driver-manager --tail=3 2>/dev/null || true)
      if echo "$DRIVER_LOG" | grep -q "cannot delete Pods with local storage"; then
        echo "    Driver blocked by inference pod — cleaning..."
        oc delete pods -n models-as-a-service --all --force --grace-period=0 2>/dev/null || true
        oc delete pod -n nvidia-gpu-operator -l app=nvidia-driver-daemonset --force --grace-period=0 2>/dev/null || true
      fi
      echo "    GPU state: $STATE (${ELAPSED}s / ${TIMEOUT}s)"
      sleep "$INTERVAL"
      ELAPSED=$((ELAPSED + INTERVAL))
    done
  fi

  # Fix 2: Restore LLM Inference Service
  LLM_REPLICAS=$(oc get llminferenceservice llama-3-1-8b-fp8 -n models-as-a-service -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  if [[ "$LLM_REPLICAS" -lt 4 ]]; then
    echo ""
    echo ">>> Restoring LLM Inference Service replicas..."
    oc patch llminferenceservice llama-3-1-8b-fp8 -n models-as-a-service --type merge -p '{"spec":{"replicas":4}}'
  fi

  # Fix 3: Wait for inference to become ready
  echo ""
  echo ">>> Waiting for LLM Inference Service to become Ready (up to 600s)..."
  TIMEOUT=600
  INTERVAL=30
  ELAPSED=0
  while true; do
    READY=$(oc get llminferenceservice llama-3-1-8b-fp8 -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [[ "$READY" == "True" ]]; then
      echo "    LLMInferenceService is Ready!"
      break
    fi
    if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
      echo "    WARNING: LLM not ready after ${TIMEOUT}s. Check logs:"
      echo "    oc logs -n models-as-a-service -l app=llama-3-1-8b-fp8-kserve -c main --tail=20"
      break
    fi
    echo "    Status: $READY (${ELAPSED}s / ${TIMEOUT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  # Fix 4: Re-apply ServiceMonitor labels (operators recreate them on restart)
  echo ""
  echo ">>> Re-labeling operator ServiceMonitors (suppress bearerTokenFile rejections)..."
  oc label servicemonitor nfd-controller-manager-metrics-monitor -n openshift-nfd \
    openshift.io/user-monitoring=false --overwrite 2>/dev/null || true
  oc label servicemonitor odh-model-controller-metrics-monitor -n redhat-ods-applications \
    openshift.io/user-monitoring=false --overwrite 2>/dev/null || true
  oc label servicemonitor tempo-operator-controller-manager-metrics-monitor -n openshift-operators \
    openshift.io/user-monitoring=false --overwrite 2>/dev/null || true
  oc label servicemonitor opentelemetry-operator-metrics-monitor -n openshift-operators \
    openshift.io/user-monitoring=false --overwrite 2>/dev/null || true

  # Fix 5: Prometheus secret (monitoring stack)
  if oc get configmap prometheus-web-tls-ca -n redhat-ods-monitoring &>/dev/null; then
    if ! oc get secret prometheus-web-tls-ca -n redhat-ods-monitoring &>/dev/null; then
      echo ""
      echo ">>> Creating prometheus-web-tls-ca secret..."
      CA_DATA=$(oc get configmap prometheus-web-tls-ca -n redhat-ods-monitoring -o jsonpath='{.data.service-ca\.crt}')
      oc create secret generic prometheus-web-tls-ca -n redhat-ods-monitoring --from-literal=service-ca.crt="$CA_DATA"
      oc delete pod -n redhat-ods-monitoring -l app.kubernetes.io/name=prometheus --ignore-not-found 2>/dev/null || true
    fi
  fi

  # Fix 6: Perses service alias
  if ! oc get svc perses -n redhat-ods-monitoring &>/dev/null; then
    echo ""
    echo ">>> Recreating 'perses' service alias..."
    cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: perses
  namespace: redhat-ods-monitoring
  labels:
    app: perses-alias
spec:
  type: ExternalName
  externalName: data-science-perses.redhat-ods-monitoring.svc.cluster.local
EOF
  fi

  echo ""
  echo "========================================="
  echo "Recovery complete. Run this script again without --fix to verify."
  echo "========================================="
fi

exit $ERRORS
