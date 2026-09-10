# llm-d + MaaS Booth Hybrid Demo

Conference-booth demo for **Red Hat OpenShift AI 3.5**: Models-as-a-Service governance plus **llm-d** multi-replica prefix-cache-aware routing on **4× NVIDIA L4** GPUs.

Two independent consumers share one governed model pool:

1. **OpenShift Dev Spaces + Continue** — AI-assisted Ansible development (dev subscription)
2. **Open WebUI** — Ops chatbot (ops subscription)

## What This Demo Shows

| Feature | Product | Description |
|---|---|---|
| Model Catalog / Registry | OpenShift AI 3.5 | Discover and version Red Hat AI validated models |
| llm-d serving | KServe `LLMInferenceService` | 4× vLLM replicas + prefix caching (see architecture dry-run note on EPP/MaaS) |
| Models-as-a-Service | OpenShift AI 3.5 | Dual subscriptions, API keys, rate limits, cost centers |
| Dev consumer | Dev Spaces + Continue | Cloud IDE wired to MaaS |
| Ops consumer | Open WebUI | Chat UI on a second MaaS subscription |
| Tail-latency story | Prefix Cache Lab UI + EPP leave-behind | Live unique vs shared TTFT; canned EPP P95 chart |

## Quick Start

**Laptop (interactive):**

```bash
# From an OpenShift 4.22+ AWS cluster (cluster-admin)
oc login --server=https://<api-server>:6443

# Full setup (60-120 min; dominated by 4x GPU + model load)
bash setup/full-setup.sh

# Resume from a phase after a failure
bash setup/full-setup.sh 6
```

**In-cluster (close the laptop after apply):** clone this repo on the cluster and run setup in a keep-alive pod. See [docs/bootstrapper.md](docs/bootstrapper.md).

```bash
oc apply -k manifests/bootstrapper/
oc logs -f -n rh-demo-bootstrapper deploy/demo-bootstrapper
```

Or **Import YAML** [`manifests/bootstrapper/kickoff.yaml`](manifests/bootstrapper/kickoff.yaml) in the OpenShift console (replace `DEMO_GIT_REPO_PLACEHOLDER`).

## Prerequisites

- OpenShift **4.22+** on AWS (IPI) with cluster-admin
- AWS quota for **4× `g6.2xlarge`** (NVIDIA L4)
- `oc`, Python 3.9+, `curl`, `openssl`
- **Web Terminal Operator** (installed with the bootstrapper / phase 1) — [docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/web_console/web-terminal#installing-web-terminal)

See [docs/prerequisites.md](docs/prerequisites.md). In-cluster kickoff: [docs/bootstrapper.md](docs/bootstrapper.md).

## Setup Phases

| Phase | Script | Description |
|---|---|---|
| 0 | `00-gpu-provisioner.sh` | Provision **4×** L4 GPU workers |
| 1 | `01-install-operators.sh` | RHOAI, GPU, Dev Spaces, Kuadrant stack, … |
| 2 | `02-platform-config.sh` | Gateway, Kuadrant, monitoring |
| 3 | `03-maas-platform.sh` | MaaS Postgres / TLS |
| 4 | `04-rhoai-config.sh` | DataScienceCluster + HardwareProfile + OpenShift AI 3.5 dashboard flags (Gen AI Studio, MCP, llm-d templates, Eval Hub) and control-plane operators (OGX, AI Pipelines, TrustyAI, MLflow) |
| 5 | `05-model-registry.sh` | Register Llama 3.1 8B Instruct FP8 |
| 6 | `06-deploy-llmd-model.sh` | llm-d `LLMInferenceService` (4 replicas) + `MaaSModelRef` |
| 7 | `07-verify-maas-llmd.sh` | End-to-end MaaS + llm-d checks |
| 8 | `08-setup-subscriptions.sh` | Dual subscriptions + API keys |
| 9 | `09-deploy-devspaces.sh` | CheCluster + Continue config |
| 10 | `10-deploy-chatbot.sh` | Open WebUI |
| 11 | `11-baseline-and-observability.sh` | Leave-behind assets; optional short bench |
| 12 | `12-prefix-cache-lab.sh` | Prefix Cache Lab booth UI (build + Route) |

## Booth Day Ops

```bash
bash setup/health-check.sh          # verify
bash setup/health-check.sh --fix   # post-reboot GPU recovery (restores 4 replicas)
bash setup/show-credentials.sh      # URLs + truncated keys
bash setup/reset-demo.sh            # regenerate keys; clear WebUI/DevWorkspaces
```

Live walkthrough: [docs/demo-guide.md](docs/demo-guide.md) (~8–12 min).  
Architecture: [docs/architecture.md](docs/architecture.md).  
P95 leave-behind: [docs/assets/baseline-comparison.md](docs/assets/baseline-comparison.md).

## Important Notes

- **Pre-warm** the Dev Spaces workspace and complete Open WebUI first login before the booth opens.
- Do **not** run long GuideLLM jobs during visitor demos; use the **Prefix Cache Lab** UI (`demo/scenarios/02-prefix-cache-lab/`) plus the canned EPP chart.
- Optional prep-day GuideLLM burst: `demo/scenarios/01-replay-benchmark/`.
- Scale GPU MachineSets to 0 overnight to control AWS cost.
- Open WebUI image is community (`ghcr.io/open-webui/open-webui`) — demo exception vs UBI-only policy.
- Prefix Cache Lab image is built from UBI9 (`apps/prefix-cache-lab/Containerfile`).
- In-cluster bootstrapper image is UBI9 (`apps/demo-bootstrapper/Containerfile`, `quay.io/aarrichi/rh-demo-bootstrapper:ubi9-1`).
- The RHOAI Subscription uses channel `stable-3.x` (currently **3.5.0**). Setup scripts discover KServe presets and MaaS CRs at runtime — see [architecture notes](docs/architecture.md#validated-on-openshift-ai-350).
- Phase 4 enables OpenShift AI 3.5 dashboard features and control-plane operators. It does **not** start AutoML, training, or extra GPU playground servers (those would steal the 4× L4 llm-d pool).

## Documentation References

- [OpenShift AI 3.5](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/)
- [Govern LLM access with Models-as-a-Service (3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/)
- [KServe + llm-d](https://developers.redhat.com/articles/2026/04/21/kserve-llm-d-optimized-gen-ai-inference)
- [MaaS on OpenShift](https://developers.redhat.com/articles/2026/03/24/run-model-service-multiple-llms-openshift)
