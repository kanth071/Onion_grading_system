"""Generates the auditable PDF inspection report."""
import os
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image as RLImage,
    HRFlowable, KeepTogether,
)
from reportlab.graphics.shapes import Drawing, Rect, String, Circle

from . import grading

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
REPORTS_DIR = os.path.join(BASE_DIR, "data", "reports")

INK = colors.HexColor("#1c1e18")
MUTED = colors.HexColor("#6b7280")
BORDER = colors.HexColor("#e4e2d8")

GREEN = colors.HexColor("#1a9c47")
GREEN_LIGHT = colors.HexColor("#e8f7ec")
ORANGE = colors.HexColor("#e8770a")
ORANGE_LIGHT = colors.HexColor("#fff1e2")
RED = colors.HexColor("#d13030")
RED_LIGHT = colors.HexColor("#fbe9e9")
PURPLE = colors.HexColor("#8b3fd6")
PURPLE_LIGHT = colors.HexColor("#f2e9fb")

ROW_COLORS = {"healthy": GREEN, "damaged": ORANGE, "rotten": RED, "sprouted": PURPLE}
ROW_HEX = {"healthy": "#1a9c47", "damaged": "#e8770a", "rotten": "#d13030", "sprouted": "#8b3fd6"}
CLASS_ORDER = ["healthy", "damaged", "rotten", "sprouted"]

GRADE_COLORS = {
    "Grade 1": (GREEN, GREEN_LIGHT),
    "Grade 2": (ORANGE, ORANGE_LIGHT),
    "URS": (RED, RED_LIGHT),
    grading.NO_DETECTION: (RED, RED_LIGHT),
}

PAGE_MARGIN = 13 * mm
CONTENT_WIDTH = A4[0] - 2 * PAGE_MARGIN


def _wrap_lines(text, font, size, max_width):
    """Greedy word-wrap using real glyph widths (shapes.String doesn't wrap on its own)."""
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if stringWidth(trial, font, size) <= max_width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def _stat_card(width, height, label, value, sublabel=None, value_color=INK,
               bg=colors.white, border=BORDER, value_size=15):
    d = Drawing(width, height)
    d.add(Rect(0, 0, width, height, rx=6, ry=6, fillColor=bg, strokeColor=border, strokeWidth=0.75))
    pad = 8
    d.add(String(pad, height - 16, label.upper(), fontName="Helvetica-Bold", fontSize=6.8, fillColor=MUTED))
    value_lines = _wrap_lines(value, "Helvetica-Bold", value_size, width - 2 * pad)
    vy = height - 34
    for line in value_lines[:2]:
        d.add(String(pad, vy, line, fontName="Helvetica-Bold", fontSize=value_size, fillColor=value_color))
        vy -= value_size + 2
    if sublabel:
        sub_lines = _wrap_lines(sublabel, "Helvetica", 7, width - 2 * pad)
        sy = 8 + (len(sub_lines) - 1) * 9
        for line in sub_lines[:2]:
            d.add(String(pad, sy, line, fontName="Helvetica", fontSize=7, fillColor=MUTED))
            sy -= 9
    return d


def _confidence_band(avg_confidence, low_confidence):
    pct = avg_confidence * 100
    if low_confidence:
        return "low — manual verification required"
    if pct >= 85:
        return "high confidence"
    return "moderate — spot-check advised"


