// Onion Quality Grading — frontend SPA (vanilla JS, no build step).
// Talks to the FastAPI backend at API_BASE.

const DEFAULT_API_BASE = "http://localhost:8000";
const state = {
  apiBase: localStorage.getItem("apiBase") || DEFAULT_API_BASE,
  screen: "camera",
  files: [],               // File[] — 1 photo behaves as single, 2+ as batch, no upfront mode choice
  batchLabel: "",
  pxPerCm: "",
  lastResult: null,
  history: [],
};

const app = document.getElementById("app");
const toastEl = document.getElementById("toast");

function toast(msg, ms = 3200) {
  toastEl.textContent = msg;
  toastEl.classList.remove("hidden");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => toastEl.classList.add("hidden"), ms);
}

async function api(path, opts = {}) {
  const res = await fetch(state.apiBase + path, opts);
  if (!res.ok) {
    let detail = res.statusText;
    try { detail = (await res.json()).detail || detail; } catch (_) {}
    throw new Error(detail);
  }
  return res.json();
}

// ---------------------------------------------------------------- routing

function setNavActive(name) {
  document.querySelectorAll(".nav-btn").forEach(b => {
    b.classList.toggle("active", b.dataset.nav === name);
  });
}

function go(screen, opts = {}) {
  state.screen = screen;
  if (screen === "camera") {
    state.files = [];
    state.batchLabel = "";
    state.pxPerCm = "";
  }
  setNavActive(screen === "processing" || screen === "results" ? "camera" : screen);
  document.getElementById("homeBackBtn").classList.toggle("hidden", screen === "camera");
  render(opts);
  window.scrollTo(0, 0);
}

document.querySelectorAll(".nav-btn").forEach(btn => {
  btn.addEventListener("click", () => go(btn.dataset.nav));
});

document.getElementById("homeBackBtn").addEventListener("click", () => go("camera"));

document.getElementById("apiSettingsBtn").addEventListener("click", () => {
  const val = prompt("Backend server URL (FastAPI):", state.apiBase);
  if (val) {
    state.apiBase = val.replace(/\/$/, "");
    localStorage.setItem("apiBase", state.apiBase);
    toast("Server URL updated");
  }
});

// ---------------------------------------------------------------- screens

function render(opts) {
  if (state.screen === "camera") return renderCamera();
  if (state.screen === "processing") return renderProcessing();
  if (state.screen === "results") return renderResults();
  if (state.screen === "history") return renderHistory();
  if (state.screen === "settings") return renderSettings();
}

// The app opens directly onto this screen — camera-first, no dashboard/menu
// and no upfront single-vs-batch choice. Tap "Take Photo" as many times as
// needed; whatever ends up in the list gets analyzed together as one
// inspection when you tap Analyze — 1 photo behaves like "single", 2+
// behaves like "batch", with no mode to pick in advance.
function renderCamera() {
  app.innerHTML = `
    <button class="camera-btn" id="btnCamera">
      <span class="camera-btn-icon">📷</span>
      <span>Take Photo</span>
    </button>
    <button class="btn block" id="btnGallery" style="margin-top:10px;">🖼 Choose from Gallery</button>

    <div class="warn-box" style="margin-top:14px;">
      📸 Use a real photo of the actual batch (crate, tray, or table) — the AI is trained on
      real inspection photos, not glossy product/catalog photography, and won't read those reliably.
    </div>

    <div class="card" id="photosCard" style="margin-top:14px; display:none;">
      <label for="batchLabel">Batch ID / label (optional)</label>
      <input type="text" id="batchLabel" placeholder="e.g. ON-2026-001" value="${state.batchLabel}" />
      <div class="thumbs" id="thumbs"></div>
      <button class="btn primary block" id="btnAnalyze">Analyze</button>
    </div>

    <details class="calib-details">
      <summary>Size calibration (optional)</summary>
      <label for="pxPerCm">Pixels per cm</label>
      <input type="number" id="pxPerCm" placeholder="Leave blank to skip undersized detection" value="${state.pxPerCm}" />
      <p class="muted">Place a known reference object in-frame and enter its pixel width ÷ real width (cm) to enable the "undersized" size check.</p>
    </details>

    <input type="file" id="fileInputCamera" accept="image/*" capture="environment" class="hidden-file-input" />
    <input type="file" id="fileInputGallery" accept="image/*" class="hidden-file-input" multiple />
  `;

  const cameraInput = document.getElementById("fileInputCamera");
  const galleryInput = document.getElementById("fileInputGallery");
  document.getElementById("btnCamera").onclick = () => cameraInput.click();
  document.getElementById("btnGallery").onclick = () => galleryInput.click();

  document.getElementById("pxPerCm").addEventListener("input", (e) => state.pxPerCm = e.target.value);

  const photosCard = document.getElementById("photosCard");
  const thumbs = document.getElementById("thumbs");
  const analyzeBtn = document.getElementById("btnAnalyze");
  document.getElementById("batchLabel").addEventListener("input", (e) => state.batchLabel = e.target.value);
  analyzeBtn.addEventListener("click", runAnalysis);

  function refreshThumbs() {
    photosCard.style.display = state.files.length ? "block" : "none";
    analyzeBtn.textContent = state.files.length > 1 ? `Analyze (${state.files.length} photos)` : "Analyze";
    thumbs.innerHTML = "";
    state.files.forEach((f, i) => {
      const div = document.createElement("div");
      div.className = "thumb";
      const img = document.createElement("img");
      img.src = URL.createObjectURL(f);
      const rm = document.createElement("button");
      rm.className = "rm";
      rm.textContent = "✕";
      rm.onclick = () => { state.files.splice(i, 1); refreshThumbs(); };
      div.appendChild(img);
      div.appendChild(rm);
      thumbs.appendChild(div);
    });
  }

  function onFilesChosen(e) {
    const chosen = Array.from(e.target.files || []);
    if (!chosen.length) return;
    state.files = state.files.concat(chosen);
    refreshThumbs();
  }

  cameraInput.addEventListener("change", onFilesChosen);
  galleryInput.addEventListener("change", onFilesChosen);
}

