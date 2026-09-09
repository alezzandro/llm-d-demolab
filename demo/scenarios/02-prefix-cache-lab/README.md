# Scenario 02 — Prefix Cache Lab (booth llm-d beat)

Live web UI that runs a short unique-vs-shared-prefix microbenchmark against the MaaS endpoint and charts TTFT on the page.

## Purpose

Replace the text-heavy llm-d slide with a **click → numbers move** moment:

1. **Without shared prefix** — unique system prompts (cache miss)
2. **With shared prefix** — repeated system prompt (prefix-cache hit)
3. Static EPP leave-behind chart (naive LB vs llm-d routing P95)

## URL

```bash
bash setup/show-credentials.sh
# → Prefix Cache Lab URL
```

Or:

```bash
oc get route prefix-cache-lab -n prefix-cache-lab -o jsonpath='https://{.spec.host}{"\n"}'
```

## Usage

1. Open the Route in a browser
2. Click **Run comparison** (or the two individual buttons)
3. Point at the TTFT bars and the large **% improvement** callout
4. Scroll to the canned EPP chart for the routing story
5. Click **Reset results** before the next visitor

## Verify

```bash
bash demo/scenarios/02-prefix-cache-lab/test.sh
```

Checks Deployment/Route, `/api/health`, the index page, and a live **smoke** job
(1 unique + 1 shared non-stream completion through MaaS; polls `/api/run/{id}`).

## Cleanup

No cluster cleanup required. Use **Reset results** in the UI, or:

```bash
bash demo/scenarios/02-prefix-cache-lab/cleanup.sh
```

## Talking points

- Every replica has `--enable-prefix-caching`
- Shared context is cheap on the second hit; unique prefixes pay full prefill
- Full prefix-cache-aware **routing** (EPP) numbers are the leave-behind chart (live EPP via MaaS is not on the booth path; see architecture notes)
