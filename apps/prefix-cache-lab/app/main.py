from __future__ import annotations

import asyncio
import json
import secrets
import time
from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field

from . import bench, config

APP_DIR = Path(__file__).resolve().parent
ROOT_DIR = APP_DIR.parent

app = FastAPI(title="Prefix Cache Lab", version="1.0.0")
app.mount("/static", StaticFiles(directory=str(ROOT_DIR / "static")), name="static")
templates = Jinja2Templates(directory=str(ROOT_DIR / "templates"))

_run_lock = asyncio.Lock()
_jobs: dict[str, dict[str, Any]] = {}
_JOB_TTL_SECONDS = 1800


def _load_epp_baseline() -> dict[str, Any]:
    path = Path(config.EPP_BASELINE_PATH)
    if not path.is_file():
        alt = ROOT_DIR / "data" / "epp-baseline.json"
        path = alt if alt.is_file() else path
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError:
        return {
            "title": "EPP baseline unavailable",
            "subtitle": "",
            "note": f"Could not read {config.EPP_BASELINE_PATH}",
            "series": [],
            "highlight": None,
        }


def _prune_jobs() -> None:
    now = time.time()
    stale = [
        jid
        for jid, job in _jobs.items()
        if now - float(job.get("created_at", now)) > _JOB_TTL_SECONDS
    ]
    for jid in stale:
        _jobs.pop(jid, None)


class RunRequest(BaseModel):
    mode: Literal["unique", "shared", "compare", "smoke"] = Field(
        description="unique | shared | compare | smoke"
    )


async def _execute_mode(mode: str) -> dict[str, Any]:
    if mode == "smoke":
        unique = await bench.run_mode("unique", requests=1)
        shared = await bench.run_mode("shared", requests=1)
        return {
            "mode": "smoke",
            "unique": unique.to_dict(),
            "shared": shared.to_dict(),
            "ok": unique.ok_count >= 1 and shared.ok_count >= 1,
        }

    if mode == "compare":
        unique = await bench.run_mode("unique")
        shared = await bench.run_mode("shared")
        return {
            "mode": "compare",
            "unique": unique.to_dict(),
            "shared": shared.to_dict(),
            "improvement": {
                "ttft_median_pct": bench.improvement_pct(
                    unique.ttft_median_ms, shared.ttft_median_ms
                ),
                "ttft_p95_pct": bench.improvement_pct(
                    unique.ttft_p95_ms, shared.ttft_p95_ms
                ),
            },
        }

    summary = await bench.run_mode(mode)  # type: ignore[arg-type]
    return {"mode": mode, mode: summary.to_dict()}


async def _job_worker(job_id: str, mode: str) -> None:
    job = _jobs[job_id]
    job["status"] = "running"
    job["message"] = f"Running {mode}…"
    try:
        async with _run_lock:
            # Overall cap so a stuck MaaS call cannot hold the booth UI forever.
            result = await asyncio.wait_for(
                _execute_mode(mode),
                timeout=max(config.TIMEOUT_SECONDS * 4, 240.0),
            )
        job["status"] = "completed"
        job["message"] = "Completed"
        job["result"] = result
    except asyncio.TimeoutError:
        job["status"] = "failed"
        job["message"] = "Timed out waiting for MaaS"
        job["error"] = "benchmark timed out"
    except Exception as exc:  # noqa: BLE001
        job["status"] = "failed"
        job["message"] = "Failed"
        job["error"] = str(exc)
    finally:
        job["finished_at"] = time.time()


@app.get("/api/health")
async def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "maas_configured": bool(config.MAAS_API_KEY and config.MAAS_BASE_URL),
        "model_id": config.MODEL_ID,
        "concurrency": config.CONCURRENCY,
        "requests_per_run": config.REQUESTS_PER_RUN,
        "busy": _run_lock.locked(),
    }


@app.get("/", response_class=HTMLResponse)
async def index(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "model_id": config.MODEL_ID,
            "concurrency": config.CONCURRENCY,
            "requests_per_run": config.REQUESTS_PER_RUN,
            "epp": _load_epp_baseline(),
        },
    )


@app.post("/api/run")
async def run_bench(body: RunRequest) -> dict[str, Any]:
    """Start a bench job and return immediately (poll /api/run/{id})."""
    _prune_jobs()
    if _run_lock.locked():
        raise HTTPException(status_code=409, detail="A run is already in progress")

    job_id = secrets.token_hex(8)
    _jobs[job_id] = {
        "id": job_id,
        "mode": body.mode,
        "status": "queued",
        "message": "Queued",
        "created_at": time.time(),
        "result": None,
        "error": None,
    }
    asyncio.create_task(_job_worker(job_id, body.mode))
    return {"job_id": job_id, "status": "queued", "mode": body.mode}


@app.get("/api/run/{job_id}")
async def get_run(job_id: str) -> dict[str, Any]:
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Unknown job_id")
    return {
        "job_id": job_id,
        "mode": job["mode"],
        "status": job["status"],
        "message": job.get("message"),
        "error": job.get("error"),
        "result": job.get("result"),
    }
