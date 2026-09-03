"""Generates the auditable PDF inspection report."""
import os

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image as RLImage,
)

from . import grading

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
REPORTS_DIR = os.path.join(BASE_DIR, "data", "reports")

ROW_COLORS = {
    "healthy": colors.HexColor("#22b14c"),
    "damaged": colors.HexColor("#ff8c00"),
    "rotten": colors.HexColor("#dc1414"),
    "sprouted": colors.HexColor("#a020f0"),
    "undersized": colors.HexColor("#e6c800"),
}


def build_report_pdf(inspection: dict) -> str:
    os.makedirs(REPORTS_DIR, exist_ok=True)
    out_path = os.path.join(REPORTS_DIR, f"{inspection['id']}.pdf")

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("TitleBig", parent=styles["Title"], fontSize=20)
    h2 = styles["Heading2"]
    normal = styles["Normal"]
    small = ParagraphStyle("small", parent=styles["Normal"], fontSize=8, textColor=colors.grey)

    doc = SimpleDocTemplate(out_path, pagesize=A4, topMargin=20 * mm, bottomMargin=20 * mm)
    story = []

    story.append(Paragraph("Onion Quality Inspection Report", title_style))
    story.append(Spacer(1, 4 * mm))

    meta = [
        ["Inspection ID", inspection["id"]],
        ["Date", inspection["created_at"]],
        ["Mode", inspection["mode"].capitalize()],
        ["Batch label", inspection["batch_label"] or "-"],
        ["Images analyzed", str(inspection["num_images"])],
        ["Total onions detected", str(inspection["total_onions"])],
    ]
    meta_table = Table(meta, colWidths=[60 * mm, 100 * mm])
    meta_table.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("TEXTCOLOR", (0, 0), (0, -1), colors.grey),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 6 * mm))

    story.append(Paragraph("Quality Breakdown", h2))
    total = max(inspection["total_onions"], 1)
    breakdown_rows = [["Category", "Count", "Percent"]]
    for key in ["healthy", "damaged", "rotten", "sprouted", "undersized"]:
        count = inspection[key]
        pct = round(100 * count / total, 1)
        breakdown_rows.append([key.capitalize(), str(count), f"{pct}%"])
    bt = Table(breakdown_rows, colWidths=[60 * mm, 40 * mm, 40 * mm])
    style_cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#333333")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.lightgrey),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
    ]
    for i, key in enumerate(["healthy", "damaged", "rotten", "sprouted", "undersized"], start=1):
        style_cmds.append(("TEXTCOLOR", (0, i), (0, i), ROW_COLORS[key]))
    bt.setStyle(TableStyle(style_cmds))
    story.append(bt)
    story.append(Spacer(1, 8 * mm))

    story.append(Paragraph("Final Grade", h2))
    grade_style = ParagraphStyle("grade", parent=styles["Title"], fontSize=20, leading=24,
                                  textColor=colors.HexColor("#22b14c") if inspection["grade"] == "Grade 1"
                                  else colors.HexColor("#ff8c00") if inspection["grade"] == "Grade 2"
                                  else colors.HexColor("#dc1414"))
    story.append(Paragraph(grading.grade_label(inspection["grade"]), grade_style))
    story.append(Paragraph(f"Grade-A (healthy): {inspection['grade_a_pct']}%", normal))

    defect = grading.dominant_defect(
        {k: inspection[k] for k in ("healthy", "damaged", "rotten", "sprouted", "undersized")},
        inspection["total_onions"],
    )
    if inspection["grade"] != "Grade 1" and defect:
        defect_label, defect_pct = defect
        story.append(Paragraph(f"Primary factor: {defect_label.capitalize()} ({defect_pct}%)", normal))

    story.append(Paragraph(f"AI confidence: {round(inspection['avg_confidence'] * 100, 1)}%", normal))
    if inspection["low_confidence"]:
        story.append(Paragraph(
            "&#9888; Low confidence — manual verification recommended.",
            ParagraphStyle("warn", parent=normal, textColor=colors.HexColor("#dc1414"))))
    story.append(Spacer(1, 6 * mm))

    story.append(Paragraph("Estimated Price", h2))
    # reportlab's default Helvetica font has no glyph for U+20B9 (renders as a
    # missing-glyph box in most viewers) — "Rs." is the safe fallback here.
    story.append(Paragraph(f"Rs. {inspection['estimated_price_per_quintal']} / quintal", normal))
    story.append(Paragraph(
        "Demo/configurable estimate — replace with an authorized market price source for production use.",
        small))
    story.append(Spacer(1, 8 * mm))

    story.append(Paragraph("Analyzed Images", h2))
    for img in inspection["images_json"]:
        annotated_path = img.get("annotated_abs_path")
        if annotated_path and os.path.exists(annotated_path):
            try:
                story.append(RLImage(annotated_path, width=150 * mm, height=100 * mm, kind="proportional"))
                story.append(Spacer(1, 3 * mm))
            except Exception:
                pass

    story.append(Spacer(1, 10 * mm))
    story.append(Paragraph(
        "Grade 1 = high-quality onions. Grade 2 = acceptable but lower quality. "
        "URS = Unfit for Sale — does not meet the minimum quality requirement.",
        small))
    story.append(Paragraph(
        "Grading thresholds and pricing are configurable prototype values, not official "
        "procurement standards, unless verified against the applicable specification.",
        small))

    doc.build(story)
    return out_path
