"""
evaluate_model.py -- honest per-class evaluation for any onion-grading .pt
against the repo's canonical validation set (training/merged_v2/valid).

WHY THIS EXISTS
----------------
Ultralytics metrics are only meaningful when the model's class ids line up
with the dataset's class ids. That silently broke during the v6/v7
fine-tunes: those models were trained on a scratch dataset that declared
the order ['healthy','damaged','sprouted','rotten'] while the canonical
dataset (training/merged_v2/data.yaml) declares ['healthy','damaged',
'rotten','sprouted']. Validating v7 straight against merged_v2/valid then
reported ~0.0 mAP for rotten/sprouted even though the model is fine --
it was just comparing every box against the wrong class id.

This harness therefore aligns class ids BY NAME before scoring, so it works
for any model regardless of its internal class order, and it reports which
mapping it used so a mismatch is visible instead of silently poisoning the
metrics.

It also breaks down damaged/rotten recall by image type, because the
validation set is dominated by synthetic single-crop close-ups (256x256)
and dense composites (640x640) that overstate real-world performance: the
real-photo subset is where the model actually has to prove itself.

USAGE
-----
    python evaluate_model.py onion-grading-v7.pt
    python evaluate_model.py onion-grading-v7.pt --conf 0.25 --iou 0.45
"""
import argparse
import glob
import os

from PIL import Image
from ultralytics import YOLO

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASET = os.path.join(REPO_ROOT, "training", "merged_v2")
DEFAULT_VALID_IMAGES = os.path.join(DATASET, "valid", "images")
DEFAULT_VALID_LABELS = os.path.join(DATASET, "valid", "labels")

# Canonical class names and their ids in merged_v2's data.yaml. Every model
# is scored against THIS ordering; the model's own ids are remapped below.
CANONICAL_NAMES = ["healthy", "damaged", "rotten", "sprouted"]


def load_gt(label_path, img_w, img_h, to_model_id):
    """Dataset labels are in CANONICAL id order; remap each box's class id
    into the model's id space so gt and predictions are comparable."""
    boxes = []
    if not os.path.exists(label_path):
        return boxes
    with open(label_path) as f:
        for line in f.read().strip().splitlines():
            if not line.strip():
                continue
            c, cx, cy, w, h = map(float, line.split())
            boxes.append((to_model_id(int(c)), (cx - w / 2) * img_w, (cy - h / 2) * img_h,
                          (cx + w / 2) * img_w, (cy + h / 2) * img_h))
    return boxes


def iou(b1, b2):
    x1 = max(b1[0], b2[0]); y1 = max(b1[1], b2[1])
    x2 = min(b1[2], b2[2]); y2 = min(b1[3], b2[3])
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    union = (b1[2] - b1[0]) * (b1[3] - b1[1]) + (b2[2] - b2[0]) * (b2[3] - b2[1]) - inter
    return inter / union if union > 0 else 0


def group_of(size):
    """Validation images fall into three appearance regimes; a model that is
    good only on the first two has NOT been proven on real photos."""
    w, h = size
    if (w, h) == (256, 256):
        return "crop-closeup (256px)"
    if (w, h) == (640, 640):
        return "dense composite (640px)"
    return "real photo"