def build_report_pdf(inspection: dict) -> str:
    os.makedirs(REPORTS_DIR, exist_ok=True)
    out_path = os.path.join(REPORTS_DIR, f"{inspection['id']}.pdf")

    styles = getSampleStyleSheet()
    normal = styles["Normal"]
    small = ParagraphStyle("small", parent=normal, fontSize=8, textColor=MUTED, leading=11)
    eyebrow = ParagraphStyle("eyebrow", parent=normal, fontSize=8.5, textColor=MUTED,
                              fontName="Helvetica-Bold", leading=11)
    title_style = ParagraphStyle("TitleBig", parent=styles["Title"], fontSize=18, leading=21,
                                  textColor=INK, alignment=0, spaceAfter=1)
    subtitle_style = ParagraphStyle("subtitle", parent=normal, fontSize=9.5, textColor=MUTED)
    section_h = ParagraphStyle("sectionH", parent=normal, fontSize=11, fontName="Helvetica-Bold",
                                textColor=INK, spaceBefore=0, spaceAfter=4)
    brand_style = ParagraphStyle("brand", parent=normal, fontSize=14, fontName="Helvetica-Bold", textColor=INK)
    tagline_style = ParagraphStyle("tagline", parent=normal, fontSize=8, textColor=MUTED)
    cert_style = ParagraphStyle("cert", parent=normal, fontSize=8.5, textColor=MUTED, alignment=TA_RIGHT, leading=12)

    doc = SimpleDocTemplate(out_path, pagesize=A4, topMargin=PAGE_MARGIN, bottomMargin=PAGE_MARGIN,
                             leftMargin=PAGE_MARGIN, rightMargin=PAGE_MARGIN)
    story = []

    # ---------------------------------------------------------------- header
    try:
        issued = datetime.fromisoformat(inspection["created_at"]).strftime("%d %b %Y, %H:%M")
    except ValueError:
        issued = inspection["created_at"]

    # Core Helvetica has no emoji glyphs (WinAnsi encoding tops out at Latin-1) -
    # draw a simple icon mark instead of trying to render an actual emoji character.
    icon = Drawing(10 * mm, 10 * mm)
    icon.add(Rect(0, 0, 10 * mm, 10 * mm, rx=3, ry=3, fillColor=GREEN, strokeColor=None))
    icon.add(Circle(5 * mm, 5 * mm, 3 * mm, fillColor=colors.white, strokeColor=None))
    brand_text = Paragraph(
        "OnionGrade AI<br/><font size=8 color='#6b7280'>Automated Produce Quality Assessment</font>",
        brand_style)
    brand_block = Table([[icon, brand_text]], colWidths=[13 * mm, CONTENT_WIDTH * 0.6 - 13 * mm])
    brand_block.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (0, 0), 6),
    ]))
    header_right = Paragraph(
        f"Certificate <b>{inspection['id']}</b><br/>Issued {issued}", cert_style)
    header = Table([[brand_block, header_right]], colWidths=[CONTENT_WIDTH * 0.6, CONTENT_WIDTH * 0.4])
    header.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
    ]))
    story.append(header)
    story.append(Spacer(1, 4))
    story.append(HRFlowable(width="100%", thickness=1, color=BORDER))
    story.append(Spacer(1, 6))

    story.append(Paragraph("INSPECTION REPORT", eyebrow))
    story.append(Paragraph("Onion Quality Inspection Report", title_style))

    mode_label = "Single-image" if inspection["mode"] == "single" else "Batch"
    story.append(Paragraph(
        f"{mode_label} inspection &middot; {inspection['total_onions']} onions detected "
        f"&middot; automated computer-vision grading", subtitle_style))
    story.append(Spacer(1, 8))

    no_detection = inspection["grade"] == grading.NO_DETECTION

    if no_detection:
        # ------------------------------------------------ no-detection state
        warn_card = Drawing(CONTENT_WIDTH, 26 * mm)
        warn_card.add(Rect(0, 0, CONTENT_WIDTH, 26 * mm, rx=8, ry=8, fillColor=RED_LIGHT,
                            strokeColor=RED, strokeWidth=0.75))
        warn_card.add(String(10, 26 * mm - 20, "No Onions Detected",
                              fontName="Helvetica-Bold", fontSize=15, fillColor=RED))
        note_lines = _wrap_lines(
            "The model found nothing to grade in the submitted photo(s). No grade or price "
            "could be computed. Retake the photo closer, with better lighting, so the batch "
            "fills the frame, and try again.", "Helvetica", 9, CONTENT_WIDTH - 20)
        ny = 26 * mm - 38
        for line in note_lines:
            warn_card.add(String(10, ny, line, fontName="Helvetica", fontSize=9, fillColor=INK))
            ny -= 12
        story.append(warn_card)
        story.append(Spacer(1, 14))
    else:
        grade = inspection["grade"]
        grade_color, grade_bg = GRADE_COLORS.get(grade, (INK, colors.white))
        conf_pct = round(inspection["avg_confidence"] * 100, 1)
        conf_band = _confidence_band(inspection["avg_confidence"], inspection["low_confidence"])

        # ------------------------------------------------------ stat cards
        gap = 3 * mm
        card_w = (CONTENT_WIDTH - 3 * gap) / 4
        card_h = 19 * mm
        cards = [
            _stat_card(card_w, card_h, "Overall Grade", grading.grade_label(grade).split(" — ")[0],
                       sublabel=(grading.grade_label(grade).split(" — ", 1)[1]
                                 if " — " in grading.grade_label(grade) else None),
                       value_color=grade_color, bg=grade_bg, border=grade_color, value_size=15),
            _stat_card(card_w, card_h, "Onions Detected", str(inspection["total_onions"]),
                       sublabel=f"from {inspection['num_images']} image(s)"),
            _stat_card(card_w, card_h, "Grade-A Content", f"{inspection['grade_a_pct']}%",
                       sublabel="healthy share"),
            _stat_card(card_w, card_h, "AI Confidence", f"{conf_pct}%", sublabel=conf_band,
                       value_color=(RED if inspection["low_confidence"] else INK)),
        ]
        card_row = Table([cards], colWidths=[card_w] * 4)
        card_row.setStyle(TableStyle([
            ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), gap),
            ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ]))
        story.append(card_row)
        story.append(Spacer(1, 10))

        # ------------------------------------------------- quality breakdown
        story.append(Paragraph("Quality Breakdown", section_h))
        total = max(inspection["total_onions"], 1)
        header_row = ["CATEGORY", "COUNT", "SHARE"]
        breakdown_rows = [header_row]
        for key in CLASS_ORDER:
            count = inspection[key]
            pct = round(100 * count / total, 1)
            dot = f'<font color="{ROW_HEX[key]}">&#8226;</font>'
            label = Paragraph(f"{dot} {key.capitalize()}", normal)
            breakdown_rows.append([label, str(count), f"{pct}%"])
        breakdown_rows.append([Paragraph("<b>Total</b>", normal), f"{inspection['total_onions']}", "100.0%"])

        bt = Table(breakdown_rows, colWidths=[CONTENT_WIDTH * 0.5, CONTENT_WIDTH * 0.25, CONTENT_WIDTH * 0.25])
        n_rows = len(breakdown_rows)
        bt.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f3f4f0")),
            ("TEXTCOLOR", (0, 0), (-1, 0), MUTED),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, 0), 7.5),
            ("FONTSIZE", (0, 1), (-1, -1), 9.5),
            ("LINEBELOW", (0, 0), (-1, -2), 0.5, BORDER),
            ("LINEABOVE", (0, n_rows - 1), (-1, n_rows - 1), 1, INK),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
            ("TOPPADDING", (0, 0), (-1, -1), 3.5),
            ("ALIGN", (1, 0), (-1, -1), "LEFT"),
        ]))
        story.append(bt)
        story.append(Spacer(1, 10))

        # ---------------------------------------------- grade determination
        story.append(Paragraph("Grade Determination", section_h))
        badge = Drawing(24 * mm, 24 * mm)
        badge.add(Circle(12 * mm, 12 * mm, 11 * mm, fillColor=grade_color, strokeColor=None))
        short_grade = grade.replace("Grade ", "G") if grade.startswith("Grade") else grade if grade != grading.NO_DETECTION else "?"
        badge.add(String(12 * mm, 13 * mm, short_grade, fontName="Helvetica-Bold", fontSize=11,
                          fillColor=colors.white, textAnchor="middle"))
        badge.add(String(12 * mm, 8 * mm, "GRADE", fontName="Helvetica-Bold", fontSize=5.5,
                          fillColor=colors.white, textAnchor="middle"))

        defect = grading.dominant_defect({k: inspection[k] for k in CLASS_ORDER}, inspection["total_onions"])
        majority_cls = inspection.get("majority_class")
        majority_pct = inspection.get("majority_class_pct")

        explain_parts = [
            f"Based on the quality assessment above, this consignment qualifies as "
            f"<b>{grading.grade_label(grade)}</b> with <b>{inspection['grade_a_pct']}%</b> Grade-A content."
        ]
        if majority_cls:
            explain_parts.append(
                f"The majority of detected onions were classified as "
                f"<b>{majority_cls.capitalize()}</b> ({majority_pct}%).")
        if grade != "Grade 1" and defect:
            defect_label, defect_pct = defect
            explain_parts.append(
                f"The primary factor was <b>{defect_label.capitalize()}</b> ({defect_pct}%).")
        explain_parts.append(
            f"AI confidence for this inspection was <b>{conf_pct}%</b> ({conf_band}).")
        if inspection["low_confidence"]:
            explain_parts.append(
                '<font color="#d13030">A manual spot-check is strongly recommended before final acceptance.</font>')

        explain_para = Paragraph(" ".join(explain_parts), ParagraphStyle(
            "explain", parent=normal, fontSize=8.5, leading=12, textColor=INK))

        det_table = Table([[badge, explain_para]], colWidths=[28 * mm, CONTENT_WIDTH - 28 * mm])
        det_table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("BOX", (0, 0), (-1, -1), 0.75, BORDER),
            ("LEFTPADDING", (0, 0), (0, 0), 6), ("RIGHTPADDING", (0, 0), (0, 0), 3),
            ("LEFTPADDING", (1, 0), (1, 0), 8), ("RIGHTPADDING", (1, 0), (1, 0), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]))
        story.append(det_table)
        story.append(Spacer(1, 10))

        # ------------------------------------------------- estimated price
        story.append(Paragraph("Estimated Market Value", section_h))
        price_para = Paragraph(
            f'<font size=20 color="#1c1e18"><b>Rs. {inspection["estimated_price_per_quintal"]:.2f}</b></font>'
            f'&nbsp;&nbsp;<font size=9 color="#6b7280">per quintal</font>', normal)
        price_note = Paragraph(
            "Configurable demonstration estimate, not a live market feed. Substitute an "
            "authorized mandi / APMC price source for commercial use.", small)
        price_table = Table([[price_para, price_note]], colWidths=[CONTENT_WIDTH * 0.45, CONTENT_WIDTH * 0.55])
        price_table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ]))
        story.append(price_table)
        story.append(Spacer(1, 10))

    # ---------------------------------------------------- photographic evidence
    images = inspection["images_json"]
    if images:
        evidence_heading = Paragraph("Photographic Evidence", section_h)
        for i, img in enumerate(images, start=1):
            annotated_path = img.get("annotated_abs_path")
            if not (annotated_path and os.path.exists(annotated_path)):
                continue
            try:
                thumb = RLImage(annotated_path, width=48 * mm, height=34 * mm, kind="proportional")
            except Exception:
                continue
            img_total = img.get("total_onions", 0)
            caption_parts = [
                f"<b>Fig. {i} — Annotated detection image ({i} of {len(images)})</b><br/>"
                f"{img_total} onion(s) detected, per-instance confidence overlaid by the detection model."
            ]
            caption = Paragraph(" ".join(caption_parts), ParagraphStyle(
                "caption", parent=normal, fontSize=8.5, leading=11.5, textColor=INK))
            row = [thumb, caption]
            evidence_table = Table([row], colWidths=[52 * mm, CONTENT_WIDTH - 52 * mm])
            evidence_table.setStyle(TableStyle([
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (1, 0), (1, 0), 0),
                ("RIGHTPADDING", (0, 0), (0, 0), 8),
            ]))
            # Keep the section heading glued to the first figure so it never
            # gets orphaned alone at the bottom of a page.
            block = [evidence_heading, evidence_table] if evidence_heading else [evidence_table]
            evidence_heading = None
            if img_total > 40:
                block.append(Spacer(1, 4))
                readability = Paragraph(
                    "<b>Readability note:</b> at this onion density the individual confidence "
                    "labels overlap and are not legible at print size. The aggregate figures "
                    "above are the authoritative record for this inspection.",
                    ParagraphStyle("readability", parent=small, backColor=colors.HexColor("#fff6e0"),
                                   borderColor=colors.HexColor("#f0d98c"), borderWidth=0.5,
                                   borderPadding=6, textColor=colors.HexColor("#7a5c00")))
                block.append(readability)
            story.append(KeepTogether(block))
            story.append(Spacer(1, 6))

    story.append(Spacer(1, 4))
    story.append(HRFlowable(width="100%", thickness=0.75, color=BORDER))
    story.append(Spacer(1, 6))

    # ---------------------------------------------------------------- footer
    sig_style = ParagraphStyle("sig", parent=normal, fontSize=7.5, textColor=MUTED)
    sig_cell = lambda label: [Spacer(1, 8), HRFlowable(width="90%", thickness=0.5, color=BORDER),
                               Spacer(1, 2), Paragraph(label, sig_style)]
    footer_table = Table([[sig_cell("Inspected By (Automated System)"),
                            sig_cell("Reviewed By"),
                            sig_cell("Authorized Signature &amp; Stamp")]],
                          colWidths=[CONTENT_WIDTH / 3] * 3)
    footer_table.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    story.append(footer_table)
    story.append(Spacer(1, 5))
    story.append(Paragraph(
        f"This is a system-generated inspection report produced by OnionGrade AI. {inspection['id']}",
        ParagraphStyle("footnote", parent=small, fontSize=7.5)))
    story.append(Paragraph(
        "Grade 1 = high-quality onions. Grade 2 = acceptable but lower quality. "
        "URS = Unfit for Sale — does not meet the minimum quality requirement. "
        "Grading thresholds and pricing are configurable prototype values, not official "
        "procurement standards, unless verified against the applicable specification.",
        ParagraphStyle("footnote2", parent=small, fontSize=7.5)))

    doc.build(story)
    return out_path
