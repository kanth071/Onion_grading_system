"""
finetune_from_photos.py -- turnkey fine-tune on YOUR real photos.

WHY
---
The deployed model (onion-grading-v7.pt) is accurate on its synthetic
validation set but misses damaged/rotten onions on real crate/market
photos (damaged recall drops ~0.94 -> ~0.54 on the real-photo subset).
The fix is domain-matched training data, i.e. photos like the ones the
app will actually see.

WHAT THIS DOES
--------------
1. Ingests a folder of real photos organized by class:
       new_photos/healthy/*.jpg
       new_photos/damaged/*.jpg      (cuts, split skin, black smut, staining)
       new_photos/rotten/*.jpg       (soft, spoiled, dark/mushy)
       new_photos/sprouted/*.jpg     (green shoots / roots visible)
   Each photo should be ONE onion filling most of the frame, roughly
   square, phone camera is fine. Folder name == the label, so no manual
   box drawing is needed.
2. Builds a canonical-order dataset `merged_v3/` (healthy=0, damaged=1,
   rotten=2, sprouted=3 -- the SAME order as training/merged_v2's
   data.yaml) by merging:
     - the existing merged_v2 train/valid images (kept),
     - your real photos as clean single-onion examples (85/15 split),
     - synthetic dense multi-onion piles composited from YOUR crops, so
       the model also learns "spot the defect in a wide crate shot" --
       the exact failure mode you reported.
3. Fine-tunes onion-grading-v7.pt on it (class ids are remapped by name
   via cls_remap, so the output model is guaranteed canonical order --
   this permanently ends the v6/v7 rotten/sprouted class-order trap),
   saves the result as onion-grading-v8.pt in the project root, and the
   app picks it up automatically on restart.

USAGE
-----
    # put photos in new_photos/<class>/..., then:
    python training/finetune_from_photos.py                 # build + train
    python training/finetune_from_photos.py --build-only     # just build the dataset
    # honest evaluation of the result:
    python training/evaluate_model.py onion-grading-v8.pt
"""
import argparse
import glob
import os
import random
import shutil
import sys

import numpy as np
from PIL import Image

# Reuse the tested composite-pile generator from the v2 dataset build.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_dense_composites as bdc  # noqa: E402

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MERGED_V2 = os.path.join(REPO_ROOT, "training", "merged_v2")
DEFAULT_PHOTOS = os.path.join(REPO_ROOT, "new_photos")
DEFAULT_OUT = os.path.join(REPO_ROOT, "training", "merged_v3")
DEFAULT_BASE = os.path.join(REPO_ROOT, "onion-grading-v7.pt")
DEFAULT_OUTPUT_PT = os.path.join(REPO_ROOT, "onion-grading-v8.pt")

CLASSES = ["healthy", "damaged", "rotten", "sprouted"]  # canonical order
CLASS_IDS = {c: i for i, c in enumerate(CLASSES)}
TARGET_SIZE = 640  # single-onion samples are resized so the longest side fits this

random.seed(7)
np.random.seed(7)


def collect_photos(root):
    """Returns {class: [image paths]} from root/<class>/ folders."""
    pool = {c: [] for c in CLASSES}
    if not os.path.isdir(root):
        print(f"WARNING: photo folder '{root}' not found -- continuing with no new photos.")
        return pool
    for cls in CLASSES:
        cls_dir = os.path.join(root, cls)
        if not os.path.isdir(cls_dir):
            print(f"WARNING: no '{cls}' subfolder under {root}")
            continue
        for p in sorted(glob.glob(os.path.join(cls_dir, "*"))):
            if p.lower().endswith((".jpg", ".jpeg", ".png")):
                pool[cls].append(p)
        before = len(pool[cls])
        pool[cls] = [p for p in pool[cls] if _usable(p)]
        dropped = before - len(pool[cls])
        if dropped:
            print(f"  {cls}: dropped {dropped} blank/tiny photo(s)")
    return pool


def _usable(path, min_side=128, min_std=14.0):
    """Reject tiny and flat/blank images (same idea as the v2 build)."""
    try:
        im = Image.open(path).convert("L")
    except Exception:
        return False
    w, h = im.size
    if min(w, h) < min_side:
        return False
    cx0, cy0, cx1, cy1 = int(w * 0.25), int(h * 0.25), int(w * 0.75), int(h * 0.75)
    center = np.array(im.crop((cx0, cy0, cx1, cy1)), dtype=np.float32)
    return center.std() >= min_std