async function runAnalysis() {
  go("processing");
  const steps = ["stepUpload", "stepDetect", "stepClassify", "stepGrade"];
  let stepIdx = 0;
  const bar = document.getElementById("progressBar");
  const advance = () => {
    if (stepIdx < steps.length) {
      document.getElementById(steps[stepIdx])?.classList.add("done");
      stepIdx++;
      if (bar) bar.style.width = Math.min(95, stepIdx * 25) + "%";
    }
  };
  advance();
  const tick = setInterval(advance, 700);

  try {
    const form = new FormData();
    state.files.forEach(f => form.append("files", f));
    form.append("mode", state.files.length > 1 ? "batch" : "single");
    if (state.batchLabel) form.append("batch_label", state.batchLabel);
    if (state.pxPerCm) form.append("px_per_cm", state.pxPerCm);

    const result = await api("/api/inspections", { method: "POST", body: form });
    clearInterval(tick);
    if (bar) bar.style.width = "100%";
    steps.forEach(id => document.getElementById(id)?.classList.add("done"));
    state.lastResult = result;
    setTimeout(() => go("results"), 300);
  } catch (err) {
    clearInterval(tick);
    toast("Analysis failed: " + err.message, 5000);
    go("camera");
  }
}

function renderProcessing() {
  app.innerHTML = `
    <h1>Analyzing…</h1>
    <div class="card">
      <div class="spinner"></div>
      <div class="progress-wrap"><div class="progress-bar" id="progressBar"></div></div>
      <div class="step-list">
        <div id="stepUpload">Uploading photos</div>
        <div id="stepDetect">Detecting onions</div>
        <div id="stepClassify">Checking defects</div>
        <div id="stepGrade">Calculating quality &amp; grade</div>
      </div>
    </div>
  `;
}

function gradeClass(grade) {
  if (grade === "Grade 1") return "g1";
  if (grade === "Grade 2") return "g2";
  return "urs";
}

const GRADE_LABELS = {
  "Grade 1": "Grade 1 — High Quality",
  "Grade 2": "Grade 2 — Acceptable, Lower Quality",
  "URS": "URS — Below Standard (Unfit for Sale)",
};
function gradeLabel(grade) { return GRADE_LABELS[grade] || grade; }

const DEFECT_CLASSES = ["damaged", "rotten", "sprouted", "undersized"];
const DEFECT_LABELS = { damaged: "Damaged", rotten: "Rotten", sprouted: "Sprouted", undersized: "Undersized" };
// Answers "why did this batch get this grade?" instead of a bare "Below Standard: X%".
function dominantDefect(r) {
  const total = r.total_onions || 0;
  if (total <= 0) return null;
  let bestKey = null, bestCount = 0;
  for (const key of DEFECT_CLASSES) {
    const count = r[key] || 0;
    if (count > bestCount) { bestKey = key; bestCount = count; }
  }
  if (!bestKey) return null;
  return { label: DEFECT_LABELS[bestKey], pct: Math.round((bestCount / total) * 1000) / 10 };
}

