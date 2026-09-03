#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
GPU_PROVISIONER_DIR="${REPO_ROOT}/ocp-gpu-provisioner-aws"
REQUIRED_GPU_NODES=4

source "${SCRIPT_DIR}/ensure-authenticated.sh"

echo "========================================="
echo "Phase 0: GPU Provisioner (${REQUIRED_GPU_NODES}x L4)"
echo "========================================="

echo "1. Cloning ocp-gpu-provisioner-aws..."
if [[ -d "$GPU_PROVISIONER_DIR" ]]; then
  echo "   Already cloned, pulling latest..."
  git -C "$GPU_PROVISIONER_DIR" pull --quiet
else
  git clone https://github.com/alezzandro/ocp-gpu-provisioner-aws.git "$GPU_PROVISIONER_DIR"
fi

echo "2. Setting up Python virtual environment..."
cd "$GPU_PROVISIONER_DIR"
if [[ ! -d ".venv" ]]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install -e . --quiet

echo "3. Running GPU provisioner (g6.2xlarge, ${REQUIRED_GPU_NODES} replicas)..."
ocp-gpu-provisioner --instance-type g6.2xlarge --replicas "${REQUIRED_GPU_NODES}"

echo "   Scaling down extra GPU MachineSets; keeping one at ${REQUIRED_GPU_NODES} replicas..."
GPU_MACHINESETS=$(oc get machinesets -n openshift-machine-api --no-headers -o custom-columns='NAME:.metadata.name' | grep gpu || true)
FIRST_GPU_MS=""
for ms in $GPU_MACHINESETS; do
  if [[ -z "$FIRST_GPU_MS" ]]; then
    FIRST_GPU_MS="$ms"
    oc scale machineset "$ms" -n openshift-machine-api --replicas="${REQUIRED_GPU_NODES}" 2>/dev/null || true
  else
    oc scale machineset "$ms" -n openshift-machine-api --replicas=0 2>/dev/null || true
  fi
done
echo "   Keeping: ${FIRST_GPU_MS} at ${REQUIRED_GPU_NODES} replicas"

echo "4. Waiting for ${REQUIRED_GPU_NODES} GPU nodes to become Ready..."
echo "   This may take 10-20 minutes for AWS instances to launch..."
TIMEOUT=1200
INTERVAL=30
ELAPSED=0
while true; do
  GPU_NODES=$(oc get nodes -l node-role.kubernetes.io/worker-gpu --no-headers 2>/dev/null | grep -c " Ready" || true)
  if [[ "$GPU_NODES" -ge "$REQUIRED_GPU_NODES" ]]; then
    echo "   ${GPU_NODES} GPU nodes are Ready!"
    break
  fi
  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "ERROR: Timeout waiting for ${REQUIRED_GPU_NODES} GPU nodes (have ${GPU_NODES})"
    exit 1
  fi
  echo "   Waiting... GPU Ready=${GPU_NODES}/${REQUIRED_GPU_NODES} (${ELAPSED}s / ${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "5. Verifying nvidia.com/gpu capacity across GPU nodes..."
TOTAL_GPU=0
for capacity in $(oc get nodes -l node-role.kubernetes.io/worker-gpu \
  -o jsonpath='{range .items[*]}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null); do
  TOTAL_GPU=$((TOTAL_GPU + ${capacity:-0}))
done
if [[ "$TOTAL_GPU" -ge "$REQUIRED_GPU_NODES" ]]; then
  echo "   Total GPU capacity: nvidia.com/gpu=${TOTAL_GPU}"
else
  echo "   WARNING: Only ${TOTAL_GPU} GPUs reported. Drivers may still install in Phase 1."
fi

deactivate
cd "$REPO_ROOT"

echo ""
echo "Phase 0 complete: ${REQUIRED_GPU_NODES} GPU worker nodes provisioned."
echo "========================================="
