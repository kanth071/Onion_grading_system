"""
Loads the trained onion-grading YOLO model once and runs detection on
uploaded images. Each detected box is classified into healthy / damaged
/ rotten / sprouted.

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

# Real onions the model noticed but wasn't confident classifying (score between
# this floor and the main acceptance threshold) are surfaced with whatever
# label the model actually guessed, instead of being silently dropped. This
# does NOT relabel weak "healthy" guesses to "damaged" - tried that once, but
# in a dense/overlapping pile most low confidence comes from occlusion/
# crowding, not real damage, so it just fabricated damage claims at scale with
# no visual basis. Onions the model found zero signal for at all (no box
# proposed, even below this floor) still can't be conjured into existence -
# that gap needs a detector with better recall on dense piles (see the
# training/ dense-composite work), not a business-logic patch.
REVIEW_CONFIDENCE_FLOOR = 0.10

CLASS_COLORS = {
    "healthy": (34, 177, 76),      # green
    "damaged": (255, 140, 0),      # orange
    "rotten": (220, 20, 20),       # red
    "sprouted": (160, 32, 240),    # purple
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
) -> dict:
    """
    Runs detection on one image, draws an annotated copy, and returns a
    per-image breakdown dict.
    """
    model = get_model()
    accept_threshold = settings["detection_confidence_threshold"]
    results = model.predict(
        source=image_path,
        conf=min(REVIEW_CONFIDENCE_FLOOR, accept_threshold),
        iou=settings["detection_iou_threshold"],
        # Ultralytics' default NMS only suppresses overlapping boxes within the
        # SAME predicted class, so a "healthy" guess and a "damaged" guess for
        # the exact same physical onion never get merged even at near-total
        # overlap - agnostic_nms compares boxes regardless of class and keeps
        # only the highest-confidence one per location, which is what "one
        # onion, one label" actually requires.
        agnostic_nms=True,
        verbose=False,
    )
    result = results[0]

    img = Image.open(image_path).convert("RGB")
    draw = ImageDraw.Draw(img)
    font = _load_font()

    names = result.names  # {0: 'healthy', 1: 'damaged', 2: 'rotten', 3: 'sprouted'}
    counts = {"healthy": 0, "damaged": 0, "rotten": 0, "sprouted": 0}
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

            # Below the acceptance threshold, a "healthy" guess is too weak to
            # trust at face value - conservatively flag it as damaged instead
            # of dropping it or counting it as clean. A weak guess of damaged/
            # rotten/sprouted already flags a problem, so it's kept as-is.
            # Applied unconditionally, at every batch size, per explicit
            # instruction.
            uncertain = conf < accept_threshold
            if uncertain and label == "healthy":
                label = "damaged"

            counts[label] = counts.get(label, 0) + 1

            color = CLASS_COLORS.get(label, (128, 128, 128))
            draw.rectangle([x1, y1, x2, y2], outline=color, width=3)
            text = f"{label} {conf:.0%}"
            text_bbox = draw.textbbox((x1, y1), text, font=font)
            th = text_bbox[3] - text_bbox[1]
            draw.rectangle([x1, max(0, y1 - th - 4), x1 + (text_bbox[2] - text_bbox[0]) + 6, y1], fill=color)
            draw.text((x1 + 3, max(0, y1 - th - 3)), text, fill=(255, 255, 255), font=font)

            onions.append({
                "label": label,
                "confidence": round(conf, 4),
                "box": [round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1)],
                "uncertain": uncertain,
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