function renderResults() {
  const r = state.lastResult;
  if (!r) return go("camera");
  const total = Math.max(r.total_onions, 1);
  const rows = [
    ["healthy", "Healthy"], ["damaged", "Damaged"], ["rotten", "Rotten"],
    ["sprouted", "Sprouted"], ["undersized", "Undersized"],
  ];

  const breakdownHtml = rows.map(([key, label]) => {
    const count = r[key] || 0;
    const pct = Math.round((count / total) * 1000) / 10;
    return `
      <div class="breakdown-row">
        <span class="breakdown-label"><span class="dot ${key}"></span>${label}</span>
        <span><span class="breakdown-count">${count}</span><span class="breakdown-pct">${pct}%</span></span>
      </div>`;
  }).join("");

  const gallery = (r.images_json || []).map(img =>
    `<img src="${state.apiBase}${img.annotated_url}" alt="annotated" />`
  ).join("");

  const confClass = r.low_confidence ? "low" : "ok";
  const confPct = Math.round(r.avg_confidence * 100);
  const defect = r.grade !== "Grade 1" ? dominantDefect(r) : null;

  app.innerHTML = `
    <h1>Inspection Result</h1>
    <div class="card">
      <p class="muted">ID: ${r.id}<br/>${r.num_images} image(s) analyzed &middot; ${r.total_onions} onions detected</p>

      <h2>Quality Breakdown</h2>
      ${breakdownHtml}
    </div>

    <div class="card">
      <div class="grade-badge ${gradeClass(r.grade)}">
        ${gradeLabel(r.grade)}
        <div class="grade-sub">Grade-A (healthy): ${r.grade_a_pct}%</div>
      </div>
      ${defect ? `<p class="muted" style="text-align:center; margin-top:8px;">Primary factor: <strong>${defect.label} (${defect.pct}%)</strong></p>` : ""}
      <p style="text-align:center;">
        <span class="confidence-pill ${confClass}">AI Confidence ${confPct}%</span>
      </p>
      ${r.low_confidence ? `<div class="warn-box">⚠️ Low confidence — manual verification recommended.</div>` : ""}
      ${!r.undersized_calibrated ? `<p class="muted" style="text-align:center;">Undersized check not calibrated for this inspection.</p>` : ""}
    </div>

    <div class="card">
      <h2>Estimated Price</h2>
      <p style="font-size:22px; font-weight:800;">₹ ${r.estimated_price_per_quintal} <span class="muted" style="font-weight:400; font-size:13px;">/ quintal</span></p>
      <p class="muted">${r.pricing?.note || "Demo/configurable pricing."}</p>
    </div>

    <div class="card">
      <h2>Annotated Images</h2>
      <div class="legend">
        <span><span class="dot healthy"></span>Healthy</span>
        <span><span class="dot damaged"></span>Damaged</span>
        <span><span class="dot rotten"></span>Rotten</span>
        <span><span class="dot sprouted"></span>Sprouted</span>
        <span><span class="dot undersized"></span>Undersized</span>
      </div>
      <div class="gallery">${gallery}</div>
    </div>

    <button class="btn primary block" id="btnDownload">⬇ Download PDF Report</button>
    <button class="btn block" id="btnAnother">➕ New Inspection</button>
  `;

  document.getElementById("btnDownload").onclick = () => {
    window.open(state.apiBase + `/api/inspections/${r.id}/report.pdf`, "_blank");
  };
  document.getElementById("btnAnother").onclick = () => go("camera");
}

async function renderHistory() {
  app.innerHTML = `<h1>Inspection History</h1><div class="card"><div class="spinner"></div></div>`;
  try {
    const list = await api("/api/inspections?limit=100");
    if (!list.length) {
      app.innerHTML = `
        <h1>Inspection History</h1>
        <div class="empty-state"><span class="emoji">📭</span>No inspections yet.</div>
      `;
      return;
    }
    const rows = list.map(r => `
      <tr data-id="${r.id}">
        <td>${r.id.replace("ON-", "")}</td>
        <td>${r.batch_label || "-"}</td>
        <td>${r.grade_a_pct}%</td>
        <td><span class="grade-chip ${gradeClass(r.grade)}">${r.grade}</span></td>
      </tr>`).join("");
    app.innerHTML = `
      <h1>Inspection History</h1>
      <div class="card">
        <table class="hist">
          <thead><tr><th>ID</th><th>Batch</th><th>Grade-A</th><th>Grade</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
      </div>
    `;
    document.querySelectorAll("table.hist tbody tr").forEach(tr => {
      tr.addEventListener("click", async () => {
        const id = tr.dataset.id;
        const full = await api(`/api/inspections/${id}`);
        full.pricing = {
          estimated_price_per_quintal: full.estimated_price_per_quintal,
          note: "Demo/configurable pricing.",
        };
        state.lastResult = full;
        go("results");
      });
    });
  } catch (err) {
    app.innerHTML = `<h1>Inspection History</h1><div class="warn-box">Could not load history: ${err.message}. Is the backend running at ${state.apiBase}?</div>`;
  }
}

