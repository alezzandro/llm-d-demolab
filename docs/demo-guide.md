# Demo Guide — llm-d + MaaS Booth Hybrid

**Audience:** conference booth visitors  
**Duration:** ~8–12 minutes (compress Catalog if needed)  
**Presenter prep:** `health-check.sh`, `show-credentials.sh`, Dev Workspace running, Open WebUI first login done, **Prefix Cache Lab** tab open

## Story in one sentence

MaaS decides **who** can use the model and **how much**; llm-d makes the **same four GPUs** deliver far better **P95** latency when prefixes hit the KV cache (and, with EPP, when traffic sticks to the warm replica).

## Timing table

| Beat | Time | Screen / action |
|---|---|---|
| Hook | 1 min | Shared LLM; GPU cost; pain is **P95**, not average |
| Catalog / Registry | 1–2 min | RHOAI → Catalog → Llama 3.1 8B FP8 → Registry version / ModelCar |
| MaaS | 2 min | Two subscriptions, keys, rate limits, cost centers |
| llm-d | 2–3 min | Prefix Cache Lab UI — Run comparison; glance at EPP chart |
| Dev Spaces | 2–3 min | Continue chat / autocomplete on sample Ansible |
| Open WebUI | 1–2 min | Ops chatbot on second subscription |
| Close | 30s | Govern access (MaaS) + optimize GPUs (llm-d) |

**Short path:** if a visitor has ~5 minutes, do Hook → Prefix Cache Lab → Dev Spaces → Close.

---

## Pre-demo checklist

```bash
bash setup/health-check.sh
bash setup/show-credentials.sh
```

- [ ] 4 GPU nodes Ready; `LLMInferenceService` Ready with `replicas: 4`
- [ ] `MaaSModelRef` Ready; gateway Programmed
- [ ] Dev Spaces workspace **already open** (avoid 30–60s cold start)
- [ ] Open WebUI admin account created; model responds
- [ ] Prefix Cache Lab Route loads; optional dry-run of **Run comparison** once before the floor opens

---

## Beat scripts

### 1. Hook (1 min)

> Teams want one shared LLM for many apps. GPUs are expensive. Scaling replicas with round-robin improves throughput but **worst-case latency** (P95 TTFT) stays painful because every replica recomputes the same prompt prefixes.

### 2. Catalog / Registry (1–2 min)

Open RHOAI dashboard → Model Catalog → Llama 3.1 8B Instruct FP8 (or registered model) → Model Registry version **v1.5** and OCI ModelCar URI.

Talking points:

- Validated ModelCar from `registry.redhat.io`
- Audit trail: who registered what version
- Fits L4 with FP8; we run **four** replicas for routing

### 3. MaaS governance (2 min)

Show two `MaaSSubscription` objects (or dashboard equivalent):

| | Dev Spaces | Open WebUI |
|---|---|---|
| Cost center | `engineering-tools` | `customer-support` |
| Rate limit | 50k / 1h | 100k / 1h |
| API key | independent | independent |

> Same model pool. Separate keys, quotas, and chargeback metadata. That is Models-as-a-Service.

### 4. llm-d / prefix cache (2–3 min)

1. Glance at Topology / pods in `models-as-a-service` — **four** vLLM backends on four L4s  
2. Open **Prefix Cache Lab** (`show-credentials.sh` → Prefix Cache Lab URL)  
3. Click **Run comparison** (or unique → shared). Wait ~20–40s.  
4. Point at the TTFT bars and the large **% improvement** callout  
5. Scroll to the canned **EPP vs naive LB** chart — especially concurrency **64** TTFT p95 **24391 ms → 478 ms** (~98%)

Talking points:

- Live buttons: same MaaS endpoint; **unique** prefixes miss cache, **shared** prefixes hit `--enable-prefix-caching`  
- Canned chart: what **prefix-cache-aware EPP routing** adds on top (sticky warm replica). Live EPP through MaaS is not on the booth path (empty chat body on 3.4.2 dry-run; 3.5 still uses Service LB) — see architecture note  
- Model id for clients: **`llama-3-1-8b-instruct-fp8`**

Between visitors: click **Reset results** in the Lab UI (no cluster teardown).

### 5. Dev Spaces consumer (2–3 min)

Deep-link / open pre-warmed workspace → Continue chat or tab-complete on `sample-playbooks/`.

> This traffic uses the **dev** subscription key. Platform engineering gets AI assist without a shadow SaaS endpoint.

### 6. Open WebUI consumer (1–2 min)

Chat: “Generate an Ansible playbook to restart a failed Deployment and notify Slack.”

> Same weights, **ops** subscription — separate quota and cost center. Governance without a second GPU farm.

### 7. Close (30s)

> MaaS = who and how much. llm-d = how fast on the GPUs you already bought. Together: governed, multi-tenant, production-shaped inference on OpenShift AI.

---

## Objections / FAQ

| Question | Answer |
|---|---|
| Why 4 GPUs? | llm-d’s wow moment needs multiple replicas; lab numbers use 4. |
| Can we do this on 1 GPU? | MaaS yes; prefix-cache routing story needs ≥2 replicas. |
| Why not live flag toggle? | Restarting vLLM to flip `--enable-prefix-caching` takes minutes; the Lab UI proves the effect with unique vs shared prefixes in ~30s. |
| Is this the same as the MaaS-only demo? | That demo used 1 replica and no EPP. This merges MaaS with real llm-d. |
| Deployments → Edit opens a blank wizard | Must open Edit from the action menu (React Router state). Hard-refreshing `/ai-hub/models/deployments/deploy` always shows create. Also needs `opendatahub.io/connections` + OCI connection Secret (phase 06). |

## Between visitors

```bash
# Prefer: Reset results in Prefix Cache Lab (no key churn)
bash setup/reset-demo.sh   # only if you need fresh keys / clean consumers
# Re-open Dev Spaces workspace deep-link; confirm WebUI login
bash setup/show-credentials.sh
```

Do **not** scale the `LLMInferenceService` to 0 between visitors unless recovering GPUs.

## Overnight

Scale GPU MachineSets to 0 (or stop instances) to control AWS cost. Next morning: scale back to 4, then `bash setup/health-check.sh --fix`.
