#!/bin/bash
# End-to-end verification for the Prefix Cache Lab booth UI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${REPO_ROOT}/setup/ensure-authenticated.sh"

NS="prefix-cache-lab"
ERRORS=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; ERRORS=$((ERRORS + 1)); }

echo "========================================="
echo "  Prefix Cache Lab — end-to-end test"
echo "========================================="

echo "1. Namespace / Deployment"
if oc get ns "${NS}" &>/dev/null; then
  pass "namespace ${NS} exists"
else
  fail "namespace ${NS} missing (run setup/12-prefix-cache-lab.sh)"
  exit 1
fi

READY=$(oc get deploy prefix-cache-lab -n "${NS}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${READY:-0}" -ge 1 ]]; then
  pass "deployment ready (${READY})"
else
  fail "deployment not ready"
fi

HOST=$(oc get route prefix-cache-lab -n "${NS}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "$HOST" ]]; then
  pass "route ${HOST}"
else
  fail "route missing"
  exit 1
fi
BASE="https://${HOST}"

echo ""
echo "2. HTTP surface"
HEALTH=$(curl -sk --max-time 20 "${BASE}/api/health" || true)
if echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('status')=='ok' and d.get('maas_configured') is True" 2>/dev/null; then
  pass "/api/health ok + maas_configured"
else
  fail "/api/health failed: ${HEALTH:0:120}"
fi

INDEX_CODE=$(curl -sk --max-time 20 -o /tmp/pcl-index.html -w "%{http_code}" "${BASE}/" || echo "000")
if [[ "$INDEX_CODE" == "200" ]] && grep -q "Prefix Cache Lab" /tmp/pcl-index.html; then
  pass "index page HTTP 200"
else
  fail "index page HTTP ${INDEX_CODE}"
fi

echo ""
echo "3. Smoke job (1 unique + 1 shared via MaaS — poll /api/run/{id})"
# Wait if a previous run is still holding the lock.
for i in $(seq 1 60); do
  BUSY=$(curl -sk --max-time 10 "${BASE}/api/health" | python3 -c "import sys,json; print(json.load(sys.stdin).get('busy', False))" 2>/dev/null || echo True)
  [[ "$BUSY" == "False" ]] && break
  echo "  waiting for idle lab… (${i}s)"
  sleep 2
done

START=$(curl -sk --max-time 30 -X POST "${BASE}/api/run" \
  -H "Content-Type: application/json" \
  -d '{"mode":"smoke"}' || true)
JOB_ID=$(echo "$START" | python3 -c "import sys,json; print(json.load(sys.stdin).get('job_id',''))" 2>/dev/null || true)
if [[ -z "$JOB_ID" ]]; then
  fail "could not start smoke job: ${START:0:160}"
else
  pass "started job ${JOB_ID}"
  RESULT_FILE=/tmp/pcl-smoke.json
  SMOKE_OK=0
  for i in $(seq 1 90); do
    POLL=$(curl -sk --max-time 20 "${BASE}/api/run/${JOB_ID}" || true)
    STATUS=$(echo "$POLL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)
    if [[ "$STATUS" == "completed" ]]; then
      echo "$POLL" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('result'), indent=2))" > "${RESULT_FILE}"
      if python3 <<'PY'
import json, sys
d = json.load(open("/tmp/pcl-smoke.json"))
u, s = d.get("unique") or {}, d.get("shared") or {}
print(f"  unique ok={u.get('ok_count')}/{u.get('requests')} ttft={u.get('ttft_median_ms')}ms errors={u.get('errors')}")
print(f"  shared ok={s.get('ok_count')}/{s.get('requests')} ttft={s.get('ttft_median_ms')}ms errors={s.get('errors')}")
sys.exit(0 if d.get("ok") and (u.get("ok_count") or 0) >= 1 and (s.get("ok_count") or 0) >= 1 else 1)
PY
      then
        pass "smoke unique+shared completions succeeded"
        SMOKE_OK=1
      else
        fail "smoke completed but MaaS completions failed"
        SMOKE_OK=1
      fi
      break
    fi
    if [[ "$STATUS" == "failed" ]]; then
      fail "smoke job failed: ${POLL:0:200}"
      SMOKE_OK=1
      break
    fi
    sleep 2
  done
  if [[ "$SMOKE_OK" -eq 0 ]]; then
    fail "smoke job timed out waiting for completion"
  fi
fi

echo ""
echo "========================================="
if [[ "$ERRORS" -eq 0 ]]; then
  echo "PASS: Prefix Cache Lab is working."
  echo "UI: ${BASE}"
  exit 0
fi
echo "FAIL: ${ERRORS} check(s) failed."
exit 1
