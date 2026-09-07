import os
import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import db, grading, report, settings as settings_mod
from .inference import analyze_image

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
DATA_DIR = os.path.join(BASE_DIR, "data")
ORIGINAL_DIR = os.path.join(DATA_DIR, "uploads", "original")
ANNOTATED_DIR = os.path.join(DATA_DIR, "uploads", "annotated")

app = FastAPI(title="Onion Quality Grading API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# StaticFiles requires these to exist at mount time (import time), which
# happens before the startup event fires — so create them here, not there.
os.makedirs(ORIGINAL_DIR, exist_ok=True)
os.makedirs(ANNOTATED_DIR, exist_ok=True)


@app.on_event("startup")
def _startup():
    db.init_db()


app.mount("/static/original", StaticFiles(directory=ORIGINAL_DIR), name="original")
app.mount("/static/annotated", StaticFiles(directory=ANNOTATED_DIR), name="annotated")


# ---------------------------------------------------------------- settings

@app.get("/api/settings")
def get_settings():
    return settings_mod.load_settings()


@app.put("/api/settings")
def update_settings(new_settings: dict):
    return settings_mod.save_settings(new_settings)


# ------------------------------------------------------------- inspections

@app.post("/api/inspections")
async def create_inspection(
    files: List[UploadFile] = File(...),
    mode: str = Form("single"),
    batch_label: Optional[str] = Form(None),
):
    if not files:
        raise HTTPException(400, "At least one image is required.")

    cfg = settings_mod.load_settings()
    inspection_id = "ON-" + datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6].upper()
    created_at = datetime.now().isoformat(timespec="seconds")

    inspection_orig_dir = os.path.join(ORIGINAL_DIR, inspection_id)
    inspection_annot_dir = os.path.join(ANNOTATED_DIR, inspection_id)
    os.makedirs(inspection_orig_dir, exist_ok=True)
    os.makedirs(inspection_annot_dir, exist_ok=True)

    totals = {"healthy": 0, "damaged": 0, "rotten": 0, "sprouted": 0}
    all_confidences = []
    images_meta = []

    for idx, upload in enumerate(files, start=1):
        ext = os.path.splitext(upload.filename or "")[1] or ".jpg"
        safe_name = f"img_{idx}{ext}"
        orig_path = os.path.join(inspection_orig_dir, safe_name)
        # Annotated output is always saved as .jpg regardless of the upload's
        # original format - browsers/Flutter's image decoder can't reliably
        # display some source formats (e.g. AVIF isn't supported by Flutter's
        # bundled image codec at all), so re-encoding to a universally
        # supported format here avoids a broken image on the results screen.
        annot_name = f"img_{idx}.jpg"
        annot_path = os.path.join(inspection_annot_dir, annot_name)

        content = await upload.read()
        with open(orig_path, "wb") as f:
            f.write(content)

        try:
            result = analyze_image(orig_path, annot_path, cfg)
        except Exception as exc:
            raise HTTPException(500, f"Detection failed on image {idx} ({upload.filename}): {exc}")

        for k in totals:
            totals[k] += result["counts"].get(k, 0)
        if result["onions"]:
            all_confidences.extend([o["confidence"] for o in result["onions"]])

        images_meta.append({
            "filename": upload.filename,
            "original_url": f"/static/original/{inspection_id}/{safe_name}",
            "annotated_url": f"/static/annotated/{inspection_id}/{annot_name}",
            "annotated_abs_path": annot_path,
            "total_onions": result["total_onions"],
            "counts": result["counts"],
            "avg_confidence": result["avg_confidence"],
        })

    total_onions = sum(totals.values())
    avg_confidence = round(sum(all_confidences) / len(all_confidences), 4) if all_confidences else 0.0

    if total_onions == 0:
        # Zero detections is not the same thing as "URS" - URS means onions
        # were found and graded below standard. Silently running 0/0 through
        # compute_grade would report a confident-looking URS grade and price
        # for a photo the model found nothing in, which is misleading.
        grade_a_pct = 0.0
        grade = grading.NO_DETECTION
        low_confidence = False
        price = {
            "base_price_per_quintal": cfg["base_price_per_quintal"],
            "grade_adjustment_pct": 0.0,
            "estimated_price_per_quintal": None,
            "note": "No onions were detected in the submitted photo(s), so no price can be estimated.",
        }
        majority = None
    else:
        grade_a_pct = round(100 * totals["healthy"] / total_onions, 1)
        grade = grading.compute_grade(grade_a_pct, cfg)
        low_confidence = grading.is_low_confidence(avg_confidence, cfg)
        price = grading.estimate_price(grade, cfg)
        majority = grading.majority_class(totals, total_onions)

    record = {
        "id": inspection_id,
        "created_at": created_at,
        "mode": mode,
        "batch_label": batch_label,
        "num_images": len(files),
        "total_onions": total_onions,
        **totals,
        "grade_a_pct": grade_a_pct,
        "grade": grade,
        "majority_class": majority[0] if majority else None,
        "majority_class_pct": majority[1] if majority else None,
        "avg_confidence": avg_confidence,
        "low_confidence": low_confidence,
        # DB column is NOT NULL; None (no-detection case) stores as 0.0 there
        # and is restored as None below from grade == NO_DETECTION instead.
        "estimated_price_per_quintal": price["estimated_price_per_quintal"] or 0.0,
        "settings_json": cfg,
        "images_json": images_meta,
    }
    db.insert_inspection(record)

    response = dict(record)
    response["pricing"] = price
    return response


@app.get("/api/inspections")
def api_list_inspections(limit: int = 100):
    return db.list_inspections(limit=limit)


@app.get("/api/inspections/{inspection_id}")
def api_get_inspection(inspection_id: str):
    inspection = db.get_inspection(inspection_id)
    if not inspection:
        raise HTTPException(404, "Inspection not found.")
    return inspection


@app.get("/api/inspections/{inspection_id}/report.pdf")
def api_get_report(inspection_id: str):
    inspection = db.get_inspection(inspection_id)
    if not inspection:
        raise HTTPException(404, "Inspection not found.")
    pdf_path = report.build_report_pdf(inspection)
    return FileResponse(pdf_path, media_type="application/pdf",
                         filename=f"{inspection_id}_report.pdf")


@app.get("/api/health")
def health():
    return {"status": "ok"}
