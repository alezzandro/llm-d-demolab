import os


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return int(raw)


def _float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return float(raw)


MAAS_BASE_URL = os.environ.get(
    "MAAS_BASE_URL",
    "http://localhost:8080/v1",
).rstrip("/")
MAAS_API_KEY = os.environ.get("MAAS_API_KEY", "")
MODEL_ID = os.environ.get("MODEL_ID", "llama-3-1-8b-instruct-fp8")

# Booth-friendly defaults: light enough for 4× L4 + MaaS gateway,
# still show a unique vs shared TTFT gap in ~30–60s.
CONCURRENCY = _int("BENCH_CONCURRENCY", 4)
REQUESTS_PER_RUN = _int("BENCH_REQUESTS", 8)
MAX_TOKENS = _int("BENCH_MAX_TOKENS", 8)
TIMEOUT_SECONDS = _float("BENCH_TIMEOUT_SECONDS", 45.0)
PREFIX_CHARS = _int("BENCH_PREFIX_CHARS", 512)
REQUEST_RETRIES = _int("BENCH_RETRIES", 2)

EPP_BASELINE_PATH = os.environ.get(
    "EPP_BASELINE_PATH",
    "/app/data/epp-baseline.json",
)
