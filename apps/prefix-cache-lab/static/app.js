(() => {
  const buttons = {
    unique: document.getElementById("btn-unique"),
    shared: document.getElementById("btn-shared"),
    compare: document.getElementById("btn-compare"),
    reset: document.getElementById("btn-reset"),
  };
  const progress = document.getElementById("progress");
  const progressText = document.getElementById("progress-text");
  const errorBox = document.getElementById("error");
  const results = document.getElementById("results");
  const winValue = document.getElementById("win-value");
  const winSub = document.getElementById("win-sub");
  const uniqueMedian = document.getElementById("unique-median");
  const uniqueP95 = document.getElementById("unique-p95");
  const sharedMedian = document.getElementById("shared-median");
  const sharedP95 = document.getElementById("shared-p95");

  let chart;
  let eppChart;
  let state = { unique: null, shared: null };

  function setBusy(busy, label) {
    Object.values(buttons).forEach((btn) => {
      if (!btn) return;
      if (btn === buttons.reset) {
        btn.disabled = busy;
        return;
      }
      btn.disabled = busy;
    });
    progress.classList.toggle("active", busy);
    progressText.textContent = label || "Running…";
  }

  function showError(msg) {
    if (!msg) {
      errorBox.classList.remove("active");
      errorBox.textContent = "";
      return;
    }
    errorBox.textContent = msg;
    errorBox.classList.add("active");
  }

  function fmt(ms) {
    if (ms == null) return "—";
    return `${Number(ms).toLocaleString(undefined, { maximumFractionDigits: 1 })} ms`;
  }

  function ensureChart() {
    if (chart) return chart;
    const ctx = document.getElementById("ttft-chart");
    chart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: ["Latency median", "Latency p95"],
        datasets: [
          {
            label: "Unique prefixes",
            backgroundColor: "#6a6e73",
            data: [0, 0],
            borderRadius: 4,
          },
          {
            label: "Shared prefix",
            backgroundColor: "#0066cc",
            data: [0, 0],
            borderRadius: 4,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 650 },
        plugins: {
          legend: { position: "bottom" },
          title: { display: false },
        },
        scales: {
          y: {
            beginAtZero: true,
            title: { display: true, text: "milliseconds" },
          },
        },
      },
    });
    return chart;
  }

  function renderEppChart(epp) {
    if (!epp || !epp.highlight || eppChart) return;
    const ctx = document.getElementById("epp-chart");
    if (!ctx) return;
    const c64 = (epp.series || []).find((s) => s.label.includes("64"));
    const metrics = c64?.metrics || [];
    const median = metrics.find((m) => m.name.includes("median"));
    const p95 = metrics.find((m) => m.name.includes("p95"));
    eppChart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: ["TTFT median @64", "TTFT p95 @64"],
        datasets: [
          {
            label: "Naive LB",
            backgroundColor: "#6a6e73",
            data: [median?.naive ?? 0, p95?.naive ?? 0],
            borderRadius: 4,
          },
          {
            label: "llm-d EPP",
            backgroundColor: "#ee0000",
            data: [median?.llmd ?? 0, p95?.llmd ?? 0],
            borderRadius: 4,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 700 },
        plugins: { legend: { position: "bottom" } },
        scales: {
          y: {
            beginAtZero: true,
            title: { display: true, text: "milliseconds" },
          },
        },
      },
    });
  }

  function updateUI() {
    const u = state.unique;
    const s = state.shared;
    if (!u && !s) {
      results.hidden = true;
      return;
    }
    results.hidden = false;
    uniqueMedian.textContent = fmt(u?.ttft_median_ms);
    uniqueP95.textContent = fmt(u?.ttft_p95_ms);
    sharedMedian.textContent = fmt(s?.ttft_median_ms);
    sharedP95.textContent = fmt(s?.ttft_p95_ms);

    const c = ensureChart();
    c.data.datasets[0].data = [u?.ttft_median_ms ?? 0, u?.ttft_p95_ms ?? 0];
    c.data.datasets[1].data = [s?.ttft_median_ms ?? 0, s?.ttft_p95_ms ?? 0];
    c.update();

    if (u?.ttft_p95_ms != null && s?.ttft_p95_ms != null && u.ttft_p95_ms > 0) {
      const pct = (1 - s.ttft_p95_ms / u.ttft_p95_ms) * 100;
      winValue.textContent = `${pct.toFixed(1)}%`;
      winSub.textContent = "Latency p95 improvement (shared vs unique prefixes)";
    } else if (u?.ttft_median_ms != null && s?.ttft_median_ms != null && u.ttft_median_ms > 0) {
      const pct = (1 - s.ttft_median_ms / u.ttft_median_ms) * 100;
      winValue.textContent = `${pct.toFixed(1)}%`;
      winSub.textContent = "Latency median improvement (shared vs unique prefixes)";
    } else {
      winValue.textContent = "—";
      winSub.textContent = "Run both modes (or Compare) to see improvement";
    }
  }

  function applyResult(mode, data) {
    if (mode === "compare" || mode === "smoke") {
      state.unique = data.unique;
      state.shared = data.shared;
    } else if (mode === "unique") {
      state.unique = data.unique;
    } else {
      state.shared = data.shared;
    }
    const errs = [
      ...(state.unique?.errors || []),
      ...(state.shared?.errors || []),
    ];
    if (errs.length) {
      showError(errs.slice(0, 2).join(" | "));
    }
    updateUI();
  }

  async function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async function pollJob(jobId, label) {
    const started = performance.now();
    while (true) {
      const sec = ((performance.now() - started) / 1000).toFixed(0);
      progressText.textContent = `${label} ${sec}s`;
      const resp = await fetch(`/api/run/${jobId}`);
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Poll HTTP ${resp.status}`);
      }
      if (data.status === "completed") {
        return data.result;
      }
      if (data.status === "failed") {
        throw new Error(data.error || data.message || "Run failed");
      }
      await sleep(1000);
    }
  }

  async function run(mode) {
    showError("");
    const labels = {
      unique: "Running unique-prefix load…",
      shared: "Running shared-prefix load…",
      compare: "Running unique then shared comparison…",
      smoke: "Smoke test…",
    };
    setBusy(true, labels[mode] || "Running…");

    try {
      const resp = await fetch("/api/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode }),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `HTTP ${resp.status}`);
      }
      const result = await pollJob(data.job_id, labels[mode] || "Running…");
      applyResult(mode, result);
    } catch (err) {
      showError(err.message || String(err));
    } finally {
      setBusy(false);
    }
  }

  buttons.unique?.addEventListener("click", () => run("unique"));
  buttons.shared?.addEventListener("click", () => run("shared"));
  buttons.compare?.addEventListener("click", () => run("compare"));
  buttons.reset?.addEventListener("click", () => {
    state = { unique: null, shared: null };
    showError("");
    updateUI();
    if (chart) {
      chart.data.datasets[0].data = [0, 0];
      chart.data.datasets[1].data = [0, 0];
      chart.update();
    }
  });

  try {
    const epp = JSON.parse(document.getElementById("epp-data").textContent);
    renderEppChart(epp);
  } catch (_) {
    /* optional */
  }
})();