def save_single_onion(src, out_img_dir, out_lbl_dir, name):
    """Resize one photo (onion fills frame) and write a full-frame box."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    scale = TARGET_SIZE / max(w, h)
    if scale < 1:
        im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    w, h = im.size
    out = os.path.join(out_img_dir, name + ".jpg")
    im.save(out, quality=92)
    # Box inset 2.5% so the label doesn't ride the image edge.
    m = 0.025
    with open(os.path.join(out_lbl_dir, name + ".txt"), "w") as f:
        f.write(f"{CLASS_IDS[os.path.basename(os.path.dirname(src))]} "
                f"0.5 0.5 {1 - 2 * m:.4f} {1 - 2 * m:.4f}\n")
    return out


def generate_composites(pool, n, out_img_dir, out_lbl_dir, tag):
    """Dense multi-onion piles from the user's own crops (reuses v2 code)."""
    profiles = [
        {"healthy": 0.7, "damaged": 0.15, "rotten": 0.08, "sprouted": 0.07},
        {"healthy": 0.4, "damaged": 0.3, "rotten": 0.15, "sprouted": 0.15},
        {"healthy": 0.15, "damaged": 0.35, "rotten": 0.25, "sprouted": 0.25},
        {"healthy": 0.55, "damaged": 0.2, "rotten": 0.1, "sprouted": 0.15},
    ]
    # Only composite from classes that actually have user photos; a profile
    # naming an empty pool would crash the generator.
    available = [c for c in pool if pool[c]]
    usable = [p for p in profiles if any(p.get(c, 0) > 0 for c in available)]
    if not usable:
        return 0
    made = 0
    for i in range(n):
        profile = random.choice(usable)
        profile = {c: w for c, w in profile.items() if c in available}
        canvas, labels = bdc.generate_one(pool, profile)
        if not labels:
            continue
        name = f"{tag}_{i:04d}"
        canvas.save(os.path.join(out_img_dir, name + ".jpg"), quality=88)
        with open(os.path.join(out_lbl_dir, name + ".txt"), "w") as f:
            f.write("\n".join(labels) + "\n")
        made += 1
    return made


