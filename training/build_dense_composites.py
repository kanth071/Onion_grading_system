"""
Generates dense, heavily-overlapping multi-onion composite images —
targeting the exact failure mode found when testing onion-grading-v1.pt
on a real wholesale-market pile photo: the model only found 5-8 onions
out of ~25-30 visible, because the existing synthetic composites (532
images) never packed onions anywhere near that densely.

Crops are pasted with soft (feathered) edges, randomized size/rotation/
flip/brightness, and heavy mutual overlap (later onions drawn over
earlier ones, like a real pile). A box is dropped from the label if a
later onion ends up covering more than ~75% of it — an object that
occluded shouldn't be a training target, same as real annotators would
do.
"""
import os
import random
import glob

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

_CUTOUT_CACHE = {}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # onion grading/
CROPS_ROOT = os.path.join(os.path.dirname(ROOT), "onion_grading", "data_real")
DATASET = os.path.join(ROOT, "training", "merged_v2")

CLASS_IDS = {"healthy": 0, "damaged": 1, "rotten": 2, "sprouted": 3}
CANVAS = 640

random.seed(42)
np.random.seed(42)


def load_crop_pool():
    """Returns {class_name: [PIL.Image, ...]} using the same label recovery as relabel_bad_crops.py."""
    import re
    box_data = {}
    boxes_txt = os.path.join(os.path.dirname(ROOT), "onion_grading", "roboflow_meta", "boxes.txt")
    with open(boxes_txt, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("|")
            labels = []
            if len(parts) > 3 and parts[3]:
                for b in parts[3].split(";"):
                    labels.append(b.split(",")[0])
            box_data[parts[0]] = labels

    def norm_label(label):
        l = label.lower()
        if "sprout" in l or "root" in l:
            return "sprouted"
        if "rotten" in l:
            return "rotten"
        return "damaged"

    pat = re.compile(r"^(.*?)_(train|valid|test)_([0-9a-fA-F]{8})_(\d+)(?:_augflip_[hv])?\.jpg$")

    pool = {"healthy": [], "damaged": [], "rotten": [], "sprouted": []}
    for fn in os.listdir(os.path.join(CROPS_ROOT, "good")):
        if fn.lower().endswith((".jpg", ".jpeg", ".png")):
            pool["healthy"].append(os.path.join(CROPS_ROOT, "good", fn))

    for fn in os.listdir(os.path.join(CROPS_ROOT, "bad")):
        if not fn.lower().endswith(".jpg"):
            continue
        m = pat.match(fn)
        cls = "damaged"
        if m:
            base, _split, _variant, idx = m.groups()
            labels = box_data.get(base + ".jpg")
            if labels and int(idx) < len(labels):
                cls = norm_label(labels[int(idx)])
        pool[cls].append(os.path.join(CROPS_ROOT, "bad", fn))

    before = {k: len(v) for k, v in pool.items()}
    pool = {k: [p for p in v if _is_textured(p)] for k, v in pool.items()}
    after = {k: len(v) for k, v in pool.items()}
    print("Filtered flat/blank crops:", {k: before[k] - after[k] for k in before})

    return pool


def _is_textured(path, min_std=14.0):
    """
    Cheap contamination filter: a small random sample of crops turned out
    to be flat/blank patches (background sliver, blurry table edge) instead
    of onions - discard anything with near-zero pixel variance in its
    center region, since a real onion always has visible skin texture/
    shading there.
    """
    try:
        im = Image.open(path).convert("L")
    except Exception:
        return False
    w, h = im.size
    cx0, cy0, cx1, cy1 = int(w * 0.25), int(h * 0.25), int(w * 0.75), int(h * 0.75)
    center = np.array(im.crop((cx0, cy0, cx1, cy1)), dtype=np.float32)
    return center.std() >= min_std


def make_background(size):
    palettes = [
        ((120, 80, 45), (70, 45, 25)),   # wood crate
        ((150, 130, 100), (100, 85, 60)),  # cardboard
        ((110, 105, 95), (70, 65, 60)),   # concrete floor
        ((90, 70, 55), (50, 35, 25)),     # dark wood
    ]
    top, bottom = random.choice(palettes)
    bg = Image.new("RGB", size)
    arr = np.zeros((size[1], size[0], 3), dtype=np.uint8)
    for y in range(size[1]):
        t = y / size[1]
        row = tuple(int(top[c] * (1 - t) + bottom[c] * t) for c in range(3))
        arr[y, :, :] = row
    noise = np.random.randint(-12, 12, arr.shape, dtype=np.int16)
    arr = np.clip(arr.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    bg = Image.fromarray(arr)
    return bg.filter(ImageFilter.GaussianBlur(1.5))


def get_cutout(crop_path):
    """
    RGBA version of the source crop with a soft vignette baked into alpha
    BEFORE any rotation happens. These crops are tightly bound around a
    single onion (little true background), so a simple soft-edged
    near-full-frame mask is enough - real segmentation (rembg is blocked by
    this machine's Application Control policy; GrabCut degenerates to ~0%
    foreground on these low-contrast/near-full-frame crops - both tested
    and rejected) isn't needed here. Building alpha first and rotating the
    RGBA image together (instead of masking after rotation) is what
    actually matters: PIL fills newly-exposed corners from `rotate(...,
    expand=True)` with alpha=0 automatically for RGBA, so no black/white
    corner artifacts leak in - that was the real bug in the first attempt.
    """
    cached = _CUTOUT_CACHE.get(crop_path)
    if cached is not None:
        return cached.copy()
    raw = Image.open(crop_path).convert("RGB")
    w, h = raw.size
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    pad = max(2, int(min(w, h) * 0.04))
    md.ellipse([pad, pad, w - pad, h - pad], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    cutout = raw.convert("RGBA")
    cutout.putalpha(mask)
    _CUTOUT_CACHE[crop_path] = cutout
    return cutout.copy()


def soft_paste(canvas, crop_path, cx, cy, diameter):
    cutout = get_cutout(crop_path)
    scale = diameter / max(cutout.width, cutout.height)
    new_size = (max(1, int(cutout.width * scale)), max(1, int(cutout.height * scale)))
    cutout = cutout.resize(new_size, Image.LANCZOS)

    angle = random.uniform(0, 360)
    cutout = cutout.rotate(angle, expand=True, resample=Image.BILINEAR)  # RGBA: new corners get alpha=0
    if random.random() < 0.5:
        cutout = cutout.transpose(Image.FLIP_LEFT_RIGHT)

    rgb = cutout.convert("RGB")
    rgb = ImageEnhance.Brightness(rgb).enhance(random.uniform(0.85, 1.15))
    rgb = ImageEnhance.Contrast(rgb).enhance(random.uniform(0.9, 1.1))
    mask = cutout.getchannel("A")

    w, h = cutout.size
    x0, y0 = cx - w // 2, cy - h // 2
    canvas.paste(rgb, (x0, y0), mask)

    occ_mask = np.zeros((CANVAS, CANVAS), dtype=np.uint8)
    mask_arr = np.array(mask)
    x1, y1 = x0 + w, y0 + h
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(CANVAS, x1), min(CANVAS, y1)
    if sx1 > sx0 and sy1 > sy0:
        mx0, my0 = sx0 - x0, sy0 - y0
        occ_mask[sy0:sy1, sx0:sx1] = mask_arr[my0:my0 + (sy1 - sy0), mx0:mx0 + (sx1 - sx0)] > 40

    bbox = (max(0, x0), max(0, y0), min(CANVAS, x1), min(CANVAS, y1))
    return bbox, occ_mask


def generate_one(pool, class_weights):
    canvas = make_background((CANVAS, CANVAS))
    n_onions = random.randint(13, 24)

    placed = []  # (bbox, class_id, occ_mask, area)
    classes = list(class_weights.keys())
    weights = list(class_weights.values())

    attempts = 0
    while len(placed) < n_onions and attempts < n_onions * 6:
        attempts += 1
        cls = random.choices(classes, weights=weights, k=1)[0]
        crop_path = random.choice(pool[cls])

        diameter = random.randint(70, 165)
        margin = diameter // 3
        cx = random.randint(margin, CANVAS - margin)
        cy = random.randint(margin, CANVAS - margin)

        try:
            result = soft_paste(canvas, crop_path, cx, cy, diameter)
        except Exception:
            continue
        if result is None:
            continue
        bbox, occ_mask = result
        area = occ_mask.sum()
        if area < 30:
            continue
        placed.append([bbox, CLASS_IDS[cls], occ_mask, area])

    # Drop boxes that ended up >75% covered by later (in-front) onions.
    labels = []
    for i, (bbox, cls_id, occ_mask, area) in enumerate(placed):
        covered = np.zeros_like(occ_mask)
        for later in placed[i + 1:]:
            covered |= later[2]
        remaining = occ_mask & ~covered
        visible_frac = remaining.sum() / max(area, 1)
        if visible_frac < 0.25:
            continue
        x0, y0, x1, y1 = bbox
        cx_n = (x0 + x1) / 2 / CANVAS
        cy_n = (y0 + y1) / 2 / CANVAS
        w_n = (x1 - x0) / CANVAS
        h_n = (y1 - y0) / CANVAS
        if w_n <= 0 or h_n <= 0:
            continue
        labels.append(f"{cls_id} {cx_n:.5f} {cy_n:.5f} {w_n:.5f} {h_n:.5f}")

    return canvas, labels


def main(n_train=260, n_valid=30):
    pool = load_crop_pool()
    print("Crop pool sizes:", {k: len(v) for k, v in pool.items()})

    profiles = [
        {"healthy": 0.7, "damaged": 0.15, "rotten": 0.08, "sprouted": 0.07},
        {"healthy": 0.4, "damaged": 0.3, "rotten": 0.15, "sprouted": 0.15},
        {"healthy": 0.15, "damaged": 0.35, "rotten": 0.25, "sprouted": 0.25},
        {"healthy": 0.55, "damaged": 0.2, "rotten": 0.1, "sprouted": 0.15},
    ]

    for split, n in (("train", n_train), ("valid", n_valid)):
        img_dir = os.path.join(DATASET, split, "images")
        lbl_dir = os.path.join(DATASET, split, "labels")
        for i in range(n):
            profile = random.choice(profiles)
            canvas, labels = generate_one(pool, profile)
            if not labels:
                continue
            name = f"densepile_{split}_{i:04d}"
            canvas.save(os.path.join(img_dir, name + ".jpg"), quality=88)
            with open(os.path.join(lbl_dir, name + ".txt"), "w") as f:
                f.write("\n".join(labels) + "\n")
        print(f"{split}: generated dense composites")


if __name__ == "__main__":
    main()
