"""
Minimal SQLite-backed inspection history store. No ORM needed at this
scale; swap for Postgres later by re-pointing these functions.
"""
import json
import os
import sqlite3
from contextlib import contextmanager

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
DATA_DIR = os.path.join(BASE_DIR, "data")
DB_PATH = os.path.join(DATA_DIR, "inspections.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS inspections (
    id TEXT PRIMARY KEY,
    created_at TEXT NOT NULL,
    mode TEXT NOT NULL,
    batch_label TEXT,
    num_images INTEGER NOT NULL,
    total_onions INTEGER NOT NULL,
    healthy INTEGER NOT NULL,
    damaged INTEGER NOT NULL,
    rotten INTEGER NOT NULL,
    sprouted INTEGER NOT NULL,
    undersized INTEGER NOT NULL,
    grade_a_pct REAL NOT NULL,
    grade TEXT NOT NULL,
    avg_confidence REAL NOT NULL,
    low_confidence INTEGER NOT NULL,
    estimated_price_per_quintal REAL NOT NULL,
    undersized_calibrated INTEGER NOT NULL DEFAULT 0,
    settings_json TEXT NOT NULL,
    images_json TEXT NOT NULL
);
"""


@contextmanager
def get_conn():
    os.makedirs(DATA_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    with get_conn() as conn:
        conn.execute(SCHEMA)


def insert_inspection(record: dict):
    with get_conn() as conn:
        conn.execute(
            """
            INSERT INTO inspections (
                id, created_at, mode, batch_label, num_images, total_onions,
                healthy, damaged, rotten, sprouted, undersized,
                grade_a_pct, grade, avg_confidence, low_confidence,
                estimated_price_per_quintal, undersized_calibrated,
                settings_json, images_json
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                record["id"], record["created_at"], record["mode"], record["batch_label"],
                record["num_images"], record["total_onions"],
                record["healthy"], record["damaged"], record["rotten"],
                record["sprouted"], record["undersized"],
                record["grade_a_pct"], record["grade"], record["avg_confidence"],
                int(record["low_confidence"]), record["estimated_price_per_quintal"],
                int(record["undersized_calibrated"]),
                json.dumps(record["settings_json"]), json.dumps(record["images_json"]),
            ),
        )


def _row_to_dict(row: sqlite3.Row) -> dict:
    d = dict(row)
    d["low_confidence"] = bool(d["low_confidence"])
    d["undersized_calibrated"] = bool(d["undersized_calibrated"])
    d["settings_json"] = json.loads(d["settings_json"])
    d["images_json"] = json.loads(d["images_json"])
    return d


def list_inspections(limit: int = 100) -> list:
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT * FROM inspections ORDER BY created_at DESC LIMIT ?", (limit,)
        ).fetchall()
    return [_row_to_dict(r) for r in rows]


def get_inspection(inspection_id: str) -> dict:
    with get_conn() as conn:
        row = conn.execute(
            "SELECT * FROM inspections WHERE id = ?", (inspection_id,)
        ).fetchone()
    return _row_to_dict(row) if row else None
