"""
Loads the trained onion-grading YOLO model once and runs detection on
uploaded images. Each detected box is:
  1. classified by the model into healthy / damaged / rotten / sprouted
  2. optionally re-flagged as "undersized" if the caller supplied a
     pixels-per-cm calibration value (undersized is a SIZE measurement,
     not something the model was trained to see — see merged/data.yaml).

Undersized onions are counted separately and are subtracted out of the
"healthy" bucket, matching the report format: healthy + damaged + rotten
+ sprouted + undersized == total onions detected.

Picks the highest-numbered onion-grading-v*.pt file in the project root
(new fine-tunes get dropped in as vN+1 and the app picks them up on
restart automatically - no code change needed each time). Progress so
far, measured on merged/valid: v1 never detected a sprouted onion
correctly (mAP50 0.00); v2 fixed that (0.34) and raised overall mAP50
0.48 -> 0.60; v3 pushed rotten 0.40 -> 0.47 and overall to 0.63. All
three still miss most onions in a very dense/overlapping pile photo -
that gap is a training-data-density issue, not something a fine-tune on
the existing photos fixes (see training/ for the in-progress attempt at
addressing it directly with denser synthetic composites).
"""
import glob
import os
import re
from typing import Optional

from PIL import Image, ImageDraw, ImageFont
from ultralytics import YOLO

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _find_latest_model() -> str:
    candidates = []
    for path in glob.glob(os.path.join(PROJECT_ROOT, "onion-grading-v*.pt")):
        m = re.search(r"-v(\d+)\.pt$", path, re.IGNORECASE)
        if m:
            candidates.append((int(m.group(1)), path))
    if not candidates:
        # last-resort fallback so a missing/renamed file gives a clear error, not a silent crash
        return os.path.join(PROJECT_ROOT, "onion-grading-v1.pt")
    candidates.sort(key=lambda t: t[0])
    return candidates[-1][1]


MODEL_PATH = _find_latest_model()

CLASS_COLORS = {
    "healthy": (34, 177, 76),      # green
    "damaged": (255, 140, 0),      # orange
    "rotten": (220, 20, 20),       # red
    "sprouted": (160, 32, 240),    # purple
    "undersized": (230, 200, 0),   # yellow
}

_model: Optional[YOLO] = None


def get_model() -> YOLO:
    global _model
    if _model is None:
        if not os.path.exists(MODEL_PATH):
            raise FileNotFoundError(
                f"Trained model not found at {MODEL_PATH}. "
                "Place onion-grading-v1.pt in the project root."
            )
        _model = YOLO(MODEL_PATH)
    return _model


def _load_font():
    try:
        return ImageFont.truetype("arial.ttf", 16)
    except Exception:
        return ImageFont.load_default()


def analyze_image(
    image_path: str,
    annotated_out_path: str,
    settings: dict,
    px_per_cm: Optional[float] = None,
) -> dict:
    """
    Runs detection on one image, draws an annotated copy, and returns a
    per-image breakdown dict.
    """
    model = get_model()
    results = model.predict(
        source=image_path,
        conf=settings["detection_confidence_threshold"],
        iou=settings["detection_iou_threshold"],
        verbose=False,
    )
    result = results[0]

    img = Image.open(image_path).convert("RGB")
    draw = ImageDraw.Draw(img)
    font = _load_font()

    names = result.names  # {0: 'healthy', 1: 'damaged', 2: 'rotten', 3: 'sprouted'}
    counts = {"healthy": 0, "damaged": 0, "rotten": 0, "sprouted": 0, "undersized": 0}
    confidences = []
    onions = []

    boxes = result.boxes
    if boxes is not None:
        for box in boxes:
            cls_id = int(box.cls[0].item())
            label = names.get(cls_id, str(cls_id))
            conf = float(box.conf[0].item())
            x1, y1, x2, y2 = [float(v) for v in box.xyxy[0].tolist()]
            confidences.append(conf)

            undersized = False
            diameter_cm = None
            if px_per_cm and px_per_cm > 0:
                width_cm = (x2 - x1) / px_per_cm
                height_cm = (y2 - y1) / px_per_cm
                diameter_cm = round((width_cm + height_cm) / 2.0, 2)
                if diameter_cm < settings["undersized_diameter_cm"]:
                    undersized = True

            # undersized is tracked as its own bucket and takes priority
            # over "healthy" in the tally (matches the sample report where
            # healthy + damaged + rotten + sprouted + undersized == total).
            bucket = "undersized" if (undersized and label == "healthy") else label
            counts[bucket] = counts.get(bucket, 0) + 1

            color = CLASS_COLORS.get(bucket, (128, 128, 128))
            draw.rectangle([x1, y1, x2, y2], outline=color, width=3)
            tag = bucket if bucket == label else f"{label} (undersized)"
            text = f"{tag} {conf:.0%}"
            text_bbox = draw.textbbox((x1, y1), text, font=font)
            th = text_bbox[3] - text_bbox[1]
            draw.rectangle([x1, max(0, y1 - th - 4), x1 + (text_bbox[2] - text_bbox[0]) + 6, y1], fill=color)
            draw.text((x1 + 3, max(0, y1 - th - 3)), text, fill=(255, 255, 255), font=font)

            onions.append({
                "label": label,
                "bucket": bucket,
                "confidence": round(conf, 4),
                "box": [round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1)],
                "diameter_cm": diameter_cm,
            })

    os.makedirs(os.path.dirname(annotated_out_path), exist_ok=True)
    img.save(annotated_out_path, quality=90)

    total = sum(counts.values())
    avg_conf = round(sum(confidences) / len(confidences), 4) if confidences else 0.0

    return {
        "total_onions": total,
        "counts": counts,
        "avg_confidence": avg_conf,
        "onions": onions,
    }
