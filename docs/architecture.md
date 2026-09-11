# Architecture

## Overview

Governed multi-consumer LLM serving on OpenShift AI 3.5: **MaaS** for who/how-much, **llm-d** for how-fast on the same 4× L4 pool.

```
┌────────────────────────────────────────────────────────────────────────────┐
│                     OpenShift 4.22 + RHOAI 3.5 (AWS)                        │
│                                                                            │
│  Catalog → Registry → LLMInferenceService (4× vLLM + EPP)                 │
│                              ▲                                             │
│                              │                                             │
│                    maas-default-gateway                                    │
│                    Kuadrant / Authorino                                    │
│                              ▲                                             │
│              ┌───────────────┴────────────────┐                            │
│              │                                │                            │
│     Dev Spaces + Continue              Open WebUI                          │
│     (devspaces-subscription)           (chatbot-subscription)              │
│     costCenter: engineering-tools      costCenter: customer-support        │
│                                                                            │
│     Prefix Cache Lab (booth UI) ──► same MaaS endpoint (ops key)           │
└────────────────────────────────────────────────────────────────────────────┘
```

## llm-d serving path

```
Client (MaaS API key)
  → Gateway (maas-default-gateway)
  → Authorino / subscription quota
  → Endpoint Picker (EPP)
       plugins: prefix-cache-scorer (w3), queue-scorer (w2), active-request-scorer (w2)
  → vLLM replica with matching KV prefix (1 of 4 L4 GPUs)
```

**Why EPP matters:** naive LB across replicas recomputes shared prefixes (~25% KV hit rate). Prefix-cache-aware routing targets 80–90%+ hits and collapses P95 TTFT under concurrency.

## Component map

| Component | Purpose | Namespace |
|---|---|---|
| DataScienceCluster | KServe + MaaS + ModelRegistry | cluster-scoped |
| HardwareProfile `gpu-l4-nvidia` | Dashboard GPU template | `redhat-ods-applications` |
| `LLMInferenceService` `llama-3-1-8b-fp8` | 4-replica llm-d serving | `models-as-a-service` |
| `MaaSModelRef` `llama-3-1-8b` | Registers pool with MaaS | `models-as-a-service` |
| MaaSSubscription ×2 | Independent quotas / cost centers | `models-as-a-service` |
| MaaSAuthPolicy ×2 | Group → model access | `models-as-a-service` |
| CheCluster | Dev Spaces | `openshift-devspaces` |
| Open WebUI | Ops chat UI | `open-webui` |
| Prefix Cache Lab | Booth unique/shared TTFT microbench UI | `prefix-cache-lab` |
| Perses / UWM | MaaS usage + model metrics | `redhat-ods-monitoring` |

## Dual-subscription punchline

Same model weights and GPU pool; separate API keys, rate limits, and cost-center metadata:

| Consumer | Group | Subscription | Limit (demo) | Cost center |
|---|---|---|---|---|
| Dev Spaces / Continue | `devspaces-users` | `devspaces-subscription` | 50k tokens / 1h | `engineering-tools` |
| Open WebUI | `chatbot-users` | `chatbot-subscription` | 100k tokens / 1h | `customer-support` |

## Request flow (consumer)

```
User (Continue or Open WebUI)
  → POST .../models-as-a-service/llama-3-1-8b-fp8/v1/chat/completions
  → Authorization: Bearer <subscription-api-key>
  → Gateway + Authorino validate key + quota
  → EPP picks replica with best prefix / queue score
  → vLLM returns completion; MaaS records token usage
```

## Model lifecycle (demo narrative)

```
Model Catalog (Red Hat AI)
  → Register in Model Registry (version + ModelCar URI)
  → Deploy LLMInferenceService (llm-d, replicas=4)
  → MaaSModelRef + dual subscriptions
  → Consumers: Dev Spaces + Open WebUI
```

## Hardware

- **4×** AWS `g6.2xlarge` (NVIDIA L4 ~24GB each)
- One GPU per vLLM replica; no tensor parallelism for this 8B FP8 model
- Node selector / toleration: `worker-gpu` + `nvidia.com/gpu`

## Out of scope (v1) / dry-run notes

