# Canned baseline vs llm-d comparison (booth leave-behind)

Numbers below are representative results from the llm-d intro showroom
(4× GPU, Llama 3.1 8B Instruct FP8, GuideLLM concurrent profile).
Capture your own cluster numbers during prep day with
`setup/11-baseline-and-observability.sh` or
`demo/scenarios/01-replay-benchmark/trigger.sh` and replace this table.

## Request Latency Comparison: 4 GPU naive vs 4 GPU llm-d

### Concurrent @ 32

| Metric | 4 GPU vLLM (naive LB) | 4 GPU llm-d | Improvement |
|---|---:|---:|---:|
| Req Latency Mdn (s) | 20.6 | 15.3 | 26% |
| Req Latency p95 (s) | 29.4 | 20.6 | 30% |
| TTFT Mdn (ms) | 1579.6 | 167.3 | 89% |
| TTFT p95 (ms) | 7551.4 | 4677.0 | 38% |

### Concurrent @ 64

| Metric | 4 GPU vLLM (naive LB) | 4 GPU llm-d | Improvement |
|---|---:|---:|---:|
| Req Latency Mdn (s) | 32.7 | 20.2 | 38% |
| Req Latency p95 (s) | 51.9 | 25.1 | 52% |
| TTFT Mdn (ms) | 4492.7 | 245.8 | 95% |
| TTFT p95 (ms) | 24391.2 | 478.0 | 98% |

## Talking points

- Same hardware, same model, same prompts — only routing changes.
- Naive round-robin wastes KV cache prefixes across replicas (~25% hit rate).
- llm-d `prefix-cache-scorer` routes repeat prefixes to the warm replica (80–90%+ hits).
- Advantage grows under higher concurrency (booth wow: P95 TTFT collapse at c=64).

## Live booth guidance

Prefer the **Prefix Cache Lab** UI (`demo/scenarios/02-prefix-cache-lab/`) for the
live unique-vs-shared TTFT beat; this table (also rendered as a chart in that UI)
is the EPP routing leave-behind.

Do **not** run a 300s GuideLLM job during visitor demos.
Optionally use a 30–60s short burst via `demo/scenarios/01-replay-benchmark/`
for Perses / Observe metrics only.
