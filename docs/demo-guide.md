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
| Catalog / Registry | 1–2 min | OpenShift AI → Catalog → Llama 3.1 8B FP8 → Registry version / ModelCar |
| MaaS | 2 min | Two subscriptions, keys, rate limits, cost centers |
| llm-d | 2–3 min | Physics (no click) → Prefix Cache Lab **Run comparison** → EPP leave-behind chart |
| Playground | 1–2 min | Gen AI Studio chat on the same llm-d pool (bypasses MaaS) |
| Dev Spaces | 2–3 min | Continue chat / autocomplete on sample Ansible |
| Open WebUI | 1–2 min | Ops chatbot on second subscription |
| Close | 30s | Govern access (MaaS) + optimize GPUs (llm-d) |

**Short path (~6 min):** Hook → Prefix Cache Lab → Playground → Close.

**Do not during booth hours:** AutoML, training jobs, long GuideLLM runs, scaling the `LLMInferenceService` to 0, enabling InferencePool/EPP on the live MaaS path.

---

## Pre-demo checklist

```bash
bash setup/health-check.sh
bash setup/show-credentials.sh
```

- [ ] 4 GPU nodes Ready; `LLMInferenceService` Ready with `replicas: 4` (no leftover Init/Unknown vLLM pods)
- [ ] `MaaSModelRef` Ready; gateway Programmed; MaaS `/v1/models` HTTP 200
- [ ] Dev Spaces workspace **already open**; Continue extension enabled globally (not just config.json)
- [ ] Open WebUI admin account created; model responds **without** builtin tool cards (`grep_knowledge_files`)
- [ ] Prefix Cache Lab Route loads; dry-run **Run comparison** once before the floor opens
- [ ] Lab tab stays open; **Reset results** between visitors
- [ ] Gen AI Studio → Playground loads in project `models-as-a-service` (OGXServer Ready)

---

## Beat scripts

### 1. Hook (1 min)

**Say this**

> Teams want one shared LLM for many apps. NVIDIA L4s are expensive. Adding replicas with round-robin improves *throughput*, but **worst-case latency** — P95 time-to-first-token — stays painful because every replica recomputes the same prompt prefixes.

**Do not say**

- “We made the model smarter.” This is serving, not fine-tuning.
- “Average latency is the KPI.” Visitors feel the tail: the slowest 5% of requests.

**Point at:** four GPU worker nodes / four vLLM pods if Topology is already on screen.

---

### 2. Catalog / Registry (1–2 min)

Open OpenShift AI → **AI hub → Catalog** → Llama 3.1 8B Instruct FP8 (or the registered model) → Model Registry version **v1.5** and the OCI ModelCar URI.

**Say this**

- Validated ModelCar from `registry.redhat.io` — not a random Hugging Face pull.
- Registry is the audit trail: who registered which version.
- FP8 fits an L4; we run **four** replicas so there is a routing story, not because 8B needs tensor parallelism.

Skip or compress if the visitor is already in “show me latency.”

---

### 3. MaaS governance (2 min)

Show two `MaaSSubscription` objects (or **MaaS settings** in the dashboard):

| | Dev Spaces | Open WebUI |
|---|---|---|
| Cost center | `engineering-tools` | `customer-support` |
| Rate limit | 50k tokens / 1h | 100k tokens / 1h |
| API key | independent | independent |

**Say this**

> Same model pool. Separate keys, quotas, and chargeback metadata. That is Models-as-a-Service: **who** and **how much**, not a second GPU farm per team.

**Do not say**

- That MaaS by itself makes P95 collapse. Governance and performance are different layers.