- Side-by-side live naive LB deployment (would need 8 GPUs)
- Full 300s GuideLLM during booth hours (prep-day / canned numbers only)
- Sample `OGXServer`, MCP servers, AutoML/training jobs (would compete with the 4× L4 llm-d pool)

Phase 4 enables OpenShift AI 3.5 **dashboard flags** and **control-plane** DSC operators (OGX, AI Pipelines, TrustyAI, MLflow) so Gen AI Studio, MCP catalog, Eval Hub, and llm-d templates appear in the UI. Ray, Kueue, and TrainingOperator stay **Removed**. Playground chat still needs an `OGXServer` you deploy later; see [Activating the OGX Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/working_with_ogx/activating-the-ogx-operator_rag) and [Customize the dashboard (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_resources/customizing-the-dashboard).

### InferencePool / EPP (not on the live MaaS path)

Enabling the well-known scheduler preset or embedding a showroom-style custom EPP config caused **`/v1/chat/completions` through the MaaS gateway to return HTTP 200 with an empty body** (validated on OpenShift AI **3.4.2** dry-run). Direct calls to vLLM pods worked; `/v1/models` through MaaS also worked. Traffic to `InferencePool` backends was affected; switching the HTTPRoute backends back to the workload `Service` restored chat completions.

**Booth v1 serving choice (still used on 3.5):** `LLMInferenceService` with **4 replicas**, `--enable-prefix-caching`, MaaS gateway, and **Service** load-balancing (no InferencePool/EPP on the request path). Use [`docs/assets/baseline-comparison.md`](assets/baseline-comparison.md) for the prefix-cache-aware routing P95 story until the MaaS+InferencePool response-body issue is re-validated upstream.

**Prefix Cache Lab UI** (`apps/prefix-cache-lab`, namespace `prefix-cache-lab`): FastAPI booth page that issues concurrent streamed chat completions through MaaS — **unique** prefixes vs a **shared** system prompt — and charts TTFT live. It does **not** toggle the vLLM flag or enable InferencePool; the EPP chart on the page is the canned leave-behind. Deployed by [`setup/12-prefix-cache-lab.sh`](../setup/12-prefix-cache-lab.sh).

**Served model id** (for API clients / Continue): `llama-3-1-8b-instruct-fp8` (not the CR name `llama-3-1-8b-fp8`).

## Validated on OpenShift AI 3.5.0

The RHOAI Subscription uses channel **`stable-3.x`** with Automatic approval, so a booth cluster receives the latest 3.x CSV (**3.5.0** at validation time), not 3.4.x. Setup scripts discover versioned CRs at runtime. Differences from the original 3.4 manifests:

1. **KServe preset** — NVIDIA `LLMInferenceServiceConfig` names are versioned. On 3.5 the accelerator template is `v3-5-0-kserve-config-llm-single-node-template-nvidia-cuda`. [`setup/06-deploy-llmd-model.sh`](../setup/06-deploy-llmd-model.sh) substitutes whatever preset exists on the cluster.
2. **MaaS vs ODH AuthPolicy** — The Gateway must be annotated `opendatahub.io/managed: "false"`, and the `LLMInferenceService` must set `security.opendatahub.io/enable-auth: "false"`. Otherwise `odh-model-controller` installs `{gateway}-authn` on the same Gateway and Kuadrant **overrides** MaaS `maas-gateway-auth` (API keys / `X-MaaS-Username`). Phase 8 deletes the competing policy if it is still present. See [Govern LLM access with Models-as-a-Service (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/).
3. **API keys in-cluster** — `maas-api` runs in `redhat-ai-gateway-infra`. The bootstrapper ServiceAccount is not in `chatbot-users` / `devspaces-users`, so phase 8 mints keys by calling `maas-api` with `X-MaaS-Username` (`DEMO_ADMIN_USER`) and a JSON `X-MaaS-Group` header, then stores them in Secrets.
4. **Telemetry** — Patch `MaasTenantConfig/default-tenant` in `models-as-a-service` (3.5). The older `Tenant` CR is unused on this stack.
5. **Dashboard** — Do not add deprecated `spec.dashboardConfig.maasAuthPolicies`; the CRD CEL rule rejects adding that key when it was absent. Phase 4 turns on 3.5 feature flags (`genAiStudio`, `mcpCatalog`, `llmdTemplates`, `disableLMEval=false`, …) plus OGX / AI Pipelines / TrustyAI / MLflow. Do not add Ray/Kueue/TrainingOperator on the booth cluster.
6. **Model Registry** — Register models with `oc exec -c rest-container` against `http://127.0.0.1:8080`. Curling the ClusterIP from inside the same pod times out (CNI hairpin).
7. **Verify script** — Look for `maas-api` in `redhat-ai-gateway-infra` (fallback: `redhat-ods-applications`) and DSC condition `ModelsAsAServiceReady` (fallback: `ModelsAsServiceReady`).
8. **Bootstrapper** — `git config --global --add safe.directory /work/src` because the PVC clone is not owned by the container user. `oc logs` only follows PID 1; after a failure the entrypoint sleeps — resume with `DEMO_RETRY=true` and delete the pod (see [bootstrapper.md](bootstrapper.md)). After setup succeeds, leave `DEMO_RETRY=false` and clear `DEMO_SETUP_ARGS`. An overnight pod restart with those flags still set re-runs a phase and overwrites `/work/status` to `failed` even when serving is healthy.
9. **Overnight MaaS HTTP 503** — If the Connectivity Link (Kuadrant) operator and MaaS gateway pods restart together, Envoy can fail to fetch `plugin.wasm` from Service `kuadrant-operator-wasm` in `openshift-operators`. The WASM filter **fails closed** (`wasm_fail_stream`): every MaaS route returns empty HTTP 503 while the Gateway stays Programmed and vLLM still answers on the workload Service. Bounce the MaaS gateway pods (`setup/health-check.sh --fix`) so Envoy re-fetches the plugin.
10. **Leftover `Init:ContainerStatusUnknown` vLLM pods** — After a GPU node drain or `UnexpectedAdmissionError`, old `llama-3-1-8b-fp8-kserve-*` pods stay Failed with no IP while four healthy replicas serve traffic. They are not a serving outage. `health-check.sh --fix` and phase 6 force-delete those leftovers; they never delete Running replicas.
11. **Open WebUI 0.10+ Native/Agentic tools** — Floating `open-webui:main` now defaults to Native function calling and injects builtin tools such as `grep_knowledge_files`. Llama 3.1 8B is a poor tool-caller on that path. Phase 10 sets `DEFAULT_MODEL_PARAMS={"function_calling":"legacy"}` and patches the PVC sqlite ConfigVars (env alone is ignored after first start). See [Open WebUI tools](https://docs.openwebui.com/features/extensibility/plugin/tools/).
12. **Dev Spaces Continue extension** — `postStart` copies `continue-ai-config` to `~/.continue/` (json + yaml for Continue 2.x) and downloads `Continue.continue.vsix` onto persistUserHome. Che-code opens `/projects/.code-workspace`, so sample-folder recommendations never install. Phase 9 applies two ConfigMaps into every user workspace namespace: `vscode-editor-configurations` (recommendations) and `vscode-default-extensions` (`DEFAULT_EXTENSIONS` vsix install). See [Configuring default extensions](https://eclipse.dev/che/docs/stable/administration-guide/default-extensions-for-microsoft-visual-studio-code/) and [Configuring Visual Studio Code](https://docs.redhat.com/en/documentation/red_hat_openshift_dev_spaces/3.24/html/administration_guide/configuring-visual-studio-code). Restart the DevWorkspace after those ConfigMaps land; the vsix install can take ~60s after the editor process starts.

OpenShift alert `TargetDown` for `openshift-ingress/istio-pod-monitor` (about 33% of targets) is a scrape-config false positive: Kuadrant scrapes Istio `status-port` 15021 at `/stats/prometheus`. Ingress and MaaS gateways stay Ready.

## References

- [OpenShift AI 3.5](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/)
- [Customize the dashboard (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_resources/customizing-the-dashboard)
- [Govern LLM access with Models-as-a-Service (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/)
- [KServe + llm-d article](https://developers.redhat.com/articles/2026/04/21/kserve-llm-d-optimized-gen-ai-inference)
- [MaaS article](https://developers.redhat.com/articles/2026/03/24/run-model-service-multiple-llms-openshift)