def build_dataset(photos_root, out_dir):
    pool = collect_photos(photos_root)
    total_new = sum(len(v) for v in pool.values())
    print("New real-photo pool sizes:", {k: len(v) for k, v in pool.items()})
    if total_new == 0:
        raise SystemExit("No usable new photos found; nothing to train on. "
                         "Put photos in new_photos/<class>/ and re-run.")

    for split in ("train", "valid"):
        img_dir = os.path.join(out_dir, split, "images")
        lbl_dir = os.path.join(out_dir, split, "labels")
        os.makedirs(img_dir, exist_ok=True)
        os.makedirs(lbl_dir, exist_ok=True)

    # 1) Existing canonical data stays put (train->train, valid->valid).
    for split in ("train", "valid"):
        src_img = os.path.join(MERGED_V2, split, "images")
        src_lbl = os.path.join(MERGED_V2, split, "labels")
        dst_img = os.path.join(out_dir, split, "images")
        dst_lbl = os.path.join(out_dir, split, "labels")
        for fn in os.listdir(src_img):
            if fn.lower().endswith((".jpg", ".jpeg", ".png")):
                shutil.copy(os.path.join(src_img, fn), os.path.join(dst_img, fn))
        for fn in os.listdir(src_lbl):
            if fn.endswith(".txt"):
                shutil.copy(os.path.join(src_lbl, fn), os.path.join(dst_lbl, fn))
    print(f"Copied existing canonical data into {out_dir}")

    # 2) Real single-onion photos: 85% train / 15% valid per class. Keeping
    # some of your real photos OUT of training is what makes the eval honest.
    train_dir = os.path.join(out_dir, "train")
    valid_dir = os.path.join(out_dir, "valid")
    for cls, paths in pool.items():
        random.shuffle(paths)
        n_valid = max(1, round(len(paths) * 0.15))
        valid_paths, train_paths = paths[:n_valid], paths[n_valid:]
        for i, p in enumerate(train_paths):
            save_single_onion(p, os.path.join(train_dir, "images"),
                              os.path.join(train_dir, "labels"),
                              f"realuser_{cls}_train_{i:03d}")
        for i, p in enumerate(valid_paths):
            save_single_onion(p, os.path.join(valid_dir, "images"),
                              os.path.join(valid_dir, "labels"),
                              f"realuser_{cls}_valid_{i:03d}")
    print("Wrote real-photo single-onion samples (train + valid holdout)")

    # 3) Dense piles from the user's crops give the model multi-onion scenes.
    n_train_piles = max(80, min(200, total_new * 3))
    made_t = generate_composites(pool, n_train_piles,
                                 os.path.join(train_dir, "images"),
                                 os.path.join(train_dir, "labels"), "userpile_train")
    made_v = generate_composites(pool, max(10, n_train_piles // 6),
                                 os.path.join(valid_dir, "images"),
                                 os.path.join(valid_dir, "labels"), "userpile_valid")
    print(f"Generated {made_t} train + {made_v} valid dense piles from your crops")


def write_data_yaml(out_dir):
    data_yaml = os.path.join(out_dir, "data.yaml")
    with open(data_yaml, "w") as f:
        f.write("train: " + os.path.join(out_dir, "train", "images").replace("\\", "/") + "\n")
        f.write("val: " + os.path.join(out_dir, "valid", "images").replace("\\", "/") + "\n")
        f.write(f"nc: {len(CLASSES)}\n")
        f.write("names: " + str(CLASSES) + "\n")
    return data_yaml


def print_stats(out_dir):
    print("\n=== merged_v3 dataset class balance ===")
    for split in ("train", "valid"):
        counts = {c: 0 for c in CLASSES}
        lbl_dir = os.path.join(out_dir, split, "labels")
        for fn in sorted(os.listdir(lbl_dir)):
            if not fn.endswith(".txt"):
                continue
            with open(os.path.join(lbl_dir, fn)) as f:
                for line in f:
                    if line.strip():
                        counts[CLASSES[int(line.split()[0])]] += 1
        n_img = len([f for f in os.listdir(os.path.join(out_dir, split, "images"))
                     if f.lower().endswith((".jpg", ".jpeg", ".png"))])
        print(f"{split:<6} {n_img:>5} images  "
              + "  ".join(f"{c}={counts[c]}" for c in CLASSES))


def train_model(out_dir, data_yaml, base_model, output_pt, epochs, run_name):
    from ultralytics import YOLO

    run_dir = os.path.join(REPO_ROOT, "backend", "runs", "training", run_name)
    os.makedirs(run_dir, exist_ok=True)
    print(f"\nFine-tuning {base_model} on {data_yaml} ({epochs} epochs)...")
    model = YOLO(base_model)
    model.train(data=data_yaml, epochs=epochs, imgsz=640, batch=8, lr0=0.0007,
                patience=0, project=os.path.join(REPO_ROOT, "backend", "runs", "training"),
                name=run_name, exist_ok=True, workers=2, verbose=True,
                cls_remap=True, seed=0)

    best = os.path.join(run_dir, "weights", "best.pt")
    if not os.path.exists(best):
        raise SystemExit(f"Training finished but no weights at {best}")

    # Refuse to deploy a model whose class order drifted from canonical.
    names = YOLO(best).names
    actual = [names[i] for i in sorted(names)]
    if actual != CLASSES:
        raise SystemExit(f"Refusing to deploy: model names {actual} != canonical {CLASSES}. "
                         "Check cls_remap / dataset class order and retrain.")
    shutil.copy(best, output_pt)
    print(f"\nDeployed {output_pt} (class names verified canonical: {actual})")
    print("Restart the backend to pick it up. Then evaluate honestly with:")
    print(f"  python training/evaluate_model.py {os.path.basename(output_pt)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--photos", default=DEFAULT_PHOTOS, help="Folder with <class>/ subfolders of real photos")
    ap.add_argument("--out", default=DEFAULT_OUT, help="Output dataset directory")
    ap.add_argument("--base-model", default=DEFAULT_BASE)
    ap.add_argument("--output-pt", default=DEFAULT_OUTPUT_PT)
    ap.add_argument("--epochs", type=int, default=3, help="Fine-tune epochs (~15-20 min each on CPU)")
    ap.add_argument("--name", default="v8_realphotos", help="Ultralytics run name")
    ap.add_argument("--build-only", action="store_true", help="Build merged_v3 and stop before training")
    args = ap.parse_args()

    if os.path.isdir(args.out) and os.listdir(args.out):
        raise SystemExit(f"Output dataset {args.out} already exists and is not empty. "
                         "Remove it first (or pick --out another name).")
    build_dataset(args.photos, args.out)
    write_data_yaml(args.out)
    print_stats(args.out)
    if args.build_only:
        print("\n--build-only: dataset ready; skipping training.")
        return
    train_model(args.out, os.path.join(args.out, "data.yaml"), args.base_model,
                args.output_pt, args.epochs, args.name)


if __name__ == "__main__":
    main()