def evaluate(model_path, images_dir, labels_dir, conf, iou_thresh):
    model = YOLO(model_path)

    # Align the model's class ids to the canonical order by NAME. This is the
    # whole point of the harness: never assume id order, always verify it.
    model_names = model.names  # {id: name, ...}
    model_id_for = {name: cid for cid, name in model_names.items()}
    missing = [n for n in CANONICAL_NAMES if n not in model_id_for]
    if missing:
        raise SystemExit(
            f"Model {model_path} has names {sorted(model_names.values())} -- "
            f"missing canonical classes {missing}. Refusing to score a model "
            "whose class vocabulary does not match the dataset.")
    mapping = {c: model_id_for[n] for c, n in enumerate(CANONICAL_NAMES)}
    print(f"Model names: {dict(sorted(model_names.items()))}")
    print(f"Canonical order -> model id mapping: {mapping}")
    # Stats are indexed by MODEL class id throughout (this is what both gt,
    # after the remap above, and predictions natively use).
    model_ids = sorted(model_names)
    id_name = {cid: name for cid, name in model_names.items()}

    def model_id(name):
        return model_id_for[name]

    nc = len(model_ids)
    overall = [dict(tp=0, fp=0, fn=0) for _ in range(nc)]
    by_group = {}

    for img_path in sorted(glob.glob(os.path.join(images_dir, "*.jpg"))):
        im = Image.open(img_path)
        w, h = im.size
        grp = group_of(im.size)
        if grp not in by_group:
            by_group[grp] = [dict(tp=0, fp=0, fn=0) for _ in range(nc)]

        gt = load_gt(os.path.join(labels_dir, os.path.basename(img_path)[:-4] + ".txt"), w, h,
                     lambda c: mapping[c])
        res = model.predict(source=img_path, conf=conf, iou=iou_thresh, verbose=False)[0]
        preds = []
        if res.boxes is not None:
            for b in res.boxes:
                x1, y1, x2, y2 = [float(v) for v in b.xyxy[0].tolist()]
                preds.append((int(b.cls[0].item()), x1, y1, x2, y2))

        for stat in (overall, by_group[grp]):
            used = [False] * len(gt)
            for p in preds:
                best_i, best_j = 0.0, -1
                for j, g in enumerate(gt):
                    if used[j] or g[0] != p[0]:
                        continue
                    i = iou(p[1:], g[1:])
                    if i > best_i:
                        best_i, best_j = i, j
                if best_i >= 0.5:
                    stat[p[0]]["tp"] += 1
                    used[best_j] = True
                else:
                    stat[p[0]]["fp"] += 1
            for j, g in enumerate(gt):
                if not used[j]:
                    stat[g[0]]["fn"] += 1

    print("\n=== Per-class precision/recall (boxes, IoU >= 0.5) ===")
    print(f"{'class':<10}{'TP':>6}{'FP':>6}{'FN':>6}{'precision':>12}{'recall':>10}")
    for cid in model_ids:
        name = id_name[cid]
        s = overall[cid]
        prec = s["tp"] / (s["tp"] + s["fp"]) if s["tp"] + s["fp"] else 0.0
        rec = s["tp"] / (s["tp"] + s["fn"]) if s["tp"] + s["fn"] else 0.0
        print(f"{name:<10}{s['tp']:>6}{s['fp']:>6}{s['fn']:>6}{prec:>12.3f}{rec:>10.3f}")

    print("\n=== Recall by image type (damaged / rotten / sprouted) ===")
    print(f"{'image type':<28}" + "".join(f"{n:>22}" for n in ("damaged", "rotten", "sprouted")))
    for grp, stat in by_group.items():
        cells = []
        for name in ("damaged", "rotten", "sprouted"):
            s = stat[model_id(name)]
            rec = s["tp"] / (s["tp"] + s["fn"]) if s["tp"] + s["fn"] else float("nan")
            cells.append(f"{rec:>13.3f} ({s['tp']}/{s['tp'] + s['fn']})")
        print(f"{grp:<28}" + "".join(cells))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", help="Path to a trained .pt model, e.g. onion-grading-v7.pt")
    ap.add_argument("--conf", type=float, default=0.25, help="Detection confidence threshold")
    ap.add_argument("--iou", type=float, default=0.45, help="NMS IoU threshold")
    ap.add_argument("--images", default=DEFAULT_VALID_IMAGES)
    ap.add_argument("--labels", default=DEFAULT_VALID_LABELS)
    args = ap.parse_args()
    evaluate(args.model, args.images, args.labels, args.conf, args.iou)


if __name__ == "__main__":
    main()
