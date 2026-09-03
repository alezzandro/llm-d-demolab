Prep-day / optional booth burst only. Do **not** run a 300s GuideLLM job during live visitor demos.

## Purpose

Generate short concurrent load against the MaaS endpoint so Perses / OpenShift metrics show activity. Pair with [`docs/assets/baseline-comparison.md`](../../../docs/assets/baseline-comparison.md) for the canned naive-vs-llm-d P95 story.

## Requirements

- Image **`ghcr.io/vllm-project/guidellm:v0.7.1-amd64`** (not `:latest` — that tag is arm64 and fails with `Exec format error` on amd64 nodes)
- GuideLLM **v0.7** CLI (`guidellm run …`); legacy `GUIDELLM_*` env vars are ignored
- MaaS API key passed as `api_key=` in `--backend` (health probe otherwise 401s)

## Usage

```bash
# From repo root, authenticated as cluster-admin
bash demo/scenarios/01-replay-benchmark/trigger.sh
# Follow logs:
oc logs -f job/guidellm-llmd-short -n models-as-a-service
bash demo/scenarios/01-replay-benchmark/cleanup.sh
```

## Talking points while it runs

- Same 4 L4 GPUs under concurrent load
- Point at rising request rate / latency panels
- Cite leave-behind P95 numbers for the intelligent-routing story