Official overview: [Govern LLM access with Models-as-a-Service (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/).

---

### 4. llm-d performance (2–3 min)

This is the wow beat. Run it as **three layers**. Do not skip the honesty line on layer 3.

#### Layer A — Physics (30–45s, no click)

Prefill vs decode, in one breath:

1. The expensive part of a chat request is **prefill**: turning the prompt (system + tools + RAG header + user) into a KV cache.
2. **Decode** (generating tokens) reuses that cache. Shared prefixes — the same system prompt, the same tool schema — should be free the second time **on the replica that already computed them**.
3. Four GPUs with naive round-robin still **recompute** that prefix whenever the next request lands on a cold replica. Throughput goes up; **P95 TTFT** does not.

**Say this**

> GPUs are the scarce resource. llm-d is how you stop paying prefill tax on every replica for the same enterprise prefix.

**Do not say**

- “KV cache is just RAM for the model weights.” Weights are loaded once; KV cache is **per-request computed context**.

#### Layer B — Live Prefix Cache Lab (90–120s)

1. Glance at Topology / pods in `models-as-a-service` — **four** vLLM backends, one L4 each.
2. Open **Prefix Cache Lab** (`show-credentials.sh` → Prefix Cache Lab URL). Keep this tab dedicated.
3. Click **Run comparison** (unique + shared). Wait ~20–40s. Do not click again mid-run.
4. Point at median / p95 bars and the large **% improvement** callout.

**What the visitor should see**

| Mode | What the Lab sends | Cache | Bars |
|---|---|---|---|
| Unique | Distinct system prompts | Miss — full prefill | High TTFT |
| Shared | Repeated system prompt | Hit — `--enable-prefix-caching` | Lower TTFT |

Same model id **`llama-3-1-8b-instruct-fp8`**, same MaaS endpoint, same four GPUs. Only the prefix changes.

**Say this**

> Live buttons prove prefix caching **on each replica**. Shared enterprise context is cheap on the second hit; unique prefixes pay full prefill.

**If the gap is small**

- Let both runs finish; do not restart vLLM.
- Click **Reset results**, run comparison once more (first unique run can still be warming).
- If MaaS is HTTP 503, that is gateway WASM fail-closed — `health-check.sh --fix`, not a Lab bug. See Overnight.

**Do not say**

- That this live chart **is** EPP / InferencePool. It is not. Service load-balancing is on the live path.

Between visitors: **Reset results** in the Lab UI (no cluster teardown).

#### Layer C — EPP leave-behind (45–60s)

Scroll to the canned **prefix-cache-aware routing vs naive LB** chart.

Wow metric (showroom, 4× GPU, Llama 3.1 8B Instruct FP8, GuideLLM concurrent @ 64):

**TTFT p95 24391 ms → 478 ms (~98% faster).**

At concurrency 32 the same story is milder (TTFT p95 7551 → 4677 ms). Advantage **grows under load** because naive LB wastes KV prefixes (~25% hit rate) while `prefix-cache-scorer` sticks repeat prefixes to the warm replica (80–90%+ hits).

Full table: [docs/assets/baseline-comparison.md](assets/baseline-comparison.md).

**Say this**

> Caching on a replica is layer one. **Routing** is layer two: send the next request to the GPU that already has that prefix. That is the Endpoint Picker. These numbers are the leave-behind from that routing story.

**Honesty line (required)**

> Live EPP through MaaS is **not** on this booth path. On OpenShift AI 3.4.2, InferencePool behind MaaS returned HTTP 200 with an empty chat body. This cluster uses the workload Service. Live buttons = prefix caching. Chart = what prefix-cache-aware routing adds on top.

**Do not say**

- “Watch the live bars; that *is* EPP.”
- “We toggled `--enable-prefix-caching` live.” Restarting vLLM takes minutes; unique vs shared is the 30-second proof.

---

### 5. Gen AI Playground (1–2 min)

**Navigate:** OpenShift AI → **Gen AI studio** → **Playground** → project **models-as-a-service**.

If the playground is not created yet: **Create playground** (or **Add to playground** from AI asset endpoints) and pick Llama 3.1 8B Instruct FP8 as Inference.

Prompt: **“Write a short Ansible task to install and start nginx on Red Hat Enterprise Linux 9.”**

Optional MCP (OpenShift MCP is read-only): **“How many pods are running in models-as-a-service?”**

**Say this**

> Same four GPUs, but this path is the **platform Playground** — OGX talks to vLLM on the cluster network. Dev Spaces and Open WebUI go through **MaaS** so we can meter and limit them. Trusted in-cluster tools versus multi-tenant consumption.

**Do not say**

- That Playground traffic shows up on the Usage dashboard. It bypasses Limitador on purpose.

See [Experimenting with models in the gen AI playground (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/experimenting_with_models_in_the_gen_ai_playground/index).

---

### 6. Dev Spaces consumer (2–3 min)

Deep-link / open the **pre-warmed** workspace → Continue chat or tab-complete on `sample-playbooks/`.

If Continue is missing from Extensions, reload the Dev Spaces tab. First start installs the Continue vsix about a minute after the editor process is up (`DEFAULT_EXTENSIONS`). `postStart` only copies `~/.continue/` config; the extension itself comes from ConfigMaps in the user namespace (`vscode-editor-configurations` + `vscode-default-extensions`).

**Say this**

> This traffic uses the **dev** subscription key. Platform engineering gets AI assist without a shadow SaaS endpoint.

If Continue is cold, type in chat rather than waiting on autocomplete.

---

### 7. Open WebUI consumer (1–2 min)

Prompt: “Generate an Ansible playbook to restart a failed Deployment and notify Slack.”

Open WebUI 0.10+ Native mode is disabled (`function_calling: legacy`) so the 8B model does not invent `grep_knowledge_files` calls.

**Say this**

> Same weights, **ops** subscription — separate quota and cost center. Governance without a second GPU farm.

---

### 8. Close (30s)

> MaaS = who and how much. llm-d = how fast on the GPUs you already bought. Together: governed, multi-tenant, production-shaped inference on OpenShift AI 3.5.

Hand them: Catalog → Registry → 4× `LLMInferenceService` → dual subscriptions → live prefix-cache gap → EPP P95 chart as the routing roadmap.

---

## Optional: what’s new in OpenShift AI 3.5 (60–90s)

Only if the visitor asks. **Not** the default 8–12 min path. Phase 4 enables the dashboard flags and control-plane operators (OGX, AI Pipelines, TrustyAI, MLflow). Playground itself is deployed (CPU `OGXServer` + OpenShift MCP). Do **not** start AutoML or training jobs — those would compete with the four L4s.

Glance, then return to MaaS + llm-d:

| If they ask | Open | One line |
|---|---|---|
| Gen AI Studio / Playground | Gen AI studio | Prompt chat on the llm-d pool; MCP optional. Default beat is §5. [Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user) |
| MCP / agents | AI hub → MCP servers | OpenShift MCP is deployed; Fetch / Sequential-Thinking listed in the catalog ConfigMap |
| llm-d templates | Deployments wizard / Settings | Topology and routing fields (`llmdTemplates`); live booth still uses Service LB |
| Eval Hub | Develop & train → Evaluations | TrustyAI / LMEval nav is on; do not start a GPU eval during the show |

---

## Objections / FAQ

| Question | Answer |
|---|---|
| Why 4 GPUs? | The routing story needs multiple replicas. Lab / showroom numbers use 4× L4. One GPU can show MaaS, not prefix-aware routing. |
| Can we do this on 1 GPU? | MaaS yes. Live unique-vs-shared cache still works on one replica; EPP P95 collapse needs ≥2. |
| Why not toggle prefix-caching live? | Restarting vLLM takes minutes. Unique vs shared prefixes prove the KV hit in ~30s. |
| Are the live bars EPP? | **No.** Live = `--enable-prefix-caching` under Service LB. Chart = prefix-cache-aware EPP routing leave-behind. |
| Is this the MaaS-only demo? | That used 1 replica and no llm-d beat. This is MaaS plus a real 4-replica pool. |
| Why is EPP not live? | InferencePool through MaaS returned empty chat bodies (3.4.2 dry-run). Re-validate upstream before putting it on the booth path. |
| Deployments → Edit is blank | Open Edit from the action menu (React Router state). Hard-refreshing `/ai-hub/models/deployments/deploy` is always create. Needs `opendatahub.io/connections` + OCI connection Secret (phase 06). |
| Why is Gen AI Studio empty? | Confirm `OGXServer/ogx-genai-playground` is Ready and you selected project `models-as-a-service`. Create playground once if the UI has no instance yet. |
| Does Playground count on Usage? | **No.** OGX talks to vLLM over ClusterIP and bypasses Limitador on purpose. |
| Can we run AutoML / training? | Not during booth hours. Ray / Kueue / TrainingOperator stay Removed so the four L4s stay on the model. |

---

## Between visitors

```bash
# Prefer: Reset results in Prefix Cache Lab (no key churn)
bash setup/reset-demo.sh   # only if you need fresh keys / clean consumers
# Re-open Dev Spaces workspace deep-link; confirm WebUI login
bash setup/show-credentials.sh
```

Do **not** scale the `LLMInferenceService` to 0 between visitors unless recovering GPUs.

---

## Overnight

Scale GPU MachineSets to 0 (or stop instances) to control AWS cost. Next morning: scale back to 4, then `bash setup/health-check.sh --fix`.

`--fix` also restarts MaaS gateway pods when `/v1/models` returns HTTP 503 (Kuadrant WASM fail-closed after a gateway/operator race) and clears a leftover bootstrapper `DEMO_RETRY` without re-running setup. The bootstrapper PVC status is advisory; a `failed` file after a completed install is not a demo outage.
