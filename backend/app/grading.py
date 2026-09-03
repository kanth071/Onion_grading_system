"""
Grading + pricing engines.

Deliberately plain Python logic, NOT another AI model — this is what keeps
grading rules auditable, testable, and changeable by an admin without
retraining anything. See settings.py for the tunable thresholds.
"""


def compute_grade(grade_a_pct: float, settings: dict) -> str:
    if grade_a_pct >= settings["grade1_min_pct"]:
        return "Grade 1"
    if grade_a_pct >= settings["grade2_min_pct"]:
        return "Grade 2"
    return "URS"


# URS = Unfit for Sale / below the minimum quality requirement, not an
# abbreviation most users will recognize on sight — always pair the code
# with this label wherever a grade is shown to a person.
GRADE_LABELS = {
    "Grade 1": "Grade 1 — High Quality",
    "Grade 2": "Grade 2 — Acceptable, Lower Quality",
    "URS": "URS — Below Standard (Unfit for Sale)",
}


def grade_label(grade: str) -> str:
    return GRADE_LABELS.get(grade, grade)


_DEFECT_CLASSES = ["damaged", "rotten", "sprouted", "undersized"]


def dominant_defect(counts: dict, total: int):
    """
    Returns (class_name, pct) for whichever defect bucket makes up the
    largest share of the batch, or None if there's nothing to explain
    (empty batch, or every onion is healthy). Used to answer "why did
    this batch get URS/Grade 2?" instead of just showing a bare percentage.
    """
    if total <= 0:
        return None
    best_key, best_count = None, 0
    for key in _DEFECT_CLASSES:
        count = counts.get(key, 0)
        if count > best_count:
            best_key, best_count = key, count
    if not best_key:
        return None
    return best_key, round(100 * best_count / total, 1)


def estimate_price(grade: str, settings: dict) -> dict:
    base = settings["base_price_per_quintal"]
    adj_pct = settings["grade_price_adjustment_pct"].get(grade, 0.0)
    estimated = round(base * (1 + adj_pct / 100.0), 2)
    return {
        "base_price_per_quintal": base,
        "grade_adjustment_pct": adj_pct,
        "estimated_price_per_quintal": estimated,
        "note": "Demo/configurable pricing. Replace base_price_per_quintal with an "
                "authorized/current market price source before production use.",
    }


def is_low_confidence(avg_confidence: float, settings: dict) -> bool:
    return avg_confidence < settings["low_confidence_threshold"]
