# Prerequisites

## Cluster Requirements

- **OpenShift 4.22+** on AWS (IPI installation)
- **cluster-admin** access via `oc` CLI
- **Python 3.9+** (GPU provisioner)
- CLI tools: `curl`, `openssl`, `git`, `base64`

## AWS Requirements

- IAM permissions to create EC2 **`g6.2xlarge`** instances
- Quota for **at least 4× `g6.2xlarge`** in one Availability Zone
- VPC/subnets allowing new instances in the cluster VPC

## Network Access

| Destination | Purpose |
|---|---|
| `registry.redhat.io` | ModelCar OCI images, operators, vLLM runtime |
| `registry.access.redhat.com` | UBI, PostgreSQL, MySQL |
| `ghcr.io` | Open WebUI + optional GuideLLM images |
| `github.com` | GPU provisioner clone, Dev Spaces workspace git |
| `quay.io` | Universal developer image for Dev Spaces |

## Time Estimate

| Phase | Script | Duration |
|---|---|---|
| GPU Provisioning | `00-gpu-provisioner.sh` | 10–20 min |
| Operator Installation | `01-install-operators.sh` | 5–15 min |
| Platform Configuration | `02-platform-config.sh` | 5–10 min |
| MaaS Platform | `03-maas-platform.sh` | 5 min |
| RHOAI Configuration | `04-rhoai-config.sh` | 5–10 min |
| Model Registry | `05-model-registry.sh` | 5 min |
| llm-d Model Deploy | `06-deploy-llmd-model.sh` | 15–25 min |
| Verification | `07-verify-maas-llmd.sh` | 2–5 min |
| Subscriptions | `08-setup-subscriptions.sh` | 2 min |
| Dev Spaces | `09-deploy-devspaces.sh` | 5–10 min |
| Chatbot | `10-deploy-chatbot.sh` | 2–5 min |
| Observability assets | `11-baseline-and-observability.sh` | 1–5 min |
| **Total** | `full-setup.sh` | **~60–120 min** |

## Pre-Flight Check

```bash
oc version
oc whoami
oc auth can-i create clusterrole --all-namespaces
python3 --version
oc get infrastructure cluster -o jsonpath='{.status.platform}'   # expect: AWS
oc get machinesets -n openshift-machine-api
```

## Cluster Sizing

| Resource | Purpose | Minimum |
|---|---|---|
| Control plane | Default IPI | 3× m6i.xlarge (typical) |
| Compute workers | Platform operators | 2× m6i.xlarge (typical) |
| GPU workers | llm-d replicas | **4× g6.2xlarge** (1× L4 each) |

Additional storage: Postgres ~10Gi, MySQL ~10Gi, Open WebUI ~5Gi, Dev Spaces PVC ~10Gi/user, benchmark PVC 5Gi.

## Model

- **Llama 3.1 8B Instruct FP8-dynamic** ModelCar  
  `oci://registry.redhat.io/rhelai1/modelcar-llama-3-1-8b-instruct-fp8-dynamic:1.5`
- Fits one L4 per replica; 4 replicas for llm-d EPP story
- Context: `--max-model-len=16000` with `--enable-prefix-caching`

## Cost Control

- GPU instances dominate spend — scale MachineSets to 0 overnight
- Keep the 4-replica model warm during booth hours (reload is slow)
- Prefer canned P95 numbers over long GuideLLM runs on the show floor
