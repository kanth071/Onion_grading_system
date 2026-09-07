# GradeLens AI — Onion Quality Grading Platform

**[Demo video](https://drive.google.com/file/d/1W0t8OEfG1TnkzP_I9HhQb1T0AlgZ2C4P/view?usp=drivesdk)**

AI-powered onion batch inspection: upload a single photo or a multi-image
batch → a YOLO model detects and classifies each onion (healthy / damaged /
rotten / sprouted) → results are aggregated into a Grade-A % → a configurable
grading engine assigns **Grade 1 / Grade 2 / URS** → a pricing engine
estimates ₹/quintal → an auditable PDF report is generated.

The backend auto-selects the highest-numbered trained checkpoint in the
project root (`onion-grading-v*.pt`), so it always runs the latest model
without a config change. See `merged/README_DATASET_CARD.md` for dataset
provenance and known limits — in particular, **sprouted** is trained on very
few real examples and **rotten** boxes are mostly small surface spots, not
whole onions.

There are **two clients**, both talking to the same FastAPI backend:

- `frontend/` — mobile-responsive web app / PWA (no build step, works in any
  browser, installable to a phone home screen).
- `flutter_app/` — the native Android/iOS/desktop/web app, with dashboard,
  new-inspection, history, analytics, and settings screens. Same backend
  API, real camera integration.

## Architecture

```
┌──────────────────────┐        ┌──────────────────────┐
│   frontend/  (PWA)    │        │  flutter_app/ (Flutter) │
│   app.js, index.html  │        │  dashboard / upload /    │
│   fetch() over HTTP   │        │  history / analytics /   │
│                       │        │  settings screens        │
└───────────┬───────────┘        └───────────┬───────────┘
            │  REST + JSON                    │  http package
            └────────────────┬────────────────┘
                              ▼
                 backend/app  (FastAPI)
                              │
   ┌───────────────┬─────────┼─────────────┬───────────────┐
   ▼               ▼         ▼             ▼               ▼
inference.py   grading.py  settings.py    db.py         report.py
loads the      Grade 1/2/  configurable   SQLite        PDF report
newest         URS rules   thresholds,    inspection    (reportlab)
onion-grading- + price     persisted to   history       with grade,
v*.pt, runs    estimate    backend/data/  (backend/     price, and
YOLO detection (plain      settings.json  data/         annotated
+ classifies,  Python,                    inspections.db) photos
draws          not an AI
color-coded    model)
boxes
```

**`backend/app/main.py`** wires it together as the REST API:

| Endpoint | Purpose |
|---|---|
| `GET /api/settings` / `PUT /api/settings` | read/write grading + pricing thresholds |
| `POST /api/inspections` | run inference on an uploaded photo/batch, grade it, store it |
| `GET /api/inspections` | list inspection history |
| `GET /api/inspections/{id}` | one inspection's full detail |
| `GET /api/inspections/{id}/report.pdf` | the auditable PDF report |
| `GET /api/health` | liveness check |

Design points worth knowing:

- **Grading and pricing are plain Python rules, not a second AI model** —
  auditable, testable, and editable from the app's Settings screen with no
  retraining required.
- **Model selection is automatic**: `inference.py` globs for
  `onion-grading-v*.pt` in the project root and picks the highest version
  number, so dropping in a newly trained checkpoint is enough to deploy it.
- **NO_DETECTION is distinct from URS** — URS means onions were found and
  graded below standard; NO_DETECTION means the model found nothing to grade
  (bad photo, empty frame, or a domain-gap miss). The UI must never conflate
  the two.
- **Low-confidence gate**: an inspection whose average detection confidence
  falls below a configurable threshold is flagged "manual verification
  recommended" instead of silently trusted.

## What's implemented

- **Single image** and **batch inspection** modes (batch = multiple photos
  treated as one inspection; counts are summed across photos — users shoot
  non-overlapping sections rather than the app solving cross-image
  duplicate detection, which is a later-phase problem, not an MVP one).
- Per-onion detection + classification, annotated images with color-coded
  boxes (🟢 healthy, 🟠 damaged, 🔴 rotten, 🟣 sprouted, 🟡 undersized) so an
  inspector can see *why* a grade was given, not just the final number.
- **Undersized** is handled the way `merged/data.yaml` specifies — it's not
  a trained visual class. If an optional pixels-per-cm calibration value is
  supplied (from a reference object in frame), boxes below the configured
  diameter are reclassified as undersized; otherwise that check is skipped
  and the report says so.
- **Grading engine and pricing engine are separate from the AI**, both
  plain, auditable Python rules, both live-configurable from the app's
  Settings screen (backed by `PUT /api/settings`) — no retraining needed to
  change a threshold.
- **AI confidence gate**: average detection confidence below a configurable
  threshold flags "Low confidence — manual verification recommended"
  instead of silently trusting the model.
- **Inspection history** (SQLite) with search/filter, an **Analytics**
  dashboard (quality distribution, inspection trend, common defects), and a
  **PDF report** per inspection (`GET /api/inspections/{id}/report.pdf`)
  with the full breakdown, grade, price, and annotated photos embedded.
- All grading/pricing numbers are explicitly labeled in the UI and PDF as
  configurable prototype values, not official procurement rates — swap
  `base_price_per_quintal` for a real market-price feed before production
  use, and verify the grade thresholds against the actual DoCA spec if this
  goes beyond a demo.

## Known limitations (carried over from the dataset card)

- Don't ship the **sprouted** grade as trustworthy yet — it's trained on
  copies of only a handful of real source crops. Treat sprouted detections
  as low-confidence in practice even when the model reports high
  confidence.
- **Rotten** boxes are trained on small surface-spot annotations, not
  whole-onion calls — a spot detection doesn't necessarily mean the whole
  onion should be discarded.
- No cross-photo duplicate detection in batch mode yet (documented MVP
  tradeoff, not a bug).
