# Onion Quality Grading — Fullstack App

AI-powered onion batch inspection: upload single or multi-image batches →
YOLO detects and classifies each onion (healthy / damaged / rotten /
sprouted) → results are aggregated into Grade-A % → a configurable grading
engine assigns Grade 1 / Grade 2 / URS → a pricing engine estimates ₹/quintal
→ an auditable PDF report is generated.

Built on your trained model: `onion-grading-v1.pt` (YOLO detection, 4
classes — see `merged/data.yaml` and `merged/README_DATASET_CARD.md` for
provenance and known limits, especially that **sprouted** is trained on very
few real examples and **rotten** boxes are mostly small surface spots, not
whole onions).

There are **two clients**, both talking to the same FastAPI backend:

- `frontend/` — mobile-responsive web app / PWA (no build step, works in any
  browser, installable to a phone home screen). Built first, before Flutter
  was available in this environment.
- `flutter_app/` — the native Android/iOS app, once the Flutter SDK
  (`flutter_windows_3.44.6-stable`) was installed and extracted to
  `C:\src\flutter`. Same screens, same API, real camera integration.

## Architecture

```
frontend/ (PWA)        flutter_app/ (native)
     |  fetch()              |  http package
     v                       v
          backend/  FastAPI
     |
     +-- app/inference.py   loads onion-grading-v1.pt, runs detection,
     |                      draws annotated boxes (color-coded per class)
     +-- app/grading.py     Grade 1 / Grade 2 / URS + price estimate
     |                      (plain Python rules, not another AI model)
     +-- app/settings.py    configurable thresholds, persisted to
     |                      backend/data/settings.json
     +-- app/db.py          SQLite inspection history
     +-- app/report.py      PDF report (reportlab)
     +-- app/main.py        REST API + static image serving
```

## Running it

### 1. Backend

A venv with everything already installed is at `backend/venv/`:

```
cd backend
venv\Scripts\activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

(To rebuild it elsewhere: `python -m venv venv && venv\Scripts\pip install -r requirements.txt`
— exact versions that were verified working are pinned in `requirements-lock.txt`.)

The API is now at `http://localhost:8000` (docs at `/docs`). It looks for
`onion-grading-v1.pt` in the project root (one level above `backend/`) —
that's already where your trained model is.

`--host 0.0.0.0` matters if you want to open the app from your phone on the
same Wi-Fi: use your PC's LAN IP instead of `localhost`.

### 2. Frontend

Any static file server works, e.g.:

```
cd frontend
python -m http.server 5500
```

Open `http://localhost:5500` in a browser (or on your phone at
`http://<your-PC-LAN-IP>:5500`). Tap the ⚙ icon top-right once and set the
backend URL (defaults to `http://localhost:8000`; on a phone you must point
it at your PC's LAN IP, e.g. `http://192.168.1.23:8000`).

On mobile Chrome, the browser menu → "Add to Home Screen" installs it as an
app icon (PWA), matching the mobile-app framing from the original plan.

### 3. Native mobile app (Flutter)

The SDK is at `C:\src\flutter` (added to your user PATH — open a new
terminal for it to take effect, or run `$env:PATH = "C:\src\flutter\bin;" + $env:PATH`
in the current one).

```
cd flutter_app
flutter pub get
flutter run                 # picks a connected device/emulator, or Chrome
```

Same server-URL gear icon as the web app (top app bar) — defaults to
`http://10.0.2.2:8000`, which is the special address an Android emulator
uses to reach `localhost` on your PC. On a **real phone**, point it at your
PC's LAN IP instead (e.g. `http://192.168.1.23:8000`), same as the web app.

Build a standalone debug APK:

```
flutter build apk --debug
```

Output lands at `flutter_app/build/app/outputs/flutter-apk/app-debug.apk` —
copy it to a phone and install directly (enable "install from unknown
sources" once) if you don't want to run via a cable/ADB.

Two Windows-specific things worth knowing:
- `flutter doctor` will complain about missing Android `cmdline-tools`.
  Harmless here — the SDK platform, build-tools, and license were already
  present from Android Studio, which is everything Gradle needs to build
  the APK.
- `flutter run -d windows` / `-d chrome` for **desktop/plugin symlinks**
  needs Windows **Developer Mode** enabled (Settings → Privacy & security →
  For developers) — Android builds don't need it, but if you want to run
  the Windows desktop target too, flip that on first.
- The backend is plain HTTP, so `android/app/src/main/res/xml/network_security_config.xml`
  explicitly allows cleartext traffic — Android 9+ blocks it by default
  otherwise and every API call would silently fail with no useful error.

## What's implemented from your spec

- **Single image** and **batch inspection** modes (batch = multiple photos
  treated as one inspection; per the plan, counts are simply summed across
  photos — ask users to shoot non-overlapping sections rather than solving
  cross-image duplicate detection, which is flagged as a later-phase
  problem, not an MVP one).
- Per-onion detection + classification, annotated images with color-coded
  boxes (🟢 healthy, 🟠 damaged, 🔴 rotten, 🟣 sprouted, 🟡 undersized) so an
  inspector can see *why* a grade was given, not just the final number.
- **Undersized** is handled the way `merged/data.yaml` specifies — it's not
  a trained visual class. If you supply an optional pixels-per-cm
  calibration value (from a reference object in frame), boxes below the
  configured diameter are reclassified as undersized; otherwise that check
  is simply skipped and the report says so.
- **Grading engine and pricing engine are separate from the AI**, both
  plain, auditable Python rules, both live-configurable from the app's
  "Grading & Pricing Rules" screen (backed by `PUT /api/settings`) — no
  retraining needed to change a threshold.
- **AI confidence gate**: average detection confidence below a configurable
  threshold flags "Low confidence — manual verification recommended"
  instead of silently trusting the model.
- **Inspection history** (SQLite) and a **PDF report** per inspection
  (`GET /api/inspections/{id}/report.pdf`) with the full breakdown, grade,
  price, and annotated photos embedded.
- All grading/pricing numbers are explicitly labeled in the UI and PDF as
  configurable prototype values, not official procurement rates — swap
  `base_price_per_quintal` for a real market-price feed before production
  use, and verify the grade thresholds against the actual DoCA spec if this
  goes beyond a demo.

## Known limitations (carried over from the dataset card)

- Don't ship the **sprouted** grade as trustworthy yet — it's trained on
  copies of only 3 real source crops. Treat sprouted detections as
  low-confidence in practice even when the model reports high confidence.
- **Rotten** boxes are trained on small surface-spot annotations, not
  whole-onion calls — a spot detection doesn't necessarily mean the whole
  onion should be discarded.
- No cross-photo duplicate detection in batch mode yet (documented MVP
  tradeoff, not a bug).
