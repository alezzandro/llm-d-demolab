"""In-process MaaS microbenchmark.

Uses non-streaming chat completions: in-cluster → MaaS Route streaming is
unreliable on this platform (ELB idle cut / incomplete chunked body).
Prefix-cache benefit still shows up clearly in end-to-end request latency.
"""

from __future__ import annotations

import asyncio
import math
import secrets
import statistics
import time
from dataclasses import asdict, dataclass
from typing import Any, Literal

import httpx

from . import config

Mode = Literal["unique", "shared"]

SHARED_PREFIX = (
    "You are a Red Hat OpenShift platform engineer assisting with Day-2 operations. "
    "Always prefer certified Operators, OpenShift Routes, and NetworkPolicy least privilege. "
    "When generating Ansible, use fully qualified collection names and idempotent modules. "
    "Context for this lab session (shared across requests so prefix caching can hit):\n"
    "Cluster policy: enforce SELinux, TLS between services, ServiceAccount tokens for "
    "inter-service auth, UBI9 runtimes, and Models-as-a-Service subscriptions for chargeback. "
    "Model pool: Llama 3.1 8B Instruct FP8 on four NVIDIA L4 GPUs with vLLM "
    "--enable-prefix-caching. Routing goal: reuse KV-cache prefixes for repeated system "
    "prompts from Dev Spaces and Open WebUI consumers.\n"
)


@dataclass
class RequestResult:
    ok: bool
    ttft_ms: float | None  # end-to-end latency stand-in (non-stream)
    latency_ms: float
    error: str | None = None


@dataclass
class RunSummary:
    mode: str
    concurrency: int
    requests: int
    ok_count: int
    error_count: int
    duration_ms: float
    ttft_median_ms: float | None
    ttft_p95_ms: float | None
    latency_median_ms: float | None
    latency_p95_ms: float | None
    errors: list[str]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _percentile(sorted_vals: list[float], p: float) -> float | None:
    if not sorted_vals:
        return None
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    k = (len(sorted_vals) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_vals[int(k)]
    return sorted_vals[f] * (c - k) + sorted_vals[c] * (k - f)


def _unique_prefix() -> str:
    nonce = secrets.token_hex(16)
    filler = (f"UNIQUE-{nonce}-" * 80)[: config.PREFIX_CHARS]
    return (
        "You are answering a one-off request. This system prompt is intentionally unique "
        f"so KV prefix cache cannot be reused.\nNonce={nonce}\n{filler}"
    )


def _messages(mode: Mode) -> list[dict[str, str]]:
    if mode == "shared":
        system = (SHARED_PREFIX * 3)[: config.PREFIX_CHARS]
    else:
        system = _unique_prefix()
    return [
        {"role": "system", "content": system},
        {
            "role": "user",
            "content": "Reply with exactly one short sentence confirming you are ready.",
        },
    ]


async def _once(client: httpx.AsyncClient, mode: Mode) -> RequestResult:
    url = f"{config.MAAS_BASE_URL}/chat/completions"
    headers = {
        "Authorization": f"Bearer {config.MAAS_API_KEY}",
        "Content-Type": "application/json",
    }
    body = {
        "model": config.MODEL_ID,
        "messages": _messages(mode),
        "max_tokens": config.MAX_TOKENS,
        "temperature": 0,
        "stream": False,
    }
    start = time.perf_counter()
    try:
        resp = await client.post(url, headers=headers, json=body)
        latency_ms = (time.perf_counter() - start) * 1000
        if resp.status_code >= 400:
            return RequestResult(
                ok=False,
                ttft_ms=None,
                latency_ms=latency_ms,
                error=f"HTTP {resp.status_code}: {resp.text[:300]}",
            )
        data = resp.json()
        content = (
            ((data.get("choices") or [{}])[0].get("message") or {}).get("content")
        )
        if not content:
            return RequestResult(
                ok=False,
                ttft_ms=None,
                latency_ms=latency_ms,
                error="empty completion content",
            )
        # Non-stream: use e2e latency as the charted metric.
        return RequestResult(ok=True, ttft_ms=latency_ms, latency_ms=latency_ms)
    except Exception as exc:  # noqa: BLE001
        return RequestResult(
            ok=False,
            ttft_ms=None,
            latency_ms=(time.perf_counter() - start) * 1000,
            error=str(exc),
        )


async def _one_request(
    client: httpx.AsyncClient,
    mode: Mode,
    sem: asyncio.Semaphore,
) -> RequestResult:
    last: RequestResult | None = None
    async with sem:
        for attempt in range(config.REQUEST_RETRIES + 1):
            last = await _once(client, mode)
            if last.ok:
                return last
            if attempt < config.REQUEST_RETRIES:
                await asyncio.sleep(0.35 * (attempt + 1))
    assert last is not None
    return last


async def run_mode(mode: Mode, *, requests: int | None = None) -> RunSummary:
    n_requests = requests if requests is not None else config.REQUESTS_PER_RUN
    if not config.MAAS_API_KEY:
        return RunSummary(
            mode=mode,
            concurrency=config.CONCURRENCY,
            requests=0,
            ok_count=0,
            error_count=1,
            duration_ms=0,
            ttft_median_ms=None,
            ttft_p95_ms=None,
            latency_median_ms=None,
            latency_p95_ms=None,
            errors=["MAAS_API_KEY is not set"],
        )

    sem = asyncio.Semaphore(config.CONCURRENCY)
    timeout = httpx.Timeout(config.TIMEOUT_SECONDS, connect=10.0)
    started = time.perf_counter()
    async with httpx.AsyncClient(timeout=timeout, verify=False) as client:
        if mode == "shared" and n_requests > 1:
            await _one_request(client, mode, sem)

        tasks = [_one_request(client, mode, sem) for _ in range(n_requests)]
        results = await asyncio.gather(*tasks)

    duration_ms = (time.perf_counter() - started) * 1000
    oks = [r for r in results if r.ok and r.ttft_ms is not None]
    ttfts = sorted(r.ttft_ms for r in oks if r.ttft_ms is not None)
    lats = sorted(r.latency_ms for r in oks)
    errors = [r.error for r in results if r.error][:5]

    return RunSummary(
        mode=mode,
        concurrency=config.CONCURRENCY,
        requests=len(results),
        ok_count=len(oks),
        error_count=len(results) - len(oks),
        duration_ms=round(duration_ms, 1),
        ttft_median_ms=(
            round(statistics.median(ttfts), 1) if ttfts else None
        ),
        ttft_p95_ms=(
            round(_percentile(ttfts, 95) or 0, 1) if ttfts else None
        ),
        latency_median_ms=(
            round(statistics.median(lats), 1) if lats else None
        ),
        latency_p95_ms=(
            round(_percentile(lats, 95) or 0, 1) if lats else None
        ),
        errors=errors,
    )


def improvement_pct(before: float | None, after: float | None) -> float | None:
    if before is None or after is None or before <= 0:
        return None
    return round((1.0 - (after / before)) * 100.0, 1)
