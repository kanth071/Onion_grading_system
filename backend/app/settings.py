"""
Configurable grading / pricing / detection settings.

Persisted to data/settings.json so an admin can tune thresholds without
retraining or redeploying the AI model. All numeric thresholds here are
DEMO / PROTOTYPE defaults, not official government procurement standards.
"""
import json
import os
import threading

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
DATA_DIR = os.path.join(BASE_DIR, "data")
SETTINGS_PATH = os.path.join(DATA_DIR, "settings.json")

DEFAULT_SETTINGS = {
    # --- Grading engine (Grade-A % = healthy / total onions detected) ---
    "grade1_min_pct": 80.0,   # Grade-A% >= this -> Grade 1
    "grade2_min_pct": 60.0,   # Grade-A% >= this (and < grade1) -> Grade 2
    # below grade2_min_pct -> URS / Below Standard

    # --- AI confidence gate ---
    "low_confidence_threshold": 0.65,  # avg detection confidence below this -> flag for manual review

    # --- Pricing engine (demo values, NOT an authorized price feed) ---
    "base_price_per_quintal": 2500.0,
    "grade_price_adjustment_pct": {
        "Grade 1": 10.0,
        "Grade 2": -5.0,
        "URS": -20.0,
    },

    # --- Size / "undersized" calibration (optional, off unless caller supplies px_per_cm) ---
    "undersized_diameter_cm": 4.0,  # onions with estimated diameter below this are "undersized"

    "detection_confidence_threshold": 0.25,  # YOLO box confidence cutoff to even count a detection
    "detection_iou_threshold": 0.45,
}

_lock = threading.Lock()


def _ensure_file():
    os.makedirs(DATA_DIR, exist_ok=True)
    if not os.path.exists(SETTINGS_PATH):
        with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_SETTINGS, f, indent=2)


def load_settings() -> dict:
    _ensure_file()
    with _lock:
        with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    # backfill any keys added after a user's settings.json was created
    merged = {**DEFAULT_SETTINGS, **data}
    return merged


def save_settings(new_settings: dict) -> dict:
    current = load_settings()
    current.update(new_settings)
    with _lock:
        with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
            json.dump(current, f, indent=2)
    return current