async function renderSettings() {
  app.innerHTML = `<h1>Grading &amp; Pricing Rules</h1><div class="card"><div class="spinner"></div></div>`;
  let cfg;
  try {
    cfg = await api("/api/settings");
  } catch (err) {
    app.innerHTML = `<h1>Grading &amp; Pricing Rules</h1><div class="warn-box">Could not load settings: ${err.message}. Is the backend running at ${state.apiBase}?</div>`;
    return;
  }

  app.innerHTML = `
    <h1>Grading &amp; Pricing Rules</h1>
    <p class="muted">Prototype thresholds — configurable, not official procurement standards.</p>

    <div class="card">
      <h2>What the grades mean</h2>
      <div class="breakdown-row"><span>🥇 <strong>Grade 1</strong></span><span class="muted">High-quality onions</span></div>
      <div class="breakdown-row"><span>🥈 <strong>Grade 2</strong></span><span class="muted">Acceptable, lower quality</span></div>
      <div class="breakdown-row"><span>❌ <strong>URS</strong></span><span class="muted">Unfit for Sale — below minimum quality</span></div>
    </div>

    <div class="card">
      <h2>Grading Engine</h2>
      <label>Grade 1: Grade-A % ≥</label>
      <input type="number" id="grade1_min_pct" value="${cfg.grade1_min_pct}" />
      <label>Grade 2: Grade-A % ≥</label>
      <input type="number" id="grade2_min_pct" value="${cfg.grade2_min_pct}" />
      <p class="muted">Below Grade 2's threshold → URS / Below Standard.</p>

      <label>Low-confidence threshold (flags manual review)</label>
      <input type="number" step="0.01" id="low_confidence_threshold" value="${cfg.low_confidence_threshold}" />

      <label>Undersized diameter threshold (cm)</label>
      <input type="number" step="0.1" id="undersized_diameter_cm" value="${cfg.undersized_diameter_cm}" />
    </div>

    <div class="card">
      <h2>Pricing Engine</h2>
      <label>Base market price (₹ / quintal)</label>
      <input type="number" id="base_price_per_quintal" value="${cfg.base_price_per_quintal}" />
      <div class="row">
        <div>
          <label>Grade 1 adjustment (%)</label>
          <input type="number" id="adj_g1" value="${cfg.grade_price_adjustment_pct["Grade 1"]}" />
        </div>
        <div>
          <label>Grade 2 adjustment (%)</label>
          <input type="number" id="adj_g2" value="${cfg.grade_price_adjustment_pct["Grade 2"]}" />
        </div>
        <div>
          <label>URS adjustment (%)</label>
          <input type="number" id="adj_urs" value="${cfg.grade_price_adjustment_pct["URS"]}" />
        </div>
      </div>
    </div>

    <button class="btn primary block" id="btnSave">Save Settings</button>
  `;

  document.getElementById("btnSave").onclick = async () => {
    const payload = {
      grade1_min_pct: parseFloat(document.getElementById("grade1_min_pct").value),
      grade2_min_pct: parseFloat(document.getElementById("grade2_min_pct").value),
      low_confidence_threshold: parseFloat(document.getElementById("low_confidence_threshold").value),
      undersized_diameter_cm: parseFloat(document.getElementById("undersized_diameter_cm").value),
      base_price_per_quintal: parseFloat(document.getElementById("base_price_per_quintal").value),
      grade_price_adjustment_pct: {
        "Grade 1": parseFloat(document.getElementById("adj_g1").value),
        "Grade 2": parseFloat(document.getElementById("adj_g2").value),
        "URS": parseFloat(document.getElementById("adj_urs").value),
      },
    };
    try {
      await api("/api/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      toast("Settings saved");
    } catch (err) {
      toast("Save failed: " + err.message, 5000);
    }
  };
}

// ---------------------------------------------------------------- init

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}

go("camera");
